/// Flutter plugin for **iroh 1.x**: peer-to-peer QUIC networking on Android, iOS, macOS, Linux,
/// and Windows.
///
/// This plugin adds the native build for each platform to the pure-Dart
/// [`iroh_quic`](https://pub.dev/packages/iroh_quic) binding. cargokit compiles the crate
/// `irohdart_ffi` into your app. This library exports the full public API of `iroh_quic`, for
/// example [Iroh], [Endpoint], [EndpointAddr], and [SecretKey]. Thus, a Flutter app needs only one
/// dependency, `iroh_flutter`:
///
/// ```dart
/// import 'package:iroh_flutter/iroh_flutter.dart';
///
/// await Iroh.init(); // The plugin build includes the native library. No other step is necessary.
/// ```
///
/// On desktop, you can use `iroh_quic` directly with a prebuilt library
/// (`dart run iroh_quic:setup`). In a Flutter app, this plugin builds and includes the native
/// library automatically.
library;

export 'package:iroh_quic/iroh_quic.dart';
