@TestOn('vm')
library;

import 'package:iroh_quic/iroh_quic.dart';
import 'package:test/test.dart';

/// Tests the `Endpoint.bind()` -> `addr` -> `close()` cycle. Async `Future`s must complete on the
/// Dart event loop. The embedded tokio runtime must survive repeated bind and close cycles without
/// a leak or a hang. Relay servers are disabled, so the tests do not need a network.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  test('bind with a fixed secret key exposes the matching id, then closes', () async {
    final sk = SecretKey.generate();
    final endpoint = await Endpoint.bind(
      secretKey: sk,
      alpns: ['iroh-dart/test/0'.codeUnits],
      relayMode: RelayMode.disabled,
    );
    addTearDown(endpoint.close);

    expect(endpoint.isClosed, isFalse);
    expect(endpoint.id, sk.publicKey, reason: 'id must match the supplied secret key');
    expect(endpoint.addr.id, sk.publicKey);
    expect(
      endpoint.boundSockets,
      isNotEmpty,
      reason: 'binding must allocate at least one local UDP socket',
    );

    await endpoint.close();
    expect(endpoint.isClosed, isTrue);
  });

  test('bind without a secret key yields a random identity', () async {
    final a = await Endpoint.bind(relayMode: RelayMode.disabled);
    final b = await Endpoint.bind(relayMode: RelayMode.disabled);
    addTearDown(a.close);
    addTearDown(b.close);
    expect(a.id, isNot(b.id), reason: 'two fresh endpoints must differ');
  });

  test('setAlpns updates accepted protocols without error', () async {
    final endpoint = await Endpoint.bind(relayMode: RelayMode.disabled);
    addTearDown(endpoint.close);
    endpoint.setAlpns(['iroh-dart/a/0'.codeUnits, 'iroh-dart/b/0'.codeUnits]);
    expect(endpoint.isClosed, isFalse);
  });

  test('repeated bind/close does not leak or hang the runtime', () async {
    for (var i = 0; i < 6; i++) {
      final endpoint = await Endpoint.bind(relayMode: RelayMode.disabled);
      expect(endpoint.isClosed, isFalse);
      await endpoint.close();
      expect(endpoint.isClosed, isTrue);
    }
  });
}
