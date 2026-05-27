# Wallet Association Events v0.2

Relay transports may deliver encrypted wallet-to-dapp session events. Event
payloads are sealed under the existing session key and carried as `wap_event`
relay frames.

```json
{
  "eventId": "uuid",
  "issuedAt": "2026-05-24T00:00:00Z",
  "sessionTokenBase64": "...",
  "type": "accounts_changed",
  "accounts": []
}
```

Event types:

- `session_revoked`
- `accounts_changed`
- `chains_changed`
- `features_changed`
- `wallet_locked`
- `wallet_unlocked`

Dapps must ignore events that cannot be decrypted, reference a different
session id, or contain a mismatched session token.
