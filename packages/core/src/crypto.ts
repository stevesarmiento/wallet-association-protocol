import { chacha20poly1305 } from "@noble/ciphers/chacha";
import { x25519 } from "@noble/curves/ed25519";
import { hkdf } from "@noble/hashes/hkdf";
import { sha256 } from "@noble/hashes/sha256";
import { WALLET_ASSOCIATION_PROTOCOL_VERSION, type AssociationEnvelope } from "./protocol";

const NONCE_LENGTH = 12;
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

export interface AssociationKeyPair {
  secretKey: Uint8Array;
  publicKeyBase64: string;
}

export interface AssociationCrypto {
  generateKeyPair(): AssociationKeyPair;
  deriveHandshakeKey(input: {
    secretKey: Uint8Array;
    walletPublicKeyBase64: string;
    handshakeId: string;
    origin: string;
  }): Uint8Array;
  deriveSessionKey(input: { sessionTokenBase64: string; sessionId: string; origin: string }): Uint8Array;
  sealJson(keyId: string, key: Uint8Array, payload: unknown): AssociationEnvelope;
  openJson<T>(key: Uint8Array, envelope: AssociationEnvelope): T;
  randomUUID(): string;
  now(): Date;
}

export function createAssociationCrypto(): AssociationCrypto {
  return {
    generateKeyPair() {
      const secretKey = x25519.utils.randomSecretKey();
      return {
        secretKey,
        publicKeyBase64: encodeBase64(x25519.getPublicKey(secretKey))
      };
    },
    deriveHandshakeKey({ secretKey, walletPublicKeyBase64, handshakeId, origin }) {
      return deriveHandshakeKey({ secretKey, walletPublicKeyBase64, handshakeId, origin });
    },
    deriveSessionKey({ sessionTokenBase64, sessionId, origin }) {
      return deriveSessionKey({ sessionTokenBase64, sessionId, origin });
    },
    sealJson(keyId, key, payload) {
      return sealJson(keyId, key, payload);
    },
    openJson<T>(key: Uint8Array, envelope: AssociationEnvelope): T {
      return openJson<T>(key, envelope);
    },
    randomUUID() {
      if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
        return crypto.randomUUID();
      }
      return `${Date.now().toString(36)}-${encodeBase64(randomBytes(16)).replace(/[^a-zA-Z0-9]/g, "")}`;
    },
    now() {
      return new Date();
    }
  };
}

export function deriveHandshakeKey(input: {
  secretKey: Uint8Array;
  walletPublicKeyBase64: string;
  handshakeId: string;
  origin: string;
}): Uint8Array {
  const walletPublicKey = decodeBase64(input.walletPublicKeyBase64);
  if (walletPublicKey.length !== 32) {
    throw new Error("Invalid wallet public key");
  }
  const sharedSecret = x25519.getSharedSecret(input.secretKey, walletPublicKey);
  return deriveKey(sharedSecret, `native-wallet-association-v2:${input.origin}:${input.handshakeId}`, "handshake");
}

export function deriveSessionKey(input: { sessionTokenBase64: string; sessionId: string; origin: string }): Uint8Array {
  const sessionToken = decodeBase64(input.sessionTokenBase64);
  if (sessionToken.length === 0) {
    throw new Error("Invalid session token");
  }
  return deriveKey(sessionToken, `native-wallet-association-v2:${input.origin}:${input.sessionId}`, "session");
}

export function sealJson(
  keyId: string,
  key: Uint8Array,
  payload: unknown,
  options?: { nonce?: Uint8Array }
): AssociationEnvelope {
  const plaintext = textEncoder.encode(JSON.stringify(payload));
  const nonce = options?.nonce ?? randomBytes(NONCE_LENGTH);
  if (nonce.length !== NONCE_LENGTH) {
    throw new Error("Invalid association envelope nonce length");
  }
  const ciphertext = chacha20poly1305(key, nonce).encrypt(plaintext);
  return {
    protocolVersion: WALLET_ASSOCIATION_PROTOCOL_VERSION,
    keyId,
    sealedBoxBase64: encodeBase64(concatBytes(nonce, ciphertext))
  };
}

export function openJson<T>(key: Uint8Array, envelope: AssociationEnvelope): T {
  const combined = decodeBase64(envelope.sealedBoxBase64);
  if (combined.length <= NONCE_LENGTH) {
    throw new Error("Invalid association envelope");
  }
  const nonce = combined.slice(0, NONCE_LENGTH);
  const ciphertext = combined.slice(NONCE_LENGTH);
  const plaintext = chacha20poly1305(key, nonce).decrypt(ciphertext);
  return JSON.parse(textDecoder.decode(plaintext)) as T;
}

export function publicKeyBase64FromSecretKey(secretKey: Uint8Array): string {
  if (secretKey.length !== 32) {
    throw new Error("Invalid X25519 secret key");
  }
  return encodeBase64(x25519.getPublicKey(secretKey));
}

export function encodeBase64(bytes: Uint8Array): string {
  const nodeBuffer = globalThisBuffer();
  if (nodeBuffer) {
    return nodeBuffer.from(bytes).toString("base64");
  }
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

export function decodeBase64(base64: string): Uint8Array {
  const nodeBuffer = globalThisBuffer();
  if (nodeBuffer) {
    return new Uint8Array(nodeBuffer.from(base64, "base64"));
  }
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

export function encodeHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map(byte => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function decodeHex(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) {
    throw new Error("Invalid hex string");
  }
  const bytes = new Uint8Array(hex.length / 2);
  for (let index = 0; index < bytes.length; index += 1) {
    bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return bytes;
}

function deriveKey(inputKeyMaterial: Uint8Array, salt: string, info: string): Uint8Array {
  return hkdf(sha256, inputKeyMaterial, textEncoder.encode(salt), textEncoder.encode(info), 32);
}

function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const length = parts.reduce((total, part) => total + part.length, 0);
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const part of parts) {
    bytes.set(part, offset);
    offset += part.length;
  }
  return bytes;
}

function randomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  if (typeof crypto !== "undefined" && typeof crypto.getRandomValues === "function") {
    crypto.getRandomValues(bytes);
    return bytes;
  }
  throw new Error("Secure random values are unavailable");
}

function globalThisBuffer(): { from(value: Uint8Array | string, encoding?: string): { toString(encoding: string): string } & Uint8Array } | null {
  const candidate = (globalThis as { Buffer?: unknown }).Buffer;
  return typeof candidate === "function"
    ? (candidate as unknown as { from(value: Uint8Array | string, encoding?: string): { toString(encoding: string): string } & Uint8Array })
    : null;
}
