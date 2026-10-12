// REST calls to the fleet server. Errors carry the HTTP status and the server's `{error}` text.
import type { Snapshot } from "@/bindings/Snapshot";

/** What the server got back from the agent when it sent an apply. */
export type AgentStatus = "202" | "409" | "200" | "unreachable" | "error";

export type ApplyHostResponse = { apply_id: string; agent_status: AgentStatus };
export type ApplyChannelResponse = {
  apply_ids: Record<string, string>;
  agent_status: Record<string, AgentStatus>;
};

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

async function request(method: string, path: string, body?: unknown): Promise<Response> {
  // X-Fleet: the server refuses state-changing requests without it (CSRF guard).
  const headers: Record<string, string> = { "x-fleet": "1" };
  if (body !== undefined) headers["content-type"] = "application/json";
  let res: Response;
  try {
    res = await fetch(path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(0, "The fleet server is not answering");
  }
  if (!res.ok) {
    let message = `${res.status} ${res.statusText}`.trim();
    try {
      const j = (await res.json()) as { error?: unknown };
      if (typeof j.error === "string" && j.error) message = j.error;
    } catch {
      // Not JSON: keep the status line.
    }
    throw new ApiError(res.status, message);
  }
  return res;
}

const enc = encodeURIComponent;

/** True when the server answers this viewer with 403 (not an allowed login or tag). */
export async function isForbidden(): Promise<boolean> {
  try {
    await request("GET", "/api/snapshot");
    return false;
  } catch (e) {
    return e instanceof ApiError && e.status === 403;
  }
}

export async function getSnapshot(): Promise<Snapshot> {
  return (await request("GET", "/api/snapshot")).json();
}

export async function applyHost(host: string): Promise<ApplyHostResponse> {
  return (await request("POST", `/api/hosts/${enc(host)}/apply`)).json();
}

export async function applyChannel(channel: string): Promise<ApplyChannelResponse> {
  return (await request("POST", `/api/channels/${enc(channel)}/apply`)).json();
}

export async function promote(commit: string): Promise<void> {
  await request("POST", "/api/promote", { commit });
}

export async function getApplyLog(host: string, applyId: string): Promise<string> {
  return (await request("GET", `/api/hosts/${enc(host)}/applies/${enc(applyId)}/log`)).text();
}

/** A sentence for an agent's answer to an apply the server sent it, or null when it started. */
export function agentStatusText(host: string, s: AgentStatus): string | null {
  switch (s) {
    case "202":
      return null;
    case "200":
      return `${host} already ran this apply`;
    case "409":
      return `${host} is busy with another apply. This one is sent when it finishes.`;
    case "unreachable":
      return `${host}: agent not answering. The apply is queued and sent when it is back.`;
    case "error":
      return `${host}: the agent returned an error`;
  }
}
