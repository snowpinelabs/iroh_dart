/// The set of iroh features available to this binding.
///
/// Exposes which capabilities the API supports so callers can check before using one rather than
/// discovering an [IrohUnsupportedException] at the call site. The supported platforms (iOS,
/// Android, macOS, Windows, Linux) all offer the full native feature set; iroh-blobs is not wrapped
/// in v1.
final class IrohCapabilities {
  const IrohCapabilities({required this.direct, required this.relay, required this.blobs});

  /// The native feature set: direct (hole-punched) and relayed connections, no blobs.
  const IrohCapabilities.native() : direct = true, relay = true, blobs = false;

  /// Capabilities for the platform this code is running on.
  factory IrohCapabilities.current() => const IrohCapabilities.native();

  /// Whether direct, hole-punched peer-to-peer connections are available.
  final bool direct;

  /// Whether relayed connections (via a relay server) are available.
  final bool relay;

  /// Whether iroh-blobs content transfer is available. `false` in v1 (not yet wrapped).
  final bool blobs;

  @override
  String toString() => 'IrohCapabilities(direct: $direct, relay: $relay, blobs: $blobs)';
}
