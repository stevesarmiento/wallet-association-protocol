import { describe, expect, it, vi } from "vitest";
import {
  WalletAssociationError,
  type AssociationCrypto,
  type AssociationDiscoverResponse,
  type AssociationEnvelope,
  type AssociationResponsePayload,
  type WalletAssociationStorage,
  type WalletAssociationStoredSession
} from "@wallet-association/core";
import type { AssociationTransport } from "@wallet-association/transport-localhost";
import { createWalletAssociationWallet } from "../src";

const discovery: AssociationDiscoverResponse = {
  name: "Native Wallet",
  version: "0.1.0",
  protocolVersion: "2",
  transports: [{ type: "localhost", host: "127.0.0.1", port: 51884 }],
  chains: ["solana:devnet"],
  features: ["solana:signMessage", "solana:signTransaction"],
  encryption: "x25519-hkdf-sha256-chacha20poly1305",
  sessionTokenTtlSeconds: 604800
};

const associationResponse: AssociationResponsePayload = {
  sessionId: "session-id",
  sessionTokenBase64: "session-token",
  expiresAt: "2026-06-01T00:00:00.000Z",
  accounts: [
    {
      address: "11111111111111111111111111111111",
      publicKey: Array.from({ length: 32 }, () => 1),
      chains: ["solana:devnet"],
      features: ["solana:signMessage", "solana:signTransaction"],
      label: "Account 1"
    }
  ],
  chains: ["solana:devnet"],
  features: ["solana:signMessage", "solana:signTransaction"],
  signingPolicy: "prompt"
};

describe("Wallet Standard adapter", () => {
  it("attempts resume first when a stored session exists", async () => {
    const { wallet, associatePayloads } = makeWallet({
      stored: {
        sessionId: "stored-session",
        sessionTokenBase64: "stored-token",
        expiresAt: "2026-06-01T00:00:00.000Z",
        origin: "https://app.example",
        walletName: "Native Wallet",
        walletVersion: "0.1.0"
      }
    });

    await connect(wallet);

    expect(associatePayloads).toEqual([
      {
        kind: "resume",
        resumeSessionId: "stored-session",
        resumeSessionTokenBase64: "stored-token"
      }
    ]);
  });

  it("clears invalid stored sessions and creates a new session", async () => {
    const clear = vi.fn();
    const { wallet, associatePayloads } = makeWallet({
      failResume: true,
      storageOverrides: { clear }
    });

    await connect(wallet);

    expect(clear).toHaveBeenCalledOnce();
    expect(associatePayloads.map(payload => payload.kind)).toEqual(["resume", "create"]);
  });

  it("signs messages and transactions through encrypted RPC", async () => {
    const { wallet, rpcPayloads } = makeWallet();
    const { accounts } = await connect(wallet);
    const account = accounts[0];

    const messageResult = await (wallet.features["solana:signMessage"] as any).signMessage({
      account,
      message: new Uint8Array([104, 105]),
      chain: "solana:devnet"
    });
    const transactionResult = await (wallet.features["solana:signTransaction"] as any).signTransaction({
      account,
      transaction: new Uint8Array([1, 2, 3]),
      chain: "solana:devnet"
    });

    expect(Array.from(messageResult.signature)).toEqual([1, 2, 3]);
    expect(Array.from(transactionResult.signedTransaction)).toEqual([4, 5, 6]);
    expect(rpcPayloads.map(payload => payload.method)).toEqual(["solana.signMessage", "solana.signTransaction"]);
  });

  it("disconnect clears in-memory accounts without clearing storage", async () => {
    const clear = vi.fn();
    const { wallet } = makeWallet({ storageOverrides: { clear } });

    await connect(wallet);
    expect(wallet.accounts).toHaveLength(1);

    await (wallet.features["standard:disconnect"] as any).disconnect();

    expect(wallet.accounts).toHaveLength(0);
    expect(clear).not.toHaveBeenCalled();
  });
});

function makeWallet(input: {
  stored?: WalletAssociationStoredSession | null;
  failResume?: boolean;
  storageOverrides?: Partial<WalletAssociationStorage>;
} = {}) {
  const associatePayloads: any[] = [];
  const rpcPayloads: any[] = [];
  const crypto: AssociationCrypto = {
    generateKeyPair: () => ({ secretKey: new Uint8Array([1]), publicKeyBase64: "dapp-public-key" }),
    deriveHandshakeKey: () => new Uint8Array([1]),
    deriveSessionKey: () => new Uint8Array([2]),
    sealJson: (keyId, _key, payload) => ({ protocolVersion: "2", keyId, sealedBoxBase64: JSON.stringify(payload) }),
    openJson: (_key, envelope) => JSON.parse(envelope.sealedBoxBase64),
    randomUUID: () => "request-id",
    now: () => new Date("2026-05-24T00:00:00.000Z")
  };
  const storage: WalletAssociationStorage = {
    get: vi.fn(() => input.stored ?? {
      sessionId: "stored-session",
      sessionTokenBase64: "stored-token",
      expiresAt: "2026-06-01T00:00:00.000Z",
      origin: "https://app.example",
      walletName: "Native Wallet",
      walletVersion: "0.1.0"
    }),
    set: vi.fn(),
    clear: vi.fn(),
    ...input.storageOverrides
  };
  const post: AssociationTransport["post"] = async <T>(path: string, body: unknown) => {
      if (path === "/v2/handshake") {
        return {
          protocolVersion: "2",
          handshakeId: "handshake-id",
          walletPublicKeyBase64: "wallet-public-key",
          expiresAt: "2026-05-24T00:01:00.000Z"
        } as T;
      }

      if (path === "/v2/associate") {
        const payload = JSON.parse((body as AssociationEnvelope).sealedBoxBase64);
        associatePayloads.push(payload);
        if (payload.kind === "resume" && input.failResume) {
          throw new WalletAssociationError("session invalid", "session_invalid");
        }
        return {
          protocolVersion: "2",
          keyId: "handshake-id",
          sealedBoxBase64: JSON.stringify(associationResponse)
        } as T;
      }

      if (path === "/v2/rpc") {
        const payload = JSON.parse((body as AssociationEnvelope).sealedBoxBase64);
        rpcPayloads.push(payload);
        return {
          protocolVersion: "2",
          keyId: associationResponse.sessionId,
          sealedBoxBase64: JSON.stringify({
            requestId: payload.requestId,
            result:
              payload.method === "solana.signMessage"
                ? { signatureBase64: "AQID" }
                : { signedTransactionBase64: "BAUG", signature: "signature" }
          })
        } as T;
      }

      throw new Error(`Unexpected path ${path}`);
    };
  const transport: AssociationTransport = {
    get: vi.fn(),
    post
  };

  const wallet = createWalletAssociationWallet({
    discovery,
    transport,
    storage,
    crypto,
    origin: "https://app.example"
  });

  return { wallet, associatePayloads, rpcPayloads };
}

async function connect(wallet: ReturnType<typeof createWalletAssociationWallet>) {
  return (wallet.features["standard:connect"] as any).connect();
}
