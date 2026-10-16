# Windows build for the iroh_flutter FFI plugin. cargokit builds the crate `irohdart_ffi` (in
# ../rust) as a shared library for x86_64-pc-windows-msvc or aarch64-pc-windows-msvc.
# The app bundle includes irohdart_ffi.dll.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "iroh_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "iroh_flutter_plugin")

include(${CMAKE_CURRENT_SOURCE_DIR}/../cargokit/cmake/cargokit.cmake)
apply_cargokit(${PLUGIN_NAME} ../rust irohdart_ffi "")

# Put the DLL in the app bundle. For FFI plugins, apply_cargokit makes only a custom
# "<name>_cargokit" target, not a real target. Thus, $<TARGET_FILE_DIR:...> fails at generate
# time with `No target "iroh_flutter_plugin"`. Use the <name>_cargokit_lib variable instead.
# It contains the output path.
set(iroh_flutter_bundled_libraries
  "${${PLUGIN_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
