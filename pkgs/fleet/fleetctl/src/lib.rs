//! `fleetctl`: a small CLI for the fleet manager's HTTP API. Access is decided by the
//! server from the caller's Tailscale identity, so there are no tokens here.

use std::collections::BTreeMap;
use std::io::Write;
use std::time::{Duration, Instant};

use anyhow::{Context, Result, anyhow, bail};
use clap::{Parser, Subcommand};
use fleet_proto::{ApplyRecord, ApplyState, AuditEvent, HostView, OnlineState, Snapshot};
use serde::de::DeserializeOwned;
use serde_json::{Value, json};

#[derive(Parser)]
#[command(name = "fleetctl", about = "Talk to the fleet manager")]
pub struct Cli {
    /// Fleet server URL.
    #[arg(
        long,
        env = "FLEET_SERVER",
        default_value = "http://nixos-manager:8080"
    )]
    pub server: String,
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand)]
pub enum Command {
    /// Table of all hosts.
    Status,
    /// Force a rebuild: apply the channel's current head, even if the host already runs it.
    Rebuild {
        /// Host to rebuild (omit when using --channel).
        host: Option<String>,
        /// Rebuild every host on this channel instead.
        #[arg(long, conflicts_with = "host")]
        channel: Option<String>,
        /// Wait for the apply to finish; exit 0 only if it succeeded.
        #[arg(long)]
        wait: bool,
        /// Give up waiting after this many seconds.
        #[arg(long, default_value_t = 900)]
        timeout: u64,
    },
    /// Print an apply's log (default: the host's last apply).
    Log {
        host: String,
        apply_id: Option<String>,
    },
    /// Move stable to the promote candidate.
    Promote {
        /// Actually promote (otherwise only show the candidate).
        #[arg(long)]
        yes: bool,
    },
    /// Recent audit events.
    Audit {
        #[arg(long, default_value_t = 20)]
        limit: u64,
    },
}

pub struct Client {
    base: String,
    http: reqwest::Client,
    /// How often `--wait` polls the snapshot.
    pub poll: Duration,
}

impl Client {
    pub fn new(server: &str) -> Self {
        let mut headers = reqwest::header::HeaderMap::new();
        // CSRF guard on the server: every state-changing request needs this.
        headers.insert("x-fleet", reqwest::header::HeaderValue::from_static("1"));
        let base = server.trim_end_matches('/');
        let base = if base.contains("://") {
            base.to_string()
        } else {
            format!("http://{base}")
        };
        Client {
            base,
            http: reqwest::Client::builder()
                .default_headers(headers)
                .timeout(Duration::from_secs(60))
                .build()
                .expect("reqwest client"),
            poll: Duration::from_secs(1),
        }
    }

    async fn send(&self, req: reqwest::RequestBuilder) -> Result<reqwest::Response> {
        let resp = req.send().await.map_err(|e| {
            anyhow!(
                "cannot reach the fleet server at {} ({e}); is Tailscale up?",
                self.base
            )
        })?;
        let status = resp.status();
        if status.is_success() {
            return Ok(resp);
        }
        let text = resp.text().await.unwrap_or_default();
        let msg = serde_json::from_str::<Value>(&text)
            .ok()
            .and_then(|v| v["error"].as_str().map(String::from))
            .unwrap_or(text);
        if status.as_u16() == 403 {
            bail!("not allowed: the server only accepts the owner's tailnet devices ({msg})");
        }
        bail!("server answered {status}: {msg}");
    }

    async fn get<T: DeserializeOwned>(&self, path: &str) -> Result<T> {
        let resp = self
            .send(self.http.get(format!("{}{path}", self.base)))
            .await?;
        resp.json()
            .await
            .with_context(|| format!("decoding response of GET {path}"))
    }

    async fn post(&self, path: &str, body: Value) -> Result<Value> {
        let resp = self
            .send(self.http.post(format!("{}{path}", self.base)).json(&body))
            .await?;
        resp.json()
            .await
            .with_context(|| format!("decoding response of POST {path}"))
    }

    pub async fn snapshot(&self) -> Result<Snapshot> {
        self.get("/api/snapshot").await
    }

    async fn log_text(&self, host: &str, id: &str) -> Result<String> {
        let resp = self
            .send(
                self.http
                    .get(format!("{}/api/hosts/{host}/applies/{id}/log", self.base)),
            )
            .await?;
        Ok(resp.text().await?)
    }
}

