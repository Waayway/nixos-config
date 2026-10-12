import type { ComponentChildren } from "preact";
import type { HostView } from "@/bindings/HostView";
import { HostRow } from "@/components/HostRow";
import { Table, TableBody, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { cn } from "@/lib/utils";

export function HostTable({
  hosts,
  now,
  onShowLog,
  onError,
}: {
  hosts: HostView[];
  now: number;
  onShowLog: (host: string, applyId: string) => void;
  onError: (what: string, e: unknown) => void;
}) {
  if (hosts.length === 0) {
    return (
      <p className="text-muted-foreground rounded-lg border border-dashed py-12 text-center text-sm">
        No hosts in the fleet yet.
      </p>
    );
  }
  const sorted = [...hosts].sort(
    (a, b) => a.channel.localeCompare(b.channel) || a.name.localeCompare(b.name),
  );
  return (
    <div className="bg-card overflow-hidden rounded-lg border">
      <Table className="min-w-[1080px]">
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <Th className="pl-5">Host</Th>
            <Th>Running</Th>
            <Th>Checkout</Th>
            <Th>Online</Th>
            <Th>Last activation</Th>
            <Th>Last apply</Th>
            <Th className="pr-4 text-right">
              <span className="sr-only">Actions</span>
            </Th>
          </TableRow>
        </TableHeader>
        <TableBody>
          {sorted.map((h) => (
            <HostRow key={h.name} host={h} now={now} onShowLog={onShowLog} onError={onError} />
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

function Th({ className, children }: { className?: string; children?: ComponentChildren }) {
  return (
    <TableHead
      className={cn(
        "text-muted-foreground bg-muted/40 h-9 text-[11px] font-medium tracking-wider uppercase",
        className,
      )}
    >
      {children}
    </TableHead>
  );
}
