#
# iroh_flutter macOS plugin. cargokit builds the owned `irohdart-ffi` staticlib (repo-root
# rust) as a universal (arm64 + x86_64) library. macOS 11+. Developer-ID sign +
# notarize happens in CI.
#
Pod::Spec.new do |s|
  s.name             = 'iroh_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Dart/Flutter binding for iroh 1.0 (P2P QUIC) over the shared Rust core.'
  s.description      = 'Wraps the iroh 1.0 Rust core via flutter_rust_bridge.'
  s.homepage         = 'https://github.com/snowpinelabs/iroh_dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Leonardo Custodio' => 'leonardo@custodio.me' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  # iroh uses SystemConfiguration (reachability/DNS) and Network (nw_path_monitor) on Apple.
  s.frameworks = 'SystemConfiguration', 'Network'
  s.platform = :osx, '11.0'
  # Force-load the Rust staticlib into the framework so its FFI symbols survive dead-stripping and
  # are visible to DynamicLibrary.process() (see ios/iroh_flutter.podspec for the full rationale).
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/iroh_flutter/libirohdart_ffi.a',
  }

  s.script_phase = {
    :name => 'Build Rust library (cargokit)',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust irohdart_ffi',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${BUILT_PRODUCTS_DIR}/libirohdart_ffi.a'],
  }
end