fn short(s: &str) -> &str {
    &s[..s.len().min(8)]
}

fn state_str(s: &ApplyState) -> &'static str {
    match s {
        ApplyState::Idle => "idle",
        ApplyState::Running => "running",
        ApplyState::Ok => "ok",
        ApplyState::Skipped => "skipped",
        ApplyState::Failed => "failed",
    }
}

fn is_terminal(s: &ApplyState) -> bool {
    matches!(s, ApplyState::Ok | ApplyState::Skipped | ApplyState::Failed)
}

fn describe(a: &ApplyRecord) -> String {
    let mut s = state_str(&a.state).to_string();
    if let Some(r) = &a.skip_reason {
        s.push_str(&format!(
            " ({})",
            serde_json::to_string(r)
                .unwrap_or_default()
                .trim_matches('"')
        ));
    }
    if let Some(c) = a.exit_code.filter(|c| *c != 0) {
        s.push_str(&format!(" (exit {c})"));
    }
    if let Some(m) = &a.message {
        s.push_str(&format!(": {m}"));
    }
    s
}

fn find_host<'a>(snap: &'a Snapshot, name: &str) -> Result<&'a HostView> {
    snap.hosts
        .iter()
        .find(|h| h.name.eq_ignore_ascii_case(name))
        .ok_or_else(|| {
            let names: Vec<_> = snap.hosts.iter().map(|h| h.name.as_str()).collect();
            anyhow!("unknown host {name} (known: {})", names.join(", "))
        })
}

/// Runs a command, writing results to `out`. Returns the process exit code.
pub async fn run(client: &Client, cmd: Command, out: &mut impl Write) -> Result<i32> {
    match cmd {
        Command::Status => status(client, out).await,
        Command::Rebuild {
            host,
            channel,
            wait,
            timeout,
        } => {
            rebuild(
                client,
                host,
                channel,
                wait,
                Duration::from_secs(timeout),
                out,
            )
            .await
        }
        Command::Log { host, apply_id } => {
            let id = match apply_id {
                Some(id) => id,
                None => {
                    let snap = client.snapshot().await?;
                    let h = find_host(&snap, &host)?;
                    h.last_apply
                        .as_ref()
                        .map(|a| a.apply_id.clone())
                        .ok_or_else(|| anyhow!("{} has no apply yet", h.name))?
                }
            };
            write!(out, "{}", client.log_text(&host, &id).await?)?;
            Ok(0)
        }
        Command::Promote { yes } => promote(client, yes, out).await,
        Command::Audit { limit } => {
            let events: Vec<AuditEvent> = client.get(&format!("/api/audit?limit={limit}")).await?;
            for e in events {
                writeln!(
                    out,
                    "{}  {:<10} {:<18} {}  {}",
                    e.time,
                    e.host.as_deref().unwrap_or("-"),
                    e.kind,
                    e.actor,
                    e.details
                )?;
            }
            Ok(0)
        }
    }
}

async fn status(client: &Client, out: &mut impl Write) -> Result<i32> {
    let snap = client.snapshot().await?;
    let rows: Vec<[String; 7]> = snap
        .hosts
        .iter()
        .map(|h| {
            [
                h.name.clone(),
                h.os.clone(),
                h.channel.clone(),
                match h.online {
                    OnlineState::On => "online",
                    OnlineState::AgentUnreachable => "agent-down",
                    OnlineState::Off => "offline",
                }
                .into(),
                h.running.as_deref().map(short).unwrap_or("-").to_string()
                    + if h.running_dirty { "+dirty" } else { "" },
                h.behind.map_or("-".into(), |b| b.to_string()),
                h.last_apply.as_ref().map_or("-".into(), describe),
            ]
        })
        .collect();
    let head = [
        "HOST",
        "OS",
        "CHANNEL",
        "ONLINE",
        "RUNNING",
        "BEHIND",
        "LAST APPLY",
    ];
    let mut w = head.map(str::len);
    for r in &rows {
        for (i, c) in r.iter().enumerate() {
            w[i] = w[i].max(c.chars().count());
        }
    }
    let line = |cells: Vec<&str>| {
        cells
            .iter()
            .enumerate()
            .map(|(i, c)| format!("{c:<w$}", w = w[i]))
            .collect::<Vec<_>>()
            .join("  ")
    };
    writeln!(out, "{}", line(head.to_vec()).trim_end())?;
    for r in &rows {
        writeln!(
            out,
            "{}",
            line(r.iter().map(String::as_str).collect()).trim_end()
        )?;
    }
    Ok(0)
}

