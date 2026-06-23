#
# iroh_flutter iOS plugin. cargokit builds the owned `irohdart-ffi` staticlib (repo-root
# rust) for device + simulator and links it into the app. `fast-apple-datapath`
# is OFF in the crate's features (private API -> App Store risk). iOS 13+.
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
  s.dependency 'Flutter'
  # iroh uses SystemConfiguration (reachability/DNS) and Network (nw_path_monitor) on Apple.
  s.frameworks = 'SystemConfiguration', 'Network'
  s.platform = :ios, '13.0'
  # With use_frameworks!, iroh_flutter builds as a dynamic framework. cargokit puts the Rust staticlib
  # at $PODS_CONFIGURATION_BUILD_DIR/iroh_flutter/libirohdart_ffi.a; -force_load links its whole archive
  # INTO the framework so the FFI symbols survive dead-stripping and are visible to
  # DynamicLibrary.process() at runtime.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${PODS_CONFIGURATION_BUILD_DIR}/iroh_flutter/libirohdart_ffi.a',
  }

  # Build the Rust staticlib before compiling. `$1` is the manifest dir relative to this
  # podspec's directory (ios/ -> rust). `$2` is the cdylib/staticlib name.
  s.script_phase = {
    :name => 'Build Rust library (cargokit)',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust irohdart_ffi',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${BUILT_PRODUCTS_DIR}/libirohdart_ffi.a'],
  }
end
