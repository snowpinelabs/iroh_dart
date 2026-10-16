// This file gives the CocoaPod a compile target, so it must not be empty.
// The FFI symbols are in libirohdart_ffi.a, which cargokit builds. The app links this static
// library, and the Dart loader finds the symbols through DynamicLibrary.process().
// The -force_load flag in the podspec makes sure that the linker keeps the symbols.
// This file does not refer to the native library.
__attribute__((visibility("default"))) __attribute__((used))
int iroh_flutter_plugin_placeholder(void) { return 0; }
