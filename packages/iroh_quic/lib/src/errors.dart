/// The exception hierarchy for `iroh_quic`.
///
/// Each wrapper method that can fail throws a subtype of [IrohException]. The subtype tells which
/// operation failed: load, key, bind, connect, accept, connection, or stream. The message contains
/// the text of the Rust error.
///
/// The wrapper methods convert each Rust error from FRB into an [IrohException]. They do not
/// throw the generated FRB error types.
library;

/// Base class for every error raised by the iroh_quic binding.
sealed class IrohException implements Exception {
  const IrohException(this.message, {this.cause});

  /// A description of the error. If the error comes from iroh, this is the text of the iroh error.
  final String message;

  /// The original error, if this exception wraps an error from a lower layer.
  final Object? cause;

  /// A short tag for the error type. [toString] shows it. Each subclass gives its own tag.
  String get kind;

  @override
  String toString() => 'IrohException($kind): $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// The native library did not load, or its ABI version is not the ABI version of the Dart
/// bindings. The loader refuses a native library with a different ABI version.
final class IrohLoadException extends IrohException {
  const IrohLoadException(super.message, {super.cause});
  @override
  String get kind => 'load';
}

/// A key, endpoint ID, endpoint address, or relay URL is not valid.
final class IrohKeyException extends IrohException {
  const IrohKeyException(super.message, {super.cause});
  @override
  String get kind => 'key';
}

/// An endpoint did not bind. The cause can be the sockets, the QUIC endpoint, the crypto provider,
/// or the TLS configuration.
final class IrohBindException extends IrohException {
  const IrohBindException(super.message, {super.cause});
  @override
  String get kind => 'bind';
}

/// `Endpoint.connect` failed before the [Connection] was ready.
final class IrohConnectException extends IrohException {
  const IrohConnectException(super.message, {super.cause});
  @override
  String get kind => 'connect';
}

/// An accept operation failed. Examples are [Endpoint.accept], [Incoming.accept], and the
/// registration or the start of a [Router].
final class IrohAcceptException extends IrohException {
  const IrohAcceptException(super.message, {super.cause});
  @override
  String get kind => 'accept';
}

/// An operation on an open connection failed, or the connection closed unexpectedly.
/// [Router.shutdown] also throws this exception.
final class IrohConnectionException extends IrohException {
  const IrohConnectionException(super.message, {super.cause});
  @override
  String get kind => 'connection';
}

/// An operation on a send stream or a receive stream failed (read, write, finish, reset, or stop).
final class IrohStreamException extends IrohException {
  const IrohStreamException(super.message, {super.cause});
  @override
  String get kind => 'stream';
}

/// The current capability set does not support the operation. For example, this package does not
/// wrap iroh-blobs. This class is different from [UnsupportedError], so callers can catch it as an
/// [IrohException].
final class IrohUnsupportedException extends IrohException {
  const IrohUnsupportedException(super.message, {super.cause});
  @override
  String get kind => 'unsupported';
}
