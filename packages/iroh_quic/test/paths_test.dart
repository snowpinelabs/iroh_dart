@TestOn('vm')
@Timeout(Duration(seconds: 60))
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:iroh_quic/iroh_quic.dart';
import 'package:test/test.dart';

/// Path snapshots, the path wait helpers, and stream affinity (iroh 1.5). The tests connect two
/// endpoints in one process through their loopback direct addresses. Relay servers are disabled,
/// so each connection has only direct IP paths.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  const alpn = 'iroh-dart/paths/0';

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

  /// Connects a client to a server. Returns the client connection and the server connection.
  Future<(Connection client, Connection server)> connectPair() async {
    final server = await Endpoint.bind(alpns: [alpn.codeUnits], relayMode: RelayMode.disabled);
    final client = await Endpoint.bind(relayMode: RelayMode.disabled);
    addTearDown(server.close);
    addTearDown(client.close);
    final serverAddr = EndpointAddr(server.id, ipAddrs: loopback(server.boundSockets));
    final accepted = server.accept();
    final conn = await client.connect(serverAddr, alpn.codeUnits);
    final serverConn = await accepted;
    return (conn, serverConn!);
  }

  const wait = Duration(seconds: 10);

  group('paths', () {
    test('paths returns the open direct paths with unique IDs', () async {
      final (conn, _) = await connectPair();
      final direct = await conn.waitAnyPath((p) => p.isIp).timeout(wait);
      expect(direct, isNotNull);

      final paths = conn.paths;
      expect(paths, isNotEmpty);
      expect(paths.every((p) => p.isIp && !p.isRelay), isTrue, reason: 'relay is disabled');
      expect(paths.map((p) => p.id).toSet(), hasLength(paths.length));
      expect(paths.where((p) => p.isSelected).length, lessThanOrEqualTo(1));
      expect(paths.every((p) => p.remoteAddr.isNotEmpty), isTrue);
      expect(paths.every((p) => !p.rtt.isNegative), isTrue);
      expect(() => paths.add(paths.first), throwsUnsupportedError);
    });

    test('pathsStream emits the current snapshot first', () async {
      final (conn, _) = await connectPair();
      await conn.waitAnyPath((p) => p.isIp).timeout(wait);
      final first = await conn.pathsStream().first.timeout(wait);
      expect(first.any((p) => p.isIp), isTrue);
    });

    test('wait helpers examine the current paths first', () async {
      final (conn, _) = await connectPair();
      final direct = (await conn.waitAnyPath((p) => p.isIp).timeout(wait))!;

      // No path agrees with this test, so the future completes with the current snapshot.
      final none = await conn.waitNoPath((_) => false).timeout(wait);
      expect(none!.map((p) => p.id), contains(direct.id));

      // A path ID that the connection did not use is not open.
      final closed = await conn.waitPathClosed(const PathId(0xFFFFFF)).timeout(wait);
      expect(closed!.map((p) => p.id), contains(direct.id));
    });

    test('wait helpers and pathsStream end when the connection closes', () async {
      final (conn, _) = await connectPair();
      final direct = (await conn.waitAnyPath((p) => p.isIp).timeout(wait))!;

      final pending = conn.waitAnyPath((_) => false);
      final pendingClosed = conn.waitPathClosed(direct.id);
      final streamDone = conn.pathsStream().drain<void>();
      conn.close(reason: 'done'.codeUnits);

      expect(await pending.timeout(wait), isNull);
      // The connection closes all its paths. The future completes with the snapshot without the
      // path, or with `null` if the stream ends first.
      final closed = await pendingClosed.timeout(wait);
      expect(closed == null || closed.every((p) => p.id != direct.id), isTrue);
      await streamDone.timeout(wait);
      expect(await conn.waitNoPath((_) => false).timeout(wait), isNull);
    });

    test('path events carry the path ID', () async {
      final (conn, _) = await connectPair();
      final events = <PathEvent>[];
      final sub = conn.pathEvents().listen(events.add);
      // Wait 2 seconds so that iroh can publish path events, as in watch_test.dart.
      await Future<void>.delayed(const Duration(seconds: 2));
      final openIds = conn.paths.map((p) => p.id).toSet();
      await sub.cancel();

      PathId? idOf(PathEvent e) => switch (e) {
        PathOpened(:final id) || PathClosed(:final id) || PathSelected(:final id) => id,
        _ => null,
      };
      final withIds = events.where((e) => e is PathOpened || e is PathSelected).toList();
      expect(withIds, isNotEmpty, reason: 'a direct loopback path opens or becomes selected');
      for (final e in events.where(
        (e) => e is PathOpened || e is PathClosed || e is PathSelected,
      )) {
        expect(idOf(e), isNotNull, reason: 'the binding sets the ID of $e');
      }
      // A selected path is open, so its ID is in the current snapshot.
      final selected = events.whereType<PathSelected>().lastOrNull;
      if (selected != null) expect(openIds, contains(selected.id));
    });
  });

  group('stream affinity', () {
    test('a sticky stream sends its data on the direct path', () async {
      final (conn, serverConn) = await connectPair();
      final direct = (await conn.waitAnyPath((p) => p.isIp).timeout(wait))!;

      final send = await conn.openUni();
      send.setAffinity(StreamAffinity.sticky(direct.id));
      final payload = Uint8List.fromList(List<int>.generate(256 * 1024, (i) => i & 0xff));
      await send.writeAll(payload);
      await send.finish();

      final recv = await serverConn.acceptUni().timeout(wait);
      expect(await recv.readToEnd(1 << 20).timeout(wait), payload);
    });

    test('a blocked stream sends no data until the affinity changes', () async {
      final (conn, serverConn) = await connectPair();
      await conn.waitAnyPath((p) => p.isIp).timeout(wait);

      final send = await conn.openUni();
      send.setAffinity(StreamAffinity.block);
      // This payload is larger than the flow control windows, so the write cannot complete while
      // the stream is blocked.
      final payload = Uint8List.fromList(List<int>.generate(32 << 20, (i) => (i * 7) & 0xff));
      var writeDone = false;
      final write = send.writeAll(payload).then((_) => writeDone = true);

      var accepted = false;
      final accept = serverConn.acceptUni().then((r) {
        accepted = true;
        return r;
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(accepted, isFalse, reason: 'the peer does not see a stream that sends no data');
      expect(writeDone, isFalse, reason: 'the write waits while the stream is blocked');

      // setAffinity must not wait for the write that is in progress.
      send.setAffinity(StreamAffinity.any);
      final recv = await accept.timeout(wait);
      final received = recv.readToEnd(64 << 20);
      await write.timeout(wait);
      await send.finish();
      expect((await received.timeout(wait)).length, payload.length);
    });

    test('a sticky stream moves to a different path ID', () async {
      final (conn, serverConn) = await connectPair();
      final direct = (await conn.waitAnyPath((p) => p.isIp).timeout(wait))!;

      final send = await conn.openUni();
      // A path ID that the connection did not open carries no data.
      send.setAffinity(const StreamAffinity.sticky(PathId(0xFFFFFF)));
      await send.writeAll('sticky'.codeUnits);
      await send.finish();
      var accepted = false;
      final accept = serverConn.acceptUni().then((r) {
        accepted = true;
        return r;
      });
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(accepted, isFalse);

      send.setAffinity(StreamAffinity.sticky(direct.id));
      final recv = await accept.timeout(wait);
      expect(String.fromCharCodes(await recv.readToEnd(1024).timeout(wait)), 'sticky');
    });

    test('affinity values', () {
      expect(StreamAffinity.any, isA<StreamAffinityAny>());
      expect(StreamAffinity.block, isA<StreamAffinityBlock>());
      const sticky = StreamAffinity.sticky(PathId(3));
      expect(sticky, isA<StreamAffinitySticky>());
      expect(sticky, const StreamAffinitySticky(PathId(3)));
      expect(sticky, isNot(const StreamAffinitySticky(PathId(4))));
      expect((sticky as StreamAffinitySticky).path, const PathId(3));
      expect(const PathId(3).hashCode, const PathId(3).hashCode);
      expect(sticky.toString(), 'StreamAffinity.sticky(3)');
    });
  });
}
