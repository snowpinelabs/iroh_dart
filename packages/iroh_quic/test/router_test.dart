@TestOn('vm')
@Timeout(Duration(seconds: 40))
library;

import 'dart:typed_data';

import 'package:iroh_quic/iroh_quic.dart';
import 'package:test/test.dart';

/// The `ProtocolHandler` bridge from Dart to Rust. One iroh `Router` multiplexes two ALPN protocols
/// in one process. A **Dart async callback** handles each ALPN, and the Rust router calls it for
/// each inbound connection. Relay servers are disabled, and the client uses loopback addresses.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  const upper = 'iroh-dart/router/upper/0';
  const reverse = 'iroh-dart/router/reverse/0';

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

  test('Router dispatches by ALPN to Dart handlers, then shuts down', () async {
    final server = await Endpoint.bind(relayMode: RelayMode.disabled);
    addTearDown(server.close);

    // Register two ALPN protocols. A Dart async handler serves each one.
    final builder = await server.router();
    await builder.accept(upper.codeUnits, (Connection conn) async {
      final (send, recv) = await conn.acceptBi();
      final data = await recv.readToEnd(1 << 16);
      await send.writeAll(String.fromCharCodes(data).toUpperCase().codeUnits);
      await send.finish();
    });
    await builder.accept(reverse.codeUnits, (Connection conn) async {
      final (send, recv) = await conn.acceptBi();
      final data = await recv.readToEnd(1 << 16);
      await send.writeAll(data.reversed.toList(growable: false));
      await send.finish();
    });
    final router = await builder.spawn();

    final serverAddr = EndpointAddr(server.id, ipAddrs: loopback(server.boundSockets));

    Future<String> call(String alpn, String payload) async {
      final client = await Endpoint.bind(relayMode: RelayMode.disabled);
      addTearDown(client.close);
      final conn = await client.connect(serverAddr, alpn.codeUnits);
      final (send, recv) = await conn.openBi();
      await send.writeAll(Uint8List.fromList(payload.codeUnits));
      await send.finish();
      return String.fromCharCodes(await recv.readToEnd(1 << 16));
    }

    expect(await call(upper, 'hello'), 'HELLO', reason: 'router routed to the upper handler');
    expect(await call(reverse, 'abcde'), 'edcba', reason: 'router routed to the reverse handler');

    await router.shutdown();
  });
}
