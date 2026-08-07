# Changelog

## 1.0.3

- Loosen the `flutter_rust_bridge` runtime dependency to `^2.12.0` (was pinned to `2.12.0`).
- Version bump in lockstep with `iroh_flutter` 1.0.3 (Windows/Linux desktop build fix); no
  changes to the Dart/Rust API.

## 1.0.2

- **Rust core (Android):** new JNI bootstrap in `irohdart_ffi` (`src/android.rs`) exporting
  `IrohFlutterPlugin.initAndroidContext`, which installs the app's `JavaVM` + `Context` into
  `ndk-context` and initializes `rustls-platform-verifier`. Fixes the release-build abort
  `android context was not initialized` on `Endpoint.bind` under `iroh_flutter`.

## 1.0.1 - Dart-only (Flutter dropped)

The package is now **pure Dart** — no `flutter` SDK dependency, runnable under
`dart run` / `dart test`. The Dart/Rust API is unchanged; only the packaging moves off Flutter, so
existing code keeps working.

- **Prebuilt native libraries — no Rust toolchain required.** Run `dart run iroh_quic:setup` to
  download a signed (Ed25519) prebuilt cdylib for your desktop platform (Linux/macOS/Windows on
  x64/arm64) into a per-user cache; `Iroh.init()` finds it automatically. Prefer source? `cargo
  build --release` still works and the loader picks that up too.
- The loader now searches, in order: a local `cargo build`, the `iroh_quic:setup` cache, and a
  library bundled next to the compiled executable.
- Release pipeline reworked: CI/release migrated from Flutter to `dart`/`cargo`; the prebuilt
  libraries are cross-compiled, signed, and attached to the version's GitHub Release. The former
  cargokit precompiled-binaries machinery (Flutter-only) was removed.

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
