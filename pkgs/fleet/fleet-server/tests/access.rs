use std::collections::HashMap;
use std::net::{IpAddr, SocketAddr};
use std::sync::Arc;

use axum::{
    Router,
    body::Body,
    extract::connect_info::MockConnectInfo,
    http::{Request, StatusCode},
    middleware,
    routing::get,
};
use fleet_server::access::{Access, AccessState, decide, require_access};
use fleet_server::config::AccessConfig;
use fleet_server::tailscale::{Identity, OnlineProvider, PeerInfo, parse_status, parse_whois};
use tower::ServiceExt;

fn cfg() -> AccessConfig {
    AccessConfig::Tailscale {
        allowed_users: vec!["Waayway@github".into()],
        allowed_tags: vec![
            "tag:nixos".into(),
            "tag:personal".into(),
            "tag:fleet".into(),
        ],
    }
}

fn whois(name: &str) -> Identity {
    parse_whois(&std::fs::read_to_string(format!("tests/fixtures/{name}")).unwrap()).unwrap()
}

#[test]
fn parse_status_fixture() {
    let peers = parse_status(include_str!("fixtures/status.json")).unwrap();
    assert_eq!(peers.len(), 4);
    let me = &peers["nixos-manager"];
    assert!(me.online);
    assert_eq!(me.addr, Some("100.64.0.1".parse::<IpAddr>().unwrap()));
    let laptop = &peers["laptop"];
    assert_eq!(laptop.host, "laptop");
    assert!(laptop.online);
    assert_eq!(laptop.os, "macOS");
    assert_eq!(laptop.addr, Some("100.64.0.2".parse::<IpAddr>().unwrap()));
    assert_eq!(laptop.last_seen, Some(1_791_792_000));
    let desktop = &peers["desktop"];
    assert!(!desktop.online);
    assert_eq!(desktop.last_seen, Some(1_791_750_600));
    let ghost = &peers["ghost"];
    assert_eq!(ghost.last_seen, None);
    assert_eq!(
        ghost.addr,
        Some("fd7a:115c:a1e0::4".parse::<IpAddr>().unwrap())
    );
}

#[test]
fn user_login_allowed() {
    let id = whois("whois-user.json");
    assert_eq!(id.login.as_deref(), Some("Waayway@github"));
    assert_eq!(id.node, "laptop");
    assert_eq!(
        decide(&cfg(), Some(&id)),
        Access::Allowed {
            actor: "Waayway@github".into()
        }
    );
}

#[test]
fn tagged_nixos_allowed() {
    let id = whois("whois-tagged.json");
    assert_eq!(id.login, None);
    assert_eq!(id.tags, vec!["tag:nixos".to_string()]);
    assert_eq!(
        decide(&cfg(), Some(&id)),
        Access::Allowed {
            actor: "nixos-box".into()
        }
    );
}

#[test]
fn tagged_other_denied() {
    let id = Identity {
        login: None,
        tags: vec!["tag:server".into()],
        node: "web".into(),
    };
    assert_eq!(decide(&cfg(), Some(&id)), Access::Denied);
    let stranger = Identity {
        login: Some("eve@example.com".into()),
        tags: vec![],
        node: "x".into(),
    };
    assert_eq!(decide(&cfg(), Some(&stranger)), Access::Denied);
}

#[test]
fn no_identity_denied() {
    assert_eq!(decide(&cfg(), None), Access::Denied);
}

#[test]
fn disabled_allows() {
    assert_eq!(
        decide(&AccessConfig::Disabled, None),
        Access::Allowed {
            actor: "dev".into()
        }
    );
}

struct Fake(Option<Identity>);

#[async_trait::async_trait]
impl OnlineProvider for Fake {
    async fn peers(&self) -> HashMap<String, PeerInfo> {
        HashMap::new()
    }
    async fn whois(&self, _ip: IpAddr) -> Option<Identity> {
        self.0.clone()
    }
}

fn app(provider: Fake, access: AccessConfig) -> Router {
    let provider: Arc<dyn OnlineProvider> = Arc::new(provider);
    Router::new()
        .route("/api/snapshot", get(|| async { "ok" }))
        .route("/api/ws", get(|| async { "ok" }))
        .layer(middleware::from_fn_with_state(
            AccessState {
                provider,
                cfg: Arc::new(access),
            },
            require_access,
        ))
        .layer(MockConnectInfo(SocketAddr::from(([100, 64, 0, 9], 1234))))
}

async fn status(app: Router, path: &str) -> StatusCode {
    app.oneshot(Request::get(path).body(Body::empty()).unwrap())
        .await
        .unwrap()
        .status()
}

#[tokio::test]
async fn middleware_403() {
    let foreign = Identity {
        login: Some("eve@example.com".into()),
        tags: vec![],
        node: "evil".into(),
    };
    for path in ["/api/snapshot", "/api/ws"] {
        assert_eq!(
            status(app(Fake(Some(foreign.clone())), cfg()), path).await,
            StatusCode::FORBIDDEN
        );
        assert_eq!(
            status(app(Fake(None), cfg()), path).await,
            StatusCode::FORBIDDEN
        );
    }
    let owner = whois("whois-user.json");
    assert_eq!(
        status(app(Fake(Some(owner)), cfg()), "/api/snapshot").await,
        StatusCode::OK
    );
    assert_eq!(
        status(app(Fake(None), AccessConfig::Disabled), "/api/ws").await,
        StatusCode::OK
    );
}
