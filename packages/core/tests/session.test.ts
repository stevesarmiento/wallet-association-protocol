import { describe, expect, it } from "vitest";
import { isExpired, isStoredSession, isValidSessionTokenBase64 } from "../src";

const validToken = tokenBase64(32);

describe("session helpers", () => {
  it("validates 32-byte base64 session tokens", () => {
    expect(isValidSessionTokenBase64(validToken)).toBe(true);
    expect(isValidSessionTokenBase64(tokenBase64(31))).toBe(false);
    expect(isValidSessionTokenBase64(tokenBase64(33))).toBe(false);
    expect(isValidSessionTokenBase64("not base64")).toBe(false);
  });

  it("strictly validates stored sessions", () => {
    expect(
      isStoredSession({
        sessionId: "session",
        sessionTokenBase64: validToken,
        expiresAt: "2026-06-01T00:00:00.000Z",
        origin: "https://app.example",
        walletName: "Native",
        walletVersion: "1.0.0"
      })
    ).toBe(true);
    expect(
      isStoredSession({
        sessionId: "session",
        sessionTokenBase64: "short",
        expiresAt: "2026-06-01T00:00:00.000Z",
        origin: "https://app.example",
        walletName: "Native",
        walletVersion: "1.0.0"
      })
    ).toBe(false);
  });

  it("treats invalid dates as expired", () => {
    expect(isExpired("not-a-date")).toBe(true);
  });
});

function tokenBase64(length: number): string {
  return btoa(String.fromCharCode(...new Uint8Array(length).fill(7)));
}
