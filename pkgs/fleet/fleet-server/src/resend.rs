//! When the server re-sends a host's desired apply on its own.

use fleet_proto::{AgentStatus, ApplyState};

/// True when the desired apply should be (re-)sent to an online, reachable host:
/// there is a desired apply, the host is not running its commit (`-dirty` ignored),
/// the agent's last apply is not this `apply_id` (it never received it), and the agent
/// is not busy with another apply. A desired apply that ran and ended `failed` or
/// `skipped` is therefore never re-sent; pressing the button again creates a new one.
pub fn should_resend(
    desired: Option<&str>,
    desired_commit: Option<&str>,
    status: &AgentStatus,
) -> bool {
    let Some(desired) = desired else {
        return false;
    };
    let running = status
        .running
        .strip_suffix("-dirty")
        .unwrap_or(&status.running);
    if Some(running) == desired_commit {
        return false;
    }
    match &status.apply {
        Some(a) => a.apply_id != desired && a.state != ApplyState::Running,
        None => true,
    }
}
