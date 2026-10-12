import { useCallback, useEffect, useReducer, useRef, useState } from "preact/hooks";
import { toast } from "sonner";
import { getApplyLog, getSnapshot, isForbidden } from "@/api";
import {
  type FetchState,
  finishFetch,
  fromText,
  type HeldLog,
  type LogWatch,
  mergeChunk,
  requestFetch,
  watchLog,
} from "@/applyLog";
import type { ChannelView } from "@/bindings/ChannelView";
import type { HostView } from "@/bindings/HostView";
import type { LogChunk } from "@/bindings/LogChunk";
import type { Snapshot } from "@/bindings/Snapshot";
import type { WsMessage } from "@/bindings/WsMessage";
import { ApplyLogSheet } from "@/components/ApplyLogSheet";
import { ChannelBar } from "@/components/ChannelBar";
import { HostTable } from "@/components/HostTable";
import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";
import { connectFeed, type FeedStatus } from "@/ws";

type Action =
  | { type: "snapshot"; data: Snapshot }
  | { type: "host"; data: HostView }
  | { type: "channels"; data: ChannelView[] }
  | { type: "candidate"; data: string | null };

function reduce(s: Snapshot | null, a: Action): Snapshot | null {
  if (a.type === "snapshot") return a.data;
  if (s === null) return s;
  switch (a.type) {
    case "host": {
      const i = s.hosts.findIndex((h) => h.name === a.data.name);
      const hosts = i < 0 ? [...s.hosts, a.data] : s.hosts.map((h, j) => (j === i ? a.data : h));
      return { ...s, hosts };
    }
    case "channels":
      return { ...s, channels: a.data };
    case "candidate":
      return { ...s, promote_candidate: a.data };
  }
}

const headsKey = (channels: ChannelView[]) =>
  channels.map((c) => `${c.name}=${c.head ?? ""}`).join(" ");

/** The apply whose log is open in the sheet, and what we hold of that log. */
type OpenLog = LogWatch &
  FetchState & { log: HeldLog | null; error: string | null };

function useNow(intervalMs: number): number {
  const [now, setNow] = useState(() => Math.floor(Date.now() / 1000));
  useEffect(() => {
    const t = setInterval(() => setNow(Math.floor(Date.now() / 1000)), intervalMs);
    return () => clearInterval(t);
  }, [intervalMs]);
  return now;
}

