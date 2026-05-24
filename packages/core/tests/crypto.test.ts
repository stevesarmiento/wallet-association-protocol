import { describe, expect, it } from "vitest";
import {
  decodeHex,
  deriveHandshakeKey,
  deriveSessionKey,
  encodeHex,
  publicKeyBase64FromSecretKey
} from "../src";
import createVector from "../../../test-vectors/v0.1/handshake-create-session.json";
import messageVector from "../../../test-vectors/v0.1/sign-message-rpc.json";

describe("association crypto", () => {
  it("derives the dapp X25519 public key from the fixed private key", () => {
    expect(publicKeyBase64FromSecretKey(decodeHex(createVector.dappSecretKeyHex))).toBe(
      createVector.dappPublicKeyBase64
    );
  });

  it("derives the handshake key matching the v0.1 vector", () => {
    const key = deriveHandshakeKey({
      secretKey: decodeHex(createVector.dappSecretKeyHex),
      walletPublicKeyBase64: createVector.walletPublicKeyBase64,
      handshakeId: createVector.handshakeId,
      origin: createVector.origin
    });

    expect(encodeHex(key)).toBe(createVector.handshakeKeyHex);
  });

  it("derives the session key matching the v0.1 vector", () => {
    const key = deriveSessionKey({
      sessionTokenBase64: messageVector.sessionTokenBase64,
      sessionId: messageVector.sessionId,
      origin: messageVector.origin
    });

    expect(encodeHex(key)).toBe(messageVector.sessionKeyHex);
  });
});
