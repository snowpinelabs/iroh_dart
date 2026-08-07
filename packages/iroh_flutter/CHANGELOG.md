# Changelog

## 1.0.3

- **Windows/Linux:** fix the CMake generate failure `No target "iroh_flutter_plugin"` when
  building an app that depends on the plugin. The desktop builds declared the bundled library
  with the non-FFI-plugin `$<TARGET_FILE_DIR:...>` expression; they now use the library path
  cargokit exports, so the Rust cdylib builds and bundles correctly on both platforms.

## 1.0.2

- **Android:** fix release-build abort `android context was not initialized` on the first
  `Endpoint.bind`. The plugin now registers an `IrohFlutterPlugin` class that installs
  the app's `JavaVM` + `Context` into the native library and initializes
  `rustls-platform-verifier` (bundling its Kotlin component) before any Dart code runs.

## 1.0.1

Initial release of the `iroh_flutter` plugin (the Flutter half of the `iroh_dart` →
`iroh_quic`/`iroh_flutter` split).

- Flutter FFI plugin building the iroh 1.0 Rust core (`irohdart_ffi`) into the app via cargokit on
  Android, iOS, macOS, Linux, and Windows.
- Re-exports the full [`iroh_quic`](https://pub.dev/packages/iroh_quic) API; `Iroh.init()` loads the
  bundled native library — no `setup` step on Flutter.
- Android NDK r28+ (16 KB page alignment); iOS 13+ / macOS 11+; `-force_load` staticlib on Apple.
