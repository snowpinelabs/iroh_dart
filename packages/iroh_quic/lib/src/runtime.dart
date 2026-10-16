import 'capabilities.dart';
import 'ffi/loader.dart';

/// The main entry point of the iroh_quic binding.
///
/// Call [Iroh.init] at startup, before you use a different API. You can call it more than one
/// time. It loads the native library and makes sure that its ABI version is correct. The crate
/// starts its tokio runtime when the first async operation needs it.
abstract final class Iroh {
  /// Loads the native library, initializes FRB, and makes sure that the ABI version is correct.
  /// A second call has no effect.
  ///
  /// [libraryPath] is the path of the native library. If it is `null`, the loader finds the native
  /// library itself. See [IrohRuntime] for the search order.
  /// Throws [IrohLoadException] if FRB initialization fails, or if the native library has a
  /// different ABI version. Throws [ArgumentError] if the operating system cannot open the native
  /// library file.
  static Future<void> init({String? libraryPath}) =>
      IrohRuntime.ensureInitialized(libraryPath: libraryPath);

  /// Whether [init] completed successfully.
  static bool get isInitialised => IrohRuntime.isInitialised;

  /// The iroh features available on this platform.
  static IrohCapabilities get capabilities => IrohCapabilities.current();

  /// The ABI version reported by the loaded native library.
  static int get abiVersion => IrohRuntime.nativeAbiVersion;

  /// The `iroh` crate version this binding was built against.
  static String get irohVersion => IrohRuntime.irohVersion;
}
