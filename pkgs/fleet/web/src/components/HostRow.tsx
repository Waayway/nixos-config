import { useState } from "preact/hooks";
import type { ComponentChildren } from "preact";
import { FileTextIcon, LoaderIcon } from "lucide-react";
import { toast } from "sonner";
import { agentStatusText, applyHost } from "@/api";
import type { ActivationEvent } from "@/bindings/ActivationEvent";
import type { ApplyRecord } from "@/bindings/ApplyRecord";
import type { CheckoutStatus } from "@/bindings/CheckoutStatus";
import type { HostView } from "@/bindings/HostView";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { TableCell, TableRow } from "@/components/ui/table";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import {
  ago,
  applyBadge,
  applyTone,
  behindLabel,
  durationLabel,
  hostTone,
  onlineLabel,
  shortRev,
  type Tone,
} from "@/format";
import { cn } from "@/lib/utils";

/** Left edge of a row: one glance down the table shows which hosts need attention. */
const stripe: Record<Tone, string> = {
  ok: "shadow-[inset_3px_0_0_var(--ok)]",
  running: "shadow-[inset_3px_0_0_var(--running)]",
  skipped: "shadow-[inset_3px_0_0_var(--skipped)]",
  failed: "shadow-[inset_3px_0_0_var(--failed)]",
  warn: "shadow-[inset_3px_0_0_var(--warn)]",
  off: "shadow-[inset_3px_0_0_var(--off)]",
  idle: "shadow-[inset_3px_0_0_var(--border)]",
};

const badgeTone: Record<Tone, string> = {
  ok: "border-ok/30 bg-ok/12 text-ok",
  running: "border-running/30 bg-running/12 text-running",
  skipped: "border-skipped/40 bg-skipped/14 text-foreground",
  failed: "border-failed/30 bg-failed/12 text-failed dark:bg-failed/15",
  warn: "border-warn/30 bg-warn/12 text-warn",
  off: "",
  idle: "text-muted-foreground",
};

export function ApplyBadge({ apply }: { apply: ApplyRecord | null }) {
  const b = applyBadge(apply);
  const tone = applyTone(apply);
  return (
    <Badge variant={b.variant} className={cn("max-w-full rounded-md", badgeTone[tone])}>
      {tone === "running" && <LoaderIcon className="animate-spin" />}
      <span className="truncate">{b.text}</span>
    </Badge>
  );
}

const onlineDot: Record<HostView["online"], string> = {
  on: "bg-ok",
  agent_unreachable: "bg-warn",
  off: "bg-off/60 ring-1 ring-off",
};

const stripDirty = (rev: string) => rev.replace(/-dirty$/, "");

