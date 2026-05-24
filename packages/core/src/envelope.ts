import { WALLET_ASSOCIATION_PROTOCOL_VERSION, type AssociationEnvelope } from "./protocol";

export function isAssociationEnvelope(value: unknown): value is AssociationEnvelope {
  if (!value || typeof value !== "object") return false;
  const envelope = value as Partial<AssociationEnvelope>;
  return (
    envelope.protocolVersion === WALLET_ASSOCIATION_PROTOCOL_VERSION &&
    typeof envelope.keyId === "string" &&
    typeof envelope.sealedBoxBase64 === "string"
  );
}
