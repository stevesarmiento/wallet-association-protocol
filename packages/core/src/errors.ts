import type { AssociationErrorBody } from "./protocol";

export class WalletAssociationError extends Error {
  constructor(
    message: string,
    public code: string,
    public details?: unknown
  ) {
    super(message);
    this.name = "WalletAssociationError";
  }
}

export function isErrorResponse(data: unknown): data is AssociationErrorBody {
  return (
    typeof data === "object" &&
    data !== null &&
    "error" in data &&
    typeof (data as { error?: unknown }).error === "object" &&
    (data as { error?: unknown }).error !== null
  );
}

export function toWalletAssociationError(data: unknown, status: number): WalletAssociationError {
  const error = isErrorResponse(data) ? data.error : undefined;
  const code = typeof error?.code === "string" ? error.code : `HTTP_${status}`;
  const rawMessage = typeof error?.message === "string" ? error.message : "Wallet association request failed";
  const message = normalizedMessage(code, rawMessage, status);

  return new WalletAssociationError(message, code, error?.details ?? { status });
}

function normalizedMessage(code: string, rawMessage: string, status: number): string {
  switch (code) {
    case "user_rejected":
      return `user rejected: ${rawMessage}`;
    case "session_invalid":
      return rawMessage || "Association session is invalid or expired";
    case "malformed_request":
      return rawMessage || "Malformed association request";
    case "invalid_origin":
      return rawMessage || "Invalid association origin";
    case "unsupported_method":
      return rawMessage || "Unsupported association method";
    case "bridge_unavailable":
      return rawMessage || "Wallet association bridge is unavailable";
    default: {
      const lower = `${code} ${rawMessage}`.toLowerCase();
      if (
        status === 401 ||
        status === 403 ||
        lower.includes("reject") ||
        lower.includes("denied") ||
        lower.includes("forbidden") ||
        lower.includes("unauthorized")
      ) {
        return `user rejected: ${rawMessage}`;
      }
      return rawMessage;
    }
  }
}
