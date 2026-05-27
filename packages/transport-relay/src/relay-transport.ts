import {
  toWalletAssociationError,
  type AssociationClientTransport,
  type AssociationErrorBody,
  type AssociationEnvelope,
  type AssociationOperation,
  type AssociationTransportEvent,
} from "@wallet-association/core";
import { createRelayAssociationUri } from "./relay-uri";

export interface CreateRelayDappTransportInput {
  relayHttpUrl: string;
  origin: string;
  fetch?: typeof fetch;
  webSocketFactory?: (url: string) => RelayWebSocket;
  signal?: AbortSignal;
}

export interface RelayDappTransport extends AssociationClientTransport {
  readonly type: "relay";
  readonly connectionUri: string;
  readonly roomId: string;
  waitForWallet(options?: { signal?: AbortSignal }): Promise<void>;
}

export interface RelayRoomResponse {
  protocolVersion: "2";
  roomId: string;
  roomSecret: string;
  webSocketUrl: string;
  expiresAt: string;
}

export type RelayRole = "dapp" | "wallet";

export type RelayFrame =
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
  | { kind: "wap_response"; id: string; ok: false; error: AssociationErrorBody }
  | { kind: "wap_event"; id: string; body: AssociationEnvelope }
  | { kind: "ping" | "pong" };

export interface RelayWebSocket {
  readyState: number;
  send(data: string): void;
  close(): void;
  addEventListener(type: "open", listener: () => void): void;
  addEventListener(
    type: "message",
    listener: (event: { data: unknown }) => void,
  ): void;
  addEventListener(type: "error", listener: (event: unknown) => void): void;
  addEventListener(type: "close", listener: () => void): void;
}

const OPEN = 1;

export async function createRelayDappTransport(
  input: CreateRelayDappTransportInput,
): Promise<RelayDappTransport> {
  const fetchImpl = input.fetch ?? globalThis.fetch;
  if (typeof fetchImpl !== "function") {
    throw new Error("fetch is unavailable");
  }

  const roomResponse = await createRoom(
    input.relayHttpUrl,
    fetchImpl,
    input.signal,
  );
  const socketUrl = socketUrlForRole(
    roomResponse.webSocketUrl,
    roomResponse.roomId,
    roomResponse.roomSecret,
    "dapp",
  );
  const webSocketFactory = input.webSocketFactory ?? defaultWebSocketFactory;
  const socket = webSocketFactory(socketUrl);
  const transport = new RelayDappTransportImpl(
    socket,
    roomResponse,
    input.origin,
  );
  await transport.open(input.signal);
  return transport;
}

async function createRoom(
  relayHttpUrl: string,
  fetchImpl: typeof fetch,
  signal?: AbortSignal,
): Promise<RelayRoomResponse> {
  const init: RequestInit = {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{}",
  };
  if (signal) init.signal = signal;
  const response = await fetchImpl(new URL("/v2/rooms", relayHttpUrl), init);
  const body = (await response.json()) as unknown;
  if (!response.ok) {
    throw toWalletAssociationError(body, response.status);
  }
  if (!isRelayRoomResponse(body)) {
    throw new Error("Relay returned a malformed room response");
  }
  return body;
}

function isRelayRoomResponse(value: unknown): value is RelayRoomResponse {
  if (!value || typeof value !== "object") return false;
  const room = value as Partial<RelayRoomResponse>;
  return (
    room.protocolVersion === "2" &&
    typeof room.roomId === "string" &&
    typeof room.roomSecret === "string" &&
    typeof room.webSocketUrl === "string" &&
    typeof room.expiresAt === "string"
  );
}

function socketUrlForRole(
  webSocketUrl: string,
  roomId: string,
  roomSecret: string,
  role: RelayRole,
): string {
  const url = new URL(webSocketUrl);
  url.searchParams.set("room", roomId);
  url.searchParams.set("secret", roomSecret);
  url.searchParams.set("role", role);
  return url.toString();
}

function defaultWebSocketFactory(url: string): RelayWebSocket {
  const WebSocketCtor = globalThis.WebSocket;
  if (typeof WebSocketCtor !== "function") {
    throw new Error("WebSocket is unavailable");
  }
  return new WebSocketCtor(url);
}

class RelayDappTransportImpl implements RelayDappTransport {
  readonly type = "relay" as const;
  readonly connectionUri: string;
  readonly roomId: string;

  private sequence = 0;
  private walletConnected = false;
  private readonly pending = new Map<
    string,
    { resolve: (value: unknown) => void; reject: (reason: unknown) => void }
  >();
  private readonly eventListeners = new Set<
    (event: AssociationTransportEvent) => void
  >();
  private readonly walletWaiters = new Set<{
    resolve: () => void;
    reject: (reason: unknown) => void;
  }>();

