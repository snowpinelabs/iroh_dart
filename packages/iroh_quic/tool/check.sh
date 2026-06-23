#!/usr/bin/env bash
# iroh_quic green gate - build + test the Rust crate, then analyze + test the pure-Dart package.
# The PACKAGE is Flutter-free, but it lives in a mixed Dart+Flutter pub workspace, so resolution is
# done once at the workspace root with `flutter pub get` (falls back to `dart pub get` when Flutter
# is absent). Run from anywhere; resolves paths itself.
set -uo pipefail
export PATH="$HOME/.cargo/bin:$PATH"

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # packages/iroh_quic
WORKSPACE="$(cd "$PKG/../.." && pwd)"                     # repo root (pub workspace)
red=0

echo "=== resolve workspace ($WORKSPACE) ==="
if command -v flutter >/dev/null 2>&1; then
  (cd "$WORKSPACE" && flutter pub get) || { echo "PUB GET RED"; red=1; }
else
  (cd "$WORKSPACE" && dart pub get)    || { echo "PUB GET RED (mixed workspace usually needs flutter)"; red=1; }
fi

echo "=== rust: irohdart_ffi (build + test) ==="
# Build first so the host cdylib exists for `dart test` to dlopen (loader.dart's disk-path fallback:
# rust/target/{debug,release}/libirohdart_ffi.{so,dylib,dll}).
(cd "$PKG/rust" && cargo build) || { echo "BUILD RED: irohdart_ffi"; red=1; }
(cd "$PKG/rust" && cargo test)  || { echo "CARGO TEST RED: irohdart_ffi"; red=1; }

echo "=== dart: iroh_quic (analyze + test) ==="
(cd "$PKG" && dart analyze --fatal-infos) || { echo "ANALYZE RED: iroh_quic"; red=1; }
(cd "$PKG" && dart test)                  || { echo "TEST RED: iroh_quic";    red=1; }

if [ "$red" -ne 0 ]; then echo "GREEN GATE: RED"; exit 1; fi
echo "GREEN GATE: GREEN"
