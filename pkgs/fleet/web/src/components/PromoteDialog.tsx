import { useState } from "preact/hooks";
import { toast } from "sonner";
import { promote } from "@/api";
import type { ChannelView } from "@/bindings/ChannelView";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { shortRev } from "@/format";

/**
 * "Promote unstable → stable": fast-forwards stable to `commit` after a confirmation. The commit
 * is fixed when the dialog opens, so a commit landing on unstable meanwhile can't change what
 * the confirmation promotes.
 */
export function PromoteDialog({
  commit: candidate,
  channels,
  onError,
}: {
  commit: string;
  channels: ChannelView[];
  onError: (what: string, e: unknown) => void;
}) {
  // What the open dialog promotes, captured when it opened.
  const [target, setTarget] = useState<{ commit: string; subject: string | null } | null>(null);
  const [sending, setSending] = useState(false);
  const subjectOf = (commit: string) => channels.find((c) => c.head === commit)?.head_subject ?? null;
  const shown = target?.commit ?? candidate;
  const subject = target ? target.subject : subjectOf(candidate);
  const stable = channels.find((c) => c.name === "stable")?.head ?? null;

  async function confirm() {
    if (target === null) return;
    setSending(true);
    try {
      await promote(target.commit);
      toast.success(`stable moved to ${shortRev(target.commit)}`);
      setTarget(null);
    } catch (e) {
      onError("Promote failed", e);
    } finally {
      setSending(false);
    }
  }

  return (
    <Dialog
      open={target !== null}
      onOpenChange={(o) => {
        if (!sending) setTarget(o ? { commit: candidate, subject: subjectOf(candidate) } : null);
      }}
    >
      <DialogTrigger asChild>
        <Button size="sm" className="self-start">
          Promote unstable → stable
        </Button>
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Promote unstable → stable?</DialogTitle>
          <DialogDescription>
            Fast-forwards <span className="font-mono">stable</span> to this commit and pushes it.
            Hosts on stable change only when you apply.
          </DialogDescription>
        </DialogHeader>
        <div className="bg-muted/50 rounded-md border p-3 text-sm">
          <div className="flex items-baseline gap-2">
            <span className="font-mono font-semibold">{shortRev(shown)}</span>
            <span className="min-w-0 break-words">{subject ?? "(subject unavailable)"}</span>
          </div>
          {stable && (
            <div className="text-muted-foreground mt-1 text-xs">
              stable is now at <span className="font-mono">{shortRev(stable)}</span>
            </div>
          )}
        </div>
        <DialogFooter>
          <DialogClose asChild>
            <Button variant="outline" disabled={sending}>
              Cancel
            </Button>
          </DialogClose>
          <Button onClick={confirm} disabled={sending}>
            {sending ? "Promoting" : `Promote ${shortRev(shown)}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
