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

export function isStoredSession(value: Partial<WalletAssociationStoredSession>): value is WalletAssociationStoredSession {
  return (
    typeof value.sessionId === "string" &&
    typeof value.sessionTokenBase64 === "string" &&
    typeof value.expiresAt === "string" &&
    typeof value.origin === "string" &&
    typeof value.walletName === "string" &&
    typeof value.walletVersion === "string"
  );
}

export function isExpired(expiresAt: string, nowMs = Date.now()): boolean {
  const timestamp = Date.parse(expiresAt);
  return Number.isNaN(timestamp) || timestamp <= nowMs;
}
