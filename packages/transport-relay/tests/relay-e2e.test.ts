import { afterEach, describe, expect, it, vi } from "vitest";
import WebSocket, { type RawData } from "ws";
import {
  encodeBase64,
  type AssociationCrypto,
  type AssociationDiscoverResponse,
  type AssociationEnvelope,
  type AssociationResponsePayload,
  type WalletAssociationStorage,
} from "@wallet-association/core";
import { startRelayServer, type RelayServerHandle } from "@wallet-association/relay-server";
import { createWalletAssociationWallet } from "@wallet-association/wallet-standard";
import { createRelayDappTransport, parseRelayAssociationUri } from "../src";

const token = "session-token";
const rotatedToken = encodeBase64(new Uint8Array(Array.from({ length: 32 }, () => 9)));

const discovery: AssociationDiscoverResponse = {
  name: "Native Wallet",
  version: "0.2.0",
  protocolVersion: "2",
  transports: [{ type: "relay" }],
  chains: ["solana:devnet"],
  features: ["solana:signMessage", "solana:signTransaction", "wallet.session.rotate"],
  encryption: "x25519-hkdf-sha256-chacha20poly1305",
  sessionTokenTtlSeconds: 604800,
};

const associationResponse: AssociationResponsePayload = {
  sessionId: "session-id",
  sessionTokenBase64: token,
  expiresAt: "2026-06-01T00:00:00.000Z",
  accounts: [
    {
      address: "11111111111111111111111111111111",
      publicKey: Array.from({ length: 32 }, () => 1),
      chains: ["solana:devnet"],
      features: ["solana:signMessage", "solana:signTransaction"],
      label: "Account 1",
    },
  ],
  chains: ["solana:devnet"],
  features: ["solana:signMessage", "solana:signTransaction", "wallet.session.rotate"],
  signingPolicy: "prompt",
};

describe("relay transport E2E", () => {
  let server: RelayServerHandle | null = null;
  let walletSocket: WebSocket | null = null;

  afterEach(async () => {
    walletSocket?.close();
    walletSocket = null;
    await server?.close();
    server = null;
  });

  it("supports discover, resume, rotation, signing, and session events over relay", async () => {
    server = await startRelayServer();
    const transport = await createRelayDappTransport({
      relayHttpUrl: server.httpUrl,
      origin: "https://app.example",
      webSocketFactory: (url) => new WebSocket(url) as any,
    });
    const parsed = parseRelayAssociationUri(transport.connectionUri);

    walletSocket = await connectWallet(parsed.relay, parsed.room, parsed.secret);
    attachFakeWallet(walletSocket);
    await transport.waitForWallet();

    await expect(transport.request("discover")).resolves.toEqual(discovery);

    const storageSet = vi.fn();
    const storage: WalletAssociationStorage = {
      get: vi.fn(() => ({
        sessionId: "session-id",
        sessionTokenBase64: token,
        expiresAt: "2026-06-01T00:00:00.000Z",
        origin: "https://app.example",
        walletName: "Native Wallet",
        walletVersion: "0.2.0",
      })),
      set: storageSet,
      clear: vi.fn(),
    };
    const wallet = createWalletAssociationWallet({
      discovery,
      transport,
      storage,
      crypto: fakeCrypto(),
      origin: "https://app.example",
    });

    const changeListener = vi.fn();
    (wallet.features["standard:events"] as any).on("change", changeListener);
    const { accounts } = await (wallet.features["standard:connect"] as any).connect();
    expect(accounts).toHaveLength(1);
    expect(storageSet).toHaveBeenLastCalledWith(expect.objectContaining({ sessionTokenBase64: rotatedToken }));

    const result = await (wallet.features["solana:signMessage"] as any).signMessage({
      account: accounts[0],
      message: new Uint8Array([1, 2, 3]),
      chain: "solana:devnet",
    });

    expect(Array.from(result.signature)).toEqual([1, 2, 3]);
    await eventually(() => {
      expect(changeListener).toHaveBeenCalledWith(expect.objectContaining({ accounts: expect.any(Array) }));
    });
  });
});

