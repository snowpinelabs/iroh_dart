# iroh_dart

**Pure-Dart** binding for **[iroh](https://github.com/n0-computer/iroh) 1.0** - peer-to-peer QUIC
networking (endpoints, connections, streams, relays, address lookup) for Linux, macOS, Windows,
Android, and iOS. **No Flutter required.**

`iroh_dart` **wraps** the iroh Rust core through an owned
[flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge) crate (used in its pure-Dart
mode — the name is historical, the runtime has no Flutter dependency); it does not re-implement iroh
in Dart. The Dart API mirrors iroh 1.0's nouns exactly (`Endpoint` / `EndpointId` / `EndpointAddr`,
`addressLookup`), so iroh's docs and the n0 examples transfer directly.

> Pure Dart: the native cdylib is built with `cargo build` and loaded over `dart:ffi`
> (no Flutter, no cargokit). Runs under plain `dart run` / `dart test`.

## Quick start

Build the native library once (`cd rust && cargo build --release`), then:

```dart
import 'dart:typed_data';
import 'package:iroh_dart/iroh_dart.dart';

Future<void> main() async {
  // Loads the native library (rust/target/{debug,release}/libirohdart_ffi.so by
  // default; pass libraryPath: for a custom location) + verifies the ABI handshake.
  await Iroh.init();

  // Identity & addressing (pure data, no runtime).
  final secret = SecretKey.generate();
  print('my id: ${secret.publicKey.toZ32()}'); // publicKey == EndpointId

  // A server that echoes one bidirectional stream.
  const alpn = 'my-app/echo/0';
  final server = await Endpoint.bind(alpns: [alpn.codeUnits]);
  final serving = () async {
    final conn = await server.accept();
    final (send, recv) = await conn!.acceptBi();
    await send.writeAll(await recv.readToEnd(1 << 20));
    await send.finish();
  }();

  // A client that connects and reads the echo back.
  final client = await Endpoint.bind();
  final conn = await client.connect(server.addr, alpn.codeUnits);
  final (send, recv) = await conn.openBi();
  await send.writeAll(Uint8List.fromList('hello'.codeUnits));
  await send.finish();
  print(String.fromCharCodes(await recv.readToEnd(1 << 20))); // hello
  await serving;

  await client.close();
  await server.close();
}
```

## Platforms

| Linux | macOS | Windows | Android | iOS |
|---|---|---|---|---|
| ✅ | ✅ | ✅ | ✅ | ✅ |

The native library is built from source with `cargo` (Rust toolchain required). On desktop the
loader finds `rust/target/{debug,release}/libirohdart_ffi.so` automatically (or pass an explicit
`libraryPath:`); on mobile, cross-compile the cdylib (Android) / staticlib (iOS) and bundle it the
way your host app expects.

## API surface

- **Identity & addressing** - `SecretKey`, `PublicKey` / `EndpointId`, `Signature`, `EndpointAddr`,
  `RelayUrl`, `RelayMode`, `RelayMap`.
- **Endpoint** - `Endpoint.bind({secretKey, alpns, relayMode})`, `close`, `isClosed`, `setAlpns`,
  `boundSockets`, `addr`, `connect`, `accept`, `acceptIncoming`.
- **Connection & streams** - `openBi`/`openUni`/`acceptBi`/`acceptUni`, datagrams, `stats`,
  `remoteId`, `alpn`, `closed`; `SendStream` (`writeAll`/`finish`/`reset`),
  `RecvStream` (`read`/`readExact`/`readToEnd`/`stop`).
- **Accept filter** - `Incoming` (`remoteAddr`, `accept`/`refuse`/`retry`/`ignore`).
- **Reactive streams** - `Endpoint.watchAddr()`, `Endpoint.homeRelayStatus()`,
  `Connection.pathEvents()` (sealed `PathEvent`).
- **Multi-protocol routing** - `Endpoint.router()` -> `RouterBuilder.accept(alpn, handler)` ->
  `spawn()`/`Router.shutdown()`: register a Dart handler per ALPN and let iroh's `Router` dispatch.
- **Custom address lookup** - `Endpoint.bindWithAddressLookup(resolve:)`: dial peers known only by
  their `EndpointId`, resolving their `EndpointAddr` in Dart.

> **Lazy-stream footgun:** a freshly opened `SendStream` is invisible to the peer until the first
> `writeAll`.

Run the bundled headless example (`dart run`, no Flutter):

```sh
cd rust && cargo build --release && cd ..
dart pub get
dart run example/echo.dart
```

## Develop

```sh
dart pub get
cargo install flutter_rust_bridge_codegen --version '^2'  # standalone cargo binary
./tool/frb_codegen.sh   # regen FRB glue after editing rust/src/api/*
./tool/check.sh         # cargo build+test, then dart analyze + dart test
```

Requires Rust >= 1.91 (edition 2024; pinned to 1.96.0) and, for Android, NDK r28+.

## License

Apache-2.0 - see [`LICENSE`](LICENSE). The `iroh` crate is MIT OR Apache-2.0.
