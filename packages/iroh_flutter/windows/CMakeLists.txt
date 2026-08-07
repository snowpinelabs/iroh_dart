# Windows build for the iroh_flutter FFI plugin. cargokit builds the owned `irohdart-ffi` cdylib
# (rust, x86_64/aarch64-pc-windows-msvc) and bundles irohdart_ffi.dll.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "iroh_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "iroh_flutter_plugin")

include(${CMAKE_CURRENT_SOURCE_DIR}/../cargokit/cmake/cargokit.cmake)
apply_cargokit(${PLUGIN_NAME} ../rust irohdart_ffi "")

# Bundle the built DLL with the app. apply_cargokit doesn't create a real CMake target for FFI
# plugins (only a custom "<name>_cargokit" driver target), so $<TARGET_FILE_DIR:...> would fail at
# generate time with `No target "iroh_flutter_plugin"` (issue #16); it exposes the output path in
# the <name>_cargokit_lib variable instead.
set(iroh_flutter_bundled_libraries
  "${${PLUGIN_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
