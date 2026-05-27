import {
  createServer,
  type IncomingMessage,
  type Server,
  type ServerResponse,
} from "node:http";
import { randomBytes, randomUUID } from "node:crypto";
import type { Duplex } from "node:stream";
import { WebSocketServer, type WebSocket } from "ws";
import type { AssociationOperation } from "@wallet-association/core";

export interface RelayServerOptions {
  host?: string;
  port?: number;
  roomTtlMs?: number;
  maxFrameBytes?: number;
}

export interface RelayServerHandle {
  readonly httpUrl: string;
  readonly webSocketUrl: string;
  close(): Promise<void>;
}

type RelayRole = "dapp" | "wallet";

type RelayFrame =
  | { kind: "joined"; roomId: string; role: RelayRole; peerConnected: boolean }
  | { kind: "peer_joined"; role: RelayRole }
  | { kind: "peer_left"; role: RelayRole }
  | {
      kind: "wap_request";
      id: string;
      operation: AssociationOperation;
      body?: unknown;
    }
  | { kind: "wap_response"; id: string; ok: true; body: unknown }
  | { kind: "wap_response"; id: string; ok: false; error: unknown }
  | { kind: "wap_event"; id: string; body: unknown }
  | { kind: "ping" | "pong" };

interface RelayRoom {
  id: string;
  secret: string;
  expiresAt: Date;
  sockets: Partial<Record<RelayRole, WebSocket>>;
}

const DEFAULT_ROOM_TTL_MS = 300_000;
const DEFAULT_MAX_FRAME_BYTES = 65_536;
const INVALID_FRAME_CLOSE_CODE = 1003;
const POLICY_CLOSE_CODE = 1008;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9._:-]{1,128}$/;

export async function startRelayServer(
  options: RelayServerOptions = {},
): Promise<RelayServerHandle> {
  const host = options.host ?? "127.0.0.1";
  const roomTtlMs = options.roomTtlMs ?? DEFAULT_ROOM_TTL_MS;
  const maxFrameBytes = options.maxFrameBytes ?? DEFAULT_MAX_FRAME_BYTES;
  const rooms = new Map<string, RelayRoom>();
  const server = createServer((request, response) =>
    handleHttp(request, response, rooms, roomTtlMs, host, server),
  );
  const webSockets = new WebSocketServer({
    noServer: true,
    maxPayload: maxFrameBytes,
  });

  server.on("upgrade", (request, socket, head) => {
    const url = new URL(request.url ?? "/", `http://${host}`);
    if (url.pathname !== "/v2/relay") {
      rejectUpgrade(socket, 404, "not found");
      return;
    }

    const roomId = url.searchParams.get("room") ?? "";
    const secret = url.searchParams.get("secret") ?? "";
    const role = url.searchParams.get("role") ?? "";
    const room = rooms.get(roomId);

    if (!room || (role !== "dapp" && role !== "wallet")) {
      rejectUpgrade(socket, 403, "forbidden");
      return;
    }
    if (room.expiresAt <= new Date()) {
      rooms.delete(roomId);
      rejectUpgrade(socket, room.secret === secret ? 410 : 403, room.secret === secret ? "room expired" : "forbidden");
      return;
    }
    if (room.secret !== secret) {
      rejectUpgrade(socket, 403, "forbidden");
      return;
    }
    if (room.sockets[role]) {
      rejectUpgrade(socket, 409, "role already joined");
      return;
    }

    webSockets.handleUpgrade(request, socket, head, (webSocket) => {
      attachSocket(room, role, webSocket);
    });
  });

  await new Promise<void>((resolve) =>
    server.listen(options.port ?? 0, host, resolve),
  );
  const address = server.address();
  if (!address || typeof address === "string") {
    throw new Error("Relay server did not publish a TCP address");
  }
  const httpUrl = `http://${host}:${address.port}`;
  const webSocketUrl = `ws://${host}:${address.port}/v2/relay`;

  return {
    httpUrl,
    webSocketUrl,
    close: () =>
      new Promise<void>((resolve, reject) => {
        for (const client of webSockets.clients) client.terminate();
        webSockets.close();
        server.close((error) => (error ? reject(error) : resolve()));
      }),
  };

  function attachSocket(room: RelayRoom, role: RelayRole, socket: WebSocket) {
    room.sockets[role] = socket;
    const peerRole = role === "dapp" ? "wallet" : "dapp";
    const peer = room.sockets[peerRole];
    send(socket, {
      kind: "joined",
      roomId: room.id,
      role,
      peerConnected: Boolean(peer),
    });
    if (peer) send(peer, { kind: "peer_joined", role });

    socket.on("error", () => {
      // ws emits protocol errors such as maxPayload violations before closing.
    });

    socket.on("message", (data) => {
      if (rawDataLength(data) > maxFrameBytes) {
        socket.close(1009, "frame too large");
        return;
      }
      const frame = parseFrame(data);
      if (!frame || !isForwardableFrame(frame)) {
        socket.close(INVALID_FRAME_CLOSE_CODE, "invalid frame");
        return;
      }
      if (frame.kind === "ping") {
        send(socket, { kind: "pong" });
        return;
      }
      const target = room.sockets[peerRole];
      if (target) send(target, frame);
    });

    socket.on("close", () => {
      if (room.sockets[role] === socket) delete room.sockets[role];
      const target = room.sockets[peerRole];
      if (target) send(target, { kind: "peer_left", role });
    });
  }
}

