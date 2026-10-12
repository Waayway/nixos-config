import { describe, expect, it } from "vitest";
import { fromText, mergeChunk } from "@/applyLog";

const chunk = (offset: number, data: string, eof = false) => ({ apply_id: "a", offset, data, eof });

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
  it("reports a gap when a chunk starts past the end", () => {
    expect(mergeChunk(fromText("hello\n"), chunk(20, "later\n"))).toEqual({ kind: "gap" });
    expect(mergeChunk(undefined, chunk(5, "x"))).toEqual({ kind: "gap" });
  });
});
