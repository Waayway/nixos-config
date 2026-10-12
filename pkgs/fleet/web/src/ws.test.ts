import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { BACKOFF_START_MS, connectFeed, type FeedStatus, nextBackoff } from "@/ws";

describe("nextBackoff", () => {
  it("doubles from 1 s and stops at 30 s", () => {
    const seq = [BACKOFF_START_MS];
    while (seq.length < 7) seq.push(nextBackoff(seq[seq.length - 1]));
    expect(seq).toEqual([1000, 2000, 4000, 8000, 16000, 30000, 30000]);
  });
});

/** A WebSocket that never connects: each instance is closed by the test. */
class FakeSocket {
  static all: FakeSocket[] = [];
  onopen: (() => void) | null = null;
  onclose: (() => void) | null = null;
  onmessage: ((e: { data: unknown }) => void) | null = null;
  onerror: (() => void) | null = null;
  constructor(readonly url: string) {
    FakeSocket.all.push(this);
  }
  close() {}
}

describe("connectFeed access check", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    FakeSocket.all = [];
    vi.stubGlobal("WebSocket", FakeSocket);
    vi.stubGlobal("location", { protocol: "http:", host: "fleet.test" });
  });
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  async function firstCloseWith(forbidden: boolean) {
    const statuses: FeedStatus["kind"][] = [];
    const isForbidden = vi.fn(async () => forbidden);
    const stop = connectFeed({ onMessage: () => {}, onStatus: (s) => statuses.push(s.kind), isForbidden });
    await FakeSocket.all[0].onclose!();
    await vi.advanceTimersByTimeAsync(BACKOFF_START_MS);
    return { statuses, isForbidden, stop };
  }

  it("stops reconnecting when the viewer is forbidden", async () => {
    const { statuses, isForbidden } = await firstCloseWith(true);
    expect(isForbidden).toHaveBeenCalledTimes(1);
    expect(statuses).toEqual(["connecting", "forbidden"]);
    expect(FakeSocket.all).toHaveLength(1);
  });

  it("asks only once, then keeps retrying with backoff", async () => {
    const { statuses, isForbidden, stop } = await firstCloseWith(false);
    expect(statuses).toEqual(["connecting", "waiting", "connecting"]);
    expect(FakeSocket.all).toHaveLength(2);
    await FakeSocket.all[1].onclose!();
    expect(isForbidden).toHaveBeenCalledTimes(1);
    stop();
  });
});
