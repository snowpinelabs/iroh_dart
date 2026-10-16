# Linux build for the iroh_flutter FFI plugin. cargokit builds the crate `irohdart_ffi` (in
# ../rust) as a shared library. The app bundle includes libirohdart_ffi.so.
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "iroh_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

set(PLUGIN_NAME "iroh_flutter_plugin")

# Include the cargokit helper: `apply_cargokit(target manifest_dir lib_name any_symbol_name)`.
# manifest_dir is relative to this file (linux/ -> ../rust).
include(${CMAKE_CURRENT_SOURCE_DIR}/../cargokit/cmake/cargokit.cmake)
apply_cargokit(${PLUGIN_NAME} ../rust irohdart_ffi "")

# Put the shared library next to the app, and give its path to the Flutter tool.
# For FFI plugins, apply_cargokit makes only a custom "<name>_cargokit" target, not a real target.
# Thus, $<TARGET_FILE_DIR:...> fails at generate time with `No target "iroh_flutter_plugin"`.
# Use the <name>_cargokit_lib variable instead. It contains the output path.
set(iroh_flutter_bundled_libraries
  "${${PLUGIN_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
