# Wallet Standard Adapter v0.1

Wallet Standard is the dapp-facing wallet interface. Wallet Association
Protocol is the encrypted session and transport layer underneath.

## Required Features

A Wallet Association adapter must expose:

- `standard:connect`
- `standard:disconnect`
- `standard:events`
- `solana:signMessage`
- `solana:signTransaction`

## Connect

`standard:connect` must:

1. Try to resume a non-expired stored session.
2. Clear the stored session and create a new session when resume returns `session_invalid`.
3. Store the returned session id, session token, expiry, origin, wallet name, and wallet version.
4. Convert returned accounts to Wallet Standard accounts.

## Disconnect

`standard:disconnect` clears in-memory accounts and emits a change event. It
does not revoke the wallet-side session.

## Account Mapping

Association account fields map to Wallet Standard:

- `address` -> `WalletAccount.address`
- `publicKey` -> `WalletAccount.publicKey`
- `chains` -> `WalletAccount.chains`
- `features` -> `WalletAccount.features`
- `label` -> `WalletAccount.label`
- `icon` -> `WalletAccount.icon`

## Signing

Signing calls must use encrypted `/v2/rpc` envelopes and must reject malformed
or mismatched response request IDs.
