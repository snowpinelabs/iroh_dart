#!/usr/bin/env bash
# Copy the crate into the plugin as the vendored crate.
#
# cargokit finds the crate at `../rust` from the android, ios, macos, linux, and windows directories.
# Thus the crate must be in packages/iroh_flutter.
# The source of the crate is packages/iroh_quic/rust.
# This script copies it to packages/iroh_flutter/rust, the mirror. Git keeps the mirror.
# The Melos `bootstrap` post-hook runs this script.
# The ci and release workflows also run it and make sure that the mirror has no changes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/packages/iroh_quic/rust"
DST="$ROOT/packages/iroh_flutter/rust"

if [ ! -d "$SRC" ]; then
  echo "sync_native: source crate not found at $SRC" >&2
  exit 1
fi
if [ ! -d "$ROOT/packages/iroh_flutter" ]; then
  echo "sync_native: packages/iroh_flutter not present yet - nothing to sync."
  exit 0
fi

echo "sync_native: mirroring $SRC -> $DST (excluding build output)"
mkdir -p "$DST"
# Copy the source files. Do not copy the cargo target/ directory, which can be very large.
# --delete removes files that are not in the source. Thus the mirror is an exact copy.
rsync -a --delete --exclude 'target/' "$SRC/" "$DST/"
echo "sync_native: done."
