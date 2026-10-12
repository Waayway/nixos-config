mod common;
use common::*;
use fleet_agent::checks::check_apply;
use fleet_agent::git::Git;
use fleet_proto::SkipReason;

#[test]
fn ok_when_clean_and_ff() {
    let f = fixture();
    let c = push_remote_commit(&f, "b.txt");
    let g = Git::new(&f.cfg).unwrap();
    g.fetch(&f.cfg.repo_url).unwrap();
    assert_eq!(check_apply(&g, "unstable", &c), Ok(()));
}

#[test]
fn missing_commit() {
    let f = fixture();
    let g = Git::new(&f.cfg).unwrap();
    assert_eq!(
        check_apply(&g, "unstable", &"0".repeat(40)),
        Err(SkipReason::CommitNotFound)
    );
}

#[test]
fn commit_only_on_other_branch() {
    let f = fixture();
    git(&f.clone, &["checkout", "-q", "-b", "other"]);
    let c = commit_file(&f.clone, "o.txt", "o");
    git(&f.clone, &["checkout", "-q", "unstable"]);
    let g = Git::new(&f.cfg).unwrap();
    assert_eq!(
        check_apply(&g, "unstable", &c),
        Err(SkipReason::CommitNotOnChannel)
    );
}

#[test]
fn no_remote_channel_ref() {
    let f = fixture();
    git(
        &f.clone,
        &["update-ref", "-d", "refs/remotes/origin/stable"],
    );
    let head = git(&f.clone, &["rev-parse", "HEAD"]);
    let g = Git::new(&f.cfg).unwrap();
    assert_eq!(
        check_apply(&g, "stable", &head),
        Err(SkipReason::CommitNotOnChannel)
    );
}

#[test]
fn detached_head() {
    let f = fixture();
    let c = push_remote_commit(&f, "b.txt");
    git(&f.clone, &["checkout", "-q", "--detach"]);
    let g = Git::new(&f.cfg).unwrap();
    g.fetch(&f.cfg.repo_url).unwrap();
    assert_eq!(
        check_apply(&g, "unstable", &c),
        Err(SkipReason::WrongBranch)
    );
}

#[test]
fn tracked_change() {
    let f = fixture();
    let c = push_remote_commit(&f, "b.txt");
    let g = Git::new(&f.cfg).unwrap();
    g.fetch(&f.cfg.repo_url).unwrap();
    std::fs::write(f.clone.join("a.txt"), "changed").unwrap();
    assert_eq!(check_apply(&g, "unstable", &c), Err(SkipReason::Dirty));
}

#[test]
fn untracked_only_is_ok() {
    let f = fixture();
    let c = push_remote_commit(&f, "b.txt");
    let g = Git::new(&f.cfg).unwrap();
    g.fetch(&f.cfg.repo_url).unwrap();
    std::fs::write(f.clone.join("scratch.txt"), "x").unwrap();
    assert_eq!(check_apply(&g, "unstable", &c), Ok(()));
}

#[test]
fn local_commit_diverged() {
    let f = fixture();
    let c = push_remote_commit(&f, "b.txt");
    commit_file(&f.clone, "local.txt", "l");
    let g = Git::new(&f.cfg).unwrap();
    g.fetch(&f.cfg.repo_url).unwrap();
    assert_eq!(
        check_apply(&g, "unstable", &c),
        Err(SkipReason::NotFastForward)
    );
}
