/// Structured exception hierarchy for `iroh_dart`.
///
/// iroh surfaces `n0_error` enums (`BindError`, `ConnectError`, `AcceptError`,
/// `ConnectionError`, plus noq stream errors). We map them onto this hierarchy rather than
/// flattening to strings, so callers can branch on the retry / refuse / 0-RTT-rejected
/// distinctions that matter for connection logic.
///
/// Every wrapper method that can fail throws a subtype of [IrohException]; FRB-reported Rust
/// errors are converted at the wrapper boundary, never leaked as raw generated types.
library;

/// Base class for every error raised by the iroh_dart binding.
sealed class IrohException implements Exception {
  const IrohException(this.message, {this.cause});

  /// Human-readable description (forwarded from the underlying iroh error where available).
  final String message;

  /// The originating error, when this exception wraps a lower-level cause.
  final Object? cause;

  /// Short, stable tag used in [toString]; subclasses override.
  String get kind;

  @override
  String toString() => 'IrohException($kind): $message${cause == null ? '' : ' (cause: $cause)'}';
}

/// The native library could not be loaded, or its ABI version does not match what this Dart
/// package was generated against (refuse-on-mismatch handshake).
final class IrohLoadException extends IrohException {
  const IrohLoadException(super.message, {super.cause});
  @override
  String get kind => 'load';
}

/// A key/address could not be parsed or is malformed (identity & addressing).
final class IrohKeyException extends IrohException {
  const IrohKeyException(super.message, {super.cause});
  @override
  String get kind => 'key';
}

/// `Endpoint.bind` failed (sockets, QUIC endpoint, crypto provider, TLS config).
final class IrohBindException extends IrohException {
  const IrohBindException(super.message, {super.cause});
  @override
  String get kind => 'bind';
}

/// `endpoint.connect` failed before a [Connection] was established.
final class IrohConnectException extends IrohException {
  const IrohConnectException(super.message, {super.cause});
  @override
  String get kind => 'connect';
}

/// An inbound connection could not be accepted (accept loop).
final class IrohAcceptException extends IrohException {
  const IrohAcceptException(super.message, {super.cause});
  @override
  String get kind => 'accept';
}

/// An established connection failed or was closed unexpectedly.
final class IrohConnectionException extends IrohException {
  const IrohConnectionException(super.message, {super.cause});
  @override
  String get kind => 'connection';
}

/// A stream read/write/finish/stop operation failed (noq SendStream/RecvStream).
final class IrohStreamException extends IrohException {
  const IrohStreamException(super.message, {super.cause});
  @override
  String get kind => 'stream';
}

/// The operation is not supported in the current capability set - e.g. iroh-blobs, which is not
/// wrapped in v1. Distinct from [UnsupportedError] so callers can catch it within the
/// [IrohException] hierarchy.
final class IrohUnsupportedException extends IrohException {
  const IrohUnsupportedException(super.message, {super.cause});
  @override
  String get kind => 'unsupported';
}
