import type { Wallet, WalletAccount } from "@wallet-standard/base";
import type {
  StandardConnectFeature,
  StandardDisconnectFeature,
  StandardEventsFeature,
  StandardEventsListeners,
  StandardEventsNames,
} from "@wallet-standard/features";
import {
  createAssociationCrypto,
  decodeBase64,
  encodeBase64,
  isValidSessionTokenBase64,
  isAssociationEnvelope,
  isSolanaChain,
  type AssociationClientTransport,
  type AssociationCrypto,
  type AssociationDiscoverResponse,
  type AssociationEnvelope,
  type AssociationHandshakeResponse,
  type AssociationOperation,
  type AssociationRequestPayload,
  type AssociationResponsePayload,
  type AssociationRPCRequestPayload,
  type AssociationRPCResponsePayload,
  type AssociationSessionEventPayload,
  type AssociationSessionRotationResponse,
  type SignMessageInput,
  type SignTransactionInput,
  type WalletAssociationStorage,
  type WalletAssociationStoredSession,
  WalletAssociationError,
} from "@wallet-association/core";
import {
  DEFAULT_WALLET_ASSOCIATION_ICON,
  normalizeWalletName,
  SUPPORTED_SOLANA_SIGNING_FEATURES,
  toWalletAccount,
} from "./solana-wallet-standard";
import { createWalletAssociationStorage } from "./storage";

export interface CreateWalletAssociationWalletInput {
  discovery: AssociationDiscoverResponse;
  transport: AssociationClientTransport | LegacyAssociationTransport;
  storage?: WalletAssociationStorage;
  crypto?: AssociationCrypto;
  origin?: string;
  appName?: string;
  appIcon?: string;
  requestedChains?: string[];
  requestedFeatures?: string[];
  transportId?: string;
  storageKey?: string;
}

export interface LegacyAssociationTransport {
  get<T>(path: string, options?: { signal?: AbortSignal }): Promise<T>;
  post<T>(
    path: string,
    body: unknown,
    options?: { signal?: AbortSignal },
  ): Promise<T>;
}

