@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:iroh_quic/iroh_quic.dart';
import 'package:test/test.dart';

/// Identity and addressing. Ported from iroh-base's `#[cfg(test)]` vectors (key.rs /
/// endpoint_addr.rs). Because each call dispatches into the real iroh-base crate through FFI,
/// these are inherently differential against the Rust implementation.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  group('SecretKey / PublicKey', () {
    test('generate -> public -> sign -> verify round-trip', () {
      final sk = SecretKey.generate();
      final pk = sk.publicKey;
      final msg = Uint8List.fromList('hello world'.codeUnits);
      final sig = sk.sign(msg);
      expect(sig.toBytes().length, Signature.lengthBytes);
      expect(pk.verify(msg, sig), isTrue);
      // Tampered message must fail.
      final tampered = Uint8List.fromList('hello worle'.codeUnits);
      expect(pk.verify(tampered, sig), isFalse);
    });

    test('secret key bytes round-trip', () {
      final sk = SecretKey.generate();
      final restored = SecretKey.fromBytes(sk.toBytes());
      expect(restored.publicKey, sk.publicKey);
    });

    test('wrong-length key bytes throw IrohKeyException', () {
      expect(() => SecretKey.fromBytes(Uint8List(10)), throwsA(isA<IrohKeyException>()));
      expect(() => PublicKey.fromBytes(Uint8List(31)), throwsA(isA<IrohKeyException>()));
      expect(() => Signature.fromBytes(Uint8List(63)), throwsA(isA<IrohKeyException>()));
    });
  });

  group('encoding vectors', () {
    test('known hex vector round-trips (from iroh-base key.rs tests)', () {
      const hex = 'ae58ff8833241ac82d6ff7611046ed67b5072d142c588d0063e942d9a75502b6';
      final pk = PublicKey.fromHex(hex);
      expect(pk.asBytes().length, PublicKey.lengthBytes);
      expect(pk.toHex(), hex);
    });

    test('all-zeros is a valid public key', () {
      expect(() => PublicKey.fromBytes(Uint8List(32)), returnsNormally);
    });

    test('invalid hex throws IrohKeyException', () {
      expect(() => PublicKey.fromHex('foobarbaz'), throwsA(isA<IrohKeyException>()));
    });

    test('z-base-32 round-trips and equals the source key', () {
      final pk = SecretKey.generate().publicKey;
      final z32 = pk.toZ32();
      final back = PublicKey.fromZ32(z32);
      expect(back, pk);
      expect(back.asBytes(), pk.asBytes());
    });

    test('fmtShort is a non-empty hex prefix', () {
      final pk = PublicKey.fromHex(
        'ae58ff8833241ac82d6ff7611046ed67b5072d142c588d0063e942d9a75502b6',
      );
      final short = pk.fmtShort();
      expect(short, isNotEmpty);
      expect('ae58ff8833241ac82d6ff7611046ed67b5072d142c588d0063e942d9a75502b6', startsWith(short));
    });

    test('PublicKey value equality + hashCode', () {
      final a = PublicKey.fromHex(
        'ae58ff8833241ac82d6ff7611046ed67b5072d142c588d0063e942d9a75502b6',
      );
      final b = PublicKey.fromHex(
        'ae58ff8833241ac82d6ff7611046ed67b5072d142c588d0063e942d9a75502b6',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });

  group('EndpointAddr', () {
    test('builder + postcard encode/decode round-trip', () {
      final id = SecretKey.generate().publicKey;
      final addr = EndpointAddr(
        id,
      ).withRelayUrl(RelayUrl.parse('https://relay.example.com./')).withIpAddr('192.168.1.5:7777');

      final decoded = EndpointAddr.decode(addr.encode());
      expect(decoded.id, id);
      expect(decoded.ipAddrs, contains('192.168.1.5:7777'));
      expect(decoded.relayUrls, hasLength(1));
    });

    test('canonical() validates components via iroh', () {
      final id = SecretKey.generate().publicKey;
      final canonical = EndpointAddr(id).withIpAddr('10.0.0.1:1234').canonical();
      expect(canonical.id, id);
      expect(canonical.ipAddrs, contains('10.0.0.1:1234'));
    });

    test('invalid socket address throws IrohKeyException', () {
      final id = SecretKey.generate().publicKey;
      expect(
        () => EndpointAddr(id).withIpAddr('not-an-addr').encode(),
        throwsA(isA<IrohKeyException>()),
      );
    });
  });

  group('RelayUrl / RelayMode', () {
    test('parses and canonicalises a relay URL', () {
      final url = RelayUrl.parse('https://relay.example.com.');
      expect(url.value, contains('relay.example.com'));
    });

    test('invalid relay URL throws IrohKeyException', () {
      expect(() => RelayUrl.parse('not a url'), throwsA(isA<IrohKeyException>()));
    });

    test('RelayMode constructors', () {
      expect(RelayMode.n0Default, isA<RelayModeDefault>());
      expect(RelayMode.disabled, isA<RelayModeDisabled>());
      expect(RelayMode.staging, isA<RelayModeStaging>());
      final custom = RelayMode.custom(RelayMap.fromUrls(['https://relay.example.com.']));
      expect(custom, isA<RelayModeCustom>());
      expect((custom as RelayModeCustom).map.urls, hasLength(1));
    });
  });
}
