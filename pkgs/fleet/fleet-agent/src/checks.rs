use fleet_proto::SkipReason;

use crate::git::Git;

/// Decides whether "apply `commit` on `channel`" may proceed on this checkout.
///
/// Checks run in the spec's order and the first failure wins. Nothing here
/// modifies the checkout.
pub fn check_apply(git: &Git, channel: &str, commit: &str) -> Result<(), SkipReason> {
    if !git.commit_exists(commit) {
        return Err(SkipReason::CommitNotFound);
    }
    // A missing `origin/<channel>` makes `merge-base --is-ancestor` fail, so
    // that case is also reported as not on the channel.
    if !git.is_ancestor(commit, &format!("refs/remotes/origin/{channel}")) {
        return Err(SkipReason::CommitNotOnChannel);
    }
    if git.current_branch().as_deref() != Some(channel) {
        return Err(SkipReason::WrongBranch);
    }
    if git.is_dirty() {
        return Err(SkipReason::Dirty);
    }
    if !git.is_ancestor("HEAD", commit) {
        return Err(SkipReason::NotFastForward);
    }
    Ok(())
}
