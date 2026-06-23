/// Flutter plugin for **iroh 1.0** - peer-to-peer QUIC networking on Android, iOS, macOS, Linux,
/// and Windows.
///
/// This package adds the per-platform native build (the Rust `irohdart_ffi` core, compiled into your
/// app via cargokit) to the pure-Dart [`iroh_quic`](https://pub.dev/packages/iroh_quic) binding. The
/// entire public API — [Iroh], [Endpoint], [SecretKey], `addressLookup`, … — is re-exported here, so
/// a Flutter app only needs to depend on `iroh_flutter` and:
///
/// ```dart
/// import 'package:iroh_flutter/iroh_flutter.dart';
///
/// await Iroh.init(); // the native lib is bundled by the plugin build; no setup step needed
/// ```
///
/// On desktop you may use `iroh_quic` directly with a prebuilt download (`dart run iroh_quic:setup`);
/// inside a Flutter app, this plugin builds and bundles the library automatically.
library;

export 'package:iroh_quic/iroh_quic.dart';
