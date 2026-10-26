part of 'endpoint.dart';

/// A QUIC connection to a remote endpoint. Use it to open and accept streams, to send and receive
/// datagrams, and to see when the connection closes. Streams are **lazy**. The peer does not see a
/// new [SendStream] until the first [SendStream.writeAll].
final class Connection {
  Connection._(this._inner);

  final ffi_net.Connection _inner;

  /// The [EndpointId] of the remote endpoint.
  EndpointId get remoteId => PublicKey.fromBytes(_inner.remoteId());

  /// The bytes of the ALPN protocol that the two endpoints agreed on.
  Uint8List get alpn => _inner.alpn();

  /// An identifier for this connection. It does not change while the process runs.
  int get stableId => _inner.stableId().toInt();

  /// Returns the current values of the connection counters.
  ConnectionStats get stats {
    final s = _inner.stats();
    return ConnectionStats(
      udpTxDatagrams: s.udpTxDatagrams.toInt(),
      udpTxBytes: s.udpTxBytes.toInt(),
      udpRxDatagrams: s.udpRxDatagrams.toInt(),
      udpRxBytes: s.udpRxBytes.toInt(),
      sentPackets: s.sentPackets.toInt(),
      sentBytes: s.sentBytes.toInt(),
      lostPackets: s.lostPackets.toInt(),
      lostBytes: s.lostBytes.toInt(),
    );
  }

  /// Opens a new bidirectional stream and returns its `(send, recv)` pair.
  /// Throws [IrohConnectionException] on failure.
  Future<(SendStream, RecvStream)> openBi() async {
    final (s, r) = await _connWrap(() => _inner.openBi());
    return (SendStream._(s), RecvStream._(r));
  }

  /// Opens a new unidirectional stream and returns its send stream.
  /// Throws [IrohConnectionException] on failure.
  Future<SendStream> openUni() async => SendStream._(await _connWrap(() => _inner.openUni()));

  /// Waits for the next bidirectional stream from the peer and returns its `(send, recv)` pair.
  /// Throws [IrohConnectionException] on failure.
  Future<(SendStream, RecvStream)> acceptBi() async {
    final (s, r) = await _connWrap(() => _inner.acceptBi());
    return (SendStream._(s), RecvStream._(r));
  }

  /// Waits for the next unidirectional stream from the peer and returns its receive stream.
  /// Throws [IrohConnectionException] on failure.
  Future<RecvStream> acceptUni() async => RecvStream._(await _connWrap(() => _inner.acceptUni()));

  /// Sends [data] as one unreliable, unordered datagram. Throws [IrohConnectionException] if the
  /// datagram is too large, or if the connection does not support datagrams.
  void sendDatagram(List<int> data) {
    try {
      _inner.sendDatagram(data: data);
    } on AnyhowException catch (e) {
      throw IrohConnectionException(e.message, cause: e);
    }
  }

  /// Waits for the next application datagram and returns it.
  /// Throws [IrohConnectionException] on failure.
  Future<Uint8List> readDatagram() => _connWrap(() => _inner.readDatagram());

  /// Sends a batch of unreliable, unordered datagrams in one call. Returns the number of datagrams
  /// that iroh put in its queue. This has less overhead than one [sendDatagram] call for each
  /// datagram. If one datagram is too large, iroh refuses the full batch. Then this method throws
  /// an [IrohConnectionException].
  int sendManyDatagrams(List<List<int>> datagrams) {
    try {
      return _inner
          .sendManyDatagrams(datagrams: datagrams.map(Uint8List.fromList).toList())
          .toInt();
    } on AnyhowException catch (e) {
      throw IrohConnectionException(e.message, cause: e);
    }
  }

  /// Receives a batch of application datagrams in arrival order. This method waits until at least
  /// one datagram is available. Then it returns a maximum of [maxCount] datagrams. If [maxCount]
  /// is zero, it returns an empty list immediately. Throws [RangeError] if [maxCount] is negative,
  /// and [IrohConnectionException] on failure.
  Future<List<Uint8List>> readManyDatagrams({int maxCount = 64}) {
    RangeError.checkNotNegative(maxCount, 'maxCount');
    return _connWrap(() => _inner.readManyDatagrams(maxCount: BigInt.from(maxCount)));
  }

  /// Completes when the connection closes. The value is the close reason as text.
  Future<String> closed() => _inner.closed();

  /// Closes the connection immediately with an application [errorCode] and [reason].
  void close({int errorCode = 0, List<int> reason = const <int>[]}) =>
      _inner.close(errorCode: errorCode, reason: reason);

  /// Returns a [Stream] of [PathEvent]s for this connection. A change between a relay path and a
  /// direct path shows as a [PathSelected] event. When you cancel the subscription, the Rust task
  /// that sends the events stops.
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

/// The values of some connection counters at one time. [Connection.stats] returns this object.
final class ConnectionStats {
  /// Makes a set of connection counters from the given values.
  const ConnectionStats({
    required this.udpTxDatagrams,
    required this.udpTxBytes,
    required this.udpRxDatagrams,
    required this.udpRxBytes,
    this.sentPackets = 0,
    this.sentBytes = 0,
    this.lostPackets = 0,
    this.lostBytes = 0,
  });

  /// Datagrams sent at the UDP layer.
  final int udpTxDatagrams;

  /// Bytes sent at the UDP layer.
  final int udpTxBytes;

  /// Datagrams received at the UDP layer.
  final int udpRxDatagrams;

  /// Bytes received at the UDP layer.
  final int udpRxBytes;

  /// QUIC packets sent on all paths. One UDP datagram can contain more than one QUIC packet.
  final int sentPackets;

  /// QUIC payload bytes sent on all paths. This value does not include the UDP and IP headers.
  final int sentBytes;

  /// QUIC packets lost on all paths.
  final int lostPackets;

  /// QUIC payload bytes lost on all paths.
  final int lostBytes;

  @override
  String toString() =>
      'ConnectionStats(txDatagrams: $udpTxDatagrams, '
      'txBytes: $udpTxBytes, rxDatagrams: $udpRxDatagrams, rxBytes: $udpRxBytes, '
      'sentPackets: $sentPackets, sentBytes: $sentBytes, '
      'lostPackets: $lostPackets, lostBytes: $lostBytes)';
}

Future<T> _connWrap<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on AnyhowException catch (e) {
    throw IrohConnectionException(e.message, cause: e);
  }
}

/// An incoming connection that the endpoint did not accept yet. Read [remoteAddr], then call one
/// of [accept], [refuse], [retry], or [ignore]. Call only one of these methods, and only one time.
final class Incoming {
  Incoming._(this._inner);

  final ffi_net.Incoming _inner;

  /// The address of the remote endpoint that started this connection, as debug text.
  String get remoteAddr => _inner.remoteAddr();

  /// Accepts the connection, completes the handshake, and returns the [Connection].
  /// Throws [IrohAcceptException] on failure.
  Future<Connection> accept() async {
    try {
      return Connection._(await _inner.accept());
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }

  /// Refuses the connection. The connect attempt of the peer fails.
  /// Throws [IrohAcceptException] on failure.
  void refuse() => _decide(_inner.refuse);

  /// Sends a QUIC retry packet. The peer must then prove its address and connect again. iroh does
  /// this step automatically. Throws [IrohAcceptException] on failure.
  void retry() => _decide(_inner.retry);

  /// Ignores the connection. The endpoint sends no packet to the peer.
  /// Throws [IrohAcceptException] on failure.
  void ignore() => _decide(_inner.ignore);

  void _decide(void Function() action) {
    try {
      action();
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }
}
