@TestOn('vm')
@Timeout(Duration(seconds: 40))
library;

import 'dart:typed_data';

import 'package:iroh_quic/iroh_quic.dart';
import 'package:test/test.dart';

/// The Dart->Rust custom `AddressLookup` bridge. A client dials a server known only by its
/// [EndpointId]; iroh calls back into a **Dart** resolver to discover the server's address, then
/// connects. Relays disabled; the resolver returns loopback addresses.
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
        // Resolve only the known server; everything else is unknown.
        if (id == serverId) {
          return EndpointAddr(serverId, ipAddrs: serverAddrs);
        }
        return null;
      },
    );
    addTearDown(client.close);

    // Server echoes one bidi stream.
    final served = () async {
      final conn = await server.accept();
      final (send, recv) = await conn!.acceptBi();
      final data = await recv.readToEnd(1 << 16);
      await send.writeAll(data);
      await send.finish();
    }();

    // Connect using ONLY the server's id - no direct addresses provided. iroh must call the Dart
    // resolver to discover the address.
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
