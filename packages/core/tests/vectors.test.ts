import { describe, expect, it } from "vitest";
import { decodeHex, deriveHandshakeKey, deriveSessionKey, openJson, sealJson, type AssociationEnvelope } from "../src";
import createVector from "../../../test-vectors/v0.1/handshake-create-session.json";
import invalidVector from "../../../test-vectors/v0.1/invalid-envelope.json";
import resumeVector from "../../../test-vectors/v0.1/resume-session.json";
import messageVector from "../../../test-vectors/v0.1/sign-message-rpc.json";
import transactionVector from "../../../test-vectors/v0.1/sign-transaction-rpc.json";

describe("v0.1 test vectors", () => {
  it("opens and reproduces association create vectors", () => {
    const key = deriveHandshakeKey({
      secretKey: decodeHex(createVector.dappSecretKeyHex),
      walletPublicKeyBase64: createVector.walletPublicKeyBase64,
      handshakeId: createVector.handshakeId,
      origin: createVector.origin
    });

    expect(openJson(key, createVector.create.envelope as AssociationEnvelope)).toEqual(createVector.create.payload);
    expect(
      sealJson(createVector.handshakeId, key, createVector.createResponse.payload, {
        nonce: decodeHex(createVector.createResponse.nonceHex)
      })
    ).toEqual(createVector.createResponse.envelope);
  });

  it("opens and reproduces session resume vectors", () => {
    const key = deriveHandshakeKey({
      secretKey: decodeHex(resumeVector.dappSecretKeyHex),
      walletPublicKeyBase64: resumeVector.walletPublicKeyBase64,
      handshakeId: resumeVector.handshakeId,
      origin: resumeVector.origin
    });

    expect(openJson(key, resumeVector.resume.envelope as AssociationEnvelope)).toEqual(resumeVector.resume.payload);
    expect(
      sealJson(resumeVector.handshakeId, key, resumeVector.resume.payload, {
        nonce: decodeHex(resumeVector.resume.nonceHex)
      })
    ).toEqual(resumeVector.resume.envelope);
  });

  it("opens and reproduces Solana signing RPC vectors", () => {
    for (const vector of [messageVector, transactionVector]) {
      const key = deriveSessionKey({
        sessionTokenBase64: vector.sessionTokenBase64,
        sessionId: vector.sessionId,
        origin: vector.origin
      });

      expect(openJson(key, vector.request.envelope as AssociationEnvelope)).toEqual(vector.request.payload);
      expect(openJson(key, vector.response.envelope as AssociationEnvelope)).toEqual(vector.response.payload);
      expect(
        sealJson(vector.sessionId, key, vector.request.payload, {
          nonce: decodeHex(vector.request.nonceHex)
        })
      ).toEqual(vector.request.envelope);
    }
  });

  it("rejects malformed envelopes", () => {
    const key = deriveSessionKey({
      sessionTokenBase64: messageVector.sessionTokenBase64,
      sessionId: messageVector.sessionId,
      origin: messageVector.origin
    });

    expect(() => openJson(key, invalidVector.malformed as AssociationEnvelope)).toThrow();
  });
});
