/// The value types that the watch streams send: `Endpoint.watchAddr`, `Endpoint.homeRelayStatus`,
/// `Connection.pathEvents`, and `Connection.pathsStream`. An FRB `StreamSink` in the crate gives the
/// values to each stream. When you cancel a subscription, the crate stops the iroh watcher.
library;

/// A relay server's connection status, emitted by `Endpoint.homeRelayStatus`.
final class RelayStatus {
  const RelayStatus({
    required this.url,
    required this.connected,
    this.lastError,
    this.authDeniedReason,
  });

  /// The relay server URL.
  final String url;

  /// Whether the endpoint has a connection to this relay server at this time.
  final bool connected;

  /// The last connection error. Use it only for logs or display. Do not compare the text in code.
  final String? lastError;

  /// The reason that the relay server gave when it denied the authentication of this endpoint.
  /// Retries do not usually correct this failure, so show it to the user. It is `null` if the
  /// relay server is connected, if no attempt failed, or if the last failure had a different cause.
  final String? authDeniedReason;

  @override
  String toString() =>
      'RelayStatus($url, connected: $connected'
      '${lastError == null ? '' : ', error: $lastError'}'
      '${authDeniedReason == null ? '' : ', authDenied: $authDeniedReason'})';
}

/// The ID of a network path in one `Connection`. It is the QUIC multipath path ID.
///
/// A path ID is unique in its connection, and the connection does not use it again after the path
/// closes. [PathInfo.id] and the [PathEvent] subtypes contain path IDs. A sticky `StreamAffinity`
/// uses a path ID to select the path of a send stream.
final class PathId {
  /// Makes a path ID from its numeric [value]. The value must be in the range of an unsigned
  /// 32-bit integer.
  const PathId(this.value) : assert(value >= 0 && value <= 0xFFFFFFFF);

  /// The numeric value of the path ID.
  final int value;

  @override
  bool operator ==(Object other) => other is PathId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PathId($value)';
}

/// An open network path of a `Connection`. `Connection.paths` and `Connection.pathsStream` return
/// these values. Each value is a snapshot, and it does not change when the path changes.
final class PathInfo {
  /// Makes a path snapshot from the given values.
  const PathInfo({
    required this.id,
    required this.remoteAddr,
    required this.isIp,
    required this.isRelay,
    required this.isSelected,
    required this.rtt,
  });

  /// The ID of the path. Give it to `StreamAffinity.sticky` to send the data of a stream only on
  /// this path.
  final PathId id;

  /// The remote transport address, as debug text.
  final String remoteAddr;

  /// Whether the path is a direct IP path.
  final bool isIp;

  /// Whether the path goes through a relay server.
  final bool isRelay;

  /// Whether the connection uses this path for application data at the time of the snapshot.
  final bool isSelected;

  /// The round-trip time estimate of the path at the time of the snapshot.
  final Duration rtt;

  @override
  String toString() =>
      'PathInfo(${id.value}, $remoteAddr, ${isIp
          ? 'ip'
          : isRelay
          ? 'relay'
          : 'other'}'
      '${isSelected ? ', selected' : ''}, rtt: $rtt)';
}

/// An event about the network paths of a [Connection]. The class is sealed, so use a `switch` on
/// the subtypes. A change between a relay path and a direct path shows as a [PathSelected] event.
/// That event contains the new active address.
sealed class PathEvent {
  const PathEvent();
}

/// The connection opened a new network path to [remoteAddr].
final class PathOpened extends PathEvent {
  const PathOpened(this.remoteAddr, {this.id});

  /// The ID of the path. The binding always sets it. It is `null` only for an event that you
  /// make yourself without an ID.
  final PathId? id;

  /// The remote transport address, as debug text.
  final String remoteAddr;
}

/// The network path to [remoteAddr] closed.
final class PathClosed extends PathEvent {
  const PathClosed(this.remoteAddr, {this.id});

  /// The ID of the path. The binding always sets it. It is `null` only for an event that you
  /// make yourself without an ID.
  final PathId? id;

  /// The remote transport address, as debug text.
  final String remoteAddr;
}

/// The connection selected the path to [remoteAddr] as its active path. For example, this event
/// shows a change from a relay path to a direct path.
final class PathSelected extends PathEvent {
  const PathSelected(this.remoteAddr, {this.id});

  /// The ID of the path. The binding always sets it. It is `null` only for an event that you
  /// make yourself without an ID.
  final PathId? id;

  /// The remote transport address of the active path, as debug text.
  final String remoteAddr;
}

/// The stream did not send some path events because the listener was too slow. [missed] tells
/// how many events the stream did not send.
final class PathLagged extends PathEvent {
  const PathLagged(this.missed);

  /// The number of path events that the stream did not send.
  final int missed;
}

/// A path event from iroh that this binding does not know. It keeps the binding compatible with
/// new iroh versions.
final class PathUnknown extends PathEvent {
  const PathUnknown();
}
