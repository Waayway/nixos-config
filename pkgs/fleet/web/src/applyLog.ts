// Apply logs as the dashboard holds them. Offsets in `LogChunk` (`offset`, `next`) count bytes
// of the log.
// A server-side log follower can restart and resend from offset 0, and the full log fetched
// when the sheet opens can end in the middle of the follower's next chunk. So a chunk is
// merged by bytes: what the held log already has is dropped, only bytes past its end are
// appended. A chunk that starts past the end means something was missed and the whole log has
// to be fetched again.
import type { LogChunk } from "@/bindings/LogChunk";
import type { WsMessage } from "@/bindings/WsMessage";

export type HeldLog = { text: string; bytes: number };

export type Merge = { kind: "appended"; log: HeldLog } | { kind: "duplicate" } | { kind: "gap" };

const encoder = new TextEncoder();
const decoder = new TextDecoder();

export function byteLength(s: string): number {
  return encoder.encode(s).length;
}

export function fromText(text: string): HeldLog {
  return { text, bytes: byteLength(text) };
}

export function mergeChunk(held: HeldLog | undefined, c: LogChunk): Merge {
  const bytes = held?.bytes ?? 0;
  if (c.offset > bytes) return { kind: "gap" };
  // `next` is the agent's byte count; `data` can be longer when invalid UTF-8 was replaced.
  if (c.next <= bytes) return { kind: "duplicate" };
  const skip = bytes - c.offset;
  // Both offsets count bytes of the same log, so `skip` falls on a character boundary (exact
  // unless the overlapped part held replaced bytes).
  const tail = skip === 0 ? c.data : decoder.decode(encoder.encode(c.data).subarray(skip));
  return {
    kind: "appended",
    log: { text: (held?.text ?? "") + tail, bytes: c.next },
  };
}

/** What the dashboard knows about the apply whose log is open. */
export type LogWatch = { host: string; applyId: string; running: boolean | null };

/**
 * Whether a feed message means the open log must be fetched again, and the apply's running
 * state afterwards. Live chunks alone can't be trusted to complete the log: after a reconnect
 * or a lagged client (both answered with a `snapshot`) the remaining chunks, eof included, may
 * never arrive, and with no later chunk there is no gap to notice. So refetch on every
 * snapshot, and when the apply is seen to stop running.
 */
export function watchLog(open: LogWatch, m: WsMessage): { refetch: boolean; running: boolean | null } {
  const unchanged = { refetch: false, running: open.running };
  if (m.type === "snapshot") {
    const rec = m.data.hosts.find((h) => h.name === open.host)?.last_apply;
    return { refetch: true, running: rec?.apply_id === open.applyId ? rec.state === "running" : open.running };
  }
  if (m.type !== "host_updated" || m.data.name !== open.host) return unchanged;
  const rec = m.data.last_apply;
  // A newer apply on the host means this one has ended, whether or not we saw it end.
  const running = rec?.apply_id === open.applyId ? rec.state === "running" : rec ? false : open.running;
  return { refetch: open.running === true && running === false, running };
}

/** At most one log request at a time: a request asked for meanwhile runs once it finishes. */
export type FetchState = { fetching: boolean; again: boolean };

export function requestFetch(s: FetchState): { start: boolean; next: FetchState } {
  return s.fetching
    ? { start: false, next: { fetching: true, again: true } }
    : { start: true, next: { fetching: true, again: false } };
}

/** After a request finished: whether to start the one asked for while it ran. */
export function finishFetch(s: FetchState): { start: boolean; next: FetchState } {
  return s.again
    ? { start: true, next: { fetching: true, again: false } }
    : { start: false, next: { fetching: false, again: false } };
}
