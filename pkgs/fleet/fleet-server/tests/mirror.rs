use std::path::{Path, PathBuf};
use std::process::Command;

use fleet_server::config::{AccessConfig, OnlineSource, ServerConfig};
use fleet_server::mirror::Mirror;

fn git(dir: &Path, args: &[&str]) -> String {
    let out = Command::new("git")
        .current_dir(dir)
        .args(args)
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_AUTHOR_NAME", "t")
        .env("GIT_AUTHOR_EMAIL", "t@example.com")
        .env("GIT_COMMITTER_NAME", "t")
        .env("GIT_COMMITTER_EMAIL", "t@example.com")
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap().trim().to_string()
}

/// A bare "origin" plus a working clone used to create commits on it.
struct Origin {
    _dir: tempfile::TempDir,
    bare: PathBuf,
    work: PathBuf,
}

impl Origin {
    fn new() -> Origin {
        let dir = tempfile::tempdir().unwrap();
        let bare = dir.path().join("origin.git");
        let work = dir.path().join("work");
        std::fs::create_dir_all(&work).unwrap();
        git(
            dir.path(),
            &["init", "--bare", "-b", "main", bare.to_str().unwrap()],
        );
        git(&work, &["init", "-b", "unstable"]);
        git(&work, &["remote", "add", "origin", bare.to_str().unwrap()]);
        Origin {
            _dir: dir,
            bare,
            work,
        }
    }

    /// Commit on the current branch and push it; returns the new hash.
    fn commit(&self, subject: &str, push_branch: &str) -> String {
        git(&self.work, &["commit", "--allow-empty", "-m", subject]);
        let h = git(&self.work, &["rev-parse", "HEAD"]);
        git(
            &self.work,
            &["push", "origin", &format!("HEAD:refs/heads/{push_branch}")],
        );
        h
    }

    fn bare_ref(&self, branch: &str) -> String {
        git(&self.bare, &["rev-parse", &format!("refs/heads/{branch}")])
    }
}

fn config(state_dir: &Path, repo: &str) -> ServerConfig {
    ServerConfig {
        listen: "127.0.0.1:0".parse().unwrap(),
        agent_port: 7461,
        hosts_file: state_dir.join("hosts.json"),
        repo_url: repo.into(),
        push_url: repo.into(),
        deploy_key_file: None,
        state_dir: state_dir.to_path_buf(),
        access: AccessConfig::Disabled,
        online: OnlineSource::Tailscale,
        mirror_fetch_secs: 300,
        poll_secs: 60,
        tailscale_bin: PathBuf::from("tailscale"),
    }
}

async fn mirror_of(o: &Origin) -> (Mirror, tempfile::TempDir) {
    let state = tempfile::tempdir().unwrap();
    let m = Mirror::open_or_init(&config(state.path(), o.bare.to_str().unwrap()))
        .await
        .unwrap();
    (m, state)
}

#[tokio::test]
async fn head_after_fetch() {
    let o = Origin::new();
    let c1 = o.commit("first", "unstable");
    let (m, _s) = mirror_of(&o).await;
    assert_eq!(m.head("unstable").await, Some(c1.clone()));
    assert_eq!(m.head("stable").await, None);
    assert_eq!(m.subject(&c1).await.as_deref(), Some("first"));
    assert_eq!(m.subject("--output=x").await, None);
    let c2 = o.commit("second", "unstable");
    m.fetch().await.unwrap();
    assert_eq!(m.head("unstable").await, Some(c2));
}

#[tokio::test]
async fn behind_strips_dirty() {
    let o = Origin::new();
    let c1 = o.commit("one", "unstable");
    o.commit("two", "unstable");
    o.commit("three", "unstable");
    let (m, _s) = mirror_of(&o).await;
    assert_eq!(
        m.behind_count(&format!("{c1}-dirty"), "unstable").await,
        Some(2)
    );
    assert_eq!(m.behind_count(&c1, "unstable").await, Some(2));
}

#[tokio::test]
async fn behind_unknown_for_foreign_or_unknown() {
    let o = Origin::new();
    o.commit("one", "unstable");
    let (m, _s) = mirror_of(&o).await;
    assert_eq!(m.behind_count("unknown", "unstable").await, None);
    assert_eq!(m.behind_count(&"a".repeat(40), "unstable").await, None);
    assert_eq!(m.behind_count("--help", "unstable").await, None);
}

#[tokio::test]
async fn promote_rejects_non_ancestor() {
    let o = Origin::new();
    let c1 = o.commit("one", "unstable");
    o.commit("two", "stable");
    // A commit on a divergent line: on a side branch, not an ancestor of unstable.
    git(&o.work, &["checkout", "-b", "side", &c1]);
    let side = o.commit("side", "side");
    git(&o.work, &["checkout", "unstable"]);
    let (m, _s) = mirror_of(&o).await;
    assert!(m.promote(&side).await.is_err());
    assert!(m.promote(&"b".repeat(40)).await.is_err());
    assert!(m.promote("--delete").await.is_err());
    // stable is not an ancestor of c1 (stable is ahead), so c1 is also rejected.
    assert!(m.promote(&c1).await.is_err());
}

#[tokio::test]
async fn promote_fast_forwards_stable() {
    let o = Origin::new();
    let c1 = o.commit("one", "stable");
    git(&o.work, &["push", "origin", "HEAD:refs/heads/unstable"]);
    let c2 = o.commit("two", "unstable");
    let c3 = o.commit("three", "unstable");
    let (m, _s) = mirror_of(&o).await;
    assert_eq!(m.promote_candidate().await, Some(c3.clone()));
    m.promote(&c2).await.unwrap();
    assert_eq!(o.bare_ref("stable"), c2);
    assert_ne!(c1, c2);
    m.fetch().await.unwrap();
    assert_eq!(m.head("stable").await, Some(c2));
    assert_eq!(m.promote_candidate().await, Some(c3));
}

#[tokio::test]
async fn promote_candidate_none_when_equal() {
    let o = Origin::new();
    o.commit("one", "stable");
    o.commit("two", "unstable");
    git(&o.work, &["push", "origin", "HEAD:refs/heads/stable"]);
    let (m, _s) = mirror_of(&o).await;
    assert_eq!(m.promote_candidate().await, None);
}

#[tokio::test]
async fn fetch_error_is_err() {
    let state = tempfile::tempdir().unwrap();
    let bogus = state.path().join("does-not-exist.git");
    let cfg = config(state.path(), bogus.to_str().unwrap());
    // open_or_init tolerates a failing first fetch; fetch() reports it.
    let m = Mirror::open_or_init(&cfg).await.unwrap();
    assert!(m.fetch().await.is_err());
    assert_eq!(m.head("unstable").await, None);
}
