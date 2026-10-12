//! `GET /api/ws`: a full `Snapshot` first, then every broadcast `WsMessage`. A client that
//! falls behind the broadcast buffer gets a fresh `Snapshot` instead of the missed messages.
//! Messages from the client are ignored; the socket only carries server -> browser updates.

use axum::Extension;
use axum::extract::State;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::response::Response;
use fleet_proto::WsMessage;
use futures::SinkExt;
use tokio::sync::broadcast::error::RecvError;

use crate::access::Actor;
use crate::state::{AppState, snapshot};

pub async fn handler(
    State(state): State<AppState>,
    Extension(Actor(viewer)): Extension<Actor>,
    ws: WebSocketUpgrade,
) -> Response {
    ws.on_upgrade(move |socket| run(state, viewer, socket))
}

async fn send(socket: &mut WebSocket, msg: &WsMessage) -> bool {
    let Ok(text) = serde_json::to_string(msg) else {
        return false;
    };
    socket.send(Message::Text(text.into())).await.is_ok()
}

async fn send_snapshot(socket: &mut WebSocket, state: &AppState, viewer: &str) -> bool {
    let snap = snapshot(state, viewer.to_string()).await;
    send(socket, &WsMessage::Snapshot(snap)).await
}

async fn run(state: AppState, viewer: String, mut socket: WebSocket) {
    // Subscribe before building the snapshot so no update in between is lost.
    let mut rx = state.tx.subscribe();
    if !send_snapshot(&mut socket, &state, &viewer).await {
        return;
    }
    loop {
        tokio::select! {
            msg = rx.recv() => {
                let ok = match msg {
                    Ok(m) => send(&mut socket, &m).await,
                    Err(RecvError::Lagged(_)) => send_snapshot(&mut socket, &state, &viewer).await,
                    Err(RecvError::Closed) => false,
                };
                if !ok {
                    break;
                }
            }
            incoming = socket.recv() => match incoming {
                None | Some(Err(_)) | Some(Ok(Message::Close(_))) => break,
                Some(Ok(_)) => {}
            },
        }
    }
    // Completes the close handshake (or closes from our side); errors mean it's gone already.
    let _ = socket.close().await;
}
