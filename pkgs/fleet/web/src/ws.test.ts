import { describe, expect, it } from "vitest";
import { BACKOFF_START_MS, nextBackoff } from "@/ws";

describe("nextBackoff", () => {
  it("doubles from 1 s and stops at 30 s", () => {
    const seq = [BACKOFF_START_MS];
    while (seq.length < 7) seq.push(nextBackoff(seq[seq.length - 1]));
    expect(seq).toEqual([1000, 2000, 4000, 8000, 16000, 30000, 30000]);
  });
});
