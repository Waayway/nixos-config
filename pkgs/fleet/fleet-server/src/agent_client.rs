//! HTTP client for the fleet agent API.
//!
//! `addr` is the agent's `host:port` (see `poller::agent_base`).

use std::time::Duration;

use anyhow::Context;
use fleet_proto::{ActivationsResponse, AgentStatus, ApplyRequest, LogChunk};
use reqwest::StatusCode;
use serde::de::DeserializeOwned;

const TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Clone)]
pub struct AgentClient {
    http: reqwest::Client,
}

impl AgentClient {
    pub fn new() -> anyhow::Result<Self> {
        let http = reqwest::Client::builder()
            .timeout(TIMEOUT)
            .build()
            .context("building HTTP client")?;
        Ok(Self { http })
    }

    async fn get_json<T: DeserializeOwned>(
        &self,
        addr: &str,
        path: &str,
        query: &[(&str, &str)],
    ) -> anyhow::Result<T> {
        let url = format!("http://{addr}{path}");
        let resp = self
            .http
            .get(&url)
            .query(query)
            .send()
            .await
            .with_context(|| format!("GET {url}"))?
            .error_for_status()?;
        resp.json().await.with_context(|| format!("decoding {url}"))
    }

    pub async fn status(&self, addr: &str) -> anyhow::Result<AgentStatus> {
        self.get_json(addr, "/status", &[]).await
    }

    /// `202` started, `200` already ran, `409` busy, `400` bad request.
    pub async fn apply(&self, addr: &str, req: &ApplyRequest) -> anyhow::Result<StatusCode> {
        let url = format!("http://{addr}/apply");
        let resp = self
            .http
            .post(&url)
            .json(req)
            .send()
            .await
            .with_context(|| format!("POST {url}"))?;
        Ok(resp.status())
    }

    pub async fn log(&self, addr: &str, apply_id: &str, offset: u64) -> anyhow::Result<LogChunk> {
        let offset = offset.to_string();
        self.get_json(
            addr,
            "/apply/log",
            &[("apply_id", apply_id), ("offset", &offset)],
        )
        .await
    }

    pub async fn activations(&self, addr: &str, since: u64) -> anyhow::Result<ActivationsResponse> {
        let since = since.to_string();
        self.get_json(addr, "/activations", &[("since", &since)])
            .await
    }
}
