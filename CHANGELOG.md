# Changelog

## 1.0.1 - Dart-only (Flutter dropped)

The package is now **pure Dart** — no `flutter` SDK dependency, runnable under
`dart run` / `dart test`. The Dart/Rust API is unchanged; only the packaging moves
off Flutter, so existing code keeps working (build the cdylib with `cargo` instead
of relying on the Flutter plugin build).

- Removed the `flutter`/`flutter_test`/`flutter_lints` deps and the `flutter:` plugin section
  from `pubspec.yaml`; `flutter_rust_bridge` is used in its pure-Dart mode.
- Deleted the Flutter plugin platform folders (`android/ ios/ macos/ windows/ linux/`), the
  cargokit build hooks, and the Flutter `example/` app (replaced with `example/echo.dart`, a
  headless `dart run` smoke test).
- Native library is built with `cargo build` and loaded via `dart:ffi`
  (`ExternalLibrary.open`, existing disk-path fallback) — no cargokit/Flutter build step.
- Tests migrated from `flutter_test` to `package:test`; `tool/check.sh` + CI run
  `cargo build/test` + `dart analyze`/`dart test`.
- Verified: `dart pub get` resolves with no Flutter SDK; 36 tests + headless iroh↔iroh echo green.

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
