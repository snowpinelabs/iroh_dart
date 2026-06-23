# Windows build for the iroh_flutter FFI plugin. cargokit builds the owned `irohdart-ffi` cdylib
# (rust, x86_64/aarch64-pc-windows-msvc) and bundles irohdart_ffi.dll.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "iroh_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "iroh_flutter_plugin")

include(${CMAKE_CURRENT_SOURCE_DIR}/../cargokit/cmake/cargokit.cmake)
apply_cargokit(${PLUGIN_NAME} ../rust irohdart_ffi "")

set(iroh_flutter_bundled_libraries
  "$<TARGET_FILE_DIR:${PLUGIN_NAME}>/irohdart_ffi.dll"
  PARENT_SCOPE
)
