import { afterEach, describe, expect, it } from "vitest";
import type { AssociationDiscoverResponse } from "@wallet-association/core";
import { createWalletAssociationStorage } from "../src";

const discovery: AssociationDiscoverResponse = {
  name: "Native",
  version: "1.0.0",
  protocolVersion: "2",
  transports: [{ type: "localhost", host: "127.0.0.1", port: 51884 }],
  chains: ["solana:devnet"],
  features: ["solana:signMessage", "solana:signTransaction"],
  encryption: "x25519-hkdf-sha256-chacha20poly1305",
  sessionTokenTtlSeconds: 604800
};

const validSession = {
  sessionId: "session",
  sessionTokenBase64: tokenBase64(32),
  expiresAt: "2999-01-01T00:00:00.000Z",
  origin: "https://app.example",
  walletName: "Native",
  walletVersion: "1.0.0"
};

describe("wallet association storage", () => {
  afterEach(() => {
    delete (globalThis as { window?: unknown }).window;
  });

  it("clears malformed, invalid, mismatched, and expired stored sessions", () => {
    const localStorage = new MemoryStorage();
    (globalThis as { window?: unknown }).window = { localStorage };
    const storage = createWalletAssociationStorage({
      discovery,
      origin: "https://app.example",
      transportId: "localhost:127.0.0.1:51884"
    });
    const key = "wallet-association:v0.1:https%3A%2F%2Fapp.example:localhost:127.0.0.1:51884:Native";

    for (const value of [
      "{",
      JSON.stringify({ ...validSession, sessionTokenBase64: "" }),
      JSON.stringify({ ...validSession, origin: "https://wrong.example" }),
      JSON.stringify({ ...validSession, expiresAt: "2000-01-01T00:00:00.000Z" })
    ]) {
      localStorage.setItem(key, value);
      expect(storage.get()).toBeNull();
      expect(localStorage.getItem(key)).toBeNull();
    }
  });

  it("returns valid stored sessions", () => {
    const localStorage = new MemoryStorage();
    (globalThis as { window?: unknown }).window = { localStorage };
    const storage = createWalletAssociationStorage({
      discovery,
      origin: "https://app.example",
      transportId: "localhost:127.0.0.1:51884"
    });
    storage.set(validSession);

    expect(storage.get()).toEqual(validSession);
  });
});

class MemoryStorage {
  private readonly values = new Map<string, string>();

  getItem(key: string) {
    return this.values.get(key) ?? null;
  }

  setItem(key: string, value: string) {
    this.values.set(key, value);
  }

  removeItem(key: string) {
    this.values.delete(key);
  }
}

function tokenBase64(length: number): string {
  return btoa(String.fromCharCode(...new Uint8Array(length).fill(7)));
}
