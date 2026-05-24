import {
  isExpired,
  isStoredSession,
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
        if (!isStoredSession(session) || session.origin !== input.origin || isExpired(session.expiresAt)) {
          window.localStorage.removeItem(key);
          return null;
        }
        return session;
      } catch {
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

function sessionStorageKey(input: CreateWalletAssociationStorageInput): string {
  const walletName = encodeURIComponent(input.discovery.name || "Native");
  const origin = encodeURIComponent(input.origin);
  const storageKey = input.storageKey ?? "wallet-association:v0.1";
  return `${storageKey}:${origin}:${input.transportId}:${walletName}`;
}

function isLocalStorageAvailable(): boolean {
  return typeof window !== "undefined" && typeof window.localStorage !== "undefined";
}
