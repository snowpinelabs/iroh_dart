#
# macOS part of the iroh_flutter plugin. cargokit builds the crate `irohdart_ffi` (in ../rust) as
# a universal static library (arm64 and x86_64). The minimum version is macOS 11.
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
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  # On Apple platforms, iroh uses SystemConfiguration for reachability and DNS.
  # It uses Network for nw_path_monitor.
  s.frameworks = 'SystemConfiguration', 'Network'
  s.platform = :osx, '11.0'
  # The -force_load flag links the full static library into the framework. Thus, the linker does
  # not remove the FFI symbols, and DynamicLibrary.process() can find them.
  # ios/iroh_flutter.podspec gives the full reason.
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