export function App() {
  const [snap, dispatch] = useReducer(reduce, null);
  const [feed, setFeed] = useState<FeedStatus>({ kind: "connecting" });
  // The open log lives in a ref so WebSocket chunks and the log request always merge onto the
  // latest copy; the state mirrors it for rendering.
  const [openLog, setOpenLogState] = useState<OpenLog | null>(null);
  const openLogRef = useRef<OpenLog | null>(null);
  const setOpenLog = useCallback((o: OpenLog | null) => {
    openLogRef.current = o;
    setOpenLogState(o);
  }, []);
  const now = useNow(15_000);
  const candidateSeq = useRef(0);
  const heads = useRef("");

  // Fetches the open apply's whole log, one request at a time: asking while one is in flight
  // only marks it to run once more when the current one finishes (see `requestFetch`).
  const fetchLog = useCallback(() => {
    const o = openLogRef.current;
    if (!o) return;
    const r = requestFetch(o);
    setOpenLog({ ...o, ...r.next });
    if (r.start) void runFetches(o.host, o.applyId);

    async function runFetches(host: string, applyId: string) {
      for (;;) {
        let result: Partial<OpenLog>;
        try {
          const fetched = fromText(await getApplyLog(host, applyId));
          const held = openLogRef.current?.log;
          // Chunks that arrived while the request was in flight may already be past it.
          result = { log: held && held.bytes > fetched.bytes ? held : fetched, error: null };
        } catch (e) {
          result = { error: (e as Error).message };
        }
        const cur = openLogRef.current;
        if (!cur || cur.applyId !== applyId) return;
        const f = finishFetch(cur);
        setOpenLog({ ...cur, ...result, ...f.next });
        if (!f.start) return;
      }
    }
  }, [setOpenLog]);

  const onChunk = useCallback(
    (c: LogChunk) => {
      const o = openLogRef.current;
      if (!o || o.applyId !== c.apply_id) return;
      const m = mergeChunk(o.log ?? undefined, c);
      if (m.kind === "appended") setOpenLog({ ...o, log: m.log });
      else if (m.kind === "gap") fetchLog();
    },
    [fetchLog, setOpenLog],
  );

  useEffect(
    () =>
      connectFeed({
        onStatus: setFeed,
        isForbidden,
        onMessage: (m: WsMessage) => {
          const o = openLogRef.current;
          if (o) {
            const w = watchLog(o, m);
            if (w.running !== o.running) setOpenLog({ ...o, running: w.running });
            if (w.refetch) fetchLog();
          }
          switch (m.type) {
            case "host_updated":
              dispatch({ type: "host", data: m.data });
              break;
            case "snapshot":
              heads.current = headsKey(m.data.channels);
              candidateSeq.current++; // a pending candidate answer is older than this
              dispatch({ type: "snapshot", data: m.data });
              break;
            case "channels_updated": {
              dispatch({ type: "channels", data: m.data });
              // The promote candidate isn't part of this message; it changes only with the
              // heads. Only the newest request's answer counts, in case answers arrive swapped.
              const key = headsKey(m.data);
              if (key !== heads.current) {
                heads.current = key;
                const seq = ++candidateSeq.current;
                getSnapshot().then(
                  (s) => {
                    if (seq === candidateSeq.current)
                      dispatch({ type: "candidate", data: s.promote_candidate });
                  },
                  () => {},
                );
              }
              break;
            }
            case "apply_log":
              onChunk(m.data);
              break;
          }
        },
      }),
    [onChunk, fetchLog, setOpenLog],
  );

  const showLog = useCallback(
    (host: string, applyId: string) => {
      const rec = snap?.hosts.find((h) => h.name === host)?.last_apply;
      const running = rec?.apply_id === applyId ? rec.state === "running" : null;
      setOpenLog({ host, applyId, running, log: null, error: null, fetching: false, again: false });
      fetchLog();
    },
    [fetchLog, setOpenLog, snap],
  );

  const reportError = useCallback((what: string, e: unknown) => {
    toast.error(what, { description: (e as Error).message });
  }, []);

  const logHost = openLog && snap?.hosts.find((h) => h.name === openLog.host);
  const logRecord =
    logHost && logHost.last_apply?.apply_id === openLog?.applyId ? logHost.last_apply : null;

  return (
    <TooltipProvider delayDuration={200}>
      <div className="min-h-dvh">
        {snap?.demo && (
          <div className="bg-demo text-demo-foreground border-b border-demo-foreground/15 px-4 py-1.5 text-center text-xs font-medium tracking-wide">
            Demo · simulated fleet. Nothing here touches a real machine.
          </div>
        )}
        <header className="mx-auto flex max-w-[1400px] flex-wrap items-center gap-x-4 gap-y-1 px-4 pt-5 pb-3 sm:px-6">
          <h1 className="flex items-baseline gap-2 text-lg font-semibold tracking-tight">
            <span className="font-mono">fleet</span>
            {snap && (
              <span className="text-muted-foreground text-sm font-normal">
                {snap.hosts.length} {snap.hosts.length === 1 ? "host" : "hosts"}
              </span>
            )}
          </h1>
          <div className="text-muted-foreground ml-auto flex items-center gap-4 text-xs">
            {snap && <span>Signed in as {snap.viewer}</span>}
            <FeedIndicator feed={feed} />
          </div>
        </header>

        <main className="mx-auto flex max-w-[1400px] flex-col gap-4 px-4 pb-10 sm:px-6">
          {feed.kind === "forbidden" ? (
            <div className="py-16 text-center">
              <p className="text-sm font-medium">You don't have access to this dashboard</p>
              <p className="text-muted-foreground mt-1 text-sm">
                The fleet server only lets in the owner's Tailscale login and tagged fleet devices.
              </p>
            </div>
          ) : snap === null ? (
            <p className="text-muted-foreground py-16 text-center text-sm">
              {feed.kind === "waiting" ? "Can't reach the fleet server. Retrying." : "Loading fleet"}
            </p>
          ) : (
            <>
              <ChannelBar snapshot={snap} onError={reportError} />
              <HostTable hosts={snap.hosts} now={now} onShowLog={showLog} onError={reportError} />
            </>
          )}
        </main>
      </div>

      <ApplyLogSheet
        open={openLog !== null}
        host={openLog?.host ?? ""}
        applyId={openLog?.applyId ?? ""}
        record={logRecord ?? null}
        log={openLog?.log ?? null}
        error={openLog?.error ?? null}
        now={now}
        onClose={() => setOpenLog(null)}
      />
      <Toaster position="bottom-right" />
    </TooltipProvider>
  );
}

function FeedIndicator({ feed }: { feed: FeedStatus }) {
  const [, tick] = useState(0);
  useEffect(() => {
    if (feed.kind !== "waiting") return;
    const t = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, [feed]);
  const label =
    feed.kind === "live"
      ? "Live"
      : feed.kind === "connecting"
        ? "Connecting"
        : feed.kind === "forbidden"
          ? "No access"
          : `Disconnected · retry in ${Math.max(0, Math.ceil((feed.retryAt - Date.now()) / 1000))}s`;
  return (
    <span className="flex items-center gap-1.5" role="status">
      <span
        className={cn(
          "size-2 rounded-full",
          feed.kind === "live" ? "bg-ok" : feed.kind === "connecting" ? "bg-running animate-pulse" : "bg-failed",
        )}
      />
      {label}
    </span>
  );
}
