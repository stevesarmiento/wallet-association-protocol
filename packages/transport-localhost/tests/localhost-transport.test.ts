import { afterEach, describe, expect, it, vi } from "vitest";
import { createLocalhostTransport, resolveLocalhostTransportConfig } from "../src";

describe("localhost transport", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("posts JSON to the configured localhost endpoint", async () => {
    const fetch = vi.fn(async () => ({
      ok: true,
      status: 200,
      json: async () => ({ ok: true })
    }));
    vi.stubGlobal("fetch", fetch);

    const transport = createLocalhostTransport(resolveLocalhostTransportConfig(true));
    await expect(transport.post("/v2/rpc", { hello: "world" })).resolves.toEqual({ ok: true });

    expect(fetch).toHaveBeenCalledWith(
      "http://127.0.0.1:51884/v2/rpc",
      expect.objectContaining({
        method: "POST",
        credentials: "omit",
        body: JSON.stringify({ hello: "world" })
      })
    );
  });

  it("normalizes protocol errors", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({
        ok: false,
        status: 403,
        json: async () => ({ error: { code: "session_invalid", message: "expired" } })
      }))
    );

    const transport = createLocalhostTransport(resolveLocalhostTransportConfig(true));
    await expect(transport.get("/v2/discover")).rejects.toMatchObject({
      name: "WalletAssociationError",
      code: "session_invalid"
    });
  });
});
