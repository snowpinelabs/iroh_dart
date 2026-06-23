# iroh_dart

Dart/Flutter binding for **[iroh](https://github.com/n0-computer/iroh) 1.0** - peer-to-peer QUIC
networking (endpoints, connections, streams, relays, address lookup) for iOS, Android, macOS,
Windows, and Linux.

`iroh_dart` **wraps** the iroh Rust core through an owned
[flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge) crate; it does not re-implement
iroh in Dart. The Dart API mirrors iroh 1.0's nouns exactly (`Endpoint` / `EndpointId` /
`EndpointAddr`, `addressLookup`), so iroh's docs and the n0 examples transfer directly.

## Quick start

```dart
import 'dart:typed_data';
import 'package:iroh_dart/iroh_dart.dart';

Future<void> main() async {
  await Iroh.init(); // loads the native library + verifies the ABI handshake

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

| iOS | Android | macOS | Windows | Linux |
|---|---|---|---|---|
| ✅ | ✅ | ✅ | ✅ | ✅ |

Consumers without a Rust toolchain download a signed, prebuilt native library (cargokit
precompiled-binaries mode); consumers with Rust build from source automatically.

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

## Develop

```sh
flutter pub get
cargo install flutter_rust_bridge_codegen --version '^2'
./tool/frb_codegen.sh   # regen FRB glue after editing rust/src/api/*
./tool/check.sh         # runs cargo build+test, flutter analyze+test
```

Requires Rust >= 1.91 (edition 2024; pinned to 1.96.0) and, for Android, NDK r28+.

## License

Apache-2.0 - see [`LICENSE`](LICENSE). The `iroh` crate is MIT OR Apache-2.0.
