// Tests for the prebuilt-binary distribution path: target mapping, the Ed25519 sign->verify
// round-trip used by bin/setup.dart + tool/sign_prebuilt.dart, and the loader resolving a library
// installed only in the per-user cache (IROHDART_CACHE_DIR), with no rust/target fallback in reach.

import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:iroh_quic/src/ffi/prebuilt.dart';
import 'package:test/test.dart';

void main() {
  group('prebuilt target mapping', () {
    test('current host has a prebuilt target with a triple-tagged asset name', () {
      final target = currentPrebuiltTarget();
      // CI + dev run on desktop x64/arm64, all of which have prebuilts.
      expect(target, isNotNull, reason: 'no prebuilt mapping for ${Abi.current()}');
      expect(target!.assetName, startsWith('irohdart_ffi-${target.triple}.'));
      expect(target.signatureAssetName, '${target.assetName}.sig');
      expect(target.assetUrl.toString(), endsWith('/${target.assetName}'));
    });

    test('cache path is rooted under the version + triple and honors IROHDART_CACHE_DIR', () {
      final target = currentPrebuiltTarget()!;
      final path = prebuiltCacheLibPath(target);
      expect(path, contains('iroh_quic/v$kIrohdartLibVersion/${target.triple}'));
      expect(path, endsWith(target.libFileName));
    });

    test('asset extension matches the platform library file', () {
      final target = currentPrebuiltTarget()!;
      final ext = target.libFileName.substring(target.libFileName.lastIndexOf('.'));
      expect(target.assetName, endsWith(ext));
    });
  });

  group('Ed25519 sign -> verify (matches setup.dart / sign_prebuilt.dart)', () {
    test('a signature over the payload verifies, and a tampered payload is rejected', () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();
      final publicKey = await keyPair.extractPublicKey();

      final payload = Uint8List.fromList(List<int>.generate(4096, (i) => i & 0xff));
      final signature = await algorithm.sign(payload, keyPair: keyPair);

      final good = await algorithm.verify(
        payload,
        signature: Signature(signature.bytes, publicKey: publicKey),
      );
      expect(good, isTrue);

      final tampered = Uint8List.fromList(payload)..[0] ^= 0xff;
      final bad = await algorithm.verify(
        tampered,
        signature: Signature(signature.bytes, publicKey: publicKey),
      );
      expect(bad, isFalse);
    });
  });

  group('loader resolves a library installed only in the cache', () {
    test('Iroh.init() loads from IROHDART_CACHE_DIR with no rust/target in reach', () async {
      final target = currentPrebuiltTarget()!;
      // The host library built by tool/check.sh (`cargo build` => debug). Prefer debug (the gate's
      // fresh artifact); fall back to release. Skip if neither is present.
      File? built;
      for (final f in [
        File('rust/target/debug/${target.libFileName}'),
        File('rust/target/release/${target.libFileName}'),
      ]) {
        if (f.existsSync()) {
          built = f;
          break;
        }
      }
      if (built == null) {
        markTestSkipped('no built ${target.libFileName} under rust/target/{debug,release}');
        return;
      }

      final tmp = Directory.systemTemp.createTempSync('iroh_cache_test_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      // Lay the library out exactly where setup.dart would, under a fake cache root.
      final cacheRoot = '${tmp.path}/cache';
      final installDir = Directory('$cacheRoot/iroh_quic/v$kIrohdartLibVersion/${target.triple}');
      installDir.createSync(recursive: true);
      built.copySync('${installDir.path}/${target.libFileName}');

      // Run from a cwd with no rust/ tree, so only the cache path can satisfy the loader.
      // In a pub workspace the package_config lives at the workspace root, so walk up to find it.
      final pkgConfig = _findPackageConfig();
      final probe = File('${tmp.path}/probe.dart')
        ..writeAsStringSync('''
import 'package:iroh_quic/iroh_quic.dart';
Future<void> main() async {
  await Iroh.init();
  print('LOADED \${Iroh.irohVersion}');
}
''');

      final result = await Process.run(
        Platform.resolvedExecutable,
        ['--packages=$pkgConfig', probe.path],
        workingDirectory: tmp.path,
        environment: {'IROHDART_CACHE_DIR': cacheRoot},
      );

      expect(result.exitCode, 0, reason: 'probe failed:\n${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('LOADED'));
    });
  });
}

/// Find `.dart_tool/package_config.json` by walking up from the current directory — it sits in the
/// package dir for a standalone package and at the root for a pub-workspace member.
String _findPackageConfig() {
  var dir = Directory.current;
  while (true) {
    final candidate = File('${dir.path}/.dart_tool/package_config.json');
    if (candidate.existsSync()) return candidate.absolute.path;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('no .dart_tool/package_config.json found from ${Directory.current.path}');
    }
    dir = parent;
  }
}
