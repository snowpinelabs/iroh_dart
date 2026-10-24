# iroh_flutter

**Flutter plugin** for **[iroh](https://github.com/n0-computer/iroh) 1.x**: peer-to-peer QUIC
networking (endpoints, connections, streams, relays, address lookup) on **Android, iOS, macOS,
Linux, and Windows**.

This plugin builds the native Rust core (`irohdart_ffi`) into your app at build time via
[cargokit](https://github.com/irondash/cargokit) and re-exports the full API of the pure-Dart
[`iroh_quic`](https://pub.dev/packages/iroh_quic) package. A Rust toolchain is installed
automatically by cargokit on first build if you don't already have one.

## Usage

```yaml
dependencies:
  iroh_flutter: ^1.2.0
```

```dart
import 'package:iroh_flutter/iroh_flutter.dart';

Future<void> main() async {
  await Iroh.init(); // native lib is bundled by the plugin build, no setup step
  final secret = SecretKey.generate();
  print('my id: ${secret.publicKey.toZ32()}');
  // ... Endpoint.bind(), connect(), accept(), etc. See the iroh_quic docs.
}
```

The API is identical to `iroh_quic`; see its
[README](https://pub.dev/packages/iroh_quic) and the iroh 1.x docs.

## Platforms

| Android | iOS | macOS | Linux | Windows |
|---|---|---|---|---|
| ✅ | ✅ | ✅ | ✅ | ✅ |

- **Android:** cargokit cross-compiles a per-ABI cdylib via `cargo-ndk` into `jniLibs` (NDK r28+ for
  the 16 KB page-alignment Google Play requirement). `minSdk` 24. The plugin registers a tiny
  `IrohFlutterPlugin` class that hands the application `Context` to the native library during
  engine startup. iroh needs it over JNI for system DNS, interface enumeration, and TLS trust.
  Nothing to configure; but if you build a custom engine setup that skips plugin registration,
  make sure `IrohFlutterPlugin` is registered before the first iroh call.
- **iOS / macOS:** iOS 13+ / macOS 11+. The plugin supports both Swift Package Manager and
  CocoaPods.
  - **Swift Package Manager** (the default from Flutter 3.44): Xcode cannot run cargo in a Swift
    package build, so the package downloads a prebuilt `irohdart_ffi.xcframework` from the GitHub
    release of the plugin version. The app embeds this dynamic framework. No Rust toolchain is
    necessary.
  - **CocoaPods:** cargokit builds a staticlib and `-force_load`s it into the plugin framework.
  In both cases, the FFI symbols are visible to `DynamicLibrary.process()`.
- **Linux / Windows:** cargokit builds a cdylib bundled next to the app.

### macOS: allow network access

macOS Flutter apps run in the App Sandbox, and the sandbox blocks network access by default. Without
network entitlements, `Endpoint.bind()` throws `IrohBindException: Failed to bind sockets`. The
Flutter template allows only incoming connections, and only in debug builds, so a release build
fails even when the debug build works.

Add both keys to `macos/Runner/DebugProfile.entitlements` **and** `macos/Runner/Release.entitlements`:

```xml
<key>com.apple.security.network.client</key>
<true/>
<key>com.apple.security.network.server</key>
<true/>
```

`network.client` allows outgoing connections, and `network.server` allows the endpoint to accept
incoming connections.

### iOS: local network permission

iOS asks the user before an app talks to devices on the local network. If your app connects to
peers on the same Wi-Fi network, add an `NSLocalNetworkUsageDescription` to `ios/Runner/Info.plist`
that explains why. Connections through a relay or over the internet do not need it.

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

On iOS and macOS with Swift Package Manager, cargokit does not run. To use a native library that
you built yourself, run `tool/build_xcframework.sh` in a checkout of the repository. The script
writes `darwin/iroh_flutter/Frameworks/irohdart_ffi.xcframework`, and the Swift package then uses
it instead of the release download. As an alternative, turn off Swift Package Manager for your app
(`flutter config --no-enable-swift-package-manager`) to use cargokit through CocoaPods.

See the repository README for the full source-build guide.
