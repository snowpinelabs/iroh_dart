#!/usr/bin/env bash
# Vendor the canonical Rust crate into the Flutter plugin.
#
# cargokit resolves the crate as `../rust` relative to the plugin's android/ios/macos/linux/windows
# build files, so the crate MUST live inside packages/iroh_flutter. The single source of truth is
# packages/iroh_quic/rust; this script mirrors it into packages/iroh_flutter/rust (which is
# gitignored). Run automatically by the Melos `bootstrap` post-hook, and explicitly in release CI
# before building/publishing iroh_flutter.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/packages/iroh_quic/rust"
DST="$ROOT/packages/iroh_flutter/rust"

if [ ! -d "$SRC" ]; then
  echo "sync_native: source crate not found at $SRC" >&2
  exit 1
fi
if [ ! -d "$ROOT/packages/iroh_flutter" ]; then
  echo "sync_native: packages/iroh_flutter not present yet — nothing to sync."
  exit 0
fi

echo "sync_native: mirroring $SRC -> $DST (excluding build output)"
mkdir -p "$DST"
# Mirror sources; never copy the multi-GB cargo target/ dir. --delete keeps the mirror exact.
rsync -a --delete --exclude 'target/' "$SRC/" "$DST/"
echo "sync_native: done."
