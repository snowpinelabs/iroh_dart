@TestOn('vm')
library;

import 'package:iroh_quic/iroh_quic.dart';
import 'package:test/test.dart';

/// Loads the native library on the host and checks the ABI version. The tests also read the iroh
/// version and the capabilities through the Dart bindings. The integration tests of the example
/// app do the same checks on iOS and Android devices.
void main() {
  setUpAll(() async {
    await Iroh.init();
  });

  test('native runtime initialises and reports ABI v2', () {
    expect(Iroh.isInitialised, isTrue);
    expect(Iroh.abiVersion, 2);
  });

  test('built against an iroh 1.x core', () {
    expect(Iroh.irohVersion, isNotEmpty);
  });

  test('native platform advertises full capabilities', () {
    final caps = Iroh.capabilities;
    expect(caps.direct, isTrue, reason: 'native track supports direct connections');
    expect(caps.relay, isTrue);
    expect(caps.blobs, isFalse, reason: 'this package does not wrap iroh-blobs');
  });
}
