@TestOn('vm')
@Timeout(Duration(seconds: 40))
library;

import 'dart:typed_data';

import 'package:iroh_dart/iroh_dart.dart';
import 'package:test/test.dart';

/// Multi-protocol multiplexing by **dispatching on ALPN in Dart** over the accept loop - an
/// alternative to bridging async Rust traits. One server advertises two ALPNs and routes each
/// accepted connection to a different handler.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  const protoUpper = 'iroh-dart/upper/0';
  const protoReverse = 'iroh-dart/reverse/0';

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

  test('server routes connections by ALPN to different protocol handlers', () async {
    final server = await Endpoint.bind(
      alpns: [protoUpper.codeUnits, protoReverse.codeUnits],
      relayMode: RelayMode.disabled,
    );
    addTearDown(server.close);
    final serverAddr = EndpointAddr(server.id, ipAddrs: loopback(server.boundSockets));

    // Accept loop: dispatch on the negotiated ALPN.
    final serverDone = () async {
      final handlers = <Future<void>>[];
      for (var i = 0; i < 2; i++) {
        final conn = await server.accept();
        final alpn = String.fromCharCodes(conn!.alpn);
        handlers.add(() async {
          final (send, recv) = await conn.acceptBi();
          final data = await recv.readToEnd(1 << 16);
          final response = switch (alpn) {
            protoUpper => Uint8List.fromList(String.fromCharCodes(data).toUpperCase().codeUnits),
            protoReverse => Uint8List.fromList(data.reversed.toList(growable: false)),
            _ => data,
          };
          await send.writeAll(response);
          await send.finish();
        }());
      }
      await Future.wait(handlers);
    }();

    Future<Uint8List> call(String alpn, String payload) async {
      final client = await Endpoint.bind(relayMode: RelayMode.disabled);
      addTearDown(client.close);
      final conn = await client.connect(serverAddr, alpn.codeUnits);
      final (send, recv) = await conn.openBi();
      await send.writeAll(payload.codeUnits);
      await send.finish();
      return recv.readToEnd(1 << 16);
    }

    final upperResult = await call(protoUpper, 'hello');
    final reverseResult = await call(protoReverse, 'abcde');
    await serverDone;

    expect(String.fromCharCodes(upperResult), 'HELLO', reason: 'upper protocol uppercases');
    expect(String.fromCharCodes(reverseResult), 'edcba', reason: 'reverse protocol reverses');
  });
}
