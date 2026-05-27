# Wallet Association Connection URI v0.2

The v0.2 relay launch artifact is a URI string. QR codes and deep links may
carry this string, but rendering and OS registration are out of scope.

```text
wap://associate?version=2&transport=relay&relay=<encoded-ws-url>&room=<roomId>&secret=<roomSecret>&origin=<encoded-origin>&expiresAt=<iso-date>
```

Wallets must reject:

- schemes other than `wap`
- hosts other than `associate`
- unsupported versions
- transports other than `relay`
- missing `relay`, `room`, `secret`, `origin`, or `expiresAt`
- expired URIs

The `origin` value is browser-origin claimed by the dapp and is bound into WAP
handshake/session keys. v0.2 does not provide external domain proof.
