/// Reactive state as Dart `Stream`s. Value types emitted by `Endpoint.watchAddr`,
/// `Endpoint.homeRelayStatus`, and `Connection.pathEvents`. The streams are driven by FRB
/// `StreamSink`s; cancelling a subscription drops the underlying iroh watcher (no leak).
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

  /// Whether the endpoint is currently connected to this relay.
  final bool connected;

  /// The most recent connection error, for logs or display only. Do not match on the text.
  final String? lastError;

  /// The reason that the relay server gave when it denied the authentication of this endpoint.
  /// Retries do not usually correct this failure, so show it to the user. It is `null` when the
  /// relay is connected, when no attempt failed, or when the last failure had a different cause.
  final String? authDeniedReason;

  @override
  String toString() =>
      'RelayStatus($url, connected: $connected'
      '${lastError == null ? '' : ', error: $lastError'}'
      '${authDeniedReason == null ? '' : ', authDenied: $authDeniedReason'})';
}

/// A path lifecycle event on a [Connection]. Sealed: switch over the subtypes. The
/// relay-vs-direct transition is observable as a [PathSelected] carrying the new active address.
sealed class PathEvent {
  const PathEvent();
}

/// A new network path was opened to [remoteAddr].
final class PathOpened extends PathEvent {
  const PathOpened(this.remoteAddr);

  /// Debug rendering of the remote transport address.
  final String remoteAddr;
}

/// The network path to [remoteAddr] was closed.
final class PathClosed extends PathEvent {
  const PathClosed(this.remoteAddr);

  /// Debug rendering of the remote transport address.
  final String remoteAddr;
}

/// [remoteAddr] became the selected (active) path - a relay/direct transition.
final class PathSelected extends PathEvent {
  const PathSelected(this.remoteAddr);

  /// Debug rendering of the now-active remote transport address.
  final String remoteAddr;
}

/// Path events were dropped because the consumer fell behind; [missed] were lost.
final class PathLagged extends PathEvent {
  const PathLagged(this.missed);

  /// Number of path events that were dropped.
  final int missed;
}

/// A future iroh path-event variant not yet modelled by this binding (forward-compatibility).
final class PathUnknown extends PathEvent {
  const PathUnknown();
}
