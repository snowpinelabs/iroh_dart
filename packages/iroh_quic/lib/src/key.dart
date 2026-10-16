/// Keys and addresses for iroh. These are data value types that use iroh-base: [SecretKey],
/// [PublicKey] and [EndpointId], [Signature], [EndpointAddr], [RelayUrl], [RelayMode], and
/// [RelayMap]. They do not need an endpoint. Call [Iroh.init] one time to load the native library.
/// Then you can use these types synchronously.
library;

import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show AnyhowException;

import 'errors.dart';
import 'rust/api/key.dart' as ffi;

/// Converts a Rust error (`anyhow`) from FRB into an [IrohKeyException].
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

/// A 32-byte ed25519 secret key. An [Endpoint] uses it to sign. It authenticates and identifies
/// the endpoint.
final class SecretKey {
  const SecretKey._(this._bytes);

  /// The number of raw bytes in a secret key.
  static const int lengthBytes = 32;

  final Uint8List _bytes;

  /// Makes a new secret key from a cryptographically secure random source.
  factory SecretKey.generate() => SecretKey._(ffi.secretKeyGenerate());

  /// Wraps 32 raw secret key bytes. Throws [IrohKeyException] if the length is not 32.
  factory SecretKey.fromBytes(List<int> bytes) {
    if (bytes.length != lengthBytes) {
      throw IrohKeyException('secret key must be $lengthBytes bytes, got ${bytes.length}');
    }
    return SecretKey._(Uint8List.fromList(bytes));
  }

  /// Returns a copy of the 32 raw bytes.
  Uint8List toBytes() => Uint8List.fromList(_bytes);

  /// The [PublicKey] of this secret key. The public key is also the [EndpointId].
  PublicKey get publicKey => PublicKey._(_mapKeyErrors(() => ffi.secretKeyPublic(secret: _bytes)));

  /// Signs [message] and returns a 64-byte ed25519 [Signature].
  Signature sign(List<int> message) =>
      Signature._(_mapKeyErrors(() => ffi.secretKeySign(secret: _bytes, msg: message)));

  @override
  String toString() => 'SecretKey(****)';
}

/// A 32-byte ed25519 public key. In iroh, the public key also identifies an endpoint. Thus
/// [EndpointId] is an alias of this type.
final class PublicKey {
  const PublicKey._(this._bytes);

  /// The number of raw bytes in a public key.
  static const int lengthBytes = 32;

  final Uint8List _bytes;

  /// Validates and wraps 32 raw public key bytes. Throws [IrohKeyException] if the length is not
  /// 32, or if the bytes are not a valid ed25519 point.
  factory PublicKey.fromBytes(List<int> bytes) {
    if (bytes.length != lengthBytes) {
      throw IrohKeyException('public key must be $lengthBytes bytes, got ${bytes.length}');
    }
    final copy = Uint8List.fromList(bytes);
    _mapKeyErrors(() => ffi.publicKeyCheck(public: copy));
    return PublicKey._(copy);
  }

  /// Parses a public key from its z-base-32 form. Throws [IrohKeyException] if [z32] is not valid.
  factory PublicKey.fromZ32(String z32) =>
      PublicKey._(_mapKeyErrors(() => ffi.publicKeyFromZ32(z32: z32)));

  /// Parses a public key from lowercase hex, the iroh `Display`/`FromStr` form.
  /// Throws [IrohKeyException] if [hex] is not valid.
  factory PublicKey.fromHex(String hex) =>
      PublicKey._(_mapKeyErrors(() => ffi.publicKeyFromHex(hex: hex)));

  /// Returns a copy of the 32 raw bytes.
  Uint8List asBytes() => Uint8List.fromList(_bytes);

  /// Returns the z-base-32 text (pkarr alphabet). This is the iroh `to_z32` form.
  String toZ32() => _mapKeyErrors(() => ffi.publicKeyToZ32(public: _bytes));

  /// Returns the key as lowercase hex.
  String toHex() => _mapKeyErrors(() => ffi.publicKeyToHex(public: _bytes));

  /// Returns a short text form: the first bytes in hex. This is the iroh `fmt_short` form.
  String fmtShort() => _mapKeyErrors(() => ffi.publicKeyFmtShort(public: _bytes));

  /// Returns `true` if [signature] is a valid signature of [message] for this key. Otherwise
  /// returns `false`.
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

/// The identifier of an endpoint. In iroh, an `EndpointId` is a [PublicKey].
typedef EndpointId = PublicKey;

/// A 64-byte ed25519 signature.
final class Signature {
  const Signature._(this._bytes);

  /// The number of raw bytes in a signature.
  static const int lengthBytes = 64;

  final Uint8List _bytes;

