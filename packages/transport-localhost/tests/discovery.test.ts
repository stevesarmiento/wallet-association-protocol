import { afterEach, describe, expect, it, vi } from "vitest";
import { discoverLocalhostWallet, type AssociationTransport } from "../src";
import { WALLET_ASSOCIATION_ENCRYPTION, WALLET_ASSOCIATION_PROTOCOL_VERSION } from "@wallet-association/core";

const discovery = {
  name: "Native Wallet",
  version: "0.1.0",
  protocolVersion: WALLET_ASSOCIATION_PROTOCOL_VERSION,
  transports: [{ type: "localhost", host: "127.0.0.1", port: 51884 }],
  chains: ["solana:devnet"],
  features: ["solana:signMessage", "solana:signTransaction"],
  encryption: WALLET_ASSOCIATION_ENCRYPTION,
  sessionTokenTtlSeconds: 604800
};

describe("localhost discovery", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    delete (globalThis as { window?: unknown }).window;
  });

  it("returns null when disabled", async () => {
    expect(await discoverLocalhostWallet(false)).toBeNull();
  });

  it("probes /v2/discover when enabled", async () => {
    (globalThis as { window?: unknown }).window = { location: { origin: "https://app.example" } };
    const calls: unknown[][] = [];
    const get: AssociationTransport["get"] = async <T>(path: string, options?: { signal?: AbortSignal }) => {
      calls.push([path, options]);
      return discovery as T;
    };
    const transport: AssociationTransport = { get, post: vi.fn() };

    await expect(discoverLocalhostWallet(true, { transport })).resolves.toEqual(discovery);
    expect(calls).toEqual([["/v2/discover", expect.objectContaining({ signal: expect.any(AbortSignal) })]]);
  });

  it("returns null for incompatible discovery responses", async () => {
    (globalThis as { window?: unknown }).window = { location: { origin: "https://app.example" } };

    const get: AssociationTransport["get"] = async <T>() => ({ ...discovery, protocolVersion: "1" }) as T;

    await expect(
      discoverLocalhostWallet(true, {
        transport: {
          get,
          post: vi.fn()
        }
      })
    ).resolves.toBeNull();
  });
});
