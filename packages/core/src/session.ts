export const WALLET_ASSOCIATION_SESSION_TOKEN_BYTES = 32;

export interface WalletAssociationStoredSession {
  sessionId: string;
  sessionTokenBase64: string;
  expiresAt: string;
  origin: string;
  walletName: string;
  walletVersion: string;
}

export interface WalletAssociationStorage {
  get(): WalletAssociationStoredSession | null;
  set(session: WalletAssociationStoredSession): void;
  clear(): void;
}

export function isStoredSession(value: unknown): value is WalletAssociationStoredSession {
  if (!value || typeof value !== "object") return false;
  const session = value as Partial<WalletAssociationStoredSession>;
  return (
    typeof session.sessionId === "string" &&
    isValidSessionTokenBase64(session.sessionTokenBase64) &&
    typeof session.expiresAt === "string" &&
    typeof session.origin === "string" &&
    typeof session.walletName === "string" &&
    typeof session.walletVersion === "string"
  );
}

export function isExpired(expiresAt: string, nowMs = Date.now()): boolean {
  const timestamp = Date.parse(expiresAt);
  return Number.isNaN(timestamp) || timestamp <= nowMs;
}

export function isValidSessionTokenBase64(value: unknown): value is string {
  if (typeof value !== "string") return false;
  try {
    return decodeBase64(value).length === WALLET_ASSOCIATION_SESSION_TOKEN_BYTES;
  } catch {
    return false;
  }
}

function decodeBase64(base64: string): Uint8Array {
  const nodeBuffer = globalThisBuffer();
  if (nodeBuffer) {
    return new Uint8Array(nodeBuffer.from(base64, "base64"));
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function globalThisBuffer(): { from(value: string, encoding?: string): Uint8Array } | null {
  const candidate = (globalThis as { Buffer?: unknown }).Buffer;
  return typeof candidate === "function"
    ? (candidate as unknown as { from(value: string, encoding?: string): Uint8Array })
    : null;
}
