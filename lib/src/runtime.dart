import 'capabilities.dart';
import 'ffi/loader.dart';

/// Top-level entrypoint for the iroh_dart binding.
///
/// Call [Iroh.init] once at startup (it is idempotent) before using any other API. This loads
/// the native `irohdart-ffi` library, verifies the ABI handshake, and prepares the embedded
/// tokio runtime that drives iroh's async surface.
abstract final class Iroh {
  /// Loads and initialises the native runtime, verifying the ABI version. Idempotent.
  ///
  /// [libraryPath] overrides library resolution (host tests / non-standard layouts); in a real
  /// Flutter app it is unnecessary - the bundled library is found automatically.
  static Future<void> init({String? libraryPath}) =>
      IrohRuntime.ensureInitialized(libraryPath: libraryPath);

  /// Whether [init] has completed.
  static bool get isInitialised => IrohRuntime.isInitialised;

  /// The iroh features available on this platform.
  static IrohCapabilities get capabilities => IrohCapabilities.current();

  /// The ABI version reported by the loaded native library.
  static int get abiVersion => IrohRuntime.nativeAbiVersion;

  /// The `iroh` crate version this binding was built against.
  static String get irohVersion => IrohRuntime.irohVersion;
}
