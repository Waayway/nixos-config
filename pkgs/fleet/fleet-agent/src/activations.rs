//! Reads the activation audit file written by the fleet activation snippet.

use std::path::Path;

use fleet_proto::{ActivationEvent, ActivationsResponse};
use serde::Deserialize;

#[derive(Deserialize)]
struct RawEvent {
    time: i64,
    store_path: String,
    revision: String,
    #[serde(default)]
    generation: Option<u64>,
    trigger: String,
    #[serde(default)]
    sudo_user: Option<String>,
}

/// Events on lines `>= since` (0-based). Malformed lines are skipped and a
/// trailing line without `\n` (still being written) is left for next time.
/// `next` is the number of complete lines in the file.
pub fn read_since(path: &Path, since: u64) -> ActivationsResponse {
    let data = std::fs::read(path).unwrap_or_default();
    let complete = match data.iter().rposition(|b| *b == b'\n') {
        Some(i) => &data[..i],
        None => {
            return ActivationsResponse {
                events: vec![],
                next: 0,
            };
        }
    };
    let mut events = Vec::new();
    let mut next = 0u64;
    for (n, line) in complete.split(|b| *b == b'\n').enumerate() {
        let n = n as u64;
        next = n + 1;
        if n < since {
            continue;
        }
        if let Ok(r) = serde_json::from_slice::<RawEvent>(line) {
            events.push(ActivationEvent {
                line: n,
                time: r.time,
                store_path: r.store_path,
                revision: r.revision,
                generation: r.generation,
                trigger: r.trigger,
                sudo_user: r.sudo_user,
            });
        }
    }
    ActivationsResponse { events, next }
}
