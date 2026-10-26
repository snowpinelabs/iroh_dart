# Changelog

## 1.3.0

- **iroh 1.4.1:** the Rust core now builds against `iroh` / `iroh-base` / `iroh-dns` 1.4.1.
  iroh 1.4 has no breaking API changes. It brings bug fixes: pkarr requests use the
  endpoint's proxy, net_report probes do not use the environment's proxy, local addresses update
  on network change, relay receive retries after message drops, and correct proxy credentials.
  It also adds a timeout on captive portal checks and support for IPv6 literal relay URLs.
- New `ConnectionStats.sentPackets` and `ConnectionStats.sentBytes`: the QUIC packets and payload
  bytes sent on all paths. Also new `ConnectionStats.lostPackets` and `ConnectionStats.lostBytes`.
- **ABI version 3.** The FFI shape of `ConnStats` changed, so the Dart bindings refuse a native
  library built for ABI 2. Rebuild the native library or re-run `dart run iroh_quic:setup`.

## 1.2.0

- Version bump in lockstep with `iroh_flutter` 1.2.0, which adds Swift Package Manager support on
  iOS and macOS. The plugin uses a prebuilt `irohdart_ffi.xcframework` from the GitHub release
  `xcframework-v1.2.0`. No changes to the Dart/Rust API.

## 1.1.1

- Version bump in lockstep with `iroh_flutter` 1.1.1 (Android build fix for
  `rustls-platform-verifier` 0.7.1); no changes to the Dart/Rust API.

## 1.1.0

- **iroh 1.3.0:** the Rust core now builds against `iroh` / `iroh-base` / `iroh-dns` 1.3.0
  (was 1.0.0). This brings iroh's bug fixes (relay reconnect, router protocol ordering, Windows
  receive errors) and the new resolver in `iroh-dns`.
- New `Connection.sendManyDatagrams` and `Connection.readManyDatagrams`: send or receive a batch
  of datagrams in one call (iroh 1.3 batch datagram API).
- New `RelayStatus.authDeniedReason`: the reason a relay server denied this endpoint's
  authentication. Retries do not usually fix this, so surface it to the user.
- **ABI version 2.** The FFI surface changed shape, so the Dart bindings refuse a native library
  built for ABI 1. Rebuild the native library or re-run `dart run iroh_quic:setup`.
- Dependencies: `flutter_rust_bridge` 2.13.0 (runtime and codegen), `lints` ^6.1.0, and the latest
  Rust crates (`tokio` 1.53, `futures` 0.3.34, `rustls-platform-verifier` 0.7.1, and more).

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

The package is now **pure Dart**: no `flutter` SDK dependency, runnable under
`dart run` / `dart test`. The Dart/Rust API is unchanged; only the packaging moves off Flutter, so
existing code keeps working.

- **Prebuilt native libraries: no Rust toolchain required.** Run `dart run iroh_quic:setup` to
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
