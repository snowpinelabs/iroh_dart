// A pure-Dart smoke test with no UI. It shows that iroh_quic runs under `dart run` without
// Flutter. It binds two endpoints and connects one to the other over QUIC. The server endpoint
// returns the data that the client writes to a bidirectional stream.
//
// Run `dart run iroh_quic:setup` or `cargo build --release` first. Then run this command from
// the package root:
//   dart run example/iroh_quic_example.dart
import 'dart:typed_data';

import 'package:iroh_quic/iroh_quic.dart';

Future<void> main() async {
  // No libraryPath. The loader finds the native library automatically, for example in
  // rust/target/{debug,release}/ or in the cache.
  await Iroh.init();
  print('iroh ${Iroh.irohVersion}, ABI v${Iroh.abiVersion}');

  const alpn = 'jamnp-s/echo/0';

  final server = await Endpoint.bind(alpns: [alpn.codeUnits]);
  final serving = () async {
    final conn = await server.accept();
    final (send, recv) = await conn!.acceptBi();
    final got = await recv.readToEnd(1 << 20);
    await send.writeAll(got);
    await send.finish();
  }();

  final client = await Endpoint.bind();
  final conn = await client.connect(server.addr, alpn.codeUnits);
  final (send, recv) = await conn.openBi();
  await send.writeAll(Uint8List.fromList('hello jam'.codeUnits));
  await send.finish();
  final echoed = String.fromCharCodes(await recv.readToEnd(1 << 20));
  await serving;

  print('server id: ${server.addr.id.toZ32()}');
  print('echo: "$echoed"');
  if (echoed != 'hello jam') {
    throw StateError('echo mismatch: "$echoed"');
  }
  print('OK: pure-Dart iroh↔iroh QUIC echo works headless');

  await client.close();
  await server.close();
}
