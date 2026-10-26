//! The ABI version handshake. The Dart loader checks this version at initialization.
//!
//! Increase [`IROHDART_ABI_VERSION`] each time the shape of the FFI API changes. Thus the Dart
//! loader refuses a stale prebuilt native library at load time, and the library does not crash
//! later.

/// The current ABI version of the FFI API of this crate. The Dart side does not run if its
/// expected version is different. See `lib/src/ffi/loader.dart`.
pub const IROHDART_ABI_VERSION: u32 = 3;

/// Returns the ABI version that is compiled into this native library.
///
/// This function is also a minimal end-to-end check of the FFI path:
/// Rust -> FRB glue code -> native library -> Dart loader -> Dart call.
#[flutter_rust_bridge::frb(sync)]
pub fn irohdart_abi_version() -> u32 {
    IROHDART_ABI_VERSION
}

/// Returns the version of the `iroh` crate in this native library. Use it for diagnostics.
#[flutter_rust_bridge::frb(sync)]
pub fn irohdart_iroh_version() -> String {
    // `build.rs` sets this value from the resolved iroh version in `Cargo.lock`.
    env!("IROH_CRATE_VERSION").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version_is_pinned() {
        assert_eq!(irohdart_abi_version(), 3);
        assert_eq!(IROHDART_ABI_VERSION, 3);
    }
}
