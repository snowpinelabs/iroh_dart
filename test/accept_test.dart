@TestOn('vm')
@Timeout(Duration(seconds: 60))
library;

import 'dart:typed_data';

import 'package:iroh_dart/iroh_dart.dart';
import 'package:test/test.dart';

/// The accept loop with the Dart-driven [Incoming] filter - multiple concurrent inbound
/// connections, the `accept` path, and the `refuse` path. Relays disabled, loopback addrs.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  const alpn = 'iroh-dart/accept/0';

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

  Future<Uint8List> clientEcho(Endpoint client, EndpointAddr serverAddr, Uint8List payload) async {
    final conn = await client.connect(serverAddr, alpn.codeUnits);
    final (send, recv) = await conn.openBi();
    await send.writeAll(payload);
    await send.finish();
    return recv.readToEnd(1 << 16);
  }

  Future<void> echoOnce(Connection conn) async {
    final (send, recv) = await conn.acceptBi();
    final data = await recv.readToEnd(1 << 16);
    await send.writeAll(data);
    await send.finish();
  }

  test('filtered accept: inspect remoteAddr then accept -> echo', () async {
    final server = await Endpoint.bind(alpns: [alpn.codeUnits], relayMode: RelayMode.disabled);
    final client = await Endpoint.bind(relayMode: RelayMode.disabled);
    addTearDown(server.close);
    addTearDown(client.close);
    final serverAddr = EndpointAddr(server.id, ipAddrs: loopback(server.boundSockets));

    final served = () async {
      final incoming = await server.acceptIncoming();
      expect(incoming, isNotNull);
      expect(incoming!.remoteAddr, isNotEmpty);
      final conn = await incoming.accept();
      await echoOnce(conn);
    }();

    final payload = Uint8List.fromList('filtered-accept'.codeUnits);
    final echoed = await clientEcho(client, serverAddr, payload);
    await served;
    expect(echoed, payload);
  });

  test('multiple concurrent inbound connections are all accepted', () async {
    const n = 3;
    final server = await Endpoint.bind(alpns: [alpn.codeUnits], relayMode: RelayMode.disabled);
    addTearDown(server.close);
    final serverAddr = EndpointAddr(server.id, ipAddrs: loopback(server.boundSockets));

    final serverDone = () async {
      final echoes = <Future<void>>[];
      for (var i = 0; i < n; i++) {
        final incoming = await server.acceptIncoming();
        final conn = await incoming!.accept();
        echoes.add(echoOnce(conn));
      }
      await Future.wait(echoes);
    }();

    final clients = <Endpoint>[];
    for (var i = 0; i < n; i++) {
      clients.add(await Endpoint.bind(relayMode: RelayMode.disabled));
    }
    for (final c in clients) {
      addTearDown(c.close);
    }
    final payloads = <Uint8List>[
      for (var i = 0; i < n; i++)
        Uint8List.fromList(List<int>.generate(1000, (j) => (i * 100 + j) & 0xff)),
    ];

    final got = await Future.wait([
      for (var i = 0; i < n; i++) clientEcho(clients[i], serverAddr, payloads[i]),
    ]);
    await serverDone;

    for (var i = 0; i < n; i++) {
      expect(got[i], payloads[i], reason: 'client $i echo mismatch');
    }
  });

  test('refuse: a refused incoming makes the peer connect fail', () async {
    final server = await Endpoint.bind(alpns: [alpn.codeUnits], relayMode: RelayMode.disabled);
    final client = await Endpoint.bind(relayMode: RelayMode.disabled);
    addTearDown(server.close);
    addTearDown(client.close);
    final serverAddr = EndpointAddr(server.id, ipAddrs: loopback(server.boundSockets));

    final refused = () async {
      final incoming = await server.acceptIncoming();
      incoming!.refuse();
    }();

    await expectLater(
      client.connect(serverAddr, alpn.codeUnits).timeout(const Duration(seconds: 20)),
      throwsA(anything),
      reason: 'connecting to a refused server must not succeed',
    );
    await refused;
  });
}
