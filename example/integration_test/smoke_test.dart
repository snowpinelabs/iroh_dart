import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:iroh_dart/iroh_dart.dart';

/// On-device (simulator/emulator) verification - runs against the REAL native
/// build: cargokit compiles the Rust crate, the platform links it, and the Dart loader resolves
/// the FFI symbols at runtime. This is the proof the host `flutter test` can't give.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('native library loads and ABI handshake passes', (tester) async {
    await Iroh.init();
    expect(Iroh.abiVersion, 1);
    expect(Iroh.irohVersion, isNotEmpty);
    expect(Iroh.capabilities.direct, isTrue);
  });

  testWidgets('bind -> addr -> close on real device runtime', (tester) async {
    await Iroh.init();
    final sk = SecretKey.generate();
    final ep = await Endpoint.bind(secretKey: sk, relayMode: RelayMode.disabled);
    expect(ep.id, sk.publicKey);
    expect(ep.boundSockets, isNotEmpty);
    await ep.close();
    expect(ep.isClosed, isTrue);
  });

  testWidgets('byte-identical bidirectional echo between two endpoints', (tester) async {
    await Iroh.init();
    const alpn = 'iroh-dart/itest/echo/0';
    final server = await Endpoint.bind(alpns: [alpn.codeUnits], relayMode: RelayMode.disabled);
    final client = await Endpoint.bind(relayMode: RelayMode.disabled);
    final serverAddr = EndpointAddr(server.id, ipAddrs: loopback(server.boundSockets));

    final payload = Uint8List.fromList(List<int>.generate(8192, (i) => (i * 37 + 11) & 0xff));

    final served = () async {
      final conn = await server.accept();
      final (send, recv) = await conn!.acceptBi();
      final data = await recv.readToEnd(1 << 20);
      await send.writeAll(data);
      await send.finish();
    }();

    final conn = await client.connect(serverAddr, alpn.codeUnits);
    final (send, recv) = await conn.openBi();
    await send.writeAll(payload);
    await send.finish();
    final echoed = await recv.readToEnd(1 << 20);
    await served;

    expect(echoed, payload);
    expect(conn.remoteId, server.id);

    await client.close();
    await server.close();
  });

  testWidgets('watchAddr stream emits then cancels cleanly', (tester) async {
    await Iroh.init();
    final ep = await Endpoint.bind(relayMode: RelayMode.disabled);
    final first = await ep.watchAddr().first;
    expect(first.id, ep.id);
    // Repeated subscribe/cancel must not deadlock the native callback bridge.
    for (var i = 0; i < 10; i++) {
      final sub = ep.watchAddr().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await sub.cancel();
    }
    await ep.close();
  });
}
