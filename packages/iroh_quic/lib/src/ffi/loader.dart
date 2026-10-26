import 'dart:io' show File, Platform;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart' show ExternalLibrary;

import '../../src/rust/api/simple.dart' as ffi;
import '../../src/rust/frb_generated.dart' show RustLib;
import '../errors.dart';
import 'prebuilt.dart';

/// The ABI version of the Dart bindings. It MUST be equal to `IROHDART_ABI_VERSION` in
/// `rust/src/api/simple.rs`. A different value means that the native library and the Dart bindings
/// come from different versions. Then the loader refuses the native library. This prevents a crash
/// at a later time.
const int kIrohdartExpectedAbiVersion = 3;

/// Loads and initializes the native library one time.
///
/// A Rust toolchain is not necessary. Run `dart run iroh_quic:setup` one time to download the
/// prebuilt library into the cache. The loader then finds it automatically. As an alternative, run
/// `cargo build` in `rust/`, and the loader finds the output in `rust/target/`.
///
/// The loader uses the first native library that it finds, in this order:
///
/// 1. The `libraryPath` argument of [ensureInitialized], if you give one.
/// 2. A local `cargo build` output: `rust/target/{debug,release}/` or
///    `../rust/target/{debug,release}/`, relative to the current directory.
/// 3. The prebuilt library in the cache.
/// 4. A native library in the directory of the compiled executable.
/// 5. On iOS and macOS: the symbols of the process. The app links the Rust staticlib into its
///    binary.
/// 6. On other platforms: the platform file name, which the platform linker finds.
abstract final class IrohRuntime {
  static bool _initialised = false;

  /// Whether [ensureInitialized] has completed successfully.
  static bool get isInitialised => _initialised;

  /// Loads the native library, initializes FRB, and makes sure that the ABI version is correct.
  /// After the first successful call, a call has no effect. [libraryPath] is the path of the native
  /// library, or `null` to search for it. Throws [IrohLoadException] if FRB initialization fails,
  /// or if the ABI version of the native library is not [kIrohdartExpectedAbiVersion]. Throws
  /// [ArgumentError] if the operating system cannot open the native library file.
  static Future<void> ensureInitialized({String? libraryPath}) async {
    if (_initialised) return;

    final external = _resolveExternalLibrary(libraryPath);
    try {
      await RustLib.init(externalLibrary: external);
    } on Object catch (e) {
      final hint = libraryPath == null
          ? '. Run `dart run iroh_quic:setup` to download a prebuilt library, '
                'or build it with `cargo build --release` in rust/'
          : '';
      throw IrohLoadException(
        'failed to load the irohdart-ffi native library'
        '${libraryPath == null ? '' : ' from $libraryPath'}$hint',
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

  /// The ABI version of the loaded native library. Call [ensureInitialized] before you read it.
  static int get nativeAbiVersion => ffi.irohdartAbiVersion();

  /// The version of the `iroh` crate in the native library.
  static String get irohVersion => ffi.irohdartIrohVersion();

  static ExternalLibrary _resolveExternalLibrary(String? libraryPath) {
    if (libraryPath != null) return ExternalLibrary.open(libraryPath);
    // First, use a native library on disk. [_libSearchPaths] gives the search order.
    final found = _firstExisting(_libSearchPaths());
    if (found != null) return ExternalLibrary.open(found);
    // iOS and macOS apps link the Rust staticlib into the app binary. Thus the FFI symbols are in
    // the process (DynamicLibrary.process()), not in a separate file.
    if (Platform.isIOS || Platform.isMacOS) {
      return ExternalLibrary.process(iKnowHowToUseIt: true);
    }
    // Android and desktop apps: open the bundled native library by its file name. The platform
    // linker finds it in the library path of the app.
    return ExternalLibrary.open(_platformLibraryFileName());
  }

  /// The disk paths that the loader examines, in order, if `libraryPath` is `null`.
  static List<String> _libSearchPaths() {
    final stem = _platformLibraryFileName();
    final paths = <String>[
      // The current directory is the package root. For example, `dart test` runs there.
      'rust/target/debug/$stem',
      'rust/target/release/$stem',
      // The current directory is a subdirectory of the package root, for example `example/`.
      '../rust/target/debug/$stem',
      '../rust/target/release/$stem',
    ];
    // The prebuilt library that `dart run iroh_quic:setup` writes into the cache.
    final target = currentPrebuiltTarget();
    if (target != null) paths.add(prebuiltCacheLibPath(target));
    // A native library next to a compiled executable (`dart compile exe` output).
    paths.add('${File(Platform.resolvedExecutable).parent.path}/$stem');
    return paths;
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
