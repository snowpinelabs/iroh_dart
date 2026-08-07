// Prebuilt-binary distribution metadata shared by the loader (lib/src/ffi/loader.dart) and the
// installer (bin/setup.dart). `dart run iroh_quic:setup` downloads the signed native library for
// the current platform from the GitHub Release and writes it to [prebuiltCacheLibPath]; the loader
// then finds it there without the consumer needing a Rust toolchain.

import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

/// Version of the prebuilt native library this Dart package expects.
///
/// MUST match `version:` in pubspec.yaml: the installer downloads the signed assets from the
/// `v$kIrohdartLibVersion` GitHub Release, and the cache is keyed by this version so upgrades
/// re-download rather than load a stale library.
const String kIrohdartLibVersion = '1.0.3';

/// Base URL of the GitHub Release that hosts the signed prebuilt libraries.
const String kPrebuiltUrlPrefix =
    'https://github.com/snowpinelabs/iroh_dart/releases/download/v$kIrohdartLibVersion/';

/// Ed25519 public key (hex) whose private half signs the prebuilt binaries in CI.
///
/// The installer verifies each downloaded library against this key before installing it. This is the
/// project's existing signing key (originally generated for cargokit); the `IROHDART_SIGNING_KEY`
/// repository secret holds its private half (the 128-hex `seed||public` cargokit key works verbatim,
/// or a 64-hex 32-byte seed). To rotate: `dart run tool/gen_key.dart`, paste the new public hex here,
/// set the new private hex as the secret, and bump the package version.
const String kPrebuiltPublicKeyHex =
    '74b7c73d253932835af9e3f63c99135e85aaff6a8ab2a7b0de0558a453246743';

/// A native target iroh_quic publishes a prebuilt library for.
class PrebuiltTarget {
  const PrebuiltTarget(this.triple, this.libFileName);

  /// Rust target triple, e.g. `aarch64-apple-darwin`.
  final String triple;

  /// Platform library file name the loader opens, e.g. `libirohdart_ffi.dylib`.
  final String libFileName;

  /// Release asset name carrying the library, e.g. `irohdart_ffi-aarch64-apple-darwin.dylib`.
  /// The triple keeps it unique across the two same-extension Apple/Windows arches.
  String get assetName {
    final ext = libFileName.substring(libFileName.lastIndexOf('.'));
    return 'irohdart_ffi-$triple$ext';
  }

  /// Detached Ed25519 signature asset name (`<assetName>.sig`).
  String get signatureAssetName => '$assetName.sig';

  /// Absolute URL of the library asset on the GitHub Release.
  Uri get assetUrl => Uri.parse('$kPrebuiltUrlPrefix$assetName');

  /// Absolute URL of the detached signature asset.
  Uri get signatureUrl => Uri.parse('$kPrebuiltUrlPrefix$signatureAssetName');
}

/// The prebuilt target for the current process, or `null` when this platform/arch has no prebuilt
/// (e.g. iOS/Android — those are app-embedded, not `dart run` targets, and an unknown desktop arch).
PrebuiltTarget? currentPrebuiltTarget() {
  switch (Abi.current()) {
    case Abi.macosArm64:
      return const PrebuiltTarget('aarch64-apple-darwin', 'libirohdart_ffi.dylib');
    case Abi.macosX64:
      return const PrebuiltTarget('x86_64-apple-darwin', 'libirohdart_ffi.dylib');
    case Abi.linuxX64:
      return const PrebuiltTarget('x86_64-unknown-linux-gnu', 'libirohdart_ffi.so');
    case Abi.linuxArm64:
      return const PrebuiltTarget('aarch64-unknown-linux-gnu', 'libirohdart_ffi.so');
    case Abi.windowsX64:
      return const PrebuiltTarget('x86_64-pc-windows-msvc', 'irohdart_ffi.dll');
    case Abi.windowsArm64:
      return const PrebuiltTarget('aarch64-pc-windows-msvc', 'irohdart_ffi.dll');
    default:
      return null;
  }
}

/// Absolute path where `dart run iroh_quic:setup` installs the prebuilt library for [target] and
/// where the loader looks for it. Override the root directory with `IROHDART_CACHE_DIR`.
String prebuiltCacheLibPath(PrebuiltTarget target) =>
    _join([prebuiltCacheDir(target), target.libFileName]);

/// Directory holding the installed library for [target] (the parent of [prebuiltCacheLibPath]).
String prebuiltCacheDir(PrebuiltTarget target) =>
    _join([_cacheRoot(), 'iroh_quic', 'v$kIrohdartLibVersion', target.triple]);

String _cacheRoot() {
  final env = Platform.environment;
  final override = env['IROHDART_CACHE_DIR'];
  if (override != null && override.isNotEmpty) return override;
  if (Platform.isWindows) {
    final local = env['LOCALAPPDATA'];
    if (local != null && local.isNotEmpty) return local;
    return _join([env['USERPROFILE'] ?? '.', 'AppData', 'Local']);
  }
  final home = env['HOME'] ?? '.';
  if (Platform.isMacOS) return _join([home, 'Library', 'Caches']);
  final xdg = env['XDG_CACHE_HOME'];
  if (xdg != null && xdg.isNotEmpty) return xdg;
  return _join([home, '.cache']);
}

// dart:io accepts forward slashes on every supported platform, so a plain '/' join avoids a
// dependency on package:path for the handful of paths we build.
String _join(List<String> parts) => parts.join('/');