  constructor(
    private readonly socket: RelayWebSocket,
    private readonly room: RelayRoomResponse,
    origin: string,
  ) {
    this.roomId = room.roomId;
    this.connectionUri = createRelayAssociationUri({
      version: "2",
      transport: "relay",
      relay: room.webSocketUrl,
      room: room.roomId,
      secret: room.roomSecret,
      origin,
      expiresAt: room.expiresAt,
    });
    this.socket.addEventListener("message", (event) =>
      this.handleMessage(event.data),
    );
    this.socket.addEventListener("close", () => this.handleClose());
    this.socket.addEventListener("error", (event) => this.rejectAll(event));
  }

  open(signal?: AbortSignal): Promise<void> {
    if (this.socket.readyState === OPEN) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const onAbort = () =>
        reject(new DOMException("Relay connection aborted", "AbortError"));
      signal?.addEventListener("abort", onAbort, { once: true });
      this.socket.addEventListener("open", () => {
        signal?.removeEventListener("abort", onAbort);
        resolve();
      });
      this.socket.addEventListener("error", (event) => {
        signal?.removeEventListener("abort", onAbort);
        reject(event);
      });
    });
  }

  request<T>(
    operation: AssociationOperation,
    body?: unknown,
    options?: { signal?: AbortSignal },
  ): Promise<T> {
    if (this.socket.readyState !== OPEN) {
      return Promise.reject(new Error("Relay socket is not open"));
    }
    const id = `request-${++this.sequence}`;
    const frame: RelayFrame =
      body === undefined
        ? { kind: "wap_request", id, operation }
        : { kind: "wap_request", id, operation, body };
    return new Promise<T>((resolve, reject) => {
      const onAbort = () => {
        this.pending.delete(id);
        reject(new DOMException("Relay request aborted", "AbortError"));
      };
      options?.signal?.addEventListener("abort", onAbort, { once: true });
      this.pending.set(id, {
        resolve: (value) => {
          options?.signal?.removeEventListener("abort", onAbort);
          resolve(value as T);
        },
        reject: (reason) => {
          options?.signal?.removeEventListener("abort", onAbort);
          reject(reason);
        },
      });
      this.socket.send(JSON.stringify(frame));
    });
  }

  onEvent(listener: (event: AssociationTransportEvent) => void): () => void {
    this.eventListeners.add(listener);
    return () => this.eventListeners.delete(listener);
  }

  waitForWallet(options?: { signal?: AbortSignal }): Promise<void> {
    if (this.walletConnected) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const waiter = {
        resolve: () => {
          options?.signal?.removeEventListener("abort", onAbort);
          resolve();
        },
        reject,
      };
      const onAbort = () => {
        this.walletWaiters.delete(waiter);
        reject(new DOMException("Relay wallet wait aborted", "AbortError"));
      };
      options?.signal?.addEventListener("abort", onAbort, { once: true });
      this.walletWaiters.add(waiter);
    });
  }

  close(): void {
    this.socket.close();
  }

  private handleMessage(data: unknown) {
    const text =
      typeof data === "string"
        ? data
        : data instanceof ArrayBuffer
          ? new TextDecoder().decode(data)
          : String(data);
    const frame = JSON.parse(text) as RelayFrame;
    switch (frame.kind) {
      case "joined":
        this.walletConnected = frame.peerConnected;
        if (this.walletConnected) this.resolveWalletWaiters();
        break;
      case "peer_joined":
        if (frame.role === "wallet") {
          this.walletConnected = true;
          this.resolveWalletWaiters();
          this.emit({ type: "peer_connected" });
        }
        break;
      case "peer_left":
        if (frame.role === "wallet") {
          this.walletConnected = false;
          this.emit({ type: "peer_disconnected" });
        }
        break;
      case "wap_response": {
        const pending = this.pending.get(frame.id);
        if (!pending) return;
        this.pending.delete(frame.id);
        if (frame.ok) pending.resolve(frame.body);
        else pending.reject(toWalletAssociationError(frame.error, 500));
        break;
      }
      case "wap_event":
        this.emit({ type: "session_event", body: frame.body });
        break;
      case "ping":
        this.socket.send(JSON.stringify({ kind: "pong" } satisfies RelayFrame));
        break;
      case "pong":
      case "wap_request":
        break;
    }
  }

  private handleClose() {
    this.emit({ type: "closed" });
    this.rejectAll(new Error("Relay socket closed"));
  }

  private emit(event: AssociationTransportEvent) {
    for (const listener of this.eventListeners) {
      listener(event);
    }
  }

  private resolveWalletWaiters() {
    for (const waiter of this.walletWaiters) waiter.resolve();
    this.walletWaiters.clear();
  }

  private rejectAll(reason: unknown) {
    for (const pending of this.pending.values()) pending.reject(reason);
    this.pending.clear();
    for (const waiter of this.walletWaiters) waiter.reject(reason);
    this.walletWaiters.clear();
  }
}
