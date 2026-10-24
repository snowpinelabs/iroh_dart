# iroh for Dart and Flutter

Connect devices directly to each other, by public key, from Dart and Flutter.

[iroh](https://github.com/n0-computer/iroh) gives every device a stable identity (an ed25519 key)
and opens encrypted QUIC connections between them. It punches through NATs when it can and falls
back to a relay server when it can't, so the same code works on a LAN, across the internet, and
between phones on mobile networks. This repository wraps the iroh **1.3** Rust core for Dart; it
does not re-implement iroh, so iroh's own docs and concepts apply directly.

## Which package do I need?

| You are building… | Use | Platforms |
|---|---|---|
| A Flutter app | [`iroh_flutter`](packages/iroh_flutter) | Android · iOS · macOS · Linux · Windows |
| A Dart CLI, server, or desktop tool (no Flutter) | [`iroh_quic`](packages/iroh_quic) | Linux · macOS · Windows |

Both packages have the same API. `iroh_flutter` adds the native build for each Flutter platform,
and re-exports everything from `iroh_quic`.

## Quick start

### Flutter

```sh
flutter pub add iroh_flutter
```

```dart
import 'package:iroh_flutter/iroh_flutter.dart';

Future<void> main() async {
  await Iroh.init(); // The plugin bundles the native library. No extra setup step.
  final endpoint = await Endpoint.bind();
  print('My endpoint id: ${endpoint.id.toZ32()}');
}
```

The first build compiles the Rust core, and installs a Rust toolchain if you don't have one.
On iOS and macOS with Swift Package Manager (the Flutter default since 3.44), the plugin downloads a
prebuilt framework instead, so no Rust toolchain is needed there.

### Dart (no Flutter)

```sh
dart pub add iroh_quic
dart run iroh_quic:setup   # one time: downloads and verifies a signed prebuilt native library
```

Then use the same API as above, with `import 'package:iroh_quic/iroh_quic.dart';`. To compile the
native library yourself instead, run `dart run iroh_quic:build` (needs [Rust](https://rustup.rs)).

## Examples

All examples use the same API in both packages.

### Echo: a server and a client

An endpoint accepts connections for the ALPN protocols it lists. A client connects with one of
them and talks over bidirectional streams.

```dart
import 'dart:typed_data';

const alpn = 'my-app/echo/0';

// Server: accept one connection and echo one stream back.
final server = await Endpoint.bind(alpns: [alpn.codeUnits]);
final serving = () async {
  final conn = await server.accept();
  final (send, recv) = await conn!.acceptBi();
  await send.writeAll(await recv.readToEnd(1 << 20));
  await send.finish();
}();

// Client: connect to the server address and read the echo.
final client = await Endpoint.bind();
final conn = await client.connect(server.addr, alpn.codeUnits);
final (send, recv) = await conn.openBi();
await send.writeAll(Uint8List.fromList('hello'.codeUnits));
await send.finish();
print(String.fromCharCodes(await recv.readToEnd(1 << 20))); // hello

await serving;
await client.close();
await server.close();
```

### Connect two devices

To connect from another device, it needs the server's `EndpointAddr`: the endpoint id plus the
relay URL and IP addresses where it can be reached. Encode it to send it any way you like, for
example as a QR code, a link, or a chat message.

```dart
import 'dart:convert';

// On the server device: share this text.
final ticket = base64Url.encode(server.addr.encode());

// On the client device: decode it and connect.
final addr = EndpointAddr.decode(base64Url.decode(ticket));
final conn = await client.connect(addr, alpn.codeUnits);
```

`Endpoint.watchAddr()` emits a new address when the network changes, for example when the device
switches from Wi-Fi to mobile data.

### Keep the same identity across restarts

An endpoint's id is the public key of its `SecretKey`. Store the key to keep the same id.

```dart
final secret = SecretKey.generate();
final bytes = secret.toBytes(); // 32 bytes. Store them securely.

// Later:
final endpoint = await Endpoint.bind(secretKey: SecretKey.fromBytes(bytes));
```

### Serve more than one protocol

A router sends each incoming connection to the handler for its ALPN.

```dart
final endpoint = await Endpoint.bind();
final builder = await endpoint.router();
await builder.accept('my-app/chat/0'.codeUnits, (conn) async {
  final (send, recv) = await conn.acceptBi();
  // ...
});
await builder.accept('my-app/files/0'.codeUnits, (conn) async {
  // ...
});
final router = await builder.spawn();

// When you are done:
await router.shutdown();
```

More: [`iroh_quic/example/iroh_quic_example.dart`](packages/iroh_quic/example/iroh_quic_example.dart)
(headless Dart) and [`iroh_flutter/example`](packages/iroh_flutter/example) (Flutter app). The
[`iroh_quic` README](packages/iroh_quic/README.md) lists the full API: datagrams, unidirectional
streams, connection stats, relay status, path events, accept filters, and custom address lookup.

## Contributing

The repository is a [pub workspace](https://dart.dev/tools/pub/workspaces), so one
`flutter pub get` at the root resolves everything.

```sh
flutter pub get
./packages/iroh_quic/tool/check.sh    # Rust build and tests, then Dart analyze and tests

cd packages/iroh_flutter/example
flutter run                           # the example app on any platform
```

The Rust crate lives in `packages/iroh_quic/rust`. cargokit needs a copy of it inside the plugin,
so `packages/iroh_flutter/rust` is a committed mirror. After you change the crate, run
`bash tool/sync_native.sh` and commit the mirror too; CI fails if the mirror is stale. After you
change the Rust API, regenerate the Dart bindings with `packages/iroh_quic/tool/frb_codegen.sh`.

## Releasing

Both packages have the same version and are released together from `main`.

1. Bump the version everywhere: both `pubspec.yaml` files (and the `iroh_quic` constraint in the
   plugin), the crate's `Cargo.toml`, `kIrohdartLibVersion` in
   `packages/iroh_quic/lib/src/ffi/prebuilt.dart`, and both changelogs. Run
   `bash tool/sync_native.sh`. Merge this to `main`.
2. Build the XCFramework for Swift Package Manager: run the **xcframework** workflow on `main`
   (`gh workflow run xcframework.yml --ref main`). It attaches `irohdart_ffi.xcframework.zip` to
   the GitHub release `xcframework-v<version>` and pushes a branch that writes the version and
   checksum into `packages/iroh_flutter/darwin/iroh_flutter/Package.swift`. It also opens a pull
   request for that branch if the repository allows GitHub Actions to create pull requests;
   otherwise, open it yourself. Merge it.
3. Push the tag `v<version>`. The **release** workflow checks that `Package.swift` agrees with the
   XCFramework release, builds and signs the desktop prebuilt libraries, and publishes both
   packages to pub.dev.

The tag must come after step 2, because the published plugin must contain the XCFramework checksum.
To build the XCFramework locally, run `bash tool/build_xcframework.sh`. The Swift package then uses
your local build instead of the download.

## License

Apache-2.0. See [LICENSE](LICENSE). The iroh crate is MIT OR Apache-2.0.
