/// Identity & addressing for iroh. Pure-data value types backed by iroh-base:
/// [SecretKey], [PublicKey]/[EndpointId], [Signature], [EndpointAddr], [RelayUrl],
/// [RelayMode]/[RelayMap]. No runtime is required - call [Iroh.init] once so the native library
/// is loaded, then use these synchronously.
library;

import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show AnyhowException;

import 'errors.dart';
import 'rust/api/key.dart' as ffi;

/// Converts an FRB-surfaced Rust error (`anyhow`) into a typed [IrohKeyException].
T _mapKeyErrors<T>(T Function() body) {
  try {
    return body();
  } on AnyhowException catch (e) {
    throw IrohKeyException(e.message, cause: e);
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A 32-byte ed25519 secret (signing) key. Authenticates and identifies an [Endpoint].
final class SecretKey {
  const SecretKey._(this._bytes);

  /// Number of raw bytes in a secret key.
  static const int lengthBytes = 32;

  final Uint8List _bytes;

  /// Generates a fresh, cryptographically-random secret key.
  factory SecretKey.generate() => SecretKey._(ffi.secretKeyGenerate());

  /// Wraps 32 raw secret-key bytes. Throws [IrohKeyException] if the length is wrong.
  factory SecretKey.fromBytes(List<int> bytes) {
    if (bytes.length != lengthBytes) {
      throw IrohKeyException('secret key must be $lengthBytes bytes, got ${bytes.length}');
    }
    return SecretKey._(Uint8List.fromList(bytes));
  }

  /// The 32 raw bytes (defensive copy).
  Uint8List toBytes() => Uint8List.fromList(_bytes);

  /// The [PublicKey] (== [EndpointId]) corresponding to this secret key.
  PublicKey get publicKey => PublicKey._(_mapKeyErrors(() => ffi.secretKeyPublic(secret: _bytes)));

  /// Signs [message], returning a 64-byte ed25519 [Signature].
  Signature sign(List<int> message) =>
      Signature._(_mapKeyErrors(() => ffi.secretKeySign(secret: _bytes, msg: message)));

  @override
  String toString() => 'SecretKey(****)';
}

/// A 32-byte ed25519 public key. In iroh this also identifies an endpoint, so it is aliased as
/// [EndpointId].
final class PublicKey {
  const PublicKey._(this._bytes);

  /// Number of raw bytes in a public key.
  static const int lengthBytes = 32;

  final Uint8List _bytes;

  /// Validates and wraps 32 raw public-key bytes. Throws [IrohKeyException] if the bytes are the
  /// wrong length or do not form a valid ed25519 point.
  factory PublicKey.fromBytes(List<int> bytes) {
    if (bytes.length != lengthBytes) {
      throw IrohKeyException('public key must be $lengthBytes bytes, got ${bytes.length}');
    }
    final copy = Uint8List.fromList(bytes);
    _mapKeyErrors(() => ffi.publicKeyCheck(public: copy));
    return PublicKey._(copy);
  }

  /// Parses a public key from its z-base-32 form.
  factory PublicKey.fromZ32(String z32) =>
      PublicKey._(_mapKeyErrors(() => ffi.publicKeyFromZ32(z32: z32)));

  /// Parses a public key from lowercase hex (iroh's `Display`/`FromStr` form).
  factory PublicKey.fromHex(String hex) =>
      PublicKey._(_mapKeyErrors(() => ffi.publicKeyFromHex(hex: hex)));

  /// The 32 raw bytes (defensive copy).
  Uint8List asBytes() => Uint8List.fromList(_bytes);

  /// z-base-32 encoding (pkarr alphabet) - iroh's canonical `to_z32`.
  String toZ32() => _mapKeyErrors(() => ffi.publicKeyToZ32(public: _bytes));

  /// Lowercase-hex encoding.
  String toHex() => _mapKeyErrors(() => ffi.publicKeyToHex(public: _bytes));

  /// Short, human-readable rendering (first bytes in hex) - iroh's `fmt_short`.
  String fmtShort() => _mapKeyErrors(() => ffi.publicKeyFmtShort(public: _bytes));

  /// Returns `true` iff [signature] is valid for [message] under this key.
  bool verify(List<int> message, Signature signature) => _mapKeyErrors(
    () => ffi.publicKeyVerify(public: _bytes, msg: message, signature: signature.toBytes()),
  );

  @override
  bool operator ==(Object other) => other is PublicKey && _bytesEqual(_bytes, other._bytes);

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() => 'PublicKey(${fmtShort()})';
}

/// In iroh, an `EndpointId` is exactly a [PublicKey] (never `Node*`).
typedef EndpointId = PublicKey;

/// A 64-byte ed25519 signature.
final class Signature {
  const Signature._(this._bytes);

  /// Number of raw bytes in a signature.
  static const int lengthBytes = 64;

  final Uint8List _bytes;

  /// Wraps 64 raw signature bytes. Throws [IrohKeyException] if the length is wrong.
  factory Signature.fromBytes(List<int> bytes) {
    if (bytes.length != lengthBytes) {
      throw IrohKeyException('signature must be $lengthBytes bytes, got ${bytes.length}');
    }
    return Signature._(Uint8List.fromList(bytes));
  }

  /// The 64 raw bytes (defensive copy).
  Uint8List toBytes() => Uint8List.fromList(_bytes);

  @override
  bool operator ==(Object other) => other is Signature && _bytesEqual(_bytes, other._bytes);

  @override
  int get hashCode => Object.hashAll(_bytes);
}

/// The URL of an iroh relay server (validated + canonicalised by `url::Url`).
final class RelayUrl {
  const RelayUrl._(this.value);

  /// The canonical URL string iroh stores.
  final String value;

  /// Parses and canonicalises a relay URL string. Throws [IrohKeyException] if invalid.
  factory RelayUrl.parse(String url) =>
      RelayUrl._(_mapKeyErrors(() => ffi.relayUrlParse(url: url)));

  @override
  bool operator ==(Object other) => other is RelayUrl && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The address of an iroh endpoint: its [EndpointId] plus optional relay URLs and direct IP
/// socket addresses. Immutable; the `with*` methods return new instances, mirroring
/// iroh's builder. `Custom` transport addresses are omitted in v1.
final class EndpointAddr {
  EndpointAddr(
    this.id, {
    List<RelayUrl> relayUrls = const <RelayUrl>[],
    List<String> ipAddrs = const <String>[],
  }) : relayUrls = List<RelayUrl>.unmodifiable(relayUrls),
       ipAddrs = List<String>.unmodifiable(ipAddrs);

  /// The endpoint's identity.
  final EndpointId id;

  /// Relay URLs at which the endpoint may be reachable.
  final List<RelayUrl> relayUrls;

  /// Direct IP socket addresses (`host:port`) at which the endpoint may be reachable.
  final List<String> ipAddrs;

  /// Returns a copy with [url] added to [relayUrls].
  EndpointAddr withRelayUrl(RelayUrl url) =>
      EndpointAddr(id, relayUrls: <RelayUrl>[...relayUrls, url], ipAddrs: ipAddrs);

  /// Returns a copy with [socketAddr] (`host:port`) added to [ipAddrs].
  EndpointAddr withIpAddr(String socketAddr) =>
      EndpointAddr(id, relayUrls: relayUrls, ipAddrs: <String>[...ipAddrs, socketAddr]);

  /// Round-trips through iroh's own constructor + accessors, validating every component
  /// (id, relay URLs, socket addresses) and returning the canonicalised result.
  EndpointAddr canonical() =>
      _fromParts(_mapKeyErrors(() => ffi.endpointAddrRoundTrip(parts: _toParts())));

  /// Serialises to postcard bytes (the canonical iroh wire encoding).
  Uint8List encode() => _mapKeyErrors(() => ffi.endpointAddrEncode(parts: _toParts()));

  /// Deserialises an [EndpointAddr] from postcard bytes.
  factory EndpointAddr.decode(List<int> bytes) =>
      _fromParts(_mapKeyErrors(() => ffi.endpointAddrDecode(bytes: bytes)));

  ffi.EndpointAddrParts _toParts() => ffi.EndpointAddrParts(
    id: id.asBytes(),
    relayUrls: relayUrls.map((u) => u.value).toList(),
    ipAddrs: ipAddrs,
  );

  static EndpointAddr _fromParts(ffi.EndpointAddrParts parts) => EndpointAddr(
    PublicKey._(parts.id),
    relayUrls: parts.relayUrls.map((s) => RelayUrl._(s)).toList(),
    ipAddrs: parts.ipAddrs,
  );

  @override
  String toString() =>
      'EndpointAddr(${id.fmtShort()}, relays: ${relayUrls.length}, ips: ${ipAddrs.length})';
}

/// A set of relay servers. Used to build a custom [RelayMode].
final class RelayMap {
  RelayMap(List<RelayUrl> urls) : urls = List<RelayUrl>.unmodifiable(urls);

  /// Parses each URL string into a [RelayUrl].
  factory RelayMap.fromUrls(List<String> urls) => RelayMap(urls.map(RelayUrl.parse).toList());

  /// The relay URLs in this map.
  final List<RelayUrl> urls;
}

/// How an [Endpoint] selects relay servers. Mirrors iroh's `RelayMode`.
sealed class RelayMode {
  const RelayMode();

  /// n0's production relay servers (iroh's `RelayMode::Default`).
  static const RelayMode n0Default = RelayModeDefault._();

  /// No relay servers (iroh's `RelayMode::Disabled`).
  static const RelayMode disabled = RelayModeDisabled._();

  /// n0's staging relay servers (iroh's `RelayMode::Staging`).
  static const RelayMode staging = RelayModeStaging._();

  /// A custom set of relay servers (iroh's `RelayMode::Custom`).
  const factory RelayMode.custom(RelayMap map) = RelayModeCustom;
}

/// n0's production relay servers.
final class RelayModeDefault extends RelayMode {
  const RelayModeDefault._();
}

/// No relay servers.
final class RelayModeDisabled extends RelayMode {
  const RelayModeDisabled._();
}

/// n0's staging relay servers.
final class RelayModeStaging extends RelayMode {
  const RelayModeStaging._();
}

/// A custom set of relay servers.
final class RelayModeCustom extends RelayMode {
  const RelayModeCustom(this.map);

  /// The relay servers to use.
  final RelayMap map;
}
