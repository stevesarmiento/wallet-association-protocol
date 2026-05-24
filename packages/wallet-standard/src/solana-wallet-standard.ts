import { getBase58Encoder } from "@solana/codecs";
import type { WalletAccount, WalletIcon } from "@wallet-standard/base";
import {
  decodeBase64,
  isSolanaChain,
  type AssociationAccount
} from "@wallet-association/core";

export const SUPPORTED_SOLANA_SIGNING_FEATURES = ["solana:signMessage", "solana:signTransaction"] as const;

export const DEFAULT_WALLET_ASSOCIATION_ICON: WalletIcon =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/lU7D9QAAAABJRU5ErkJggg==";

export function toWalletAccount(
  account: AssociationAccount,
  supportedFeatures: ReadonlySet<string>
): WalletAccount | null {
  const publicKey = decodePublicKey(account.publicKey);
  if (!publicKey || typeof account.address !== "string" || account.address.length === 0) {
    return null;
  }

  const chains = Array.isArray(account.chains) ? account.chains.filter(isSolanaChain) : [];
  if (chains.length === 0) {
    return null;
  }

  const features = Array.isArray(account.features)
    ? account.features.filter(feature => supportedFeatures.has(feature))
    : [];

  const icon = toTrustedWalletIcon(account.icon);
  return {
    address: account.address,
    publicKey,
    chains,
    features: features as `${string}:${string}`[],
    ...(typeof account.label === "string" ? { label: account.label } : {}),
    ...(icon ? { icon } : {})
  };
}

export function normalizeWalletName(name: unknown): string {
  return typeof name === "string" && name.trim().length > 0 ? name.trim() : "Native";
}

function decodePublicKey(publicKey: number[] | string): Uint8Array | null {
  if (Array.isArray(publicKey)) {
    if (publicKey.length !== 32 || publicKey.some(byte => !Number.isInteger(byte) || byte < 0 || byte > 255)) {
      return null;
    }
    return new Uint8Array(publicKey);
  }

  if (typeof publicKey !== "string" || publicKey.length === 0) {
    return null;
  }

  try {
    const base64Bytes = decodeBase64(publicKey);
    if (base64Bytes.length === 32) {
      return base64Bytes;
    }
  } catch {
    // Fall back to base58.
  }

  try {
    const base58Bytes = getBase58Encoder().encode(publicKey);
    return base58Bytes.length === 32 ? new Uint8Array(base58Bytes) : null;
  } catch {
    return null;
  }
}

function toTrustedWalletIcon(icon: unknown): WalletIcon | undefined {
  if (typeof icon !== "string") {
    return undefined;
  }

  return /^data:image\/(svg\+xml|webp|png|gif);base64,/i.test(icon) ? (icon as WalletIcon) : undefined;
}
