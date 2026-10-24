// The public header of the iroh_flutter C target. A Swift package C target must have one public
// header directory. The Dart code does not use this header. It finds the FFI symbols of
// irohdart_ffi through DynamicLibrary.process().
#ifndef IROH_FLUTTER_H
#define IROH_FLUTTER_H

int iroh_flutter_plugin_placeholder(void);

#endif
