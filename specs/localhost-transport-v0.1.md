# Localhost Transport v0.1

The localhost transport delivers Wallet Association Protocol messages over
HTTP on loopback.

## Defaults

- Host: `127.0.0.1`
- Port: `51884`
- Protocol version: `"2"`
- Discovery timeout: 250ms

## Endpoints

- `GET /v2/discover`
- `POST /v2/handshake`
- `POST /v2/associate`
- `POST /v2/rpc`

Old v1 endpoints are not part of this transport.

## CORS

Wallets should only include CORS response headers for valid browser origins.
Required headers:

```http
Access-Control-Allow-Origin: <origin>
Vary: Origin
Access-Control-Allow-Methods: GET, POST, OPTIONS
Access-Control-Allow-Headers: Content-Type
```

Wallets must not include `Access-Control-Allow-Credentials`.

The `Origin` value must be an exact browser origin: `http` or `https`, host,
and optional port only. Wallets must reject `null`, `file:`, credentials, path,
query, and fragment components.

## Request Bounds

Wallets must bound localhost request parsing. Recommended v0.1 defaults:

- maximum request bytes: 65,536
- maximum body bytes: 49,152
- maximum pending handshakes: 256

POST requests must include a valid non-negative `Content-Length` and a JSON
content type (`application/json`, optionally with a charset parameter).
Oversized requests should return `413 request_too_large`; malformed requests
should return `400 malformed_request`.

## Privacy

Localhost discovery can reveal whether a wallet app is installed or running.
Dapp libraries must make localhost discovery opt-in. Discovery must not return
accounts or session material.

## Trust

Localhost is not a trust boundary. Wallets must still validate origin, require
user approval for new sessions, encrypt association/RPC payloads, and enforce
session token validation.
