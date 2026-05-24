import { describe, expect, it } from "vitest";
import { decodeHex, deriveHandshakeKey, deriveSessionKey, openJson, sealJson, type AssociationEnvelope } from "../src";
import createVector from "../../../test-vectors/v0.1/handshake-create-session.json";
import messageVector from "../../../test-vectors/v0.1/sign-message-rpc.json";

describe("association envelopes", () => {
  it("seals deterministic association payloads matching the vector", () => {
    const key = deriveHandshakeKey({
      secretKey: decodeHex(createVector.dappSecretKeyHex),
      walletPublicKeyBase64: createVector.walletPublicKeyBase64,
      handshakeId: createVector.handshakeId,
      origin: createVector.origin
    });

    const envelope = sealJson(createVector.handshakeId, key, createVector.create.payload, {
      nonce: decodeHex(createVector.create.nonceHex)
    });

    expect(envelope).toEqual(createVector.create.envelope);
  });

  it("opens deterministic RPC payloads matching the vector", () => {
    const key = deriveSessionKey({
      sessionTokenBase64: messageVector.sessionTokenBase64,
      sessionId: messageVector.sessionId,
      origin: messageVector.origin
    });

    expect(openJson(key, messageVector.request.envelope as AssociationEnvelope)).toEqual(messageVector.request.payload);
    expect(openJson(key, messageVector.response.envelope as AssociationEnvelope)).toEqual(messageVector.response.payload);
  });
});
