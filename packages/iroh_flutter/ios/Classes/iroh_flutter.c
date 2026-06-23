// Non-empty translation unit so the CocoaPod has a compile target. The actual FFI symbols live in
// the cargokit-built libirohdart_ffi.a and are resolved by the Dart loader via
// DynamicLibrary.process() (static link). Symbol retention on iOS is handled by cargokit's link
// configuration; this file intentionally references nothing from the Rust library.
__attribute__((visibility("default"))) __attribute__((used))
int iroh_flutter_plugin_placeholder(void) { return 0; }
