// Apply logs as the dashboard holds them. Offsets in `LogChunk` count UTF-8 bytes of the log.
// A server-side log follower can restart and resend from offset 0, and the full log fetched
// when the sheet opens can end in the middle of the follower's next chunk. So a chunk is
// merged by bytes: what the held log already has is dropped, only bytes past its end are
// appended. A chunk that starts past the end means something was missed and the whole log has
// to be fetched again.
import type { LogChunk } from "@/bindings/LogChunk";

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
  const data = encoder.encode(c.data);
  const skip = bytes - c.offset;
  if (skip >= data.length) return { kind: "duplicate" };
  // Both offsets count bytes of the same log, so `skip` falls on a character boundary.
  const tail = skip === 0 ? c.data : decoder.decode(data.subarray(skip));
  return {
    kind: "appended",
    log: { text: (held?.text ?? "") + tail, bytes: bytes + data.length - skip },
  };
}
