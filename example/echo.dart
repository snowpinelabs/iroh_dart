// Pure-Dart headless smoke test (migration P0): proves iroh_dart runs under
// `dart run` with no Flutter — bind two endpoints, dial one from the other over
// QUIC, and echo a bidirectional stream.
//
// Run from the package root after `cargo build --release`:
//   dart run example/echo.dart
import 'dart:typed_data';

import 'package:iroh_dart/iroh_dart.dart';

Future<void> main() async {
  await Iroh.init(
      libraryPath: 'rust/target/release/libirohdart_ffi.so');
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
