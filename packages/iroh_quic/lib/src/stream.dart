part of 'endpoint.dart';

/// The send stream of a QUIC stream. It wraps the noq `SendStream`. The peer does not see a new
/// stream until the first [writeAll]. Thus a peer that waits to accept the stream receives nothing
/// before that write.
final class SendStream {
  SendStream._(this._inner);

  final ffi_net.SendStream _inner;

  /// The QUIC stream ID.
  int get id => _inner.id().toInt();

  /// Writes all of [data]. If the peer is slow, this method waits for flow control.
  /// Throws [IrohStreamException] on failure.
  Future<void> writeAll(List<int> data) => _streamWrap(() => _inner.writeAll(data: data));

  /// Finishes the stream and tells the peer that no more data comes.
  /// Throws [IrohStreamException] on failure.
  Future<void> finish() => _streamWrap(() => _inner.finish());

  /// Resets the stream with [errorCode]. The stream does not send the data that the peer did not
  /// acknowledge. Throws [IrohStreamException] on failure.
  Future<void> reset(int errorCode) => _streamWrap(() => _inner.reset(errorCode: errorCode));

  /// Sets the network paths that can carry the data of this stream. The default is
  /// [StreamAffinity.any].
  ///
  /// Use [StreamAffinity.sticky] to send the data only on one path, for example a direct path
  /// from [Connection.waitAnyPath]. If that path closes, the data stops until you set a different
  /// affinity. Use [Connection.waitPathClosed] to see when the path closes.
  ///
  /// [StreamAffinity.block] stops the data on all paths. Blocked data still uses the send window
  /// of the connection, so use it only as a last resort. It is better to open the stream after the
  /// necessary path is available.
  ///
  /// This method does not wait for a [writeAll] that is in progress, so you can call it while a
  /// write waits on a blocked path. Throws [IrohStreamException] if the stream is closed, and
  /// [RangeError] if the path ID of a sticky affinity is not a 32-bit unsigned value.
  void setAffinity(StreamAffinity affinity) {
    try {
      switch (affinity) {
        case StreamAffinityAny():
          _inner.setAffinity(kind: ffi_net.StreamAffinityKind.any);
        case StreamAffinitySticky(:final path):
          RangeError.checkValueInInterval(path.value, 0, 0xFFFFFFFF, 'path');
          _inner.setAffinity(kind: ffi_net.StreamAffinityKind.sticky, pathId: path.value);
        case StreamAffinityBlock():
          _inner.setAffinity(kind: ffi_net.StreamAffinityKind.block);
      }
    } on AnyhowException catch (e) {
      throw IrohStreamException(e.message, cause: e);
    }
  }
}

/// The network paths that can carry the data of a [SendStream]. Give it to
/// [SendStream.setAffinity]. The class is sealed, so use a `switch` on the subtypes.
///
/// The affinity applies only to the data of the stream. The connection can send other QUIC frames
/// on all paths. If the connection stops all packets on a path, for example because of packet
/// loss, a stream that is sticky to that path cannot send its data.
sealed class StreamAffinity {
  const StreamAffinity._();

  /// The connection selects the path for the data. This is the default affinity.
  static const StreamAffinity any = StreamAffinityAny._();

  /// No path carries the data of the stream.
  static const StreamAffinity block = StreamAffinityBlock._();

  /// Only the path with the ID [path] carries the data of the stream.
  const factory StreamAffinity.sticky(PathId path) = StreamAffinitySticky;
}

/// The connection selects the path for the data. See [StreamAffinity.any].
final class StreamAffinityAny extends StreamAffinity {
  const StreamAffinityAny._() : super._();

  @override
  String toString() => 'StreamAffinity.any';
}

/// Only one path carries the data of the stream. See [StreamAffinity.sticky].
final class StreamAffinitySticky extends StreamAffinity {
  /// Makes a sticky affinity for the path with the ID [path].
  const StreamAffinitySticky(this.path) : super._();

  /// The ID of the path that carries the data.
  final PathId path;

  @override
  bool operator ==(Object other) => other is StreamAffinitySticky && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'StreamAffinity.sticky(${path.value})';
}

/// No path carries the data of the stream. See [StreamAffinity.block].
final class StreamAffinityBlock extends StreamAffinity {
  const StreamAffinityBlock._() : super._();

  @override
  String toString() => 'StreamAffinity.block';
}

/// The receive stream of a QUIC stream. It wraps the noq `RecvStream`.
final class RecvStream {
  RecvStream._(this._inner);

  final ffi_net.RecvStream _inner;

  /// The QUIC stream ID.
  int get id => _inner.id().toInt();

  /// Reads a maximum of [maxLen] bytes and returns them. Returns `null` at the end of the stream.
  /// Throws [IrohStreamException] on failure.
  Future<Uint8List?> read(int maxLen) =>
      _streamWrap(() => _inner.read(maxLen: BigInt.from(maxLen)));

  /// Reads exactly [len] bytes and returns them. Throws [IrohStreamException] if the stream ends
  /// before [len] bytes, or on a different failure.
  Future<Uint8List> readExact(int len) =>
      _streamWrap(() => _inner.readExact(len: BigInt.from(len)));

  /// Reads all bytes until the end of the stream and returns them. Throws [IrohStreamException]
  /// if the data is more than [sizeLimit] bytes, or on a different failure.
  Future<Uint8List> readToEnd(int sizeLimit) =>
      _streamWrap(() => _inner.readToEnd(sizeLimit: BigInt.from(sizeLimit)));

  /// Tells the peer to stop the data on this stream, with [errorCode].
  /// Throws [IrohStreamException] on failure.
  Future<void> stop(int errorCode) => _streamWrap(() => _inner.stop(errorCode: errorCode));
}

Future<T> _streamWrap<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on AnyhowException catch (e) {
    throw IrohStreamException(e.message, cause: e);
  }
}
