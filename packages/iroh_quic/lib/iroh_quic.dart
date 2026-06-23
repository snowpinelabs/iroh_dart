/// Pure-Dart binding for **iroh 1.0** - peer-to-peer QUIC networking (endpoints,
/// connections, streams, relays, address lookup) over the shared Rust core.
///
/// This package **wraps** iroh through an owned flutter_rust_bridge crate; it does not re-port
/// iroh to Dart. The Dart API mirrors iroh 1.0's nouns exactly (`Endpoint` / `EndpointId` /
/// `EndpointAddr`, `addressLookup`) so iroh's docs and the n0 examples transfer directly.
///
/// Start with [Iroh.init]. Query [IrohCapabilities] for the features available on a platform.
library;

export 'src/capabilities.dart';
export 'src/endpoint.dart'; // endpoint, connections, accept loop (incl. connection/stream parts)
export 'src/errors.dart';
export 'src/key.dart'; // identity & addressing
export 'src/runtime.dart';
export 'src/watch.dart'; // reactive streams (PathEvent, RelayStatus)
