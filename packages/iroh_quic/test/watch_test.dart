@TestOn('vm')
@Timeout(Duration(seconds: 60))
library;

import 'dart:typed_data';

import 'package:iroh_quic/iroh_quic.dart';
import 'package:test/test.dart';

/// Reactive state bridged to Dart `Stream`s. Verifies streams emit, that cancellation is leak-free
/// under repeated subscribe/cancel (the host proxy for the on-device `NativeCallable.listener` load
/// test), and that path events surface on a real connection.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  const alpn = 'iroh-dart/watch/0';

  List<String> loopback(List<String> bound) {
    final out = <String>[];
    for (final b in bound) {
      final i = b.lastIndexOf(':');
      if (i < 0) continue;
      final port = b.substring(i + 1);
      final host = b.substring(0, i);
      out.add(host.startsWith('[') || host.contains(':') ? '[::1]:$port' : '127.0.0.1:$port');
    }
    return out;
  }

  test('watchAddr emits the current address', () async {
    final ep = await Endpoint.bind(relayMode: RelayMode.disabled);
    addTearDown(ep.close);
    final first = await ep.watchAddr().first;
    expect(first.id, ep.id);
  });

  test('homeRelayStatus emits a status list', () async {
    final ep = await Endpoint.bind(relayMode: RelayMode.disabled);
    addTearDown(ep.close);
    final statuses = await ep.homeRelayStatus().first;
    expect(statuses, isA<List<RelayStatus>>());
  });

  test('repeated subscribe/cancel of watchAddr is leak-free', () async {
    final ep = await Endpoint.bind(relayMode: RelayMode.disabled);
    addTearDown(ep.close);
    for (var i = 0; i < 25; i++) {
      final sub = ep.watchAddr().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await sub.cancel();
    }
    // Reaching here without hanging means each StreamSink set up and tore down cleanly.
    expect(ep.isClosed, isFalse);
  });

  test('pathEvents surfaces path activity on a live connection', () async {
    final server = await Endpoint.bind(alpns: [alpn.codeUnits], relayMode: RelayMode.disabled);
    final client = await Endpoint.bind(relayMode: RelayMode.disabled);
    addTearDown(server.close);
    addTearDown(client.close);
    final serverAddr = EndpointAddr(server.id, ipAddrs: loopback(server.boundSockets));

    final served = () async {
      final conn = await server.accept();
      final (send, recv) = await conn!.acceptBi();
      final data = await recv.readToEnd(1 << 16);
      await send.writeAll(data);
      await send.finish();
    }();

    final conn = await client.connect(serverAddr, alpn.codeUnits);
    final events = <PathEvent>[];
    final sub = conn.pathEvents().listen(events.add);

    final (send, recv) = await conn.openBi();
    await send.writeAll(Uint8List.fromList('path-events'.codeUnits));
    await send.finish();
    await recv.readToEnd(1 << 16);
    await served;

    // Give the path machinery a moment to publish events, then stop listening.
    await Future<void>.delayed(const Duration(seconds: 2));
    await sub.cancel();

    expect(
      events,
      isNotEmpty,
      reason: 'a direct loopback path should produce at least one PathEvent',
    );
    expect(
      events.any((e) => e is PathOpened || e is PathSelected),
      isTrue,
      reason: 'expected an Opened/Selected event for the direct path',
    );
  });
}
