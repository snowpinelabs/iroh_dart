/// The value types that the watch streams send: `Endpoint.watchAddr`, `Endpoint.homeRelayStatus`,
/// and `Connection.pathEvents`. An FRB `StreamSink` in the crate gives the values to each stream.
/// When you cancel a subscription, the crate stops the iroh watcher.
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

/// An event about the network paths of a [Connection]. The class is sealed, so use a `switch` on
/// the subtypes. A change between a relay path and a direct path shows as a [PathSelected] event.
/// That event contains the new active address.
sealed class PathEvent {
  const PathEvent();
}

/// The connection opened a new network path to [remoteAddr].
final class PathOpened extends PathEvent {
  const PathOpened(this.remoteAddr);

  /// The remote transport address, as debug text.
  final String remoteAddr;
}

/// The network path to [remoteAddr] closed.
final class PathClosed extends PathEvent {
  const PathClosed(this.remoteAddr);

  /// The remote transport address, as debug text.
  final String remoteAddr;
}

/// The connection selected the path to [remoteAddr] as its active path. For example, this event
/// shows a change from a relay path to a direct path.
final class PathSelected extends PathEvent {
  const PathSelected(this.remoteAddr);

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
