# Wallet Association Protocol

Wallet Association Protocol is a transport-independent encrypted session
protocol for connecting dapps to external wallets.

Wallet Standard is the browser-facing wallet interface. Wallet Association
Protocol is the session and transport layer underneath.

```text
Dapp
  |
  | Wallet Standard
  v
Wallet Association Client
  |
  | transport
  v
localhost / QR / relay / WebRTC
  |
  | encrypted session protocol
  v
Wallet
```

## v0.1 Scope

Version 0.1 supports:

- localhost transport
- browser origin binding
- X25519 + HKDF-SHA256 session establishment
- ChaCha20-Poly1305 encrypted envelopes
- persisted session tokens
- Solana sign message
- Solana sign transaction
- Wallet Standard adapter

Version 0.2 adds experimental relay rendezvous building blocks:

- transport-neutral client request interface
- relay connection URI parsing/generation
- local reference relay server
- TypeScript relay dapp transport
- Swift relay wallet bridge
- encrypted session events
- session token rotation RPC

## Packages

- `@wallet-association/core`: protocol types, crypto, envelopes, validation, errors
- `@wallet-association/transport-localhost`: localhost discovery and HTTP transport
- `@wallet-association/transport-relay`: browser relay rendezvous transport
- `@wallet-association/relay-server`: local reference relay server
- `@wallet-association/wallet-standard`: Wallet Standard adapter

## Reference Implementations

The TypeScript packages are the reference dapp/client implementation. They own
browser crypto, localhost transport calls, session storage, and Wallet Standard
adaptation.

The Swift package in [`swift/`](./swift) is the Apple wallet/server reference
implementation. It owns protocol types, crypto, envelopes, session authorization
helpers, Keychain session token storage, and the localhost bridge server. Wallet
apps still own UI prompts, signing, account mapping, network policy, and settings
screens.

Native can consume the local Swift package with:

```swift
.package(path: "../wallet-association-protocol/swift")
```

## Specs

- [Association v0.1](./specs/association-v0.1.md)
- [Security v0.1](./specs/security-v0.1.md)
- [Localhost Transport v0.1](./specs/localhost-transport-v0.1.md)
- [Wallet Standard Adapter v0.1](./specs/wallet-standard-adapter-v0.1.md)
- [Transport Abstraction v0.2](./specs/transport-abstraction-v0.2.md)
- [Relay Transport v0.2](./specs/relay-transport-v0.2.md)
- [Connection URI v0.2](./specs/connection-uri-v0.2.md)
- [Events v0.2](./specs/events-v0.2.md)
- [Session Rotation v0.2](./specs/session-rotation-v0.2.md)

## Future Work

- WebRTC transport
- non-Solana feature namespaces
- formal Wallet Standard proposal
