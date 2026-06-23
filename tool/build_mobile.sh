#!/usr/bin/env bash
# Cross-compile irohdart-ffi for mobile and stage artifacts (manual helper / CI building block).
# In normal app builds cargokit drives this per-platform; this script supports local device
# testing and the distribution pipeline.
#
#   iOS:     staticlib for device (aarch64-apple-ios) + simulator (aarch64-apple-ios-sim),
#            process()-linked. fast-apple-datapath is OFF (App Store private-API risk).
#   Android: per-ABI cdylib via cargo-ndk into jniLibs (arm64-v8a, armeabi-v7a, x86_64).
#            Requires NDK r28+ for the 16KB page-alignment Google Play gate.
#
# Prereqs:
#   rustup target add aarch64-apple-ios aarch64-apple-ios-sim \
#       aarch64-linux-android armv7-linux-androideabi x86_64-linux-android
#   cargo install cargo-ndk   # already present in this env
#   Android NDK r28+ under $ANDROID_NDK_HOME or $ANDROID_SDK/ndk/<ver>
#
# Usage: tool/build_mobile.sh [ios|android|all]   (default: all)
set -euo pipefail
export PATH="$HOME/.cargo/bin:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE="$ROOT/rust"
STAGE="$ROOT"
WHAT="${1:-all}"
PROFILE="release"

build_ios() {
  echo "==================== iOS staticlib ===================="
  mkdir -p "$STAGE/ios/native/device" "$STAGE/ios/native/sim"
  for pair in "aarch64-apple-ios:device" "aarch64-apple-ios-sim:sim"; do
    target="${pair%%:*}"; slot="${pair##*:}"
    echo "-> $target ($slot)"
    # Install the target for the PINNED toolchain (rust-toolchain.toml). Running rustup from the
    # crate dir honors the pin; adding it elsewhere installs rust-std for the wrong toolchain and
    # the build fails with "can't find crate for `core`".
    (cd "$CRATE" && rustup target add "$target")
    (cd "$CRATE" && cargo build --"$PROFILE" --target "$target")
    cp "$CRATE/target/$target/$PROFILE/libirohdart_ffi.a" \
       "$STAGE/ios/native/$slot/libirohdart_ffi.a"
  done
}

build_android() {
  echo "==================== Android cdylib (cargo-ndk) ===================="
  local jni="$STAGE/android/src/main/jniLibs"
  mkdir -p "$jni"
  # Targets must exist for the pinned toolchain (see build_ios note). NDK r28+ required for the
  # 16KB page-alignment Google Play gate (verified: arm64 LOAD align = 0x4000 with NDK r29).
  (cd "$CRATE" && rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android)
  # API 24 (minSdk 24). -o stages per-ABI .so under jniLibs/<abi>/.
  (cd "$CRATE" && cargo ndk -o "$jni" \
      -t arm64-v8a -t armeabi-v7a -t x86_64 \
      build --"$PROFILE")
}

case "$WHAT" in
  ios)     build_ios ;;
  android) build_android ;;
  all)     build_ios; build_android ;;
  *) echo "usage: $0 [ios|android|all]" >&2; exit 2 ;;
esac

echo "==> Done. Staged native libs:"
find "$STAGE/ios/native" "$STAGE/android/src/main/jniLibs" \
     \( -name '*.a' -o -name '*.so' \) 2>/dev/null | sort
