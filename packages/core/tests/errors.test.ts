import { describe, expect, it } from "vitest";
import { toWalletAssociationError } from "../src";

describe("error normalization", () => {
  it("only labels user_rejected as user rejection for known protocol codes", () => {
    expect(toWalletAssociationError({ error: { code: "user_rejected", message: "denied" } }, 403).message).toContain("user rejected");

    for (const code of ["session_invalid", "malformed_request", "invalid_origin", "unsupported_method", "bridge_unavailable"]) {
      const error = toWalletAssociationError({ error: { code, message: code } }, code === "bridge_unavailable" ? 503 : 403);
      expect(error.code).toBe(code);
      expect(error.message).not.toContain("user rejected");
    }
  });

  it("keeps fallback user-denied classification for unknown forbidden responses", () => {
    const error = toWalletAssociationError({ error: { code: "custom", message: "forbidden" } }, 403);
    expect(error.message).toContain("user rejected");
  });
});
