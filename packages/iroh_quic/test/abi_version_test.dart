@TestOn('vm')
library;

import 'package:iroh_quic/iroh_quic.dart';
import 'package:test/test.dart';

/// Host check: load the native library, verify the ABI handshake, and call the no-op FFI
/// function end-to-end (Rust -> FRB glue -> native lib -> Dart). The on-device half (iOS +
/// Android) is verified separately in `example/`.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  test('native runtime initialises and reports ABI v1', () {
    expect(Iroh.isInitialised, isTrue);
    expect(Iroh.abiVersion, 1);
  });

  test('built against an iroh 1.x core', () {
    expect(Iroh.irohVersion, isNotEmpty);
  });

  test('native platform advertises full capabilities', () {
    final caps = Iroh.capabilities;
    expect(caps.direct, isTrue, reason: 'native track supports direct connections');
    expect(caps.relay, isTrue);
    expect(caps.blobs, isFalse, reason: 'blobs are out of scope in v1');
  });
}
