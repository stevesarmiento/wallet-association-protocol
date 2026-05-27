import { describe, expect, it } from "vitest";
import Ajv2020 from "ajv/dist/2020";
import associationPayloadSchema from "../../../schemas/association-payload.schema.json";
import discoverSchema from "../../../schemas/discover.schema.json";
import envelopeSchema from "../../../schemas/envelope.schema.json";
import errorSchema from "../../../schemas/error.schema.json";
import handshakeSchema from "../../../schemas/handshake.schema.json";
import connectionUriSchema from "../../../schemas/connection-uri.schema.json";
import relayFrameSchema from "../../../schemas/relay-frame.schema.json";
import relayRoomSchema from "../../../schemas/relay-room.schema.json";
import rpcPayloadSchema from "../../../schemas/rpc-payload.schema.json";
import sessionEventSchema from "../../../schemas/session-event.schema.json";
import sessionRotationSchema from "../../../schemas/session-rotation.schema.json";
import createVector from "../../../test-vectors/v0.1/handshake-create-session.json";
import messageVector from "../../../test-vectors/v0.1/sign-message-rpc.json";

const ajv = new Ajv2020({ validateFormats: false });

describe("v0.1 JSON schemas", () => {
  it("validate representative protocol messages and vectors", () => {
    const validateDiscover = ajv.compile(discoverSchema);
    expect(
      validateDiscover({
        name: "Native Wallet",
        version: "0.1.0",
        protocolVersion: "2",
        transports: [{ type: "localhost", host: "127.0.0.1", port: 51884 }],
        chains: ["solana:devnet"],
        features: ["solana:signMessage", "solana:signTransaction"],
        encryption: "x25519-hkdf-sha256-chacha20poly1305",
        sessionTokenTtlSeconds: 604800
      })
    ).toBe(true);

    const validateHandshake = ajv.compile(handshakeSchema);
    expect(
      validateHandshake({
        protocolVersion: "2",
        dappPublicKeyBase64: createVector.dappPublicKeyBase64,
        metadata: { origin: createVector.origin, appName: "Example" }
      })
    ).toBe(true);
    expect(
      validateHandshake({
        protocolVersion: "2",
        handshakeId: createVector.handshakeId,
        walletPublicKeyBase64: createVector.walletPublicKeyBase64,
        expiresAt: "2026-05-24T00:01:00.000Z"
      })
    ).toBe(true);

    const validateEnvelope = ajv.compile(envelopeSchema);
    expect(validateEnvelope(createVector.create.envelope)).toBe(true);

    const validateAssociationPayload = ajv.compile(associationPayloadSchema);
    expect(validateAssociationPayload(createVector.create.payload)).toBe(true);
    expect(validateAssociationPayload(createVector.createResponse.payload)).toBe(true);

    const validateRpcPayload = ajv.compile(rpcPayloadSchema);
    expect(validateRpcPayload(messageVector.request.payload)).toBe(true);
    expect(validateRpcPayload(messageVector.response.payload)).toBe(true);

    const validateError = ajv.compile(errorSchema);
    expect(validateError({ error: { code: "session_invalid", message: "session expired" } })).toBe(true);
  });

  it("validates representative v0.2 relay messages", () => {
    const token = "BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=";

    expect(
      ajv.compile(relayRoomSchema)({
        protocolVersion: "2",
        roomId: "room",
        roomSecret: "secret",
        webSocketUrl: "ws://127.0.0.1:9000/v2/relay",
        expiresAt: "2026-05-24T00:05:00.000Z"
      })
    ).toBe(true);

    const validateRelayFrame = ajv.compile(relayFrameSchema);
    expect(validateRelayFrame({ kind: "wap_request", id: "request-1", operation: "discover" })).toBe(true);
    expect(validateRelayFrame({ kind: "wap_response", id: "request-1", ok: true, body: { protocolVersion: "2" } })).toBe(true);
    expect(
      validateRelayFrame({
        kind: "wap_response",
        id: "request-1",
        ok: false,
        error: { error: { code: "session_invalid", message: "expired" } }
      })
    ).toBe(true);

    expect(
      ajv.compile(sessionEventSchema)({
        eventId: "event",
        issuedAt: "2026-05-24T00:00:00.000Z",
        sessionTokenBase64: token,
        type: "accounts_changed",
        accounts: []
      })
    ).toBe(true);

    const validateRotation = ajv.compile(sessionRotationSchema);
    expect(validateRotation({ reason: "dapp_requested" })).toBe(true);
    expect(
      validateRotation({
        sessionId: "session",
        sessionTokenBase64: token,
        expiresAt: "2026-05-31T00:00:00.000Z"
      })
    ).toBe(true);

    expect(
      ajv.compile(connectionUriSchema)({
        version: "2",
        transport: "relay",
        relay: "ws://127.0.0.1:9000/v2/relay",
        room: "room",
        secret: "secret",
        origin: "https://app.example",
        expiresAt: "2026-05-24T00:05:00.000Z"
      })
    ).toBe(true);
  });
});
