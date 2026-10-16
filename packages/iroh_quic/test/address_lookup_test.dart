@TestOn('vm')
@Timeout(Duration(seconds: 40))
library;

import 'dart:typed_data';

import 'package:iroh_quic/iroh_quic.dart';
import 'package:test/test.dart';

/// The custom `AddressLookup` bridge from Dart to Rust. A client connects to a server from its
/// [EndpointId] only. iroh calls a **Dart** resolver to find the address of the server, and then
/// connects. Relay servers are disabled, and the resolver gives loopback addresses.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  const alpn = 'iroh-dart/lookup/0';

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

  test('client dials a server by id, resolved via the Dart AddressLookup', () async {
    final server = await Endpoint.bind(alpns: [alpn.codeUnits], relayMode: RelayMode.disabled);
    addTearDown(server.close);
    final serverId = server.id;
    final serverAddrs = loopback(server.boundSockets);

    var resolverCalls = 0;
    final client = await Endpoint.bindWithAddressLookup(
      relayMode: RelayMode.disabled,
      resolve: (EndpointId id) {
        resolverCalls++;
        // Resolve only the known server. All other endpoint IDs are unknown.
        if (id == serverId) {
          return EndpointAddr(serverId, ipAddrs: serverAddrs);
        }
        return null;
      },
    );
    addTearDown(client.close);

    // The server echoes one bidirectional stream.
    final served = () async {
      final conn = await server.accept();
      final (send, recv) = await conn!.acceptBi();
      final data = await recv.readToEnd(1 << 16);
      await send.writeAll(data);
      await send.finish();
    }();

    // Connect with ONLY the endpoint ID of the server, without direct addresses. iroh must call
    // the Dart resolver to find the address.
    final payload = Uint8List.fromList('resolved-by-dart'.codeUnits);
    final conn = await client.connect(EndpointAddr(serverId), alpn.codeUnits);
    final (send, recv) = await conn.openBi();
    await send.writeAll(payload);
    await send.finish();
    final echoed = await recv.readToEnd(1 << 16);
    await served;

    expect(echoed, payload, reason: 'connection via Dart-resolved address works');
    expect(
      resolverCalls,
      greaterThan(0),
      reason: 'the Dart address resolver must have been invoked',
    );
    expect(conn.remoteId, serverId);
  });
}
