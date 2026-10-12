// Labels for the dashboard. Pure functions over the generated bindings; times are unix seconds.
import type { ApplyRecord } from "@/bindings/ApplyRecord";
import type { HostView } from "@/bindings/HostView";
import type { SkipReason } from "@/bindings/SkipReason";

/** First 7 characters of a revision, keeping a `-dirty` suffix. */
export function shortRev(rev: string): string {
  const dirty = rev.endsWith("-dirty");
  const base = dirty ? rev.slice(0, -"-dirty".length) : rev;
  return base.slice(0, 7) + (dirty ? "-dirty" : "");
}

export function behindLabel(n: number | null): string {
  if (n === null) return "unknown";
  return n === 0 ? "up to date" : `${n} behind`;
}

/** "5m ago", "2h ago", "3d ago"; "just now" under a minute. */
export function ago(time: number, now: number): string {
  const s = Math.max(0, now - time);
  if (s < 60) return "just now";
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return `${Math.floor(s / 86400)}d ago`;
}

export function onlineLabel(h: HostView, now: number): string {
  switch (h.online) {
    case "on":
      return "on";
    case "agent_unreachable":
      return "on, agent unreachable";
    case "off":
      return h.last_seen === null ? "off" : `off · last seen ${ago(h.last_seen, now)}`;
  }
}

/** Why an apply was skipped, as a phrase that follows "Skipped: ". */
export function skipReasonText(r: SkipReason): string {
  switch (r) {
    case "fetch_failed":
      return "git fetch failed on the host";
    case "commit_not_found":
      return "commit not found after fetching";
    case "commit_not_on_channel":
      return "commit is not on this host's channel";
    case "wrong_branch":
      return "~/.flake is on a different branch";
    case "dirty":
      return "local changes in ~/.flake";
    case "not_fast_forward":
      return "~/.flake has commits that are not on the channel";
  }
}

export type BadgeVariant = "default" | "secondary" | "destructive" | "outline";

export function applyBadge(a: ApplyRecord | null): { text: string; variant: BadgeVariant } {
  if (a === null) return { text: "Never applied", variant: "outline" };
  switch (a.state) {
    case "idle":
      return { text: "Idle", variant: "outline" };
    case "running":
      return { text: "Applying", variant: "secondary" };
    case "ok":
      return { text: "Applied", variant: "default" };
    case "skipped":
      return {
        text: a.skip_reason ? `Skipped: ${skipReasonText(a.skip_reason)}` : "Skipped",
        variant: "outline",
      };
    case "failed": {
      const what = a.message && /\bbuild\b/i.test(a.message) ? "Build failed" : "Failed";
      const code = a.exit_code !== null && a.exit_code !== 0 ? ` (exit ${a.exit_code})` : "";
      return { text: what + code, variant: "destructive" };
    }
  }
}

/** Semantic tone of a host row: drives the status stripe and badge colours. */
export type Tone = "ok" | "running" | "skipped" | "failed" | "off" | "warn" | "idle";

export function applyTone(a: ApplyRecord | null): Tone {
  if (a === null) return "idle";
  switch (a.state) {
    case "ok":
      return "ok";
    case "running":
      return "running";
    case "skipped":
      return "skipped";
    case "failed":
      return "failed";
    case "idle":
      return "idle";
  }
}

/** The one tone that best describes the host: an off machine or a broken apply wins. */
export function hostTone(h: HostView): Tone {
  if (h.online === "off") return "off";
  const t = applyTone(h.last_apply);
  if (t === "running" || t === "failed" || t === "skipped") return t;
  if (h.online === "agent_unreachable") return "warn";
  return h.behind === 0 ? "ok" : "idle";
}

/** "45s" or "2m 05s": how long an apply ran (or has been running). */
export function durationLabel(start: number | null, end: number | null, now: number): string {
  if (start === null) return "";
  const s = Math.max(0, (end ?? now) - start);
  if (s < 60) return `${s}s`;
  return `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s`;
}
