// This file gives the CocoaPod and the Swift package a compile target, so it must not be empty.
// This file does not refer to the native library.
//
// CocoaPods: the FFI symbols are in libirohdart_ffi.a, which cargokit builds. The app links this
// static library, and the Dart loader finds the symbols through DynamicLibrary.process().
// The -force_load flag in the podspec makes sure that the linker keeps the symbols.
//
// Swift Package Manager: the FFI symbols are in the dynamic framework irohdart_ffi.framework.
// The app embeds this framework and loads it at launch. The Dart loader then finds the symbols
// through DynamicLibrary.process().
__attribute__((visibility("default"))) __attribute__((used))
int iroh_flutter_plugin_placeholder(void) { return 0; }
