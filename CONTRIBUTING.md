# Contributing

## Development

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

1. Bump the version everywhere: both `pubspec.yaml` files, the `iroh_quic` constraint in the
   plugin, the `iroh_flutter` constraint in the example app and in the plugin README, the crate's
   `Cargo.toml` (then run `cargo metadata` in the crate so `Cargo.lock` follows),
   `kIrohdartLibVersion` in `packages/iroh_quic/lib/src/ffi/prebuilt.dart`, and both changelogs.
   Run `bash tool/sync_native.sh`. Merge this to `main`.
2. Build the XCFramework for Swift Package Manager: run the **xcframework** workflow on `main`
   (`gh workflow run xcframework.yml --ref main`). The run waits until a maintainer approves it
   (Actions → the run → **Review deployments**), because it runs in the `xcframework`
   environment. That environment accepts only `main`. The workflow attaches
   `irohdart_ffi.xcframework.zip` to the GitHub release `xcframework-v<version>` and pushes a
   branch that writes the version and checksum into
   `packages/iroh_flutter/darwin/iroh_flutter/Package.swift`. Then it opens a pull request for that
   branch. If the organization settings forbid pull requests from GitHub Actions, the run shows a
   warning with a link instead, and you open the pull request yourself. Merge it.
3. Push the tag `v<version>`. The **release** workflow checks that `Package.swift` agrees with the
   XCFramework release, builds and signs the desktop prebuilt libraries, and publishes both
   packages to pub.dev.

The tag must come after step 2, because the published plugin must contain the XCFramework checksum.
To build the XCFramework locally, run `bash tool/build_xcframework.sh`. The Swift package then uses
your local build instead of the download.
