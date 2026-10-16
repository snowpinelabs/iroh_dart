/// Pure-Dart binding for **iroh 1.x**, a peer-to-peer QUIC library. iroh gives endpoints,
/// connections, streams, relay servers, and address lookup.
///
/// This package **wraps** the Rust iroh library through the crate `irohdart_ffi` and FRB. It does
/// not port iroh to Dart. The Dart API uses the same names as iroh (`Endpoint`, `EndpointId`,
/// `EndpointAddr`, `addressLookup`). Thus the iroh documentation and the n0 examples apply here.
///
/// Call [Iroh.init] first. Use [IrohCapabilities] to see the features that a platform supports.
library;

export 'src/capabilities.dart';
export 'src/endpoint.dart'; // Endpoint, connection, stream, and router types.
export 'src/errors.dart';
export 'src/key.dart'; // Keys, endpoint IDs, and endpoint addresses.
export 'src/runtime.dart';
export 'src/watch.dart'; // Event types for the watch streams (PathEvent, RelayStatus).
