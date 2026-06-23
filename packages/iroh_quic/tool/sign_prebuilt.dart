// Sign prebuilt native libraries with the Ed25519 signing key, emitting a detached `<file>.sig`
// (raw 64-byte signature) next to each input. Used by .github/workflows/release.yml.
//
//   IROHDART_SIGNING_KEY=<hex key> dart run tool/sign_prebuilt.dart <file>...
//
// IROHDART_SIGNING_KEY accepts either a 32-byte Ed25519 seed (64 hex) or a 64-byte key in the
// cargokit / ed25519_edwards `seed||public` form (128 hex) — the latter lets us reuse the original
// cargokit signing key verbatim; only the first 32 bytes (the seed) are used. The matching public
// key is kPrebuiltPublicKeyHex in lib/src/ffi/prebuilt.dart; the installer (bin/setup.dart) verifies
// downloads against it. Generate a fresh pair with tool/gen_key.dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final hexKey = Platform.environment['IROHDART_SIGNING_KEY'];
  if (hexKey == null || hexKey.isEmpty) {
    stderr.writeln('sign_prebuilt: IROHDART_SIGNING_KEY (hex Ed25519 seed or cargokit key) is not set.');
    exitCode = 1;
    return;
  }
  if (args.isEmpty) {
    stderr.writeln('sign_prebuilt: usage: dart run tool/sign_prebuilt.dart <file>...');
    exitCode = 1;
    return;
  }

  final seed = _seedFromHex(hexKey.trim());
  if (seed == null) {
    stderr.writeln('sign_prebuilt: IROHDART_SIGNING_KEY must be 64 hex (32-byte seed) or 128 hex '
        '(64-byte cargokit seed||public) chars.');
    exitCode = 1;
    return;
  }

  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPairFromSeed(seed);
  for (final path in args) {
    final bytes = await File(path).readAsBytes();
    final signature = await algorithm.sign(bytes, keyPair: keyPair);
    final sigPath = '$path.sig';
    await File(sigPath).writeAsBytes(signature.bytes, flush: true);
    stdout.writeln('signed $path -> $sigPath (${signature.bytes.length} bytes)');
  }
}

/// The 32-byte Ed25519 seed from a 64-hex seed or a 128-hex cargokit `seed||public` key (first 32
/// bytes). Returns null on any other length.
Uint8List? _seedFromHex(String hex) {
  if (hex.length != 64 && hex.length != 128) return null;
  return _hexToBytes(hex.substring(0, 64));
}

Uint8List _hexToBytes(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
