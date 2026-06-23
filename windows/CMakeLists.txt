# Windows build for the iroh_dart FFI plugin. cargokit builds the owned `irohdart-ffi` cdylib
# (rust, x86_64/aarch64-pc-windows-msvc) and bundles irohdart_ffi.dll.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "iroh_dart")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "iroh_dart_plugin")

include(${CMAKE_CURRENT_SOURCE_DIR}/../cargokit/cmake/cargokit.cmake)
apply_cargokit(${PLUGIN_NAME} ../rust irohdart_ffi "")

set(iroh_dart_bundled_libraries
  "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/irohdart_ffi.dll"
  PARENT_SCOPE
)
