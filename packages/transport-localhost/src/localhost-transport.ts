import {
  toWalletAssociationError,
  type AssociationClientTransport,
  type AssociationOperation,
  type AssociationTransportDescriptor,
  type WalletAssociationError,
} from "@wallet-association/core";
import { isErrorResponse } from "@wallet-association/core";

export interface LocalhostTransportConfig {
  enabled?: boolean;
  host?: string;
  port?: number;
  protocolVersion?: "2";
  timeoutMs?: number;
}

export interface ResolvedLocalhostTransportConfig {
  enabled: boolean;
  host: string;
  port: number;
  protocolVersion: "2";
  timeoutMs: number;
}

export interface AssociationTransport {
  get<T>(path: string, options?: { signal?: AbortSignal }): Promise<T>;
  post<T>(
    path: string,
    body: unknown,
    options?: { signal?: AbortSignal },
  ): Promise<T>;
}

export const DEFAULT_LOCALHOST_TRANSPORT_CONFIG: ResolvedLocalhostTransportConfig =
  {
    enabled: false,
    host: "127.0.0.1",
    port: 51884,
    protocolVersion: "2",
    timeoutMs: 250,
  };

export function resolveLocalhostTransportConfig(
  input?: boolean | LocalhostTransportConfig,
): ResolvedLocalhostTransportConfig {
  if (input === true) {
    return { ...DEFAULT_LOCALHOST_TRANSPORT_CONFIG, enabled: true };
  }
  if (!input) {
    return { ...DEFAULT_LOCALHOST_TRANSPORT_CONFIG };
  }
  return {
    ...DEFAULT_LOCALHOST_TRANSPORT_CONFIG,
    ...input,
    enabled: input.enabled === true,
    protocolVersion:
      input.protocolVersion ??
      DEFAULT_LOCALHOST_TRANSPORT_CONFIG.protocolVersion,
  };
}

export function createLocalhostTransport(
  config: ResolvedLocalhostTransportConfig,
): AssociationTransport {
  return {
    get(path, options) {
      return requestJson(
        config,
        path,
        options?.signal
          ? { method: "GET", signal: options.signal }
          : { method: "GET" },
      );
    },
    post(path, body, options) {
      return requestJson(
        config,
        path,
        options?.signal
          ? { method: "POST", body, signal: options.signal }
          : { method: "POST", body },
      );
    },
  };
}

export function createLocalhostClientTransport(
  config: ResolvedLocalhostTransportConfig,
): AssociationClientTransport {
  const transport = createLocalhostTransport(config);
  return {
    type: "localhost",
    request<T>(
      operation: AssociationOperation,
      body?: unknown,
      options?: { signal?: AbortSignal },
    ) {
      switch (operation) {
        case "discover":
          return transport.get<T>("/v2/discover", options);
        case "handshake":
          return transport.post<T>("/v2/handshake", body, options);
        case "associate":
          return transport.post<T>("/v2/associate", body, options);
        case "rpc":
          return transport.post<T>("/v2/rpc", body, options);
      }
    },
  };
}

export function localhostTransportDescriptor(
  config: ResolvedLocalhostTransportConfig,
): AssociationTransportDescriptor {
  return {
    type: "localhost",
    host: config.host,
    port: config.port,
  };
}

async function requestJson<T>(
  config: ResolvedLocalhostTransportConfig,
  path: string,
  options: {
    method: "GET" | "POST";
    body?: unknown;
    signal?: AbortSignal;
  },
): Promise<T> {
  const requestInit: RequestInit = {
    method: options.method,
    credentials: "omit",
    headers: {
      "Content-Type": "application/json",
    },
  };
  if (options.method === "POST") {
    requestInit.body = JSON.stringify(options.body);
  }
  if (options.signal) {
    requestInit.signal = options.signal;
  }
  const response = await fetch(
    `http://${config.host}:${config.port}${path}`,
    requestInit,
  );

  let data: unknown;
  try {
    data = await response.json();
  } catch (error) {
    if (!response.ok) {
      throw toWalletAssociationError(
        data,
        response.status,
      ) as WalletAssociationError;
    }
    throw error;
  }

  if (!response.ok || isErrorResponse(data)) {
    throw toWalletAssociationError(data, response.status);
  }

  return data as T;
}
