#!/usr/bin/env bash
# iroh_quic green gate. It builds and tests the crate, then analyzes and tests the Dart package.
# The package does not use Flutter. But the pub workspace contains Dart and Flutter packages.
# Thus the script resolves dependencies one time at the workspace root with `flutter pub get`.
# If Flutter is not installed, the script uses `dart pub get`.
# You can run this script from any directory. The script finds its paths itself.
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
# Build first, so that `dart test` can open the native library for the host. The loader
# (lib/src/ffi/loader.dart) finds it in rust/target/{debug,release}/.
(cd "$PKG/rust" && cargo build) || { echo "BUILD RED: irohdart_ffi"; red=1; }
(cd "$PKG/rust" && cargo test)  || { echo "CARGO TEST RED: irohdart_ffi"; red=1; }

echo "=== dart: iroh_quic (analyze + test) ==="
(cd "$PKG" && dart analyze --fatal-infos) || { echo "ANALYZE RED: iroh_quic"; red=1; }
(cd "$PKG" && dart test)                  || { echo "TEST RED: iroh_quic";    red=1; }

if [ "$red" -ne 0 ]; then echo "GREEN GATE: RED"; exit 1; fi
echo "GREEN GATE: GREEN"
