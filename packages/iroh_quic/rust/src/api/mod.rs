//! The flutter_rust_bridge (FRB) API of `iroh_quic`. FRB reads `crate::api` and makes the Dart
//! bindings from it. Each submodule becomes one Dart module under `lib/src/rust/api/`.

pub mod address_lookup;
pub mod connection;
pub mod endpoint;
pub mod key;
pub mod router;
pub mod simple;
pub mod watch;
