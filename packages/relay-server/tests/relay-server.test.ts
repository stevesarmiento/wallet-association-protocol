import { afterEach, describe, expect, it } from "vitest";
import WebSocket from "ws";
import { startRelayServer, type RelayServerHandle } from "../src";

describe("reference relay server", () => {
  let server: RelayServerHandle | null = null;

  afterEach(async () => {
    await server?.close();
    server = null;
  });

  it("creates rooms and forwards opaque WAP frames", async () => {
    server = await startRelayServer();
    const room = await fetch(`${server.httpUrl}/v2/rooms`, {
      method: "POST",
    }).then((response) => response.json() as any);

    const dapp = await connect(
      room.webSocketUrl,
      room.roomId,
      room.roomSecret,
      "dapp",
    );
    const wallet = await connect(
      room.webSocketUrl,
      room.roomId,
      room.roomSecret,
      "wallet",
    );

    const walletFrames: any[] = [];
    wallet.on("message", (data) =>
      walletFrames.push(JSON.parse(data.toString("utf8"))),
    );

    dapp.send(
      JSON.stringify({ kind: "wap_request", id: "one", operation: "discover" }),
    );

    await eventually(() => {
      expect(
        walletFrames.some(
          (frame) => frame.kind === "wap_request" && frame.id === "one",
        ),
      ).toBe(true);
    });

    dapp.close();
    wallet.close();
  });

  it("rejects duplicate roles", async () => {
    server = await startRelayServer();
    const room = await fetch(`${server.httpUrl}/v2/rooms`, {
      method: "POST",
    }).then((response) => response.json() as any);

    const first = await connect(
      room.webSocketUrl,
      room.roomId,
      room.roomSecret,
      "dapp",
    );
    const second = new WebSocket(
      socketUrl(room.webSocketUrl, room.roomId, room.roomSecret, "dapp"),
    );

    await new Promise<void>((resolve) => {
      second.on("error", () => resolve());
      second.on("close", () => resolve());
    });
    expect([WebSocket.CLOSED, WebSocket.CLOSING]).toContain(second.readyState);
    first.close();
  });

  it("rejects bad room secrets and expired rooms during upgrade", async () => {
    server = await startRelayServer();
    const room = await createRoom(server.httpUrl);

    await expectUpgradeRejected(socketUrl(room.webSocketUrl, room.roomId, "bad-secret", "dapp"), 403);
    await server.close();
    server = null;

    server = await startRelayServer({ roomTtlMs: 1 });
    const expiredRoom = await createRoom(server.httpUrl);
    await new Promise((resolve) => setTimeout(resolve, 20));
    await expectUpgradeRejected(socketUrl(expiredRoom.webSocketUrl, expiredRoom.roomId, expiredRoom.roomSecret, "dapp"), 410);
  });

  it("closes clients that send invalid frame kinds", async () => {
    server = await startRelayServer();
    const room = await createRoom(server.httpUrl);
    const dapp = await connect(room.webSocketUrl, room.roomId, room.roomSecret, "dapp");

    const close = waitForClose(dapp);
    dapp.send(JSON.stringify({ kind: "unknown", id: "one" }));

    await expect(close).resolves.toMatchObject({ code: 1003 });
  });

  it("closes clients that send malformed response frames", async () => {
    server = await startRelayServer();
    const room = await createRoom(server.httpUrl);
    const wallet = await connect(room.webSocketUrl, room.roomId, room.roomSecret, "wallet");

    const close = waitForClose(wallet);
    wallet.send(JSON.stringify({ kind: "wap_response", id: "bad", ok: false, error: { nope: true } }));

    await expect(close).resolves.toMatchObject({ code: 1003 });
  });

  it("closes clients that exceed the frame size bound", async () => {
    server = await startRelayServer({ maxFrameBytes: 64 });
    const room = await createRoom(server.httpUrl);
    const dapp = await connect(room.webSocketUrl, room.roomId, room.roomSecret, "dapp");

    const close = waitForClose(dapp);
    dapp.send(JSON.stringify({ kind: "wap_event", id: "big", body: { fill: "x".repeat(128) } }));

    await expect(close).resolves.toMatchObject({ code: 1009 });
  });
});

async function createRoom(httpUrl: string): Promise<any> {
  return fetch(`${httpUrl}/v2/rooms`, { method: "POST" }).then((response) => response.json() as any);
}

function socketUrl(
  webSocketUrl: string,
  roomId: string,
  secret: string,
  role: string,
): string {
  const url = new URL(webSocketUrl);
  url.searchParams.set("room", roomId);
  url.searchParams.set("secret", secret);
  url.searchParams.set("role", role);
  return url.toString();
}

async function connect(
  webSocketUrl: string,
  roomId: string,
  secret: string,
  role: string,
): Promise<WebSocket> {
  const socket = new WebSocket(socketUrl(webSocketUrl, roomId, secret, role));
  await new Promise<void>((resolve, reject) => {
    socket.on("open", () => resolve());
    socket.on("error", reject);
  });
  return socket;
}

async function expectUpgradeRejected(url: string, statusCode: number): Promise<void> {
  const socket = new WebSocket(url);
  await new Promise<void>((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("Timed out waiting for upgrade rejection")), 1000);
    socket.on("unexpected-response", (_request, response) => {
      clearTimeout(timeout);
      try {
        expect(response.statusCode).toBe(statusCode);
        resolve();
      } catch (error) {
        reject(error);
      }
    });
    socket.on("open", () => {
      clearTimeout(timeout);
      reject(new Error("Expected relay upgrade to be rejected"));
    });
    socket.on("error", () => {
      // ws may emit an error after unexpected-response; the status assertion is handled above.
    });
  });
}

async function waitForClose(socket: WebSocket): Promise<{ code: number; reason: string }> {
  return new Promise((resolve) => {
    socket.on("close", (code, reason) => resolve({ code, reason: reason.toString("utf8") }));
  });
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
