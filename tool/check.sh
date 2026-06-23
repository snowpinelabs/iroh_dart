#!/usr/bin/env bash
# iroh_dart check - build + test the Rust wrapper, then analyze + test every Dart package.
# Must pass before AND after every change.
# Run from anywhere; resolves the repo root itself.
set -uo pipefail
export PATH="$HOME/.cargo/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
red=0

echo "=== rust: irohdart-ffi (build + test) ==="
# Build first so the host dylib exists for `flutter test` to dlopen (see loader.dart fallback).
(cd rust && cargo build) || { echo "BUILD RED: irohdart-ffi"; red=1; }
(cd rust && cargo test)  || { echo "CARGO TEST RED: irohdart-ffi"; red=1; }

echo "=== dart: iroh_dart (analyze + test) ==="
flutter analyze --fatal-infos || { echo "ANALYZE RED: iroh_dart"; red=1; }
flutter test                  || { echo "TEST RED: iroh_dart";    red=1; }

echo "=== dart: example (analyze) ==="
(cd example && flutter analyze --fatal-infos) || { echo "ANALYZE RED: example"; red=1; }

if [ "$red" -ne 0 ]; then echo "GREEN GATE: RED"; exit 1; fi
echo "GREEN GATE: GREEN"
