# Wallet Association Relay Transport v0.2

The relay transport lets a browser dapp and wallet meet in a short-lived room.
The relay is an untrusted packet courier.

## HTTP

- `GET /v2/health`
- `POST /v2/rooms`

Room responses include `roomId`, `roomSecret`, `webSocketUrl`, and `expiresAt`.
Default room TTL is 300 seconds.

## WebSocket

Peers connect to:

```text
/v2/relay?room=<roomId>&secret=<roomSecret>&role=dapp|wallet
```

The relay validates room existence, expiry, role uniqueness, room secret, JSON
shape, frame size, and request id shape. It must not inspect encrypted WAP
envelopes.

## Frames

```ts
type RelayFrame =
  | {
      kind: "joined";
      roomId: string;
      role: "dapp" | "wallet";
      peerConnected: boolean;
    }
  | { kind: "peer_joined"; role: "dapp" | "wallet" }
  | { kind: "peer_left"; role: "dapp" | "wallet" }
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
```

`wap_request`, `wap_response`, and `wap_event` payloads carry normal WAP
messages. Association and RPC payloads remain encrypted exactly as in localhost
v0.1.
