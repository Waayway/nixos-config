import { afterEach, describe, expect, it, vi } from "vitest";
import { applyHost, getSnapshot, promote } from "./api";

function stubFetch() {
  const fetchMock = vi.fn(async () => new Response("{}", { status: 200 }));
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}

function headersOf(call: unknown[]): Record<string, string> {
  return (call[1] as RequestInit).headers as Record<string, string>;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("request headers", () => {
  it("sends X-Fleet on every request (CSRF guard)", async () => {
    const fetchMock = stubFetch();
    await getSnapshot();
    await applyHost("hermes");
    await promote("a".repeat(40));
    expect(fetchMock).toHaveBeenCalledTimes(3);
    for (const call of fetchMock.mock.calls) {
      expect(headersOf(call)["x-fleet"]).toBe("1");
    }
    expect(headersOf(fetchMock.mock.calls[0])["content-type"]).toBeUndefined();
    expect(headersOf(fetchMock.mock.calls[2])["content-type"]).toBe("application/json");
  });
});