fn agent_note(host: &str, status: &str) -> String {
    match status {
        "202" => format!("{host}: agent started the apply"),
        "200" => format!("{host}: agent had already run this apply"),
        "409" => format!("{host}: agent is busy with another apply; the server will retry"),
        "unreachable" => format!(
            "{host}: agent unreachable; the apply is recorded and the server will re-send it when the host comes online"
        ),
        other => format!("{host}: agent answered {other}"),
    }
}

async fn rebuild(
    client: &Client,
    host: Option<String>,
    channel: Option<String>,
    wait: bool,
    timeout: Duration,
    out: &mut impl Write,
) -> Result<i32> {
    // host name -> apply id
    let mut ids: BTreeMap<String, String> = BTreeMap::new();
    match (host, channel) {
        (Some(h), None) => {
            let r = client
                .post(&format!("/api/hosts/{h}/apply"), json!({}))
                .await?;
            let id = r["apply_id"].as_str().context("response has no apply_id")?;
            let st = r["agent_status"].as_str().unwrap_or("?");
            writeln!(
                out,
                "apply_id {id}\nagent_status {st}\n{}",
                agent_note(&h, st)
            )?;
            ids.insert(h, id.to_string());
        }
        (None, Some(c)) => {
            let r = client
                .post(&format!("/api/channels/{c}/apply"), json!({}))
                .await?;
            let map = r["apply_ids"]
                .as_object()
                .context("response has no apply_ids")?;
            for (h, id) in map {
                let st = r["agent_status"][h].as_str().unwrap_or("?");
                writeln!(
                    out,
                    "{h}: apply_id {} agent_status {st}",
                    id.as_str().unwrap_or("?")
                )?;
                if st == "unreachable" {
                    writeln!(out, "{}", agent_note(h, st))?;
                }
                ids.insert(h.clone(), id.as_str().unwrap_or_default().to_string());
            }
        }
        _ => bail!("give either a host or --channel <name>"),
    }
    if !wait {
        return Ok(0);
    }
    let deadline = Instant::now() + timeout;
    let mut done: BTreeMap<String, ApplyRecord> = BTreeMap::new();
    while done.len() < ids.len() {
        let snap = client.snapshot().await?;
        for (h, id) in &ids {
            if let Some(a) = find_host(&snap, h)?.last_apply.as_ref()
                && &a.apply_id == id
                && is_terminal(&a.state)
            {
                done.insert(h.clone(), a.clone());
            }
        }
        if done.len() == ids.len() {
            break;
        }
        if Instant::now() >= deadline {
            let pending: Vec<_> = ids
                .keys()
                .filter(|h| !done.contains_key(*h))
                .cloned()
                .collect();
            writeln!(out, "timed out waiting for: {}", pending.join(", "))?;
            return Ok(1);
        }
        tokio::time::sleep(client.poll).await;
    }
    let mut code = 0;
    for (h, a) in &done {
        writeln!(out, "{h}: {}", describe(a))?;
        if a.state != ApplyState::Ok {
            code = 1;
        }
        match client.log_text(h, &a.apply_id).await {
            Ok(log) if !log.trim().is_empty() => {
                writeln!(out, "--- log {h} ---\n{}", log.trim_end())?
            }
            Ok(_) => {}
            Err(e) => writeln!(out, "(could not fetch log: {e:#})")?,
        }
    }
    Ok(code)
}

async fn promote(client: &Client, yes: bool, out: &mut impl Write) -> Result<i32> {
    let snap = client.snapshot().await?;
    let Some(commit) = snap.promote_candidate.clone() else {
        writeln!(out, "nothing to promote: stable is up to date")?;
        return Ok(0);
    };
    let subject = snap
        .channels
        .iter()
        .find(|c| c.name == "unstable")
        .and_then(|c| {
            (c.head.as_deref() == Some(&commit))
                .then(|| c.head_subject.clone())
                .flatten()
        });
    writeln!(
        out,
        "promote candidate: {} {}",
        short(&commit),
        subject.unwrap_or_default()
    )?;
    if !yes {
        writeln!(out, "re-run with --yes to move stable to this commit")?;
        return Ok(1);
    }
    client
        .post("/api/promote", json!({ "commit": commit }))
        .await?;
    writeln!(out, "stable promoted to {}", short(&commit))?;
    Ok(0)
}
