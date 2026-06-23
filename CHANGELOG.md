# Changelog

## 1.0.1 - Dart-only (Flutter dropped)

The package is now **pure Dart** — no `flutter` SDK dependency, runnable under
`dart run` / `dart test`. The Dart/Rust API is unchanged; only the packaging moves
off Flutter, so existing code keeps working (build the cdylib with `cargo` instead
of relying on the Flutter plugin build).

## 1.0.0

Initial release - a native Dart/Flutter binding for `iroh 1.0`, wrapping the iroh Rust core through
an owned flutter_rust_bridge crate. Supports iOS, Android, macOS, Windows, and Linux.

- **Identity & addressing:** `SecretKey`, `PublicKey`/`EndpointId`, `Signature`, `EndpointAddr`,
  `RelayUrl`, `RelayMode`/`RelayMap` (z-base-32, sign/verify, postcard round-trip).
- **Endpoint lifecycle:** `Endpoint.bind` (hides `presets::N0` + the rustls `CryptoProvider`),
  `close`, `isClosed`, `setAlpns`, `boundSockets`, `addr`. Async via an embedded multi-threaded
  tokio runtime.
- **Connections & streams:** `connect`, `open`/`accept` `bi`/`uni`, datagrams, `stats`, `closed`;
  `SendStream`/`RecvStream`; byte-identical echo verified.
- **Accept loop + filter:** `accept`, `acceptIncoming` -> `Incoming`
  (`remoteAddr`/`accept`/`refuse`/`retry`/`ignore`).
- **Reactive streams:** `watchAddr`, `homeRelayStatus`, `Connection.pathEvents` (sealed
  `PathEvent`), with leak-free cancellation.
- **Multi-protocol:** ALPN-based dispatch over the accept loop, **plus** a `Router`/`ProtocolHandler`
  bridge (`Endpoint.router()`) for in-process multiplexing with Dart async handlers.
- **Custom address lookup:** `Endpoint.bindWithAddressLookup` - resolve a peer's address from its
  `EndpointId` in Dart.
- Structured `IrohException` hierarchy; `IrohCapabilities` describing the supported feature set.