  /// Wraps 64 raw signature bytes. Throws [IrohKeyException] if the length is not 64.
  factory Signature.fromBytes(List<int> bytes) {
    if (bytes.length != lengthBytes) {
      throw IrohKeyException('signature must be $lengthBytes bytes, got ${bytes.length}');
    }
    return Signature._(Uint8List.fromList(bytes));
  }

  /// Returns a copy of the 64 raw bytes.
  Uint8List toBytes() => Uint8List.fromList(_bytes);

  @override
  bool operator ==(Object other) => other is Signature && _bytesEqual(_bytes, other._bytes);

  @override
  int get hashCode => Object.hashAll(_bytes);
}

/// The URL of an iroh relay server. The Rust `url::Url` type validates and normalizes it.
final class RelayUrl {
  const RelayUrl._(this.value);

  /// The normalized URL text that iroh keeps.
  final String value;

  /// Parses and normalizes a relay URL. Throws [IrohKeyException] if [url] is not valid.
  factory RelayUrl.parse(String url) =>
      RelayUrl._(_mapKeyErrors(() => ffi.relayUrlParse(url: url)));

  @override
  bool operator ==(Object other) => other is RelayUrl && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// The endpoint address of an iroh endpoint: its [EndpointId], and optional relay URLs and
/// direct IP socket addresses. Objects of this class do not change. The `with*` methods return
/// new objects, as the iroh builder does. This class does not support `Custom` transport
/// addresses.
final class EndpointAddr {
  EndpointAddr(
    this.id, {
    List<RelayUrl> relayUrls = const <RelayUrl>[],
    List<String> ipAddrs = const <String>[],
  }) : relayUrls = List<RelayUrl>.unmodifiable(relayUrls),
       ipAddrs = List<String>.unmodifiable(ipAddrs);

  /// The endpoint ID of the endpoint.
  final EndpointId id;

  /// The relay URLs where you can possibly reach the endpoint.
  final List<RelayUrl> relayUrls;

  /// The direct IP socket addresses (`host:port`) where you can possibly reach the endpoint.
  final List<String> ipAddrs;

  /// Returns a copy with [url] added to [relayUrls].
  EndpointAddr withRelayUrl(RelayUrl url) =>
      EndpointAddr(id, relayUrls: <RelayUrl>[...relayUrls, url], ipAddrs: ipAddrs);

  /// Returns a copy with [socketAddr] (`host:port`) added to [ipAddrs].
  EndpointAddr withIpAddr(String socketAddr) =>
      EndpointAddr(id, relayUrls: relayUrls, ipAddrs: <String>[...ipAddrs, socketAddr]);

  /// Sends this endpoint address through the iroh constructor and accessors, and returns the
  /// normalized result. iroh validates each part: the endpoint ID, the relay URLs, and the socket
  /// addresses. Throws [IrohKeyException] if a part is not valid.
  EndpointAddr canonical() =>
      _fromParts(_mapKeyErrors(() => ffi.endpointAddrRoundTrip(parts: _toParts())));

  /// Encodes this endpoint address as postcard bytes, the standard iroh wire format.
  /// Throws [IrohKeyException] if a part is not valid.
  Uint8List encode() => _mapKeyErrors(() => ffi.endpointAddrEncode(parts: _toParts()));

  /// Decodes an [EndpointAddr] from postcard bytes. Throws [IrohKeyException] if [bytes] are not
  /// valid.
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

  /// Parses each URL in [urls] into a [RelayUrl]. Throws [IrohKeyException] if a URL is not valid.
  factory RelayMap.fromUrls(List<String> urls) => RelayMap(urls.map(RelayUrl.parse).toList());

  /// The relay URLs in this map.
  final List<RelayUrl> urls;
}

/// How an [Endpoint] selects relay servers. This type has the same variants as the iroh
/// `RelayMode`.
sealed class RelayMode {
  const RelayMode();

  /// The n0 production relay servers (iroh `RelayMode::Default`).
  static const RelayMode n0Default = RelayModeDefault._();

  /// No relay servers (iroh `RelayMode::Disabled`).
  static const RelayMode disabled = RelayModeDisabled._();

  /// The n0 staging relay servers (iroh `RelayMode::Staging`).
  static const RelayMode staging = RelayModeStaging._();

  /// A custom set of relay servers (iroh `RelayMode::Custom`).
  const factory RelayMode.custom(RelayMap map) = RelayModeCustom;
}

/// The n0 production relay servers.
final class RelayModeDefault extends RelayMode {
  const RelayModeDefault._();
}

/// No relay servers.
final class RelayModeDisabled extends RelayMode {
  const RelayModeDisabled._();
}

/// The n0 staging relay servers.
final class RelayModeStaging extends RelayMode {
  const RelayModeStaging._();
}

/// A custom set of relay servers.
final class RelayModeCustom extends RelayMode {
  const RelayModeCustom(this.map);

  /// The relay servers to use.
  final RelayMap map;
}