export function HostRow({
  host: h,
  now,
  onShowLog,
  onError,
}: {
  host: HostView;
  now: number;
  onShowLog: (host: string, applyId: string) => void;
  onError: (what: string, e: unknown) => void;
}) {
  const [sending, setSending] = useState(false);
  const tone = hostTone(h);
  const applying = h.last_apply?.state === "running";
  // The server re-sends a desired apply the agent never got once the host answers again.
  // While the host is on, a fresh press is simply in flight; that isn't worth a line.
  const queued =
    h.online !== "on" &&
    h.desired_apply_id !== null &&
    h.last_apply?.apply_id !== h.desired_apply_id;

  async function apply() {
    setSending(true);
    try {
      const r = await applyHost(h.name);
      const note = agentStatusText(h.name, r.agent_status);
      if (note) toast.warning(note);
      else toast.success(`Apply started on ${h.name}`);
    } catch (e) {
      onError(`Apply on ${h.name} failed`, e);
    } finally {
      setSending(false);
    }
  }

  return (
    <TableRow className={cn("align-top", stripe[tone])} data-tone={tone}>
      <TableCell className="py-3 pl-5">
        <div className="font-mono text-[13px] font-semibold">{h.name}</div>
        <Sub>
          {h.os} · <span className="font-mono">{h.channel}</span>
        </Sub>
      </TableCell>

      <TableCell className="py-3">
        {h.running === null ? (
          <span className="text-muted-foreground">unknown</span>
        ) : (
          <div className="flex items-center gap-1.5">
            <span className="font-mono text-[13px]">{shortRev(stripDirty(h.running))}</span>
            {h.running_dirty && (
              <Badge variant="outline" className="border-skipped/50 text-foreground rounded-sm px-1 py-0 text-[10px]">
                dirty
              </Badge>
            )}
          </div>
        )}
        <Sub className={cn(h.behind !== null && h.behind > 0 && "text-warn font-medium")}>
          {behindLabel(h.behind)}
        </Sub>
      </TableCell>

      <TableCell className="py-3">
        <Checkout checkout={h.checkout} running={h.running} />
      </TableCell>

      <TableCell className="py-3">
        <div className="flex items-center gap-2">
          <span className={cn("size-2 shrink-0 rounded-full", onlineDot[h.online])} />
          <span className={cn(h.online === "off" && "text-muted-foreground")}>
            {onlineLabel(h, now)}
          </span>
        </div>
      </TableCell>

      <TableCell className="py-3">
        <Activation event={h.last_activation} now={now} />
      </TableCell>

      <TableCell className="max-w-[300px] py-3">
        <div className="flex items-center gap-1">
          {h.last_apply?.message && h.last_apply.state !== "ok" ? (
            <Tooltip>
              <TooltipTrigger asChild>
                <span className="min-w-0">
                  <ApplyBadge apply={h.last_apply} />
                </span>
              </TooltipTrigger>
              <TooltipContent className="max-w-sm font-mono">{h.last_apply.message}</TooltipContent>
            </Tooltip>
          ) : (
            <ApplyBadge apply={h.last_apply} />
          )}
          {h.last_apply && (
            <Button
              variant="ghost"
              size="sm"
              className="text-muted-foreground h-6 gap-1 px-1.5 text-xs"
              onClick={() => onShowLog(h.name, h.last_apply!.apply_id)}
            >
              <FileTextIcon className="size-3.5" />
              Log
            </Button>
          )}
        </div>
        {h.last_apply && (
          <Sub>
            <span className="font-mono">{shortRev(h.last_apply.commit)}</span>
            {h.last_apply.started_at !== null && <> · {ago(h.last_apply.started_at, now)}</>}
            {h.last_apply.started_at !== null && (
              <>
                {" "}
                · {durationLabel(h.last_apply.started_at, h.last_apply.finished_at, now)}
              </>
            )}
          </Sub>
        )}
        {queued && (
          <Sub className="text-running">
            {h.online === "off"
              ? `Queued: sent when ${h.name} comes online`
              : "Queued: sent when the agent answers"}
          </Sub>
        )}
      </TableCell>

      <TableCell className="py-3 pr-4 text-right">
        <Button
          size="sm"
          variant={h.behind === 0 ? "outline" : "default"}
          disabled={sending || applying}
          onClick={apply}
        >
          {sending ? "Sending" : applying ? "Applying" : "Apply newest"}
        </Button>
      </TableCell>
    </TableRow>
  );
}

function Sub({ className, children }: { className?: string; children: ComponentChildren }) {
  return <div className={cn("text-muted-foreground mt-0.5 text-xs", className)}>{children}</div>;
}

function Checkout({ checkout: c, running }: { checkout: CheckoutStatus | null; running: string | null }) {
  if (c === null) return <span className="text-muted-foreground">unknown</span>;
  const flags: { text: string; warn: boolean }[] = [];
  if (c.dirty) flags.push({ text: "local changes", warn: true });
  if (c.untracked > 0) flags.push({ text: `${c.untracked} untracked`, warn: false });
  if (c.ahead !== null && c.ahead > 0) flags.push({ text: `${c.ahead} ahead`, warn: true });
  const notRunning = c.head !== null && running !== null && c.head !== stripDirty(running);
  return (
    <>
      <div className="flex items-center gap-1.5 font-mono text-[13px]">
        <span>{c.branch ?? "detached"}</span>
        {c.head && <span className="text-muted-foreground">@ {shortRev(c.head)}</span>}
      </div>
      <Sub>
        {flags.length === 0 && !notRunning ? (
          "clean"
        ) : (
          <>
            {flags.map((f, i) => (
              <span key={f.text} className={cn(f.warn && "text-skipped font-medium")}>
                {i > 0 && " · "}
                {f.text}
              </span>
            ))}
            {notRunning && (
              <span className="text-warn">
                {flags.length > 0 && " · "}checkout is not the running system
              </span>
            )}
          </>
        )}
      </Sub>
    </>
  );
}

function triggerLabel(e: ActivationEvent): string {
  if (e.trigger.startsWith("apply:")) return "fleet apply";
  if (e.trigger === "manual") return e.sudo_user ? `manual (${e.sudo_user})` : "manual";
  return e.trigger;
}

function Activation({ event: e, now }: { event: ActivationEvent | null; now: number }) {
  if (e === null) return <span className="text-muted-foreground">none recorded</span>;
  return (
    <>
      <div>{ago(e.time, now)}</div>
      <Sub>
        <span className="font-mono">{shortRev(e.revision)}</span> · {triggerLabel(e)}
        {e.generation !== null && <> · gen {e.generation}</>}
      </Sub>
    </>
  );
}
