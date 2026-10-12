import { describe, expect, it } from "vitest";
import { finishFetch, fromText, mergeChunk, requestFetch, watchLog } from "@/applyLog";
import type { ApplyRecord } from "@/bindings/ApplyRecord";
import type { HostView } from "@/bindings/HostView";
import type { WsMessage } from "@/bindings/WsMessage";

const enc = new TextEncoder();
/** A chunk of valid UTF-8: `next` is `offset` plus the bytes of `data`. */
const chunk = (offset: number, data: string, eof = false) => ({
  apply_id: "a",
  offset,
  data,
  next: offset + enc.encode(data).length,
  eof,
});

describe("mergeChunk", () => {
  it("starts a log from offset 0", () => {
    expect(mergeChunk(undefined, chunk(0, "hello\n"))).toEqual({
      kind: "appended",
      log: { text: "hello\n", bytes: 6 },
    });
  });
  it("appends at the current byte length, counting UTF-8 bytes", () => {
    const held = fromText("→ build\n"); // the arrow is 3 bytes
    expect(held.bytes).toBe(10);
    const m = mergeChunk(held, chunk(10, "done\n", true));
    expect(m).toEqual({ kind: "appended", log: { text: "→ build\ndone\n", bytes: 15 } });
  });
  it("ignores a resent chunk from a restarted follower", () => {
    expect(mergeChunk(fromText("hello\n"), chunk(0, "hello\n"))).toEqual({ kind: "duplicate" });
  });
  it("appends only the new tail of a chunk that overlaps the held log", () => {
    // The full log was fetched mid-chunk: the follower's next chunk starts before its end.
    const held = fromText("ab→c"); // 6 bytes
    expect(mergeChunk(held, chunk(2, "→cdé\n", true))).toEqual({
      kind: "appended",
      log: { text: "ab→cdé\n", bytes: 10 },
    });
  });
  it("continues at the agent's `next` after invalid UTF-8 in a chunk", () => {
    // Log bytes "a\xffb\n": 4 bytes, sent as "a\uFFFDb\n" (6 bytes of text).
    const first = { apply_id: "a", offset: 0, data: "a\uFFFDb\n", next: 4, eof: false };
    const m = mergeChunk(undefined, first);
    expect(m).toEqual({ kind: "appended", log: { text: "a\uFFFDb\n", bytes: 4 } });
    if (m.kind !== "appended") throw new Error("unreachable");
    // The next chunk starts at byte 4: no gap, appended in full.
    expect(mergeChunk(m.log, chunk(4, "more\n", true))).toEqual({
      kind: "appended",
      log: { text: "a\uFFFDb\nmore\n", bytes: 9 },
    });
    // A resend of the first chunk is a duplicate.
    expect(mergeChunk(m.log, first)).toEqual({ kind: "duplicate" });
  });
  it("reports a gap when a chunk starts past the end", () => {
    expect(mergeChunk(fromText("hello\n"), chunk(20, "later\n"))).toEqual({ kind: "gap" });
    expect(mergeChunk(undefined, chunk(5, "x"))).toEqual({ kind: "gap" });
  });
});

describe("watchLog", () => {
  const open = (running: boolean | null) => ({ host: "hermes", applyId: "a1", running });
  const rec = (apply_id: string, state: ApplyRecord["state"]): ApplyRecord => ({
    apply_id,
    commit: "c".repeat(40),
    state,
    skip_reason: null,
    message: null,
    exit_code: null,
    started_at: 1,
    finished_at: null,
  });
  const hostMsg = (name: string, last_apply: ApplyRecord | null): WsMessage => ({
    type: "host_updated",
    data: {
      name,
      os: "nixos",
      channel: "unstable",
      online: "on",
      last_seen: null,
      running: null,
      running_dirty: false,
      behind: null,
      checkout: null,
      last_apply,
      desired_apply_id: null,
      last_activation: null,
    },
  });
  const snapshotMsg = (last_apply: ApplyRecord | null): WsMessage => ({
    type: "snapshot",
    data: {
      hosts: [(hostMsg("hermes", last_apply).data as HostView)],
      channels: [],
      promote_candidate: null,
      viewer: "v",
      demo: false,
    },
  });

  it("refetches on every snapshot (reconnect or lagged client)", () => {
    expect(watchLog(open(true), snapshotMsg(rec("a1", "running")))).toEqual({ refetch: true, running: true });
    expect(watchLog(open(true), snapshotMsg(rec("a1", "ok")))).toEqual({ refetch: true, running: false });
  });
  it("refetches when the open apply stops running", () => {
    expect(watchLog(open(true), hostMsg("hermes", rec("a1", "failed")))).toEqual({ refetch: true, running: false });
  });
  it("refetches when a newer apply replaced a running one", () => {
    expect(watchLog(open(true), hostMsg("hermes", rec("a2", "running")))).toEqual({ refetch: true, running: false });
  });
  it("does nothing while it keeps running, for an apply already finished, or for other hosts", () => {
    expect(watchLog(open(true), hostMsg("hermes", rec("a1", "running")))).toEqual({ refetch: false, running: true });
    expect(watchLog(open(false), hostMsg("hermes", rec("a1", "ok")))).toEqual({ refetch: false, running: false });
    expect(watchLog(open(true), hostMsg("atlas", rec("a1", "ok")))).toEqual({ refetch: false, running: true });
    expect(watchLog(open(true), { type: "channels_updated", data: [] })).toEqual({ refetch: false, running: true });
  });
});

describe("requestFetch / finishFetch", () => {
  it("starts a request when none is in flight", () => {
    expect(requestFetch({ fetching: false, again: false })).toEqual({ start: true, next: { fetching: true, again: false } });
  });
  it("never starts a second one; runs it once after the first finishes", () => {
    const r = requestFetch({ fetching: true, again: false });
    expect(r).toEqual({ start: false, next: { fetching: true, again: true } });
    expect(requestFetch(r.next).start).toBe(false);
    expect(finishFetch(r.next)).toEqual({ start: true, next: { fetching: true, again: false } });
    expect(finishFetch({ fetching: true, again: false })).toEqual({ start: false, next: { fetching: false, again: false } });
  });
});
