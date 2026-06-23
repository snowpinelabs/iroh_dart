part of 'endpoint.dart';

/// The send half of a QUIC stream. Backed by noq's `SendStream`. A stream is invisible
/// to the peer until the first [writeAll] (the lazy-stream footgun).
final class SendStream {
  SendStream._(this._inner);

  final ffi_net.SendStream _inner;

  /// The QUIC stream id.
  int get id => _inner.id().toInt();

  /// Writes all of [data], applying backpressure as needed.
  Future<void> writeAll(List<int> data) => _streamWrap(() => _inner.writeAll(data: data));

  /// Finishes the stream cleanly, signalling end-of-data to the peer.
  Future<void> finish() => _streamWrap(() => _inner.finish());

  /// Resets the stream, abandoning unacknowledged data with [errorCode].
  Future<void> reset(int errorCode) => _streamWrap(() => _inner.reset(errorCode: errorCode));
}

/// The receive half of a QUIC stream. Backed by noq's `RecvStream`.
final class RecvStream {
  RecvStream._(this._inner);

  final ffi_net.RecvStream _inner;

  /// The QUIC stream id.
  int get id => _inner.id().toInt();

  /// Reads up to [maxLen] bytes; returns the bytes read, or `null` at end-of-stream.
  Future<Uint8List?> read(int maxLen) =>
      _streamWrap(() => _inner.read(maxLen: BigInt.from(maxLen)));

  /// Reads exactly [len] bytes, erroring if the stream ends early.
  Future<Uint8List> readExact(int len) =>
      _streamWrap(() => _inner.readExact(len: BigInt.from(len)));

  /// Reads to end-of-stream, up to [sizeLimit] bytes.
  Future<Uint8List> readToEnd(int sizeLimit) =>
      _streamWrap(() => _inner.readToEnd(sizeLimit: BigInt.from(sizeLimit)));

  /// Asks the peer to stop sending on this stream with [errorCode].
  Future<void> stop(int errorCode) => _streamWrap(() => _inner.stop(errorCode: errorCode));
}

Future<T> _streamWrap<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on AnyhowException catch (e) {
    throw IrohStreamException(e.message, cause: e);
  }
}
