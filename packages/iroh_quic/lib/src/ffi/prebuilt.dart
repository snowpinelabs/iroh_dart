// Data about the prebuilt library. The loader (lib/src/ffi/loader.dart) and the installer
// (bin/setup.dart) use it. `dart run iroh_quic:setup` downloads the prebuilt library for the
// current platform from the GitHub Release. It writes the file to [prebuiltCacheLibPath]. The
// loader then finds the file there, and the user does not need a Rust toolchain.

import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

/// The version of the prebuilt library that this Dart package expects.
///
/// It MUST be equal to `version:` in pubspec.yaml. The installer downloads the signed assets from
/// the `v$kIrohdartLibVersion` GitHub Release. The cache path contains this version. Thus a new
/// package version downloads a new prebuilt library, and does not load an old one.
const String kIrohdartLibVersion = '1.1.1';

/// The base URL of the GitHub Release that holds the prebuilt libraries.
const String kPrebuiltUrlPrefix =
    'https://github.com/snowpinelabs/iroh_dart/releases/download/v$kIrohdartLibVersion/';

/// The Ed25519 public key (hex) of the key pair that signs the prebuilt libraries in CI.
///
/// The installer verifies the signature of each downloaded prebuilt library with this key before it
/// installs the file. The `IROHDART_SIGNING_KEY` repository secret holds the private key. The
/// secret can be a 128-hex cargokit `seed||public` key or a 64-hex 32-byte seed.
///
/// To replace the key pair:
///
/// 1. Run `dart run tool/gen_key.dart`.
/// 2. Put the new public key hex here.
/// 3. Set the new private key hex as the repository secret.
/// 4. Increase the package version.
const String kPrebuiltPublicKeyHex =
    '74b7c73d253932835af9e3f63c99135e85aaff6a8ab2a7b0de0558a453246743';

/// A native target that has a prebuilt library.
class PrebuiltTarget {
  const PrebuiltTarget(this.triple, this.libFileName);

  /// The Rust target triple, for example `aarch64-apple-darwin`.
  final String triple;

  /// The platform file name of the native library that the loader opens, for example
  /// `libirohdart_ffi.dylib`.
  final String libFileName;

  /// The name of the release asset that contains the prebuilt library, for example
  /// `irohdart_ffi-aarch64-apple-darwin.dylib`. Each operating system has two architectures with
  /// the same file extension. The triple in the name makes each asset name unique.
  String get assetName {
    final ext = libFileName.substring(libFileName.lastIndexOf('.'));
    return 'irohdart_ffi-$triple$ext';
  }

  /// The name of the asset that contains the detached Ed25519 signature (`<assetName>.sig`).
  String get signatureAssetName => '$assetName.sig';

  /// The absolute URL of the prebuilt library asset on the GitHub Release.
  Uri get assetUrl => Uri.parse('$kPrebuiltUrlPrefix$assetName');

  /// The absolute URL of the detached signature asset.
  Uri get signatureUrl => Uri.parse('$kPrebuiltUrlPrefix$signatureAssetName');
}

/// Returns the prebuilt target of the current process. Returns `null` if no prebuilt library
/// exists for this platform and architecture. iOS and Android have no prebuilt library, because
/// apps on these platforms contain the native library. An unknown desktop architecture also gives
/// `null`.
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

/// Returns the absolute path of the prebuilt library for [target] in the cache.
/// `dart run iroh_quic:setup` writes the file to this path, and the loader reads it from there.
/// Set `IROHDART_CACHE_DIR` to change the root directory of the cache.
String prebuiltCacheLibPath(PrebuiltTarget target) =>
    _join([prebuiltCacheDir(target), target.libFileName]);

/// Returns the cache directory that holds the prebuilt library for [target]. It is the parent
/// directory of [prebuiltCacheLibPath].
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

// dart:io accepts forward slashes on all supported platforms. Thus a '/' join is sufficient, and
// this file does not need package:path.
String _join(List<String> parts) => parts.join('/');
