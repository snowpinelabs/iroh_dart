/// The set of iroh features that this binding makes available.
///
/// Read these flags before you use a feature. Then you do not get an [IrohUnsupportedException]
/// at the call. All supported platforms (iOS, Android, macOS, Windows, Linux) have the full native
/// feature set. This package does not wrap iroh-blobs.
final class IrohCapabilities {
  const IrohCapabilities({required this.direct, required this.relay, required this.blobs});

  /// The native feature set: direct (hole-punched) connections and relayed connections. No blobs.
  const IrohCapabilities.native() : direct = true, relay = true, blobs = false;

  /// Returns the capabilities of the current platform.
  factory IrohCapabilities.current() => const IrohCapabilities.native();

  /// Whether direct, hole-punched peer-to-peer connections are available.
  final bool direct;

  /// Whether connections through a relay server are available.
  final bool relay;

  /// Whether iroh-blobs content transfer is available. This package does not wrap iroh-blobs, so
  /// [IrohCapabilities.native] sets this flag to `false`.
  final bool blobs;

  @override
  String toString() => 'IrohCapabilities(direct: $direct, relay: $relay, blobs: $blobs)';
}
