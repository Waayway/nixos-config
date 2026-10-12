//! Dashboard access control: only the owner's Tailscale identities get in.

use std::net::SocketAddr;
use std::sync::Arc;

use axum::{
    extract::{ConnectInfo, Request, State},
    http::StatusCode,
    middleware::Next,
    response::{IntoResponse, Response},
};

use crate::config::AccessConfig;
use crate::tailscale::{Identity, OnlineProvider};

#[derive(Debug, PartialEq)]
pub enum Access {
    Allowed { actor: String },
    Denied,
}

/// Who performed a request; inserted as a request extension for handlers.
#[derive(Clone, Debug, PartialEq)]
pub struct Actor(pub String);

pub fn decide(cfg: &AccessConfig, id: Option<&Identity>) -> Access {
    let (allowed_users, allowed_tags) = match cfg {
        AccessConfig::Disabled => {
            return Access::Allowed {
                actor: "dev".into(),
            };
        }
        AccessConfig::Tailscale {
            allowed_users,
            allowed_tags,
        } => (allowed_users, allowed_tags),
    };
    let Some(id) = id else { return Access::Denied };
    let user_ok = id.login.as_ref().is_some_and(|l| allowed_users.contains(l));
    let tag_ok = id.tags.iter().any(|t| allowed_tags.contains(t));
    if user_ok || tag_ok {
        Access::Allowed {
            actor: id.login.clone().unwrap_or_else(|| id.node.clone()),
        }
    } else {
        Access::Denied
    }
}

#[derive(Clone)]
pub struct AccessState {
    pub provider: Arc<dyn OnlineProvider>,
    pub cfg: Arc<AccessConfig>,
}

/// Middleware: whois the peer, 403 unless allowed. Needs
/// `into_make_service_with_connect_info::<SocketAddr>()` on the server.
pub async fn require_access(
    State(state): State<AccessState>,
    ConnectInfo(peer): ConnectInfo<SocketAddr>,
    mut req: Request,
    next: Next,
) -> Response {
    let identity = match *state.cfg {
        AccessConfig::Disabled => None,
        AccessConfig::Tailscale { .. } => state.provider.whois(peer.ip().to_canonical()).await,
    };
    match decide(&state.cfg, identity.as_ref()) {
        Access::Allowed { actor } => {
            req.extensions_mut().insert(Actor(actor));
            next.run(req).await
        }
        Access::Denied => (StatusCode::FORBIDDEN, "forbidden").into_response(),
    }
}
