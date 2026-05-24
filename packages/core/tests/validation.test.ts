import { describe, expect, it } from "vitest";
import {
  WALLET_ASSOCIATION_ENCRYPTION,
  WALLET_ASSOCIATION_PROTOCOL_VERSION,
  assertAssociationEnvelope,
  isCompatibleDiscovery,
  validateAssociationRequestPayload,
  validateAssociationRPCRequestPayload,
  type AssociationDiscoverResponse
} from "../src";

const discovery: AssociationDiscoverResponse = {
  name: "Native Wallet",
  version: "0.1.0",
  protocolVersion: WALLET_ASSOCIATION_PROTOCOL_VERSION,
  transports: [{ type: "localhost", host: "127.0.0.1", port: 51884 }],
  chains: ["solana:devnet"],
  features: ["solana:signMessage", "solana:signTransaction"],
  encryption: WALLET_ASSOCIATION_ENCRYPTION,
  sessionTokenTtlSeconds: 604800
};

describe("protocol validation", () => {
  it("accepts compatible discovery responses", () => {
    expect(isCompatibleDiscovery(discovery)).toBe(true);
  });

  it("rejects incompatible discovery responses", () => {
    expect(isCompatibleDiscovery({ ...discovery, protocolVersion: "1" })).toBe(false);
    expect(isCompatibleDiscovery({ ...discovery, encryption: "none" })).toBe(false);
  });

  it("validates envelope shape", () => {
    expect(() => assertAssociationEnvelope({ protocolVersion: "2", keyId: "k", sealedBoxBase64: "AA==" })).not.toThrow();
    expect(() => assertAssociationEnvelope({ protocolVersion: "2", keyId: "k" })).toThrow("Invalid association envelope");
  });

  it("validates association and RPC payload shapes", () => {
    expect(validateAssociationRequestPayload({ kind: "create" }).kind).toBe("create");
    expect(() => validateAssociationRequestPayload({ kind: "delete" })).toThrow("Invalid association request payload");

    expect(
      validateAssociationRPCRequestPayload({
        requestId: "request",
        issuedAt: "2026-05-24T00:00:00.000Z",
        sessionTokenBase64: "token",
        method: "solana.signMessage",
        params: { accountAddress: "address", messageBase64: "AA==" }
      }).method
    ).toBe("solana.signMessage");
    expect(() =>
      validateAssociationRPCRequestPayload({
        requestId: "request",
        issuedAt: "2026-05-24T00:00:00.000Z",
        sessionTokenBase64: "token",
        method: "solana.unsupported",
        params: { accountAddress: "address" }
      })
    ).toThrow("Invalid association RPC request payload");
  });
});
