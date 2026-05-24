export const WALLET_ASSOCIATION_PROTOCOL_VERSION = "2" as const;
export const WALLET_ASSOCIATION_ENCRYPTION = "x25519-hkdf-sha256-chacha20poly1305" as const;
export const WALLET_ASSOCIATION_HANDSHAKE_TTL_SECONDS = 5 * 60;
export const WALLET_ASSOCIATION_SESSION_TTL_SECONDS = 7 * 24 * 60 * 60;
export const WALLET_ASSOCIATION_RPC_CLOCK_SKEW_SECONDS = 60;

export interface AssociationTransportDescriptor {
  type: string;
  host?: string;
  port?: number;
}

export interface AssociationDiscoverResponse {
  name: string;
  version: string;
  protocolVersion: typeof WALLET_ASSOCIATION_PROTOCOL_VERSION;
  transports: AssociationTransportDescriptor[];
  chains: string[];
  features: string[];
  encryption: typeof WALLET_ASSOCIATION_ENCRYPTION;
  sessionTokenTtlSeconds: number;
}

export interface AssociationRequestMetadata {
  origin?: string;
  appName?: string;
  appIcon?: string;
}

export interface AssociationHandshakeRequest {
  protocolVersion: typeof WALLET_ASSOCIATION_PROTOCOL_VERSION;
  dappPublicKeyBase64: string;
  metadata?: AssociationRequestMetadata;
}

export interface AssociationHandshakeResponse {
  protocolVersion: typeof WALLET_ASSOCIATION_PROTOCOL_VERSION;
  handshakeId: string;
  walletPublicKeyBase64: string;
  expiresAt: string;
}

export interface AssociationEnvelope {
  protocolVersion: typeof WALLET_ASSOCIATION_PROTOCOL_VERSION;
  keyId: string;
  sealedBoxBase64: string;
}

export interface AssociationAccount {
  address: string;
  publicKey: number[] | string;
  chains: readonly string[];
  features: readonly string[];
  label?: string;
  icon?: string;
}

export type AssociationRequestKind = "create" | "resume";

export interface AssociationRequestPayload {
  kind: AssociationRequestKind;
  requestedChains?: string[];
  requestedFeatures?: string[];
  resumeSessionId?: string;
  resumeSessionTokenBase64?: string;
}

export type AssociationSigningPolicy = "prompt" | "allowWithoutPrompt";

export interface AssociationResponsePayload {
  sessionId: string;
  sessionTokenBase64: string;
  expiresAt: string;
  accounts: AssociationAccount[];
  chains: string[];
  features: string[];
  signingPolicy: AssociationSigningPolicy;
}

export type AssociationRPCMethod = "solana.signMessage" | "solana.signTransaction";

export interface AssociationRPCRequestPayload {
  requestId: string;
  issuedAt: string;
  sessionTokenBase64: string;
  method: AssociationRPCMethod;
  params: {
    accountAddress: string;
    chain?: string;
    messageBase64?: string;
    transactionBase64?: string;
  };
}

export type AssociationRPCResponsePayload =
  | {
      requestId: string;
      result: { signatureBase64: string };
    }
  | {
      requestId: string;
      result: { signedTransactionBase64: string; signature: string };
    };

export interface AssociationErrorBody {
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
}

export type SignMessageInput = {
  account: { address: string };
  message: Uint8Array;
  chain?: string;
};

export type SignTransactionInput = {
  account: { address: string };
  transaction?: Uint8Array;
  transactions?: Uint8Array[];
  chain?: string;
};

export function isSolanaChain(value: unknown): value is `${string}:${string}` {
  return typeof value === "string" && value.startsWith("solana:");
}
