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

## Privacy

Localhost discovery can reveal whether a wallet app is installed or running.
Dapp libraries must make localhost discovery opt-in. Discovery must not return
accounts or session material.

## Trust

Localhost is not a trust boundary. Wallets must still validate origin, require
user approval for new sessions, encrypt association/RPC payloads, and enforce
session token validation.
