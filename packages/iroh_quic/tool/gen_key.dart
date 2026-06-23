// Generate a fresh Ed25519 signing keypair for the prebuilt binaries.
//
//   dart run tool/gen_key.dart
//
// Paste PUBLIC into lib/src/ffi/prebuilt.dart (kPrebuiltPublicKeyHex) and store PRIVATE as the
// `IROHDART_SIGNING_KEY` repository secret consumed by .github/workflows/release.yml. Rotating the
// key invalidates already-published signatures, so bump the package version when you rotate.

import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  final keyPair = await Ed25519().newKeyPair();
  final seed = await keyPair.extractPrivateKeyBytes(); // 32-byte Ed25519 seed
  final publicKey = await keyPair.extractPublicKey();
  stdout.writeln('PUBLIC  (kPrebuiltPublicKeyHex)       : ${_hex(publicKey.bytes)}');
  stdout.writeln('PRIVATE (IROHDART_SIGNING_KEY secret) : ${_hex(seed)}');
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
