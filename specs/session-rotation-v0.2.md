# Wallet Association Session Rotation v0.2

Wallets may advertise `wallet.session.rotate` as a supported feature. Dapps can
then rotate session token material through encrypted RPC.

Request:

```json
{
  "method": "wallet.session.rotate",
  "params": { "reason": "dapp_requested" }
}
```

Response:

```json
{
  "sessionId": "...",
  "sessionTokenBase64": "...",
  "expiresAt": "2026-05-31T00:00:00Z"
}
```

The response is encrypted with the old session key. The dapp replaces stored
session material only after decrypting and validating the response. Wallets
should accept the previous token for a 60-second grace window to survive lost
responses.
