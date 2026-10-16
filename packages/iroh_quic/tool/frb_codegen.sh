#!/usr/bin/env bash
# Generates the FRB code again: the Rust rust/src/frb_generated.rs and the Dart bindings in
# lib/src/rust/. Run this script after each change to rust/src/api/*.
# The FRB codegen reads flutter_rust_bridge.yaml in the package root.
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
