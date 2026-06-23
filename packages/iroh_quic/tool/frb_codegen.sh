#!/usr/bin/env bash
# Regenerate the flutter_rust_bridge glue (Rust frb_generated.rs + Dart lib/src/rust/*).
# Run after any change to rust/src/api/*. Reads flutter_rust_bridge.yaml at the repo root.
set -euo pipefail
export PATH="$HOME/.cargo/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
  echo "flutter_rust_bridge_codegen not found - install with:" >&2
  echo "  cargo install flutter_rust_bridge_codegen --version '^2'" >&2
  exit 1
fi

flutter_rust_bridge_codegen generate "$@"
echo "FRB codegen: done. Review git diff under rust/src/frb_generated.rs and lib/src/rust/."
