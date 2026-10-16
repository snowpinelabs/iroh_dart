// This file gives the CocoaPod a compile target, so it must not be empty.
// The FFI symbols are in libirohdart_ffi.a, which cargokit builds.
// The Dart loader finds the symbols through DynamicLibrary.process().
__attribute__((visibility("default"))) __attribute__((used))
int iroh_flutter_plugin_placeholder(void) { return 0; }
