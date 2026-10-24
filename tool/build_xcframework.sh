#!/usr/bin/env bash
# Build irohdart_ffi.xcframework for the Swift package of the plugin.
#
# The Swift package (packages/iroh_flutter/darwin/iroh_flutter/Package.swift) cannot run cargo.
# Thus it uses this prebuilt dynamic framework. The script builds the crate in
# packages/iroh_flutter/rust as a `cdylib` for each Apple target. Then it puts each library into a
# framework bundle and joins the bundles into one XCFramework.
#
# Usage: tool/build_xcframework.sh [--platforms "ios ios-simulator macos"] [--out DIR] [--zip]
#
#   --platforms  The platforms in the XCFramework. The default is all three platforms.
#   --out        The output directory. The default is the Frameworks/ directory of the Swift
#                package. Package.swift uses a framework in that directory instead of the release.
#   --zip        Also write irohdart_ffi.xcframework.zip and print its SwiftPM checksum.
#
# The script needs macOS, Xcode, and the Rust toolchain of the crate (rust/rust-toolchain.toml).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE="$ROOT/packages/iroh_flutter/rust"
NAME="irohdart_ffi"
PLATFORMS="ios ios-simulator macos"
OUT="$ROOT/packages/iroh_flutter/darwin/iroh_flutter/Frameworks"
ZIP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --platforms) PLATFORMS="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --zip) ZIP=1; shift ;;
    *) echo "build_xcframework: unknown argument $1" >&2; exit 1 ;;
  esac
done

# These minimum versions must agree with Package.swift and the podspec.
export IPHONEOS_DEPLOYMENT_TARGET=13.0
export MACOSX_DEPLOYMENT_TARGET=11.0

VERSION="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$CRATE/Cargo.toml" | head -1)"
WORK="$CRATE/target/xcframework"
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
OUT="$(cd "$OUT" && pwd)"
OUT="$(cd "$OUT" && pwd)"

# The Rust targets of each platform.
targets_for() {
  case "$1" in
    ios) echo "aarch64-apple-ios" ;;
    ios-simulator) echo "aarch64-apple-ios-sim x86_64-apple-ios" ;;
    macos) echo "aarch64-apple-darwin x86_64-apple-darwin" ;;
    *) echo "build_xcframework: unknown platform $1" >&2; exit 1 ;;
  esac
}

# Build the cdylib for one target. The arguments after `--` apply only to this crate, not to the
# dependencies. They set the install name, which the app uses to find the framework at run time.
# They also stop the strip step of rustc: the Apple linker refuses a dylib that rustc stripped
# ("mis-aligned LINKEDIT string pool"). The script strips the binary with Apple `strip` later.
build_target() {
  local target="$1" install_name="$2"
  echo "build_xcframework: cargo build $target"
  (cd "$CRATE" && cargo rustc --release --lib --crate-type cdylib --target "$target" \
    -- -C strip=none -C "link-arg=-Wl,-install_name,$install_name")
}

# Write the Info.plist of a framework bundle. App Store review needs MinimumOSVersion on iOS.
write_plist() {
  local path="$1" platform="$2" min_key="$3" min_version="$4"
  cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$NAME</string>
  <key>CFBundleIdentifier</key>
  <string>io.snowpine.irohdart-ffi</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$NAME</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>$platform</string>
  </array>
  <key>$min_key</key>
  <string>$min_version</string>
</dict>
</plist>
EOF
}

framework_args=()
for platform in $PLATFORMS; do
  fw="$WORK/$platform/$NAME.framework"
  mkdir -p "$fw"
  if [ "$platform" = "macos" ]; then
    # A macOS framework must have the versioned bundle structure.
    install_name="@rpath/$NAME.framework/Versions/A/$NAME"
    binary="$fw/Versions/A/$NAME"
    mkdir -p "$fw/Versions/A/Resources"
    write_plist "$fw/Versions/A/Resources/Info.plist" MacOSX LSMinimumSystemVersion "$MACOSX_DEPLOYMENT_TARGET"
    ln -s A "$fw/Versions/Current"
    ln -s "Versions/Current/$NAME" "$fw/$NAME"
    ln -s Versions/Current/Resources "$fw/Resources"
  else
    # An iOS framework has the flat bundle structure.
    install_name="@rpath/$NAME.framework/$NAME"
    binary="$fw/$NAME"
    if [ "$platform" = "ios" ]; then plist_platform=iPhoneOS; else plist_platform=iPhoneSimulator; fi
    write_plist "$fw/Info.plist" "$plist_platform" MinimumOSVersion "$IPHONEOS_DEPLOYMENT_TARGET"
  fi

  libs=()
  for target in $(targets_for "$platform"); do
    if command -v rustup >/dev/null; then (cd "$CRATE" && rustup target add "$target" >/dev/null); fi
    build_target "$target" "$install_name"
    libs+=("$CRATE/target/$target/release/lib$NAME.dylib")
  done
  lipo -create "${libs[@]}" -output "$binary"
  # Remove the local symbols. The exported FFI symbols stay, and the Dart loader finds them.
  strip -x "$binary"
  # lipo removes the signature. Xcode signs the framework again when it embeds it into the app.
  codesign --force --sign - "$binary"
  framework_args+=(-framework "$fw")
done

rm -rf "$OUT/$NAME.xcframework"
xcodebuild -create-xcframework "${framework_args[@]}" -output "$OUT/$NAME.xcframework"
echo "build_xcframework: wrote $OUT/$NAME.xcframework"

if [ "$ZIP" = 1 ]; then
  rm -f "$OUT/$NAME.xcframework.zip"
  # ditto keeps the symbolic links of the macOS framework.
  (cd "$OUT" && ditto -c -k --sequesterRsrc --keepParent "$NAME.xcframework" "$NAME.xcframework.zip")
  echo "build_xcframework: wrote $OUT/$NAME.xcframework.zip"
  echo "checksum: $(shasum -a 256 "$OUT/$NAME.xcframework.zip" | cut -d ' ' -f 1)"
fi
