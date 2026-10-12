import { describe, expect, it } from "vitest";
import type { ApplyRecord } from "@/bindings/ApplyRecord";
import type { HostView } from "@/bindings/HostView";
import { applyBadge, behindLabel, onlineLabel, shortRev, skipReasonText } from "@/format";

const REV = "0123456789abcdef0123456789abcdef01234567";

function host(over: Partial<HostView>): HostView {
  return {
    name: "hermes",
    os: "nixos",
    channel: "unstable",
    online: "on",
    last_seen: null,
    running: REV,
    running_dirty: false,
    behind: 0,
    checkout: null,
    last_apply: null,
    desired_apply_id: null,
    last_activation: null,
    ...over,
  };
}

function apply(over: Partial<ApplyRecord>): ApplyRecord {
  return {
    apply_id: "a1",
    commit: REV,
    state: "ok",
    skip_reason: null,
    message: null,
    exit_code: null,
    started_at: 100,
    finished_at: 110,
    ...over,
  };
}

describe("shortRev", () => {
  it("keeps 7 characters", () => {
    expect(shortRev(REV)).toBe("0123456");
  });
  it("keeps -dirty", () => {
    expect(shortRev(`${REV}-dirty`)).toBe("0123456-dirty");
  });
  it("leaves short strings alone", () => {
    expect(shortRev("unknown")).toBe("unknown");
  });
});

describe("behindLabel", () => {
  it("up to date", () => expect(behindLabel(0)).toBe("up to date"));
  it("n behind", () => expect(behindLabel(3)).toBe("3 behind"));
  it("unknown", () => expect(behindLabel(null)).toBe("unknown"));
});

describe("onlineLabel", () => {
  const now = 10_000;
  it("off with last seen", () => {
    expect(onlineLabel(host({ online: "off", last_seen: now - 5 * 60 }), now)).toBe(
      "off · last seen 5m ago",
    );
  });
  it("off, last seen hours ago", () => {
    expect(onlineLabel(host({ online: "off", last_seen: now - 2 * 3600 - 30 }), now)).toBe(
      "off · last seen 2h ago",
    );
  });
  it("off, never seen", () => {
    expect(onlineLabel(host({ online: "off", last_seen: null }), now)).toBe("off");
  });
  it("agent unreachable", () => {
    expect(onlineLabel(host({ online: "agent_unreachable" }), now)).toBe("on, agent unreachable");
  });
  it("on", () => {
    expect(onlineLabel(host({ online: "on" }), now)).toBe("on");
  });
});

describe("applyBadge", () => {
  it("no apply yet", () => {
    expect(applyBadge(null)).toEqual({ text: "Never applied", variant: "outline" });
  });
  it("running", () => {
    expect(applyBadge(apply({ state: "running", finished_at: null }))).toEqual({
      text: "Applying",
      variant: "secondary",
    });
  });
  it("ok", () => {
    expect(applyBadge(apply({ state: "ok", exit_code: 0 }))).toEqual({
      text: "Applied",
      variant: "default",
    });
  });
  it("skipped on a dirty checkout", () => {
    expect(applyBadge(apply({ state: "skipped", skip_reason: "dirty" }))).toEqual({
      text: "Skipped: local changes in ~/.flake",
      variant: "outline",
    });
  });
  it("failed build with exit code", () => {
    expect(
      applyBadge(
        apply({ state: "failed", exit_code: 1, message: "nix build failed (exit status: 1)" }),
      ),
    ).toEqual({ text: "Build failed (exit 1)", variant: "destructive" });
  });
  it("failed without exit code", () => {
    expect(applyBadge(apply({ state: "failed", message: "interrupted" }))).toEqual({
      text: "Failed",
      variant: "destructive",
    });
  });
  it("idle", () => {
    expect(applyBadge(apply({ state: "idle" }))).toEqual({ text: "Idle", variant: "outline" });
  });
});

describe("skipReasonText", () => {
  it("has a distinct phrase for every reason", () => {
    const reasons = [
      "fetch_failed",
      "commit_not_found",
      "commit_not_on_channel",
      "wrong_branch",
      "dirty",
      "not_fast_forward",
    ] as const;
    const texts = reasons.map(skipReasonText);
    for (const t of texts) expect(t).toMatch(/^[a-z~].{8,}$/);
    expect(new Set(texts).size).toBe(reasons.length);
    expect(skipReasonText("dirty")).toBe("local changes in ~/.flake");
  });
});
