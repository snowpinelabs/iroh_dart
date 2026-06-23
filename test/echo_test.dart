@TestOn('vm')
@Timeout(Duration(seconds: 40))
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iroh_dart/iroh_dart.dart';

/// Byte-identical bidi echo across two in-process endpoints over `connect` / `acceptBi`, plus
/// unidirectional streams and datagrams. Relays are disabled; the client reaches the server via
/// its loopback direct addresses, so the test needs no network.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  const alpn = 'iroh-dart/echo/0';

  /// Rewrites an endpoint's bound socket addresses to loopback so a same-machine peer can dial it
  /// directly (no relay, no discovery).
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

  Future<(Endpoint server, Endpoint client, EndpointAddr serverAddr)> pair() async {
    final server = await Endpoint.bind(alpns: [alpn.codeUnits], relayMode: RelayMode.disabled);
    final client = await Endpoint.bind(relayMode: RelayMode.disabled);
    final serverAddr = EndpointAddr(server.id, ipAddrs: loopback(server.boundSockets));
    return (server, client, serverAddr);
  }

  test('byte-identical bidirectional echo (connect/openBi <-> accept/acceptBi)', () async {
    final (server, client, serverAddr) = await pair();
    addTearDown(server.close);
    addTearDown(client.close);

    final payload = Uint8List.fromList(List<int>.generate(64 * 1024, (i) => (i * 31 + 7) & 0xff));

    // Server: accept a connection, echo the first bidi stream back.
    final served = () async {
      final conn = await server.accept();
      expect(conn, isNotNull);
      final (send, recv) = await conn!.acceptBi();
      final received = await recv.readToEnd(1 << 20);
      await send.writeAll(received);
      await send.finish();
      return conn.remoteId;
    }();

    // Client: open a bidi stream, send the payload, read the echo.
    final conn = await client.connect(serverAddr, alpn.codeUnits);
    final (send, recv) = await conn.openBi();
    await send.writeAll(payload);
    await send.finish();
    final echoed = await recv.readToEnd(1 << 20);

    final remoteSeenByServer = await served;
    expect(echoed, payload, reason: 'echo must be byte-identical');
    expect(conn.remoteId, server.id);
    expect(remoteSeenByServer, client.id, reason: 'server sees the client id');
    expect(conn.alpn, Uint8List.fromList(alpn.codeUnits));
  });

  test('unidirectional stream transfer (openUni -> acceptUni)', () async {
    final (server, client, serverAddr) = await pair();
    addTearDown(server.close);
    addTearDown(client.close);

    final payload = Uint8List.fromList('one-way-hello'.codeUnits);

    final served = () async {
      final conn = await server.accept();
      final recv = await conn!.acceptUni();
      return recv.readToEnd(1 << 16);
    }();

    final conn = await client.connect(serverAddr, alpn.codeUnits);
    final send = await conn.openUni();
    await send.writeAll(payload);
    await send.finish();

    expect(await served, payload);
  });

  test('datagram round-trip (sendDatagram / readDatagram)', () async {
    final (server, client, serverAddr) = await pair();
    addTearDown(server.close);
    addTearDown(client.close);

    final datagram = Uint8List.fromList('ping'.codeUnits);

    final served = () async {
      final conn = await server.accept();
      return conn!.readDatagram();
    }();

    final conn = await client.connect(serverAddr, alpn.codeUnits);
    conn.sendDatagram(datagram);

    expect(await served, datagram);
    // Stats are accessible.
    expect(conn.stats.udpTxDatagrams, greaterThanOrEqualTo(0));
  });

  test('partial reads via read(maxLen) reassemble the payload', () async {
    final (server, client, serverAddr) = await pair();
    addTearDown(server.close);
    addTearDown(client.close);

    final payload = Uint8List.fromList(List<int>.generate(10000, (i) => (i * 13) & 0xff));

    final served = () async {
      final conn = await server.accept();
      final (send, _) = await conn!.acceptBi();
      await send.writeAll(payload);
      await send.finish();
    }();

    final conn = await client.connect(serverAddr, alpn.codeUnits);
    final (send, recv) = await conn.openBi();
    // Open the bidi stream so the server's acceptBi resolves (lazy-stream footgun).
    await send.writeAll(Uint8List.fromList(const <int>[0]));
    await send.finish();

    final assembled = <int>[];
    while (true) {
      final chunk = await recv.read(1024);
      if (chunk == null) break;
      assembled.addAll(chunk);
    }
    await served;
    expect(Uint8List.fromList(assembled), payload);
  });
}
