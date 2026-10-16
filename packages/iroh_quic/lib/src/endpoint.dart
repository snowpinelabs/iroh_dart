/// The endpoint, connection, stream, and router types. [Endpoint.bind] makes an endpoint.
/// [Endpoint.connect] makes a [Connection]. The files `connection.dart`, `router.dart`, and
/// `stream.dart` are parts of this library, so the wrapper types can share private constructors.
/// Call [Iroh.init] one time before you bind an endpoint.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show AnyhowException;

import 'errors.dart';
import 'key.dart';
import 'rust/api/address_lookup.dart' as ffi_addr;
import 'rust/api/connection.dart' as ffi_net;
import 'rust/api/endpoint.dart' as ffi_ep;
import 'rust/api/key.dart' as ffi_key;
import 'rust/api/router.dart' as ffi_router;
import 'rust/api/watch.dart' as ffi_watch;
import 'watch.dart';

part 'connection.dart';
part 'router.dart';
part 'stream.dart';

EndpointAddr _addrFromParts(ffi_key.EndpointAddrParts parts) => EndpointAddr(
  PublicKey.fromBytes(parts.id),
  relayUrls: parts.relayUrls.map(RelayUrl.parse).toList(),
  ipAddrs: parts.ipAddrs,
);

int _streamTokenCounter = 0;

/// Wraps an FRB stream. The Rust task behind the stream cannot see a Dart cancel by itself.
/// When you cancel the returned subscription, this wrapper calls `cancelStream` with the token.
/// The crate then stops the Rust task immediately, and no resources stay in use.
Stream<R> _cancellableStream<T, R>(
  Stream<T> Function(BigInt token) create,
  R Function(T value) convert,
) {
  final token = BigInt.from(++_streamTokenCounter);
  late StreamController<R> controller;
  StreamSubscription<T>? sub;
  controller = StreamController<R>(
    onListen: () {
      sub = create(token).listen(
        (value) => controller.add(convert(value)),
        onError: controller.addError,
        onDone: controller.close,
      );
    },
    onCancel: () async {
      ffi_watch.cancelStream(token: token);
      await sub?.cancel();
    },
  );
  return controller.stream;
}

/// A bound iroh endpoint. It is the local participant in the P2P network. It holds native
/// resources: sockets, tokio tasks, and relay server connections. Call [close] to release them.
final class Endpoint {
  Endpoint._(this._inner);

  final ffi_ep.Endpoint _inner;

  /// Binds a new endpoint. Returns the endpoint when it is ready to connect and accept.
  ///
  /// [secretKey] sets the identity. If it is `null`, the endpoint makes a new random key.
  /// [alpns] are the ALPN protocols that the endpoint accepts for incoming connections.
  /// [relayMode] selects the relay servers. The default is the n0 production relay servers.
  /// Throws [IrohBindException] on failure.
  static Future<Endpoint> bind({
    SecretKey? secretKey,
    List<List<int>> alpns = const <List<int>>[],
    RelayMode relayMode = RelayMode.n0Default,
  }) async {
    final (kind, customUrls) = _relayModeArgs(relayMode);
    try {
      final inner = await ffi_ep.endpointBind(
        secretKey: secretKey == null ? null : Uint8List.fromList(secretKey.toBytes()),
        alpns: alpns.map(Uint8List.fromList).toList(),
        relayModeKind: kind,
        customRelayUrls: customUrls,
      );
      return Endpoint._(inner);
    } on AnyhowException catch (e) {
      throw IrohBindException(e.message, cause: e);
    }
  }

  /// Binds an endpoint that uses a **Dart** [resolve] callback for address lookup. This callback
  /// replaces the iroh DNS/pkarr address lookup. If you `connect` to a peer with only its
  /// [EndpointId], the endpoint calls [resolve] to find its [EndpointAddr]. Return `null` for an
  /// unknown endpoint ID. [secretKey], [alpns], and [relayMode] have the same function as in
  /// [bind]. Throws [IrohBindException] on failure.
  static Future<Endpoint> bindWithAddressLookup({
    required FutureOr<EndpointAddr?> Function(EndpointId endpointId) resolve,
    SecretKey? secretKey,
    List<List<int>> alpns = const <List<int>>[],
    RelayMode relayMode = RelayMode.n0Default,
  }) async {
    final (kind, customUrls) = _relayModeArgs(relayMode);
    try {
      final inner = await ffi_addr.endpointBindWithAddressLookup(
        secretKey: secretKey == null ? null : Uint8List.fromList(secretKey.toBytes()),
        alpns: alpns.map(Uint8List.fromList).toList(),
        relayModeKind: kind,
        customRelayUrls: customUrls,
        resolve: (Uint8List idBytes) async {
          final addr = await resolve(PublicKey.fromBytes(idBytes));
          if (addr == null) return null;
          return ffi_key.EndpointAddrParts(
            id: addr.id.asBytes(),
            relayUrls: addr.relayUrls.map((u) => u.value).toList(),
            ipAddrs: addr.ipAddrs,
          );
        },
      );
      return Endpoint._(inner);
    } on AnyhowException catch (e) {
      throw IrohBindException(e.message, cause: e);
    }
  }

