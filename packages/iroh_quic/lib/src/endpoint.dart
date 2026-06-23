/// Endpoint lifecycle + connections. [Endpoint.bind] is the first async surface;
/// [Endpoint.connect] establishes a [Connection]. This library is composed from `connection.dart`
/// and `stream.dart` (as parts) so the wrapper types can share private constructors. Call
/// [Iroh.init] once before binding.
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

/// Wraps an FRB reactive stream (which blocks a Rust task that cannot otherwise observe Dart
/// cancellation) so that cancelling the returned subscription aborts the Rust task via
/// `cancelStream(token)` - making cancel prompt and leak-free.
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

/// A bound iroh endpoint - the local participant in the P2P network. Holds native runtime
/// resources (sockets, tokio tasks, relay connections); call [close] to release them.
final class Endpoint {
  Endpoint._(this._inner);

  final ffi_ep.Endpoint _inner;

  /// Binds a new endpoint and returns once it is ready to connect/accept.
  ///
  /// [secretKey] fixes the identity (a fresh random key is generated if omitted). [alpns] are the
  /// application protocols accepted for inbound connections. [relayMode] selects relay servers
  /// (defaults to n0's production relays). Throws [IrohBindException] on failure.
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

  /// Binds an endpoint that resolves peer addresses via a **Dart-implemented** [resolve] callback
  /// instead of iroh's built-in DNS/pkarr lookup. When you `connect` to a peer
  /// known only by its [EndpointId], [resolve] is invoked to discover its [EndpointAddr]; return
  /// `null` for unknown ids. Throws [IrohBindException] on failure.
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

  /// This endpoint's [EndpointId] (public key).
  EndpointId get id => PublicKey.fromBytes(_inner.id());

  /// A snapshot of this endpoint's current address (id + known relay URLs + direct IP addrs).
  /// The relay/direct lists may be empty immediately after [bind] until discovery populates them.
  EndpointAddr get addr => _addrFromParts(_inner.addr());

  /// A live [Stream] of this endpoint's [EndpointAddr] as relay/direct discovery updates it.
  /// Cancelling the subscription drops the iroh watcher.
  Stream<EndpointAddr> watchAddr() =>
      _cancellableStream((token) => _inner.watchAddr(token: token), _addrFromParts);

  /// A live [Stream] of the home-relay connection status (one [RelayStatus] per configured relay).
  Stream<List<RelayStatus>> homeRelayStatus() => _cancellableStream(
    (token) => _inner.homeRelayStatus(token: token),
    (list) => list
        .map((s) => RelayStatus(url: s.url, connected: s.connected, lastError: s.lastError))
        .toList(),
  );

  /// The local socket addresses (`host:port`) this endpoint is bound to.
  List<String> get boundSockets => _inner.boundSockets();

  /// Whether the endpoint has been closed.
  bool get isClosed => _inner.isClosed();

  /// Replaces the accepted ALPN protocols (affects new inbound connections only).
  void setAlpns(List<List<int>> alpns) =>
      _inner.setAlpns(alpns: alpns.map(Uint8List.fromList).toList());

  /// Connects to [addr] over the [alpn] protocol, returning an established [Connection].
  /// Throws [IrohConnectException] if the connection cannot be established.
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

  /// Accepts the next inbound [Connection], or `null` once the endpoint is closed. Collapses
  /// iroh's lazy two-step accept. Throws [IrohAcceptException] on failure.
  Future<Connection?> accept() async {
    try {
      final inner = await _inner.accept();
      return inner == null ? null : Connection._(inner);
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }

  /// Accepts the next inbound connection as an unaccepted [Incoming], letting you inspect the
  /// remote address and choose `accept`/`refuse`/`retry`/`ignore`. Returns `null` once
  /// the endpoint is closed. Throws [IrohAcceptException] on failure.
  Future<Incoming?> acceptIncoming() async {
    try {
      final inner = await _inner.acceptIncoming();
      return inner == null ? null : Incoming._(inner);
    } on AnyhowException catch (e) {
      throw IrohAcceptException(e.message, cause: e);
    }
  }

  /// Begins building a multi-protocol [Router] over this endpoint. Register one Dart
  /// handler per ALPN, then `spawn()`. Use this for in-process multiplexing of several protocols;
  /// for the simple single-protocol case prefer the [accept] loop.
  Future<RouterBuilder> router() async =>
      RouterBuilder._(await ffi_router.routerBuilder(endpoint: _inner));

  /// Closes the endpoint gracefully, tearing down connections and background tasks.
  Future<void> close() => _inner.close();
}

(int, List<String>) _relayModeArgs(RelayMode mode) => switch (mode) {
  RelayModeDefault() => (0, const <String>[]),
  RelayModeDisabled() => (1, const <String>[]),
  RelayModeStaging() => (2, const <String>[]),
  RelayModeCustom(:final map) => (3, map.urls.map((u) => u.value).toList()),
};
