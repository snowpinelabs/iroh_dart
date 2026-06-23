import 'dart:io' show File, Platform;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show ExternalLibrary;

import '../../src/rust/api/simple.dart' as ffi;
import '../../src/rust/frb_generated.dart' show RustLib;
import '../errors.dart';

/// The ABI revision this Dart package was generated against. MUST equal
/// `IROHDART_ABI_VERSION` in `rust/src/api/simple.rs`. A mismatch means a stale
/// prebuilt native library is loaded against newer Dart bindings (or vice-versa) - we refuse to
/// run rather than crash later (ABI-handshake convention).
const int kIrohdartExpectedAbiVersion = 1;

/// Loads and initialises the `irohdart-ffi` native library exactly once.
///
/// Pure Dart: build the cdylib with `cargo build` and the [_desktopDevSearchPaths]
/// disk-path fallback finds `rust/target/{debug,release}/libirohdart_ffi.so`. Pass an
/// explicit [libraryPath] for a custom location; on iOS/macOS the staticlib is
/// linked into the host binary and resolved via the process symbol table.
abstract final class IrohRuntime {
  static bool _initialised = false;

  /// Whether [ensureInitialized] has completed successfully.
  static bool get isInitialised => _initialised;

  /// Initialise the native runtime and verify the ABI handshake. Idempotent: safe to call
  /// before every public entrypoint. Throws [IrohLoadException] if the library cannot be loaded
  /// or its ABI version does not match [kIrohdartExpectedAbiVersion].
  static Future<void> ensureInitialized({String? libraryPath}) async {
    if (_initialised) return;

    final external = _resolveExternalLibrary(libraryPath);
    try {
      await RustLib.init(externalLibrary: external);
    } on Object catch (e) {
      throw IrohLoadException(
        'failed to load the irohdart-ffi native library'
        '${libraryPath == null ? '' : ' from $libraryPath'}',
        cause: e,
      );
    }

    final abi = ffi.irohdartAbiVersion();
    if (abi != kIrohdartExpectedAbiVersion) {
      throw IrohLoadException(
        'ABI mismatch: Dart bindings expect v$kIrohdartExpectedAbiVersion '
        'but the native library reports v$abi - rebuild the native library '
        'or regenerate the bindings (tool/frb_codegen.sh).',
      );
    }
    _initialised = true;
  }

  /// The ABI version reported by the loaded native library (after [ensureInitialized]).
  static int get nativeAbiVersion => ffi.irohdartAbiVersion();

  /// The `iroh` crate version this binding was built against.
  static String get irohVersion => ffi.irohdartIrohVersion();

  static ExternalLibrary _resolveExternalLibrary(String? libraryPath) {
    if (libraryPath != null) return ExternalLibrary.open(libraryPath);
    // Desktop dev / host tests: prefer a disk-built dylib if one is present.
    final found = _firstExisting(_desktopDevSearchPaths());
    if (found != null) return ExternalLibrary.open(found);
    // iOS & macOS apps: the Rust staticlib is linked into the app binary, so the FFI symbols live
    // in the running process (DynamicLibrary.process()), not a separate file.
    if (Platform.isIOS || Platform.isMacOS) {
      return ExternalLibrary.process(iKnowHowToUseIt: true);
    }
    // Android & desktop release: load the bundled shared library by name (the platform linker
    // resolves it from the app's library path).
    return ExternalLibrary.open(_platformLibraryFileName());
  }

  /// Disk-path fallback for desktop dev / host tests.
  static List<String> _desktopDevSearchPaths() {
    final stem = _platformLibraryFileName();
    return <String>[
      // cwd = package/repo root (e.g. during `flutter test`):
      'rust/target/debug/$stem',
      'rust/target/release/$stem',
      // cwd = example app dir (e.g. integration tests run from example/):
      '../rust/target/debug/$stem',
      '../rust/target/release/$stem',
    ];
  }

  static String _platformLibraryFileName() {
    if (Platform.isMacOS || Platform.isIOS) return 'libirohdart_ffi.dylib';
    if (Platform.isWindows) return 'irohdart_ffi.dll';
    return 'libirohdart_ffi.so';
  }

  static String? _firstExisting(List<String> paths) {
    for (final p in paths) {
      if (File(p).existsSync()) return File(p).absolute.path;
    }
    return null;
  }
}
