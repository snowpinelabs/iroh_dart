// Signs prebuilt libraries with the Ed25519 private key. For each input file, it writes a
// detached `<file>.sig` (raw 64-byte signature) next to the file.
// .github/workflows/publish.yml runs this tool.
//
//   IROHDART_SIGNING_KEY=<hex key> dart run tool/sign_prebuilt.dart <file>...
//
// IROHDART_SIGNING_KEY can be a 32-byte Ed25519 seed (64 hex). It can also be a 64-byte key in the
// cargokit / ed25519_edwards `seed||public` form (128 hex). Then the tool uses only the first 32
// bytes (the seed). The public key of the pair is kPrebuiltPublicKeyHex in
// lib/src/ffi/prebuilt.dart. The installer (bin/setup.dart) verifies downloads with it. To make a
// new key pair, run tool/gen_key.dart.

import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final hexKey = Platform.environment['IROHDART_SIGNING_KEY'];
  if (hexKey == null || hexKey.isEmpty) {
    stderr.writeln(
      'sign_prebuilt: IROHDART_SIGNING_KEY (hex Ed25519 seed or cargokit key) is not set.',
    );
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
    stderr.writeln(
      'sign_prebuilt: IROHDART_SIGNING_KEY must be 64 hex (32-byte seed) or 128 hex '
      '(64-byte cargokit seed||public) chars.',
    );
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

/// Returns the 32-byte Ed25519 seed from a 64-hex seed or a 128-hex cargokit `seed||public` key.
/// For the cargokit key, the seed is the first 32 bytes. Returns null for a different length.
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
