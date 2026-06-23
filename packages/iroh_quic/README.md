# iroh_quic

**Pure-Dart** binding for **[iroh](https://github.com/n0-computer/iroh) 1.0** - peer-to-peer QUIC
networking (endpoints, connections, streams, relays, address lookup) on **desktop Linux, macOS, and
Windows**. **No Flutter required.** For **Android / iOS**, use the companion
[`iroh_flutter`](https://pub.dev/packages/iroh_flutter) plugin — same API, native build bundled into
your app.

`iroh_quic` **wraps** the iroh Rust core; it does not re-implement iroh
in Dart. The Dart API mirrors iroh 1.0's nouns exactly (`Endpoint` / `EndpointId` / `EndpointAddr`,
`addressLookup`), so iroh's docs and the n0 examples transfer directly.

## Quick start

Download the signed prebuilt native library for your platform once — no Rust toolchain needed:

```sh
dart pub add iroh_quic
dart run iroh_quic:setup   # downloads + verifies the prebuilt lib into a per-user cache
```

(Prefer to build it yourself? `cd rust && cargo build --release` instead — the loader finds that too.)

```dart
import 'dart:typed_data';
import 'package:iroh_quic/iroh_quic.dart';

Future<void> main() async {
  // Loads the native library + verifies the ABI handshake. With no arguments the loader checks, in
  // order: a local `cargo build` (rust/target/{debug,release}), the `iroh_quic:setup` cache, and a
  // lib bundled next to the executable. Pass libraryPath: for a custom location.
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

Signed prebuilt libraries (downloaded by `dart run iroh_quic:setup`) cover the desktop targets a
pure-Dart program actually runs on:

| Linux x64 | Linux arm64 | macOS x64 | macOS arm64 | Windows x64 | Windows arm64 |
|---|---|---|---|---|---|
| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

The loader finds the prebuilt in its cache, a local `cargo build` under
`rust/target/{debug,release}/libirohdart_ffi.{so,dylib,dll}`, or a copy next to your compiled
executable — or pass an explicit `libraryPath:`.

**Mobile (Android / iOS):** these are not `dart run` targets. Use the
[`iroh_flutter`](https://pub.dev/packages/iroh_flutter) plugin, which compiles and bundles the native
library into your app automatically.

## Building the native library yourself

Don't want the prebuilt download (offline build, full audit, an unpublished arch, or a custom
profile)? Compile the crate from source — a [Rust toolchain](https://rustup.rs) is the only
prerequisite. The command installs the library into the same cache `iroh_quic:setup` uses, so
`Iroh.init()` finds it automatically:

```sh
dart run iroh_quic:build            # cargo build --release, then install
dart run iroh_quic:build --debug    # faster, unoptimized
```

Equivalently, build by hand and point the loader at the result:

```sh
cd rust && cargo build --release    # produces target/release/libirohdart_ffi.{so,dylib,dll}
```

The loader finds `rust/target/{debug,release}/` automatically when you run from the package root, or
pass `await Iroh.init(libraryPath: '/path/to/libirohdart_ffi.so')` for any location.

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
