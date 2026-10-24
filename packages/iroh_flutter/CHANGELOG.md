# Changelog

## 1.2.0

- **iOS/macOS:** support Swift Package Manager. This removes the warning `The following plugins 
  do not support Swift Package Manager`. Xcode cannot run cargo in a
  Swift package build, so the Swift package downloads a prebuilt dynamic
  `irohdart_ffi.xcframework` from the GitHub release `xcframework-v<version>`.

## 1.1.1

- **Android:** fix the app build failure `Could not find any matches for
  rustls:rustls-platform-verifier:latest.release`. `rustls-platform-verifier` 0.7.1 no longer
  bundles its Kotlin component (AAR) in the crate, and it publishes the AAR under the Maven group
  `org.rustls`. The plugin now gets the AAR from the upstream Maven repository on GitHub. It uses
  the exact version that `Cargo.lock` locks. Android builds need network access to `github.com`.

## 1.1.0

- Builds the native core against iroh 1.3.0 and exposes its new APIs (batch datagrams,
  `RelayStatus.authDeniedReason`); see the `iroh_quic` changelog. ABI version 2.
- `flutter_lints` ^6.0.0. The analysis options now exclude `build/` and the platform folders,
  so Flutter 3.47+ no longer rewrites them on `pub get`.

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
  bundled native library (no `setup` step on Flutter).
- Android NDK r28+ (16 KB page alignment); iOS 13+ / macOS 11+; `-force_load` staticlib on Apple.
