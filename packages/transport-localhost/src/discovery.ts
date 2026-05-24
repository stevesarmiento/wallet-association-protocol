import {
  isCompatibleDiscovery,
  type AssociationDiscoverResponse
} from "@wallet-association/core";
import {
  createLocalhostTransport,
  resolveLocalhostTransportConfig,
  type LocalhostTransportConfig,
  type AssociationTransport
} from "./localhost-transport";

export interface DiscoverLocalhostWalletDeps {
  transport?: AssociationTransport;
}

export async function discoverLocalhostWallet(
  input?: boolean | LocalhostTransportConfig,
  deps: DiscoverLocalhostWalletDeps = {}
): Promise<AssociationDiscoverResponse | null> {
  const config = resolveLocalhostTransportConfig(input);
  if (!config.enabled || typeof window === "undefined" || typeof fetch === "undefined") {
    return null;
  }

  const transport = deps.transport ?? createLocalhostTransport(config);
  const controller = typeof AbortController !== "undefined" ? new AbortController() : undefined;
  const timeout = controller
    ? setTimeout(() => {
        controller.abort();
      }, config.timeoutMs)
    : undefined;

  try {
    const options = controller ? { signal: controller.signal } : undefined;
    const discovery = await transport.get<AssociationDiscoverResponse>("/v2/discover", options);
    return isCompatibleDiscovery(discovery) ? discovery : null;
  } catch {
    return null;
  } finally {
    if (timeout) {
      clearTimeout(timeout);
    }
  }
}
