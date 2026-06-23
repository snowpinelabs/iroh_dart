//! The ABI-version handshake the Dart loader checks on init.
//!
//! Bump [`IROHDART_ABI_VERSION`] whenever the FFI surface changes shape so a stale prebuilt
//! binary is refused at load time rather than crashing later.

/// The current ABI revision of the `irohdart-ffi` surface. The Dart side refuses to run on a
/// mismatch (see `lib/src/ffi/loader.dart`).
pub const IROHDART_ABI_VERSION: u32 = 1;

/// Returns the ABI version compiled into this native library.
///
/// Also serves as a minimal end-to-end check that the FFI path works:
/// Rust -> FRB glue -> native lib -> Dart loader -> Dart call.
#[flutter_rust_bridge::frb(sync)]
pub fn irohdart_abi_version() -> u32 {
    IROHDART_ABI_VERSION
}

/// Returns the `iroh` crate version this wrapper was built against, for diagnostics.
#[flutter_rust_bridge::frb(sync)]
pub fn irohdart_iroh_version() -> String {
    // Set by build.rs from the resolved iroh version in Cargo.lock.
    env!("IROH_CRATE_VERSION").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn abi_version_is_pinned() {
        assert_eq!(irohdart_abi_version(), 1);
        assert_eq!(IROHDART_ABI_VERSION, 1);
    }
}
