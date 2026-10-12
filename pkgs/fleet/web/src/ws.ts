// The server -> browser feed on `/api/ws`. The server sends a full `Snapshot` first (and again
// when this client fell behind), so after every reconnect the state is replaced, not patched.
// Reconnects with backoff: 1 s, doubling up to 30 s, back to 1 s once a connection opens.
// A browser can't see the status of a refused upgrade, so when the very first connection
// closes without opening, `isForbidden` is asked once (it makes a plain HTTP request); if the
// viewer is not allowed (403), the feed stops instead of retrying forever.
import type { WsMessage } from "@/bindings/WsMessage";

export type FeedStatus =
  | { kind: "connecting" }
  | { kind: "live" }
  | { kind: "waiting"; retryAt: number } // ms since epoch
  | { kind: "forbidden" }; // the server refused this viewer; no more reconnects

export const BACKOFF_START_MS = 1000;
export const BACKOFF_MAX_MS = 30_000;

export function nextBackoff(ms: number): number {
  return Math.min(ms * 2, BACKOFF_MAX_MS);
}

export function connectFeed(handlers: {
  onMessage: (m: WsMessage) => void;
  onStatus: (s: FeedStatus) => void;
  isForbidden?: () => Promise<boolean>;
}): () => void {
  let socket: WebSocket | null = null;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let backoff = BACKOFF_START_MS;
  let closed = false;
  let opened = false;
  let accessChecked = false;

  const url = `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/api/ws`;

  function open() {
    handlers.onStatus({ kind: "connecting" });
    const ws = new WebSocket(url);
    socket = ws;
    ws.onopen = () => {
      opened = true;
      backoff = BACKOFF_START_MS;
      handlers.onStatus({ kind: "live" });
    };
    ws.onmessage = (ev) => {
      if (typeof ev.data !== "string") return;
      let msg: WsMessage;
      try {
        msg = JSON.parse(ev.data) as WsMessage;
      } catch {
        return;
      }
      handlers.onMessage(msg);
    };
    ws.onclose = async () => {
      if (socket !== ws || closed) return;
      socket = null;
      if (!opened && !accessChecked && handlers.isForbidden) {
        accessChecked = true;
        const forbidden = await handlers.isForbidden().catch(() => false);
        if (closed) return;
        if (forbidden) {
          closed = true;
          handlers.onStatus({ kind: "forbidden" });
          return;
        }
      }
      const wait = backoff;
      backoff = nextBackoff(backoff);
      handlers.onStatus({ kind: "waiting", retryAt: Date.now() + wait });
      timer = setTimeout(open, wait);
    };
    // An error is always followed by close; reconnecting is handled there.
    ws.onerror = () => {};
  }

  open();
  return () => {
    closed = true;
    if (timer) clearTimeout(timer);
    socket?.close();
    socket = null;
  };
}
