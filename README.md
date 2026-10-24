# iroh_dart monorepo

Dart + Flutter bindings for **[iroh](https://github.com/n0-computer/iroh) v1.3.0**: peer-to-peer QUIC
networking (endpoints, connections, streams, relays, address lookup) over the iroh Rust core via
[flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge) + `dart:ffi`.

This is a [pub workspace](https://dart.dev/tools/pub/workspaces) (Melos) with two published packages
that share one Rust crate:

| Package | What | Platforms |
|---|---|---|
| [`packages/iroh_quic`](packages/iroh_quic) | **Pure-Dart** binding. `dart run` / CLI / server. Loads a signed prebuilt native lib (`dart run iroh_quic:setup`) or builds from source. | Linux · macOS · Windows |
| [`packages/iroh_flutter`](packages/iroh_flutter) | **Flutter plugin**. Builds the native core into your app via cargokit; re-exports the full `iroh_quic` API. | Android · iOS · macOS · Linux · Windows |

The Dart API is identical across both. `iroh_flutter` just adds the per-platform native build for
Flutter apps. Pick `iroh_quic` for a desktop/CLI Dart program, `iroh_flutter` for a Flutter app.

## Layout

```
pubspec.yaml                      workspace root + Melos config (no melos.yaml)
tool/sync_native.sh               vendors the shared crate into the plugin (cargokit needs it co-located)
tool/build_xcframework.sh         builds irohdart_ffi.xcframework for the Swift package of the plugin
packages/
  iroh_quic/                      pure-Dart binding (publishable)
    rust/                         the owned `irohdart_ffi` crate (canonical source of truth)
    lib/  bin/  test/  tool/
  iroh_flutter/                   Flutter plugin (publishable)
    android/ darwin/ linux/ windows/   cargokit native build per platform
                                  (darwin/ = iOS + macOS: podspec + Swift package)
    cargokit/                     vendored build glue
    rust/                         generated copy of the crate (gitignored; from sync_native.sh)
    example/                      example app + on-device integration tests
```

## Develop

```sh
dart pub global activate melos          # optional; plain pub get also works
flutter pub get                         # resolves the whole workspace
bash tool/sync_native.sh                # vendor the crate into iroh_flutter (also run by `melos bootstrap`)

# Pure-Dart gate (Rust + Dart tests for iroh_quic):
./packages/iroh_quic/tool/check.sh

# Flutter plugin (build the example for any platform):
cd packages/iroh_flutter/example && flutter run -d macos   # or an iOS sim / Android emulator
```

The single source of truth for the Rust crate is `packages/iroh_quic/rust`. cargokit requires the
crate beside the plugin, so `tool/sync_native.sh` mirrors it into `packages/iroh_flutter/rust` (which
is gitignored and re-vendored before publishing).

## Native library distribution

- **iroh_quic (desktop):** signed prebuilt cdylibs are built per release, Ed25519-signed, and
  attached to the GitHub Release; `dart run iroh_quic:setup` downloads + verifies one. No Rust
  toolchain needed. Or `dart run iroh_quic:build` to compile from source.
- **iroh_flutter (mobile/desktop):** cargokit compiles the crate during the consumer's app build (no
  download); force `cargokit_options.yaml: use_precompiled_binaries: false` to always build from
  source. Exception: with Swift Package Manager on iOS/macOS, Xcode cannot run cargo, so the Swift
  package downloads a prebuilt `irohdart_ffi.xcframework` from the GitHub release
  `xcframework-v<version>`. CocoaPods builds keep using cargokit.

### Releasing the XCFramework

`darwin/iroh_flutter/Package.swift` holds the version and SwiftPM checksum of the XCFramework, and
the checksum must be in the tagged commit. So, after the version bump and before the tag:

1. Run the **xcframework** workflow (Actions → xcframework → Run workflow) on the release branch.
   It runs `tool/build_xcframework.sh`, attaches `irohdart_ffi.xcframework.zip` to the release
   `xcframework-v<version>`, and opens a pull request that writes the version and checksum into
   `Package.swift`.
2. Merge that pull request, then push the `v<version>` tag as usual. The release workflow stops
   before it publishes anything if the checksum, the version, or the crate source does not agree
   with the XCFramework release.

For a local build, `bash tool/build_xcframework.sh` writes the framework into
`darwin/iroh_flutter/Frameworks/` (gitignored), and `Package.swift` uses it instead of the
download.

See each package's README for details.

## License

Apache-2.0. See [LICENSE](LICENSE).
