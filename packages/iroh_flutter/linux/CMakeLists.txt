# Linux build for the iroh_flutter FFI plugin. cargokit cross/native-builds the owned
# `irohdart-ffi` cdylib (rust, via cargo-zigbuild in CI) and bundles
# libirohdart_ffi.so with the app.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "iroh_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "iroh_flutter_plugin")

# Pull in cargokit's helper. `apply_cargokit(target manifest_dir lib_name any_symbol_name)`.
# manifest_dir is relative to this file (linux/ -> rust).
include(${CMAKE_CURRENT_SOURCE_DIR}/../cargokit/cmake/cargokit.cmake)
apply_cargokit(${PLUGIN_NAME} ../rust irohdart_ffi "")

# Bundle the built shared library next to the app, and expose it to the Flutter tool.
# apply_cargokit doesn't create a real CMake target for FFI plugins (only a custom
# "<name>_cargokit" driver target), so $<TARGET_FILE_DIR:...> would fail at generate time with
# `No target "iroh_flutter_plugin"` (issue #16); it exposes the output path in the
# <name>_cargokit_lib variable instead.
set(iroh_flutter_bundled_libraries
  "${${PLUGIN_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
