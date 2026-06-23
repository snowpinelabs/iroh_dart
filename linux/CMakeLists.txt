# Linux build for the iroh_dart FFI plugin. cargokit cross/native-builds the owned
# `irohdart-ffi` cdylib (rust, via cargo-zigbuild in CI) and bundles
# libirohdart_ffi.so with the app.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "iroh_dart")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "iroh_dart_plugin")

# Pull in cargokit's helper. `apply_cargokit(target manifest_dir lib_name any_symbol_name)`.
# manifest_dir is relative to this file (linux/ -> rust).
include(${CMAKE_CURRENT_SOURCE_DIR}/../cargokit/cmake/cargokit.cmake)
apply_cargokit(${PLUGIN_NAME} ../rust irohdart_ffi "")

# Bundle the built shared library next to the app, and expose it to the Flutter tool.
set(iroh_dart_bundled_libraries
  "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/libirohdart_ffi.so"
  PARENT_SCOPE
)
