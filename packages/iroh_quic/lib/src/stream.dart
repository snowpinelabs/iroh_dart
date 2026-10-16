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