export function createWalletAssociationWallet(
  input: CreateWalletAssociationWalletInput,
): Wallet {
  const crypto = input.crypto ?? createAssociationCrypto();
  const origin = input.origin ?? getOrigin();
  const transportId = input.transportId ?? "localhost";
  const transport = normalizeTransport(input.transport);
  const storage =
    input.storage ??
    createWalletAssociationStorage({
      discovery: input.discovery,
      origin,
      transportId,
      ...(input.storageKey ? { storageKey: input.storageKey } : {}),
    });

  const solanaChains = input.discovery.chains.filter(
    isSolanaChain,
  ) as `${string}:${string}`[];
  const supportedFeatures = new Set(SUPPORTED_SOLANA_SIGNING_FEATURES);

  let accounts: WalletAccount[] = [];
  let session: WalletAssociationStoredSession | null = null;
  let walletLocked = false;
  const listeners = new Set<
    (properties: { accounts?: readonly WalletAccount[] }) => void
  >();

  transport.onEvent?.((event) => {
    if (event.type === "session_event") {
      handleSessionEvent(event.body);
    }
  });

  function emitChange() {
    for (const listener of listeners) {
      try {
        listener({ accounts });
      } catch {
        // Ignore listener errors.
      }
    }
  }

  async function connectAssociation(): Promise<AssociationResponsePayload> {
    const storedSession = storage.get();
    if (storedSession) {
      try {
        return await associate({
          kind: "resume",
          resumeSessionId: storedSession.sessionId,
          resumeSessionTokenBase64: storedSession.sessionTokenBase64,
        });
      } catch (error) {
        if (
          !(error instanceof WalletAssociationError) ||
          error.code !== "session_invalid"
        ) {
          throw error;
        }
        storage.clear();
      }
    }

    return associate({
      kind: "create",
      requestedChains: input.requestedChains ?? solanaChains,
      requestedFeatures: input.requestedFeatures ?? [
        ...SUPPORTED_SOLANA_SIGNING_FEATURES,
      ],
    });
  }

  async function associate(
    payload: AssociationRequestPayload,
  ): Promise<AssociationResponsePayload> {
    const keyPair = crypto.generateKeyPair();
    const handshake = await transport.request<AssociationHandshakeResponse>(
      "handshake",
      {
        protocolVersion: "2",
        dappPublicKeyBase64: keyPair.publicKeyBase64,
        metadata: {
          origin,
          appName: input.appName,
          appIcon: input.appIcon,
        },
      },
    );

    if (
      handshake.protocolVersion !== "2" ||
      typeof handshake.handshakeId !== "string"
    ) {
      throw new WalletAssociationError(
        "Wallet association handshake failed",
        "MALFORMED_HANDSHAKE",
      );
    }

    const handshakeKey = crypto.deriveHandshakeKey({
      secretKey: keyPair.secretKey,
      walletPublicKeyBase64: handshake.walletPublicKeyBase64,
      handshakeId: handshake.handshakeId,
      origin,
    });
    const envelope = crypto.sealJson(
      handshake.handshakeId,
      handshakeKey,
      payload,
    );
    const encryptedResponse = await transport.request<AssociationEnvelope>(
      "associate",
      envelope,
    );

    if (
      !isAssociationEnvelope(encryptedResponse) ||
      encryptedResponse.keyId !== handshake.handshakeId
    ) {
      throw new WalletAssociationError(
        "Wallet returned a malformed association response",
        "MALFORMED_RESPONSE",
      );
    }

    return crypto.openJson<AssociationResponsePayload>(
      handshakeKey,
      encryptedResponse,
    );
  }

  async function sendRpc(
    payload: Omit<
      AssociationRPCRequestPayload,
      "requestId" | "issuedAt" | "sessionTokenBase64"
    >,
  ) {
    if (!session) {
      throw new WalletAssociationError(
        "Wallet association session is not connected",
        "NOT_CONNECTED",
      );
    }

    const requestId = crypto.randomUUID();
    const requestPayload: AssociationRPCRequestPayload = {
      requestId,
      issuedAt: crypto.now().toISOString(),
      sessionTokenBase64: session.sessionTokenBase64,
      ...payload,
    };
    const sessionKey = crypto.deriveSessionKey({
      sessionTokenBase64: session.sessionTokenBase64,
      sessionId: session.sessionId,
      origin,
    });
    const envelope = crypto.sealJson(
      session.sessionId,
      sessionKey,
      requestPayload,
    );
    const encryptedResponse = await transport.request<AssociationEnvelope>(
      "rpc",
      envelope,
    );

    if (
      !isAssociationEnvelope(encryptedResponse) ||
      encryptedResponse.keyId !== session.sessionId
    ) {
      throw new WalletAssociationError(
        "Wallet returned a malformed signing response",
        "MALFORMED_RESPONSE",
      );
    }

    const response = crypto.openJson<AssociationRPCResponsePayload>(
      sessionKey,
      encryptedResponse,
    );
    if (response.requestId !== requestId) {
      throw new WalletAssociationError(
        "Wallet returned a mismatched signing response",
        "MALFORMED_RESPONSE",
      );
    }
    return response;
  }

  async function rotateSession(reason: "dapp_requested" = "dapp_requested") {
    const response = await sendRpc({
      method: "wallet.session.rotate",
      params: { reason },
    });
    const result =
      response.result as Partial<AssociationSessionRotationResponse>;
    if (
      typeof result.sessionId !== "string" ||
      !isValidSessionTokenBase64(result.sessionTokenBase64) ||
      typeof result.expiresAt !== "string"
    ) {
      throw new WalletAssociationError(
        "Wallet returned a malformed session rotation response",
        "MALFORMED_RESPONSE",
      );
    }
    session = {
      sessionId: result.sessionId,
      sessionTokenBase64: result.sessionTokenBase64,
      expiresAt: result.expiresAt,
      origin,
      walletName: normalizeWalletName(input.discovery.name),
      walletVersion: input.discovery.version,
    };
    storage.set(session);
  }

  function handleSessionEvent(body: unknown) {
    if (
      !session ||
      !isAssociationEnvelope(body) ||
      body.keyId !== session.sessionId
    ) {
      return;
    }

    try {
      const sessionKey = crypto.deriveSessionKey({
        sessionTokenBase64: session.sessionTokenBase64,
        sessionId: session.sessionId,
        origin,
      });
      const payload = crypto.openJson<AssociationSessionEventPayload>(
        sessionKey,
        body,
      );
      if (payload.sessionTokenBase64 !== session.sessionTokenBase64) {
        return;
      }

      switch (payload.type) {
        case "session_revoked":
          accounts = [];
          session = null;
          walletLocked = false;
          storage.clear();
          emitChange();
          break;
        case "accounts_changed":
          accounts = Array.isArray(payload.accounts)
            ? payload.accounts
                .map((account) => toWalletAccount(account, supportedFeatures))
                .filter((account): account is WalletAccount => account !== null)
            : [];
          emitChange();
          break;
        case "wallet_locked":
          walletLocked = true;
          break;
        case "wallet_unlocked":
          walletLocked = false;
          break;
        case "chains_changed":
        case "features_changed":
          emitChange();
          break;
      }
    } catch {
      // Ignore malformed or undecryptable wallet events.
    }
  }

  const features: Record<`${string}:${string}`, unknown> = {
    "standard:connect": {
      version: "1.0.0",
      connect: async () => {
        const hadStoredSession = storage.get() !== null;
        const response = await connectAssociation();
        session = {
          sessionId: response.sessionId,
          sessionTokenBase64: response.sessionTokenBase64,
          expiresAt: response.expiresAt,
          origin,
          walletName: normalizeWalletName(input.discovery.name),
          walletVersion: input.discovery.version,
        };
        storage.set(session);

        accounts = Array.isArray(response.accounts)
          ? response.accounts
              .map((account) => toWalletAccount(account, supportedFeatures))
              .filter((account): account is WalletAccount => account !== null)
          : [];
        emitChange();

        if (
          hadStoredSession &&
          response.features.includes("wallet.session.rotate")
        ) {
          await rotateSession();
        }

        return { accounts };
      },
    } satisfies StandardConnectFeature["standard:connect"],

    "standard:disconnect": {
      version: "1.0.0",
      disconnect: async () => {
        accounts = [];
        session = null;
        emitChange();
      },
    } satisfies StandardDisconnectFeature["standard:disconnect"],

    "standard:events": {
      version: "1.0.0",
      on: <E extends StandardEventsNames>(
        event: E,
        listener: StandardEventsListeners[E],
      ) => {
        if (event !== "change") {
          return () => {};
        }

        const changeListener = listener as (properties: {
          accounts?: readonly WalletAccount[];
        }) => void;
        listeners.add(changeListener);
        return () => {
          listeners.delete(changeListener);
        };
      },
    } satisfies StandardEventsFeature["standard:events"],

    "solana:signMessage": {
      version: "1.0.0",
      signMessage: async (...inputs: SignMessageInput[]) => {
        ensureConnected(accounts);
        ensureUnlocked(walletLocked);
        const results = [];

        for (const signInput of inputs) {
          const response = await sendRpc({
            method: "solana.signMessage",
            params: {
              accountAddress: signInput.account.address,
              messageBase64: encodeBase64(signInput.message),
              ...(signInput.chain ? { chain: signInput.chain } : {}),
            },
          });

          if (!("signatureBase64" in response.result)) {
            throw new WalletAssociationError(
              "Wallet returned a malformed message signature",
              "MALFORMED_RESPONSE",
            );
          }
          results.push({
            signature: decodeBase64(response.result.signatureBase64),
          });
        }

        return inputs.length === 1 ? results[0] : results;
      },
    },

    "solana:signTransaction": {
      version: "1.0.0",
      supportedTransactionVersions: ["legacy", 0],
      signTransaction: async (...inputs: SignTransactionInput[]) => {
        ensureConnected(accounts);
        ensureUnlocked(walletLocked);

        const transactions =
          inputs.length === 1 ? inputs[0]?.transactions : undefined;
        if (Array.isArray(transactions)) {
          const signInput = inputs[0];
          if (!signInput) {
            throw new WalletAssociationError(
              "Missing transaction input",
              "INVALID_REQUEST",
            );
          }
          const signedTransactions = [];
          for (const transaction of transactions) {
            signedTransactions.push(
              await signTransaction(signInput, transaction),
            );
          }
          return { signedTransactions };
        }

        const results = [];
        for (const signInput of inputs) {
          if (!signInput.transaction) {
            throw new WalletAssociationError(
              "Missing transaction bytes",
              "INVALID_REQUEST",
            );
          }
          results.push({
            signedTransaction: await signTransaction(
              signInput,
              signInput.transaction,
            ),
          });
        }

        return inputs.length === 1 ? results[0] : results;
      },
    },
  };

  async function signTransaction(
    signInput: SignTransactionInput,
    transaction: Uint8Array,
  ): Promise<Uint8Array> {
    const response = await sendRpc({
      method: "solana.signTransaction",
      params: {
        accountAddress: signInput.account.address,
        transactionBase64: encodeBase64(transaction),
        ...(signInput.chain ? { chain: signInput.chain } : {}),
      },
    });

    if (!("signedTransactionBase64" in response.result)) {
      throw new WalletAssociationError(
        "Wallet returned a malformed signed transaction",
        "MALFORMED_RESPONSE",
      );
    }
    return decodeBase64(response.result.signedTransactionBase64);
  }

  return {
    version: "1.0.0",
    name: normalizeWalletName(input.discovery.name),
    icon: DEFAULT_WALLET_ASSOCIATION_ICON,
    chains: solanaChains,
    get accounts() {
      return accounts;
    },
    features: features as Wallet["features"],
  };
}

function ensureConnected(accounts: WalletAccount[]): void {
  if (accounts.length === 0) {
    throw new WalletAssociationError(
      "Wallet association session is not connected",
      "NOT_CONNECTED",
    );
  }
}

function ensureUnlocked(walletLocked: boolean): void {
  if (walletLocked) {
    throw new WalletAssociationError("Wallet is locked", "wallet_locked");
  }
}

function normalizeTransport(
  transport: AssociationClientTransport | LegacyAssociationTransport,
): AssociationClientTransport {
  if ("request" in transport && typeof transport.request === "function") {
    return transport;
  }
  const legacy = transport as LegacyAssociationTransport;
  return {
    type: "localhost",
    request<T>(
      operation: AssociationOperation,
      body?: unknown,
      options?: { signal?: AbortSignal },
    ) {
      switch (operation) {
        case "discover":
          return legacy.get<T>("/v2/discover", options);
        case "handshake":
          return legacy.post<T>("/v2/handshake", body, options);
        case "associate":
          return legacy.post<T>("/v2/associate", body, options);
        case "rpc":
          return legacy.post<T>("/v2/rpc", body, options);
      }
    },
  };
}

function getOrigin(): string {
  return typeof window !== "undefined" ? window.location.origin : "";
}