function handleHttp(
  request: IncomingMessage,
  response: ServerResponse,
  rooms: Map<string, RelayRoom>,
  roomTtlMs: number,
  host: string,
  server: Server,
) {
  const url = new URL(request.url ?? "/", `http://${host}`);
  if (request.method === "GET" && url.pathname === "/v2/health") {
    respondJson(response, 200, { status: "ok" });
    return;
  }
  if (request.method === "POST" && url.pathname === "/v2/rooms") {
    pruneExpiredRooms(rooms);
    const roomId = randomUUID();
    const secret = randomBytes(24).toString("base64url");
    const expiresAt = new Date(Date.now() + roomTtlMs);
    rooms.set(roomId, { id: roomId, secret, expiresAt, sockets: {} });
    const address = server.address();
    const port = address && typeof address !== "string" ? address.port : 0;
    respondJson(response, 200, {
      protocolVersion: "2",
      roomId,
      roomSecret: secret,
      webSocketUrl: `ws://${host}:${port}/v2/relay`,
      expiresAt: expiresAt.toISOString(),
    });
    return;
  }
  respondJson(response, 404, {
    error: { code: "not_found", message: "not found" },
  });
}

function respondJson(response: ServerResponse, status: number, body: unknown) {
  response.statusCode = status;
  response.setHeader("Content-Type", "application/json");
  response.end(JSON.stringify(body));
}

function pruneExpiredRooms(rooms: Map<string, RelayRoom>) {
  const now = new Date();
  for (const [id, room] of rooms) {
    if (room.expiresAt <= now) {
      room.sockets.dapp?.close(POLICY_CLOSE_CODE, "room expired");
      room.sockets.wallet?.close(POLICY_CLOSE_CODE, "room expired");
      rooms.delete(id);
    }
  }
}

function send(socket: WebSocket, frame: RelayFrame) {
  if (socket.readyState === 1) {
    socket.send(JSON.stringify(frame));
  }
}

function rejectUpgrade(socket: Duplex, status: number, message: string) {
  socket.write(`HTTP/1.1 ${status} ${message}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
  socket.destroy();
}

function rawDataLength(data: Buffer | ArrayBuffer | Buffer[]): number {
  if (Array.isArray(data))
    return data.reduce((total, part) => total + part.byteLength, 0);
  return data.byteLength;
}

function parseFrame(data: Buffer | ArrayBuffer | Buffer[]): RelayFrame | null {
  try {
    const text = Array.isArray(data)
      ? Buffer.concat(data).toString("utf8")
      : Buffer.isBuffer(data)
        ? data.toString("utf8")
        : Buffer.from(new Uint8Array(data)).toString("utf8");
    return JSON.parse(text) as RelayFrame;
  } catch {
    return null;
  }
}

function isForwardableFrame(frame: RelayFrame): boolean {
  if (!isRecord(frame) || typeof frame.kind !== "string") return false;
  if (frame.kind === "ping" || frame.kind === "pong") return true;
  if (!("id" in frame) || typeof frame.id !== "string" || !REQUEST_ID_PATTERN.test(frame.id)) return false;
  switch (frame.kind) {
    case "wap_request":
      return ["discover", "handshake", "associate", "rpc"].includes(frame.operation);
    case "wap_response":
      if (typeof frame.ok !== "boolean") return false;
      if (frame.ok === true) return "body" in frame;
      return isErrorBody(frame.error);
    case "wap_event":
      return isRecord(frame.body);
    default:
      return false;
  }
}

function isErrorBody(value: unknown): boolean {
  if (!isRecord(value) || !isRecord(value.error)) return false;
  return typeof value.error.code === "string" && typeof value.error.message === "string";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
