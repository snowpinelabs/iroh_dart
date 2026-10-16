//! `irohdart_ffi`: the flutter_rust_bridge (FRB) wrapper crate for the iroh P2P QUIC library.
//!
//! This crate is the only Rust dependency of the `iroh_quic` Dart package. It depends on the
//! `iroh` crate directly and gives a Dart API through FRB.

#[cfg(target_os = "android")]
mod android;
pub mod api;
mod frb_generated;
mod runtime;
