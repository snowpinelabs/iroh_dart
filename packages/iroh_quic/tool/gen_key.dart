// Makes a new Ed25519 key pair to sign the prebuilt libraries.
//
//   dart run tool/gen_key.dart
//
// Put PUBLIC into lib/src/ffi/prebuilt.dart (kPrebuiltPublicKeyHex). Keep PRIVATE as the
// `IROHDART_SIGNING_KEY` repository secret, which .github/workflows/publish.yml reads. A new key
// pair makes the published signatures not valid. Thus, increase the package version when you
// replace the key pair.

import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  final keyPair = await Ed25519().newKeyPair();
  final seed = await keyPair.extractPrivateKeyBytes(); // The 32-byte Ed25519 seed.
  final publicKey = await keyPair.extractPublicKey();
  stdout.writeln('PUBLIC  (kPrebuiltPublicKeyHex)       : ${_hex(publicKey.bytes)}');
  stdout.writeln('PRIVATE (IROHDART_SIGNING_KEY secret) : ${_hex(seed)}');
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
