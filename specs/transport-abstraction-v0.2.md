# Wallet Association Transport Abstraction v0.2

v0.2 defines a transport-neutral client interface for WAP operations:

- `discover`
- `handshake`
- `associate`
- `rpc`

Transports are untrusted delivery paths. Protocol security remains in origin
binding, encrypted envelopes, session tokens, replay rejection, and wallet
approval.

TypeScript clients expose:

```ts
interface AssociationClientTransport {
  readonly type: string;
  request<T>(
    operation: AssociationOperation,
    body?: unknown,
    options?: { signal?: AbortSignal },
  ): Promise<T>;
  onEvent?(listener: (event: AssociationTransportEvent) => void): () => void;
  close?(): Promise<void> | void;
}
```

`onEvent` is optional. Transports without wallet-pushed events remain valid.
Localhost v0.1 maps operations to the existing `/v2/*` HTTP endpoints.
