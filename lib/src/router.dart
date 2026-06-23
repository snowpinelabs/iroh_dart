part of 'endpoint.dart';

/// Builds a multi-protocol [Router]. Register one Dart handler per ALPN with
/// [accept], then [spawn]. Each registration is a Dart->Rust async-trait bridge: iroh's `Router`
/// runs the accept loop and invokes your callback for every inbound [Connection] on that ALPN.
final class RouterBuilder {
  RouterBuilder._(this._inner);

  final ffi_router.RouterBuilder _inner;

  /// Registers [onAccept] as the handler for connections negotiating [alpn]. The callback receives
  /// each accepted [Connection] and should complete once it has finished handling it.
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

  /// Spawns the router's accept loop and returns the running [Router].
  Future<Router> spawn() async {
    try {
      return Router._(await _inner.spawn());
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }
}

/// A running multi-protocol router. Dispatches inbound connections to the Dart handler
/// registered for each ALPN. The router aborts when this object is garbage-collected; call
/// [shutdown] to stop it cleanly.
final class Router {
  Router._(this._inner);

  final ffi_router.Router _inner;

  /// Shuts the router down gracefully (stops accepting and closes connections).
  Future<void> shutdown() async {
    try {
      await _inner.shutdown();
    } on AnyhowException catch (e) {
      throw IrohConnectionException(e.message, cause: e);
    }
  }
}
