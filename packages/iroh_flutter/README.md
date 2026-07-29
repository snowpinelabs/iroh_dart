# iroh_flutter

**Flutter plugin** for **[iroh](https://github.com/n0-computer/iroh) 1.0** — peer-to-peer QUIC
networking (endpoints, connections, streams, relays, address lookup) on **Android, iOS, macOS,
Linux, and Windows**.

This plugin builds the native Rust core (`irohdart_ffi`) into your app at build time via
[cargokit](https://github.com/irondash/cargokit) and re-exports the full API of the pure-Dart
[`iroh_quic`](https://pub.dev/packages/iroh_quic) package. A Rust toolchain is installed
automatically by cargokit on first build if you don't already have one.

## Usage

```yaml
dependencies:
  iroh_flutter: ^1.0.2
```

```dart
import 'package:iroh_flutter/iroh_flutter.dart';

Future<void> main() async {
  await Iroh.init(); // native lib is bundled by the plugin build — no setup step
  final secret = SecretKey.generate();
  print('my id: ${secret.publicKey.toZ32()}');
  // ... Endpoint.bind(), connect(), accept(), etc. — see the iroh_quic docs.
}
```

The API is identical to `iroh_quic`; see its
[README](https://pub.dev/packages/iroh_quic) and the iroh 1.0 docs.

## Platforms

| Android | iOS | macOS | Linux | Windows |
|---|---|---|---|---|
| ✅ | ✅ | ✅ | ✅ | ✅ |

- **Android:** cargokit cross-compiles a per-ABI cdylib via `cargo-ndk` into `jniLibs` (NDK r28+ for
  the 16 KB page-alignment Google Play requirement). `minSdk` 24. The plugin registers a tiny
  `IrohFlutterPlugin` class that hands the application `Context` to the native library during
  engine startup — iroh needs it over JNI for system DNS, interface enumeration, and TLS trust.
  Nothing to configure; but if you build a custom engine setup that skips plugin registration,
  make sure `IrohFlutterPlugin` is registered before the first iroh call.
- **iOS / macOS:** cargokit builds a staticlib and `-force_load`s it into the plugin framework, so
  the FFI symbols are visible to `DynamicLibrary.process()`. iOS 13+ / macOS 11+.
- **Linux / Windows:** cargokit builds a cdylib bundled next to the app.

## Pure-Dart / desktop CLI?

If you don't need Flutter (a `dart run` CLI or server on desktop), depend on
[`iroh_quic`](https://pub.dev/packages/iroh_quic) directly and run `dart run iroh_quic:setup` to
download a signed prebuilt library.

## Building the native library yourself

cargokit builds from source by default (it needs the Rust toolchain). To **force** a source build
even when prebuilt binaries are configured, add a `cargokit_options.yaml` next to your app's
`pubspec.yaml`:

```yaml
use_precompiled_binaries: false
```

See the repository README for the full source-build guide.