  /// The [EndpointId] (public key) of this endpoint.
  EndpointId get id => PublicKey.fromBytes(_inner.id());

  /// The current endpoint address of this endpoint: the endpoint ID, the known relay URLs, and the
  /// direct IP addresses. Immediately after [bind], the relay and IP lists can be empty. The
  /// endpoint adds entries when it finds its addresses.
  EndpointAddr get addr => _addrFromParts(_inner.addr());

  /// Returns a [Stream] that sends the [EndpointAddr] of this endpoint each time it changes.
  /// When you cancel the subscription, the crate stops the iroh watcher.
  Stream<EndpointAddr> watchAddr() =>
      _cancellableStream((token) => _inner.watchAddr(token: token), _addrFromParts);

  /// Returns a [Stream] of the connection status of the home relay servers. Each event has one
  /// [RelayStatus] for each configured relay server. When you cancel the subscription, the crate
  /// stops the iroh watcher.
  Stream<List<RelayStatus>> homeRelayStatus() => _cancellableStream(
    (token) => _inner.homeRelayStatus(token: token),
    (list) => list
        .map(
          (s) => RelayStatus(
            url: s.url,
            connected: s.connected,
            lastError: s.lastError,
            authDeniedReason: s.authDeniedReason,
          ),
        )
        .toList(),
  );

  /// The local socket addresses (`host:port`) this endpoint is bound to.
  List<String> get boundSockets => _inner.boundSockets();

  /// Whether the endpoint is closed.
  bool get isClosed => _inner.isClosed();

  /// Replaces the ALPN protocols that the endpoint accepts. This change applies only to new
  /// incoming connections. The order of [alpns] sets the preference. If a peer offers more than
  /// one ALPN, the endpoint selects the first match in [alpns].
  void setAlpns(List<List<int>> alpns) =>
      _inner.setAlpns(alpns: alpns.map(Uint8List.fromList).toList());

  /// Connects to the endpoint at [addr] with the ALPN protocol [alpn], and returns the
  /// [Connection]. Throws [IrohConnectException] if the connection fails.
  Future<Connection> connect(EndpointAddr addr, List<int> alpn) async {
    final parts = ffi_key.EndpointAddrParts(
      id: addr.id.asBytes(),
      relayUrls: addr.relayUrls.map((u) => u.value).toList(),
      ipAddrs: addr.ipAddrs,
    );
    try {
      final inner = await _inner.connect(addr: parts, alpn: alpn);
      return Connection._(inner);
    } on AnyhowException catch (e) {
      throw IrohConnectException(e.message, cause: e);
    }
  }

  /// Accepts the next incoming [Connection]. Returns `null` when the endpoint is closed. iroh
  /// accepts a connection in two steps. This method does the two steps in one call.
  /// Throws [IrohAcceptException] on failure.
  Future<Connection?> accept() async {
    try {
      final inner = await _inner.accept();
      return inner == null ? null : Connection._(inner);
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }

  /// Returns the next incoming connection as an [Incoming] that is not accepted yet. You can read
  /// the remote address, then call `accept`, `refuse`, `retry`, or `ignore`. Returns `null` when
  /// the endpoint is closed. Throws [IrohAcceptException] on failure.
  Future<Incoming?> acceptIncoming() async {
    try {
      final inner = await _inner.acceptIncoming();
      return inner == null ? null : Incoming._(inner);
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }

  /// Returns a [RouterBuilder] that makes a multi-protocol [Router] for this endpoint. Register
  /// one Dart handler for each ALPN, then call `spawn()`. Use a router to serve more than one
  /// protocol in one process. For one protocol, use an [accept] loop.
  Future<RouterBuilder> router() async =>
      RouterBuilder._(await ffi_router.routerBuilder(endpoint: _inner));

  /// Closes the endpoint gracefully. This stops its connections and its background tasks.
  Future<void> close() => _inner.close();
}

(int, List<String>) _relayModeArgs(RelayMode mode) => switch (mode) {
  RelayModeDefault() => (0, const <String>[]),
  RelayModeDisabled() => (1, const <String>[]),
  RelayModeStaging() => (2, const <String>[]),
  RelayModeCustom(:final map) => (3, map.urls.map((u) => u.value).toList()),
};
