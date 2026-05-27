import { isAssociationEnvelope } from "./envelope";
import {
  WALLET_ASSOCIATION_ENCRYPTION,
  WALLET_ASSOCIATION_PROTOCOL_VERSION,
  type AssociationDiscoverResponse,
  type AssociationEnvelope,
  type AssociationRPCRequestPayload,
  type AssociationRequestPayload,
  type AssociationResponsePayload,
} from "./protocol";
import { isSolanaChain } from "./protocol";
import { isValidSessionTokenBase64 } from "./session";

export { isAssociationEnvelope };

export function isCompatibleDiscovery(
  value: unknown,
): value is AssociationDiscoverResponse {
  if (!value || typeof value !== "object") return false;
  const response = value as Partial<AssociationDiscoverResponse>;
  return (
    response.protocolVersion === WALLET_ASSOCIATION_PROTOCOL_VERSION &&
    typeof response.name === "string" &&
    typeof response.version === "string" &&
    Array.isArray(response.transports) &&
    Array.isArray(response.chains) &&
    response.chains.some(isSolanaChain) &&
    Array.isArray(response.features) &&
    response.features.includes("solana:signMessage") &&
    response.features.includes("solana:signTransaction") &&
    response.encryption === WALLET_ASSOCIATION_ENCRYPTION &&
    typeof response.sessionTokenTtlSeconds === "number"
  );
}

export function assertAssociationEnvelope(
  value: unknown,
): asserts value is AssociationEnvelope {
  if (!isAssociationEnvelope(value)) {
    throw new Error("Invalid association envelope");
  }
}

export function isAssociationRequestPayload(
  value: unknown,
): value is AssociationRequestPayload {
  if (!value || typeof value !== "object") return false;
  const payload = value as Partial<AssociationRequestPayload>;
  return payload.kind === "create" || payload.kind === "resume";
}

export function validateAssociationRequestPayload(
  value: unknown,
): AssociationRequestPayload {
  if (!isAssociationRequestPayload(value)) {
    throw new Error("Invalid association request payload");
  }
  return value;
}

export function isAssociationResponsePayload(
  value: unknown,
): value is AssociationResponsePayload {
  if (!value || typeof value !== "object") return false;
  const payload = value as Partial<AssociationResponsePayload>;
  return (
    typeof payload.sessionId === "string" &&
    isValidSessionTokenBase64(payload.sessionTokenBase64) &&
    typeof payload.expiresAt === "string" &&
    Array.isArray(payload.accounts) &&
    Array.isArray(payload.chains) &&
    Array.isArray(payload.features) &&
    (payload.signingPolicy === "prompt" ||
      payload.signingPolicy === "allowWithoutPrompt")
  );
}

export function isAssociationRPCRequestPayload(
  value: unknown,
): value is AssociationRPCRequestPayload {
  if (!value || typeof value !== "object") return false;
  const payload = value as Partial<AssociationRPCRequestPayload>;
  return (
    typeof payload.requestId === "string" &&
    typeof payload.issuedAt === "string" &&
    isValidSessionTokenBase64(payload.sessionTokenBase64) &&
    (payload.method === "solana.signMessage" ||
      payload.method === "solana.signTransaction" ||
      payload.method === "wallet.session.rotate") &&
    typeof payload.params === "object" &&
    payload.params !== null
  );
}

export function validateAssociationRPCRequestPayload(
  value: unknown,
): AssociationRPCRequestPayload {
  if (!isAssociationRPCRequestPayload(value)) {
    throw new Error("Invalid association RPC request payload");
  }
  return value;
}
