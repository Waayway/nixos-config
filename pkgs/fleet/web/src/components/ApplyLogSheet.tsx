import { useLayoutEffect, useRef } from "preact/hooks";
import type { HeldLog } from "@/applyLog";
import type { ApplyRecord } from "@/bindings/ApplyRecord";
import { ApplyBadge } from "@/components/HostRow";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
} from "@/components/ui/sheet";
import { ago, durationLabel, shortRev } from "@/format";

/** The log of one apply, appended live while it runs. */
export function ApplyLogSheet({
  open,
  host,
  applyId,
  record,
  log,
  error,
  now,
  onClose,
}: {
  open: boolean;
  host: string;
  applyId: string;
  /** The host's last apply when it is this one, so its state stays live; else null. */
  record: ApplyRecord | null;
  log: HeldLog | null;
  error: string | null;
  now: number;
  onClose: () => void;
}) {
  const scroller = useRef<HTMLPreElement>(null);
  const pinned = useRef(true);
  const running = record?.state === "running";
  if (!open) pinned.current = true;

  // Follow the end of the log unless the reader scrolled up.
  useLayoutEffect(() => {
    const el = scroller.current;
    if (el && pinned.current) el.scrollTop = el.scrollHeight;
  }, [log?.text, open]);

  return (
    <Sheet open={open} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="right" className="w-full gap-0 sm:max-w-3xl">
        <SheetHeader className="border-b pr-12">
          <SheetTitle className="flex items-center gap-2">
            <span className="font-mono">{host}</span>
            <span className="text-muted-foreground font-normal">apply log</span>
          </SheetTitle>
          <SheetDescription asChild>
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs">
              {record && <ApplyBadge apply={record} />}
              {record && (
                <span>
                  commit <span className="text-foreground font-mono">{shortRev(record.commit)}</span>
                </span>
              )}
              {record?.started_at != null && (
                <span>
                  started {ago(record.started_at, now)} ·{" "}
                  {durationLabel(record.started_at, record.finished_at, now)}
                </span>
              )}
              <span className="font-mono opacity-70">{applyId.slice(0, 8)}</span>
            </div>
          </SheetDescription>
          {record?.message && record.state !== "ok" && (
            <p className="text-foreground mt-1 font-mono text-xs break-words">{record.message}</p>
          )}
        </SheetHeader>
        <pre
          ref={scroller}
          onScroll={(e) => {
            const el = e.currentTarget;
            pinned.current = el.scrollHeight - el.scrollTop - el.clientHeight < 24;
          }}
          className="bg-muted/40 min-h-0 flex-1 overflow-auto px-4 py-3 font-mono text-xs leading-relaxed whitespace-pre-wrap break-all"
        >
          {error && log === null ? (
            <span className="text-failed">Could not load the log: {error}</span>
          ) : log === null ? (
            <span className="text-muted-foreground">Loading log</span>
          ) : log.text === "" ? (
            <span className="text-muted-foreground">The log is empty so far.</span>
          ) : (
            log.text
          )}
        </pre>
        <div className="text-muted-foreground flex items-center gap-2 border-t px-4 py-2 text-xs">
          {running ? (
            <>
              <span className="bg-running size-2 animate-pulse rounded-full" />
              Following live
            </>
          ) : (
            <>Finished</>
          )}
          {log && <span className="ml-auto font-mono">{(log.bytes / 1024).toFixed(1)} KiB</span>}
        </div>
      </SheetContent>
    </Sheet>
  );
}
