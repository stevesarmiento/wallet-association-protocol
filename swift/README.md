# Wallet Association Swift

Apple reference SDK for Wallet Association Protocol v0.1.

## Modules

- `WalletAssociationCore`: protocol constants, Codable wire types, crypto, encrypted envelopes, authorization models, authorization registry helpers, replay cache, and session token storage.
- `WalletAssociationLocalhost`: localhost HTTP bridge, CORS handling, pending handshakes, encrypted association/RPC routing, and protocol error mapping.

## Platforms

- macOS 13+
- iOS 16+

## Local SwiftPM Usage

```swift
.package(path: "../wallet-association-protocol/swift")
```

```swift
.product(name: "WalletAssociationCore", package: "WalletAssociationProtocol")
.product(name: "WalletAssociationLocalhost", package: "WalletAssociationProtocol")
```

## Localhost Bridge Setup

```swift
let tokenStore = KeychainAssociationSessionTokenStore(
    service: "com.example.wallet.association.sessions"
)

let bridge = LocalAssociationBridge(
    configuration: LocalAssociationBridgeConfiguration(
        port: AssociationProtocol.defaultPort,
        walletName: "Example Wallet",
        walletVersion: "1.0.0"
    ),
    delegate: walletDelegate
)

try bridge.start()
```

The delegate implements wallet-owned behavior:

- approve or reject new associations
- create, persist, load, and revoke session tokens
- map wallet accounts into protocol account responses
- perform signing and device/key-store authentication
- enforce app-level signing policy prompts

The SDK intentionally does not own product UI, account labels, network selection,
transaction simulation, or signing policy UX.

## Session Authorization Helpers

Use `AssociationAuthorizationRegistry` to upsert sessions, record session use,
and revoke one session or all sessions for an origin. The revoke helpers return
session IDs so the wallet can delete matching Keychain tokens.

## Keychain Token Store

`KeychainAssociationSessionTokenStore` provides a configurable default token
store. The default service is `com.walletassociation.sessions`; wallet apps can
pass an app-specific service to preserve existing Keychain data.
