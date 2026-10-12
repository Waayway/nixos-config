mod common;
use common::*;
use fleet_agent::git::Git;

#[test]
fn fetch_then_commit_exists() {
    let f = fixture();
    let c = push_remote_commit(&f, "b.txt");
    let g = Git::new(&f.cfg).unwrap();
    assert!(!g.commit_exists(&c));
    g.fetch(&f.cfg.repo_url).unwrap();
    assert!(g.commit_exists(&c));
    assert!(!g.commit_exists(&"0".repeat(40)));
    assert!(g.fetch("/nonexistent/repo").is_err());
}

#[test]
fn fetch_within_works_and_times_out() {
    use std::time::{Duration, Instant};
    let f = fixture();
    let c = push_remote_commit(&f, "b.txt");
    let g = Git::new(&f.cfg).unwrap();
    g.fetch_within(&f.cfg.repo_url, Duration::from_secs(30))
        .unwrap();
    assert!(g.commit_exists(&c));
    assert!(
        g.fetch_within("/nonexistent/repo", Duration::from_secs(30))
            .is_err()
    );

    // A git:// server that accepts and never answers.
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("git://{}/repo", listener.local_addr().unwrap());
    let hold = std::thread::spawn(move || {
        let conn = listener.accept();
        std::thread::sleep(Duration::from_secs(5));
        drop(conn);
    });
    let start = Instant::now();
    let err = g.fetch_within(&url, Duration::from_secs(1)).unwrap_err();
    assert!(format!("{err:#}").contains("timed out"), "{err:#}");
    assert!(
        start.elapsed() < Duration::from_secs(4),
        "{:?}",
        start.elapsed()
    );
    hold.join().unwrap();
}

#[test]
fn dirty_tracked_only() {
    let f = fixture();
    let g = Git::new(&f.cfg).unwrap();
    assert!(!g.is_dirty());
    std::fs::write(f.clone.join("new.txt"), "x").unwrap();
    assert!(!g.is_dirty());
    assert_eq!(g.untracked_count(), 1);
    std::fs::write(f.clone.join("a.txt"), "changed").unwrap();
    assert!(g.is_dirty());
}

#[test]
fn detached_head_branch_is_none() {
    let f = fixture();
    let g = Git::new(&f.cfg).unwrap();
    assert_eq!(g.current_branch().as_deref(), Some("unstable"));
    let head = g.head().unwrap();
    git(&f.clone, &["checkout", "-q", "--detach", &head]);
    assert_eq!(g.current_branch(), None);
    assert_eq!(g.head().as_deref(), Some(head.as_str()));
}

#[test]
fn ahead_counts_local_commits() {
    let f = fixture();
    let g = Git::new(&f.cfg).unwrap();
    assert_eq!(g.ahead_of("origin/unstable"), Some(0));
    commit_file(&f.clone, "l1.txt", "1");
    commit_file(&f.clone, "l2.txt", "2");
    assert_eq!(g.ahead_of("origin/unstable"), Some(2));
    assert_eq!(g.ahead_of("origin/nope"), None);
}

#[test]
fn ff_merge_moves_head() {
    let f = fixture();
    let before = Git::new(&f.cfg).unwrap().head().unwrap();
    let c = push_remote_commit(&f, "b.txt");
    let g = Git::new(&f.cfg).unwrap();
    g.fetch(&f.cfg.repo_url).unwrap();
    assert!(g.is_ancestor(&before, &c));
    assert!(!g.is_ancestor(&c, &before));
    g.ff_merge(&c).unwrap();
    assert_eq!(g.head().unwrap(), c);
    // diverged history cannot fast-forward
    git(&f.clone, &["reset", "-q", "--hard", &before]);
    commit_file(&f.clone, "local.txt", "l");
    assert!(g.ff_merge(&c).is_err());
}
