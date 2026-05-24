# Wallet Association Protocol v0.1 Localhost Security Review

Reviewed date: 2026-05-24

## Scope

This review covers the v0.1 localhost transport, encrypted association/session
protocol, TypeScript client packages, Swift reference wallet SDK, and Native
wallet integration. QR/deeplink, relay, WebRTC, attestation, and upstream Wallet
Standard proposal work are out of scope.

## Trust Boundaries

- Localhost is an untrusted delivery path.
- Browser `Origin` binds a browser dapp session to an origin.
- The encrypted handshake protects association payloads after discovery.
- Session tokens authorize resume and RPC requests for an origin-bound session.
- Wallet UI, signing policy, account ownership, and device/key-store
  authentication remain wallet-owned.

## Findings Fixed

- Origin validation now rejects `null`, non-HTTP(S) origins, credentials, paths,
  queries, fragments, missing hosts, and malformed ports.
- Localhost HTTP parsing is bounded by request and body limits.
- POST requests require valid `Content-Length` and JSON content type.
- Pending handshakes are capped and old entries are evicted deterministically.
- Replay cache tracks request IDs in insertion order and rejects stale or
  future-issued requests outside the clock skew window.
- Session tokens are validated as exactly 32 raw bytes.
- Swift token comparisons use constant-time equality for request-token checks.
- Browser stored sessions are strictly validated and invalid entries are cleared.
- Protocol error normalization no longer labels all 400/403 errors as user
  rejection.
- Native maps wallet-domain invalid request cases to protocol-safe errors.

## Residual Risks

- Browser `localStorage` token theft is possible through same-origin XSS.
- Local malicious processes can probe localhost availability and attempt denial
  of service.
- A local process cannot bypass origin/session approval without the session
  token, but it can flood handshakes up to configured limits.
- Browser `Origin` only exists for browser transports. Future non-browser
  transports need a separate identity binding.
- `allowWithoutPrompt` is a wallet/user policy and should remain opt-in per
  session.
- Wallet impersonation remains possible if another local service binds first.
  Dapps must treat wallet identity as unauthenticated in v0.1 unless a future
  attestation mechanism is added.

## QR/Deeplink Prerequisites

- Reuse the same core envelope, token, replay, and session validation rules.
- Define a non-HTTP identity binding for QR/deeplink contexts.
- Keep transport payloads untrusted and encrypted after the association request.
- Add conformance tests that run against both localhost and QR/deeplink.
