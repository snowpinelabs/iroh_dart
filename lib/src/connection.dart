part of 'endpoint.dart';

/// An established QUIC connection to a remote endpoint. Open or accept streams,
/// exchange datagrams, and observe closure. Streams are **lazy**: a freshly opened [SendStream]
/// is invisible to the peer until the first [SendStream.writeAll].
final class Connection {
  Connection._(this._inner);

  final ffi_net.Connection _inner;

  /// The remote peer's [EndpointId].
  EndpointId get remoteId => PublicKey.fromBytes(_inner.remoteId());

  /// The negotiated ALPN protocol bytes.
  Uint8List get alpn => _inner.alpn();

  /// A process-stable identifier for this connection.
  int get stableId => _inner.stableId().toInt();

  /// A snapshot of connection counters.
  ConnectionStats get stats {
    final s = _inner.stats();
    return ConnectionStats(
      udpTxDatagrams: s.udpTxDatagrams.toInt(),
      udpTxBytes: s.udpTxBytes.toInt(),
      udpRxDatagrams: s.udpRxDatagrams.toInt(),
      udpRxBytes: s.udpRxBytes.toInt(),
    );
  }

  /// Opens a new bidirectional stream `(send, recv)`.
  Future<(SendStream, RecvStream)> openBi() async {
    final (s, r) = await _connWrap(() => _inner.openBi());
    return (SendStream._(s), RecvStream._(r));
  }

  /// Opens a new unidirectional (send-only) stream.
  Future<SendStream> openUni() async => SendStream._(await _connWrap(() => _inner.openUni()));

  /// Accepts the next incoming bidirectional stream `(send, recv)`.
  Future<(SendStream, RecvStream)> acceptBi() async {
    final (s, r) = await _connWrap(() => _inner.acceptBi());
    return (SendStream._(s), RecvStream._(r));
  }

  /// Accepts the next incoming unidirectional (receive-only) stream.
  Future<RecvStream> acceptUni() async => RecvStream._(await _connWrap(() => _inner.acceptUni()));

  /// Sends an unreliable, unordered datagram. Throws [IrohConnectionException] if it is too large
  /// or datagrams are unsupported on this connection.
  void sendDatagram(List<int> data) {
    try {
      _inner.sendDatagram(data: data);
    } on AnyhowException catch (e) {
      throw IrohConnectionException(e.message, cause: e);
    }
  }

  /// Receives the next application datagram.
  Future<Uint8List> readDatagram() => _connWrap(() => _inner.readDatagram());

  /// Resolves when the connection closes, with the human-readable close reason.
  Future<String> closed() => _inner.closed();

  /// Closes the connection immediately with an application [errorCode] and [reason].
  void close({int errorCode = 0, List<int> reason = const <int>[]}) =>
      _inner.close(errorCode: errorCode, reason: reason);

  /// A live [Stream] of [PathEvent]s for this connection. The relay/direct transition
  /// surfaces as [PathSelected]. Cancelling the subscription drops the underlying event stream.
  Stream<PathEvent> pathEvents() =>
      _cancellableStream((token) => _inner.pathEvents(token: token), _pathEventFromInfo);
}

PathEvent _pathEventFromInfo(ffi_watch.PathEventInfo e) => switch (e.kind) {
  ffi_watch.PathEventKind.opened => PathOpened(e.remoteAddr ?? ''),
  ffi_watch.PathEventKind.closed => PathClosed(e.remoteAddr ?? ''),
  ffi_watch.PathEventKind.selected => PathSelected(e.remoteAddr ?? ''),
  ffi_watch.PathEventKind.lagged => PathLagged(e.missed?.toInt() ?? 0),
  ffi_watch.PathEventKind.unknown => const PathUnknown(),
};

/// A snapshot of a few useful connection counters (`stats`).
final class ConnectionStats {
  const ConnectionStats({
    required this.udpTxDatagrams,
    required this.udpTxBytes,
    required this.udpRxDatagrams,
    required this.udpRxBytes,
  });

  /// Datagrams sent at the UDP layer.
  final int udpTxDatagrams;

  /// Bytes sent at the UDP layer.
  final int udpTxBytes;

  /// Datagrams received at the UDP layer.
  final int udpRxDatagrams;

  /// Bytes received at the UDP layer.
  final int udpRxBytes;

  @override
  String toString() =>
      'ConnectionStats(txDatagrams: $udpTxDatagrams, '
      'txBytes: $udpTxBytes, rxDatagrams: $udpRxDatagrams, rxBytes: $udpRxBytes)';
}

Future<T> _connWrap<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on AnyhowException catch (e) {
    throw IrohConnectionException(e.message, cause: e);
  }
}

/// An inbound connection that has not yet been accepted. Inspect [remoteAddr] and then
/// choose [accept], [refuse], [retry], or [ignore] - the Dart-driven incoming filter. Each
/// instance may be decided exactly once.
final class Incoming {
  Incoming._(this._inner);

  final ffi_net.Incoming _inner;

  /// A debug rendering of the remote address that initiated this connection.
  String get remoteAddr => _inner.remoteAddr();

  /// Accepts the connection, completing the handshake.
  Future<Connection> accept() async {
    try {
      return Connection._(await _inner.accept());
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }

  /// Refuses the connection; the peer's connect attempt fails.
  void refuse() => _decide(_inner.refuse);

  /// Responds with a retry packet; the peer transparently reconnects.
  void retry() => _decide(_inner.retry);

  /// Ignores the connection, sending no packet.
  void ignore() => _decide(_inner.ignore);

  void _decide(void Function() action) {
    try {
      action();
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }
}
