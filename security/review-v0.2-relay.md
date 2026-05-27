# Wallet Association Protocol v0.2 Relay Security Notes

Reviewed date: 2026-05-27

## Trust Boundary

The relay is untrusted. It authenticates only room possession via a bearer
secret and must be treated as a packet courier. It does not authenticate wallet
identity, app identity, accounts, approvals, or signatures.

## Protections

- Association and RPC payloads continue to use WAP encrypted envelopes.
- Browser origin is included in the connection URI and metadata, then bound into
  handshake and session keys.
- Room ids and room secrets are short-lived.
- The reference relay validates room expiry, role uniqueness, frame size, frame
  shape, and request id shape.
- Wallet events are encrypted under the session key and include the session
  token for dapp-side filtering.

## Residual Risks

- v0.2 does not prove that a claimed browser origin controls its domain.
- Room bearer secrets in a URI can be copied by any process that sees the URI.
- A malicious relay can drop, delay, reorder, or disconnect messages.
- Production relays need operational abuse controls, logging policy, rate
  limits, and privacy review.
