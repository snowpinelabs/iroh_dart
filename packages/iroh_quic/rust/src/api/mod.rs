//! FRB API surface for `iroh_quic`. Each submodule maps to one Dart module under `lib/src/`
//! and is exposed in dependency order. flutter_rust_bridge scans `crate::api`.

pub mod address_lookup;
pub mod connection;
pub mod endpoint;
pub mod key;
pub mod router;
pub mod simple;
pub mod watch;