function attachFakeWallet(socket: WebSocket) {
  socket.on("message", (data: RawData) => {
    const frame = JSON.parse(data.toString("utf8"));
    if (frame.kind !== "wap_request") return;
    switch (frame.operation) {
      case "discover":
        send(socket, { kind: "wap_response", id: frame.id, ok: true, body: discovery });
        break;
      case "handshake":
        send(socket, {
          kind: "wap_response",
          id: frame.id,
          ok: true,
          body: {
            protocolVersion: "2",
            handshakeId: "handshake-id",
            walletPublicKeyBase64: "wallet-public-key",
            expiresAt: "2026-05-24T00:01:00.000Z",
          },
        });
        break;
      case "associate":
        send(socket, {
          kind: "wap_response",
          id: frame.id,
          ok: true,
          body: {
            protocolVersion: "2",
            keyId: "handshake-id",
            sealedBoxBase64: JSON.stringify(associationResponse),
          },
        });
        break;
      case "rpc": {
        const payload = JSON.parse((frame.body as AssociationEnvelope).sealedBoxBase64);
        const result =
          payload.method === "wallet.session.rotate"
            ? {
                sessionId: "rotated-session",
                sessionTokenBase64: rotatedToken,
                expiresAt: "2026-06-02T00:00:00.000Z",
              }
            : { signatureBase64: "AQID" };
        send(socket, {
          kind: "wap_response",
          id: frame.id,
          ok: true,
          body: {
            protocolVersion: "2",
            keyId: payload.method === "wallet.session.rotate" ? "session-id" : "rotated-session",
            sealedBoxBase64: JSON.stringify({ requestId: payload.requestId, result }),
          },
        });
        if (payload.method === "solana.signMessage") {
          send(socket, {
            kind: "wap_event",
            id: "event-1",
            body: {
              protocolVersion: "2",
              keyId: "rotated-session",
              sealedBoxBase64: JSON.stringify({
                eventId: "event-1",
                issuedAt: "2026-05-24T00:00:00.000Z",
                sessionTokenBase64: rotatedToken,
                type: "accounts_changed",
                accounts: associationResponse.accounts,
              }),
            },
          });
        }
        break;
      }
    }
  });
}

async function connectWallet(relay: string, room: string, secret: string): Promise<WebSocket> {
  const url = new URL(relay);
  url.searchParams.set("room", room);
  url.searchParams.set("secret", secret);
  url.searchParams.set("role", "wallet");
  const socket = new WebSocket(url);
  await new Promise<void>((resolve, reject) => {
    socket.on("open", () => resolve());
    socket.on("error", reject);
  });
  return socket;
}

function fakeCrypto(): AssociationCrypto {
  return {
    generateKeyPair: () => ({ secretKey: new Uint8Array([1]), publicKeyBase64: "dapp-public-key" }),
    deriveHandshakeKey: () => new Uint8Array([1]),
    deriveSessionKey: () => new Uint8Array([2]),
    sealJson: (keyId, _key, payload) => ({ protocolVersion: "2", keyId, sealedBoxBase64: JSON.stringify(payload) }),
    openJson: (_key, envelope) => JSON.parse(envelope.sealedBoxBase64),
    randomUUID: () => `request-${Math.random().toString(16).slice(2)}`,
    now: () => new Date("2026-05-24T00:00:00.000Z"),
  };
}

function send(socket: WebSocket, frame: unknown) {
  socket.send(JSON.stringify(frame));
}

async function eventually(assertion: () => void) {
  let lastError: unknown;
  for (let index = 0; index < 50; index += 1) {
    try {
      assertion();
      return;
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 20));
    }
  }
  throw lastError;
}
