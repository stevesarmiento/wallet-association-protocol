import {
  isExpired,
  type AssociationDiscoverResponse,
  type WalletAssociationStorage,
  type WalletAssociationStoredSession
} from "@wallet-association/core";

export interface CreateWalletAssociationStorageInput {
  discovery: AssociationDiscoverResponse;
  origin: string;
  transportId: string;
  storageKey?: string;
}

export function createWalletAssociationStorage(input: CreateWalletAssociationStorageInput): WalletAssociationStorage {
  const key = sessionStorageKey(input);

  return {
    get() {
      if (!isLocalStorageAvailable()) return null;
      try {
        const raw = window.localStorage.getItem(key);
        if (!raw) return null;
        const session = JSON.parse(raw) as Partial<WalletAssociationStoredSession>;
        if (!isValidStoredSession(session) || session.origin !== input.origin || isExpired(session.expiresAt)) {
          window.localStorage.removeItem(key);
          return null;
        }
        return session;
      } catch {
        try {
          window.localStorage.removeItem(key);
        } catch {
          // Ignore storage failures.
        }
        return null;
      }
    },
    set(session) {
      if (!isLocalStorageAvailable()) return;
      try {
        window.localStorage.setItem(key, JSON.stringify(session));
      } catch {
        // Ignore storage quota and privacy mode failures.
      }
    },
    clear() {
      if (!isLocalStorageAvailable()) return;
      try {
        window.localStorage.removeItem(key);
      } catch {
        // Ignore storage failures.
      }
    }
  };
}

function isValidStoredSession(value: unknown): value is WalletAssociationStoredSession {
  if (!value || typeof value !== "object") return false;
  const session = value as Partial<WalletAssociationStoredSession>;
  return (
    typeof session.sessionId === "string" &&
    typeof session.sessionTokenBase64 === "string" &&
    isValidSessionTokenBase64(session.sessionTokenBase64) &&
    typeof session.expiresAt === "string" &&
    typeof session.origin === "string" &&
    typeof session.walletName === "string" &&
    typeof session.walletVersion === "string"
  );
}

function isValidSessionTokenBase64(value: string): boolean {
  try {
    return decodeBase64(value).length === 32;
  } catch {
    return false;
  }
}

function decodeBase64(base64: string): Uint8Array {
  const candidate = (globalThis as { Buffer?: unknown }).Buffer;
  if (typeof candidate === "function") {
    return new Uint8Array((candidate as unknown as { from(value: string, encoding?: string): Uint8Array }).from(base64, "base64"));
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function sessionStorageKey(input: CreateWalletAssociationStorageInput): string {
  const walletName = encodeURIComponent(input.discovery.name || "Native");
  const origin = encodeURIComponent(input.origin);
  const storageKey = input.storageKey ?? "wallet-association:v0.1";
  return `${storageKey}:${origin}:${input.transportId}:${walletName}`;
}

function isLocalStorageAvailable(): boolean {
  return typeof window !== "undefined" && typeof window.localStorage !== "undefined";
}
