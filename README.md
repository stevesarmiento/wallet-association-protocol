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

## Packages

- `@wallet-association/core`: protocol types, crypto, envelopes, validation, errors
- `@wallet-association/transport-localhost`: localhost discovery and HTTP transport
- `@wallet-association/wallet-standard`: Wallet Standard adapter

## Specs

- [Association v0.1](./specs/association-v0.1.md)
- [Security v0.1](./specs/security-v0.1.md)
- [Localhost Transport v0.1](./specs/localhost-transport-v0.1.md)
- [Wallet Standard Adapter v0.1](./specs/wallet-standard-adapter-v0.1.md)

## Future Work

- QR/deeplink transport
- relay transport
- WebRTC transport
- non-Solana feature namespaces
- formal Wallet Standard proposal
