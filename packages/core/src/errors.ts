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
  const lower = `${code} ${rawMessage}`.toLowerCase();
  const message =
    status === 400 ||
    status === 401 ||
    status === 403 ||
    lower.includes("reject") ||
    lower.includes("denied") ||
    lower.includes("forbidden") ||
    lower.includes("unauthorized")
      ? `user rejected: ${rawMessage}`
      : rawMessage;

  return new WalletAssociationError(message, code, error?.details ?? { status });
}
