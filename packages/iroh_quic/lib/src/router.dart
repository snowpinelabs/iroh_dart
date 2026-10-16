part of 'endpoint.dart';

/// Makes a multi-protocol [Router]. Call [accept] to register one Dart handler for each ALPN, then
/// call [spawn]. The iroh `Router` runs the accept loop in Rust. It calls your Dart handler for
/// each incoming [Connection] on the ALPN of that handler.
final class RouterBuilder {
  RouterBuilder._(this._inner);

  final ffi_router.RouterBuilder _inner;

  /// Registers [onAccept] as the handler for connections that use the ALPN protocol [alpn]. The
  /// router gives each accepted [Connection] to [onAccept]. Complete the callback when the work on
  /// that connection is done. Throws [IrohAcceptException] on failure.
  Future<void> accept(
    List<int> alpn,
    FutureOr<void> Function(Connection connection) onAccept,
  ) async {
    try {
      await _inner.accept(
        alpn: alpn,
        onAccept: (ffi_net.Connection conn) => onAccept(Connection._(conn)),
      );
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }

  /// Starts the accept loop of the router and returns the [Router].
  /// Throws [IrohAcceptException] on failure.
  Future<Router> spawn() async {
    try {
      return Router._(await _inner.spawn());
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }
}

/// A multi-protocol router that runs. It sends each incoming connection to the Dart handler that
/// you registered for its ALPN. When the garbage collector removes this object, the router stops
/// abruptly. Call [shutdown] to stop it gracefully.
final class Router {
  Router._(this._inner);

  final ffi_router.Router _inner;

  /// Stops the router gracefully. The router stops the accept loop and closes its connections.
  /// Throws [IrohConnectionException] on failure.
  Future<void> shutdown() async {
    try {
      await _inner.shutdown();
    } on AnyhowException catch (e) {
      throw IrohConnectionException(e.message, cause: e);
    }
  }
}
