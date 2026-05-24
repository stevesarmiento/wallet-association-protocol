# Wallet Association Protocol v0.1

Wallet Association Protocol creates encrypted, user-approved wallet sessions over
replaceable transports. Version 0.1 defines the message layer used by the
localhost transport and the Wallet Standard adapter.

## Terms

- **Dapp**: Application requesting wallet accounts or signing.
- **Wallet**: External signer that enforces account, session, and signing policy.
- **Transport**: Untrusted byte/message delivery path such as localhost, QR, relay, or WebRTC.
- **Handshake**: X25519 key agreement setup for a one-time association exchange.
- **Association**: Creation or resumption of a wallet session.
- **Session**: Origin-bound authorization with a session id, session token, expiry, accounts, chains, features, and signing policy.
- **Envelope**: Encrypted JSON message.

## Version

All v0.1 protocol messages use `protocolVersion: "2"`.

## Discovery

Discovery returns wallet metadata and transport hints. Discovery must not expose
accounts.

```http
GET /v2/discover
```

```json
{
  "name": "Native",
  "version": "1.0.0",
  "protocolVersion": "2",
  "transports": [{ "type": "localhost", "host": "127.0.0.1", "port": 51884 }],
  "chains": ["solana:mainnet", "solana:devnet"],
  "features": ["solana:signMessage", "solana:signTransaction"],
  "encryption": "x25519-hkdf-sha256-chacha20poly1305",
  "sessionTokenTtlSeconds": 604800
}
```

## Handshake

```http
POST /v2/handshake
```

The dapp sends an X25519 public key and optional metadata. Browser transports
must also send the HTTP `Origin` header. Wallets must reject absent or invalid
browser origins and must reject metadata origins that do not match the HTTP
origin.

```json
{
  "protocolVersion": "2",
  "dappPublicKeyBase64": "...",
  "metadata": {
    "origin": "https://app.example",
    "appName": "Example App",
    "appIcon": "data:image/png;base64,..."
  }
}
```

Response:

```json
{
  "protocolVersion": "2",
  "handshakeId": "...",
  "walletPublicKeyBase64": "...",
  "expiresAt": "2026-05-24T00:00:00Z"
}
```

## Envelope

```json
{
  "protocolVersion": "2",
  "keyId": "handshake-or-session-id",
  "sealedBoxBase64": "base64(nonce || ciphertext || tag)"
}
```

## Association

```http
POST /v2/associate
```

The request body is an encrypted envelope keyed by `handshakeId`.

Create payload:

```json
{
  "kind": "create",
  "requestedChains": ["solana:devnet"],
  "requestedFeatures": ["solana:signMessage", "solana:signTransaction"]
}
```

Resume payload:

```json
{
  "kind": "resume",
  "resumeSessionId": "...",
  "resumeSessionTokenBase64": "..."
}
```

Encrypted response payload:

```json
{
  "sessionId": "...",
  "sessionTokenBase64": "...",
  "expiresAt": "2026-05-31T00:00:00Z",
  "accounts": [
    {
      "address": "...",
      "publicKey": [1, 2, 3],
      "chains": ["solana:devnet"],
      "features": ["solana:signMessage", "solana:signTransaction"],
      "label": "Account 1"
    }
  ],
  "chains": ["solana:devnet"],
  "features": ["solana:signMessage", "solana:signTransaction"],
  "signingPolicy": "prompt"
}
```

## RPC

```http
POST /v2/rpc
```

The request body is an encrypted envelope keyed by `sessionId`.

```json
{
  "requestId": "uuid",
  "issuedAt": "2026-05-24T00:00:00Z",
  "sessionTokenBase64": "...",
  "method": "solana.signMessage",
  "params": {
    "accountAddress": "...",
    "chain": "solana:devnet",
    "messageBase64": "..."
  }
}
```

Supported v0.1 methods:

- `solana.signMessage`
- `solana.signTransaction`

Response:

```json
{
  "requestId": "uuid",
  "result": { "signatureBase64": "..." }
}
```

or:

```json
{
  "requestId": "uuid",
  "result": { "signedTransactionBase64": "...", "signature": "..." }
}
```

## Errors

Errors use:

```json
{
  "error": {
    "code": "session_invalid",
    "message": "Association session has expired."
  }
}
```

Common v0.1 codes:

- `invalid_origin`
- `malformed_request`
- `session_invalid`
- `user_rejected`
- `unsupported_method`
- `bridge_unavailable`

Dates are ISO-8601 strings. Binary values are base64 strings unless explicitly
represented as byte arrays.
