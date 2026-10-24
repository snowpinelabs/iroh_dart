#
# iOS and macOS part of the iroh_flutter plugin for CocoaPods. cargokit builds the crate
# `irohdart_ffi` (in ../rust) as a static library. On iOS, cargokit builds it for device and
# simulator. On macOS, cargokit builds a universal static library (arm64 and x86_64). The app
# links this static library.
# The crate disables the iroh feature `fast-apple-datapath` because it uses a private Apple API.
# A private API is a risk for App Store review. The minimum versions are iOS 13 and macOS 11.
#
# Swift Package Manager does not use this file. It uses iroh_flutter/Package.swift.
#
Pod::Spec.new do |s|
  s.name             = 'iroh_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Dart/Flutter binding for iroh 1.x (P2P QUIC) over the shared Rust core.'
  s.description      = 'Wraps the iroh 1.x Rust core via flutter_rust_bridge.'
  s.homepage         = 'https://github.com/snowpinelabs/iroh_dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Leonardo Custodio' => 'leonardo@custodio.me' }
  s.source           = { :path => '.' }
  s.source_files     = 'iroh_flutter/Sources/iroh_flutter/**/*'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  # On Apple platforms, iroh uses SystemConfiguration for reachability and DNS.
  # It uses Network for nw_path_monitor.
  s.frameworks = 'SystemConfiguration', 'Network'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '11.0'
  # With use_frameworks!, iroh_flutter builds as a dynamic framework. cargokit puts the static
  # library at $PODS_CONFIGURATION_BUILD_DIR/iroh_flutter/libirohdart_ffi.a. The -force_load flag
  # links the full archive INTO the framework. Thus, the linker does not remove the FFI symbols
  # as dead code, and DynamicLibrary.process() can find them at run time.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/iroh_flutter/libirohdart_ffi.a',
  }

  # Build the static library before compilation. `$1` is the crate directory, relative to the
  # directory of this podspec (darwin/ -> ../rust). `$2` is the library name.
  s.script_phase = {
    :name => 'Build Rust library (cargokit)',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust irohdart_ffi',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${BUILT_PRODUCTS_DIR}/libirohdart_ffi.a'],
  }
end
