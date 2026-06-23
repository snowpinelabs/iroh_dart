// Non-empty translation unit so the CocoaPod has a compile target. Real FFI symbols live in the
// cargokit-built libirohdart_ffi.a, resolved by the Dart loader via DynamicLibrary.process().
__attribute__((visibility("default"))) __attribute__((used))
int iroh_dart_plugin_placeholder(void) { return 0; }
