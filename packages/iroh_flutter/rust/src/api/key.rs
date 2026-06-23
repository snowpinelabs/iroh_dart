//! Identity & addressing surface.
//!
//! These are **pure-data** operations with no runtime: the Rust side is stateless (buffers in,
//! buffers out), and the Dart side holds the bytes in immutable value classes. Everything maps to
//! iroh-base's `SecretKey` / `PublicKey` (`EndpointId`) / `Signature` / `EndpointAddr` /
//! `RelayUrl`, so the bytes crossing the boundary are exactly what iroh serialises.

use std::net::SocketAddr;
use std::str::FromStr;

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use iroh_base::{EndpointAddr, PublicKey, RelayUrl, SecretKey, Signature};

pub(crate) fn to_arr32(bytes: &[u8]) -> Result<[u8; 32]> {
    <[u8; 32]>::try_from(bytes).map_err(|_| anyhow!("expected 32 bytes, got {}", bytes.len()))
}

pub(crate) fn to_arr64(bytes: &[u8]) -> Result<[u8; 64]> {
    <[u8; 64]>::try_from(bytes).map_err(|_| anyhow!("expected 64 bytes, got {}", bytes.len()))
}

// --- SecretKey (32-byte ed25519 signing key) ---

/// Generates a fresh random secret key, returning its 32 raw bytes.
#[frb(sync)]
pub fn secret_key_generate() -> Vec<u8> {
    SecretKey::generate().to_bytes().to_vec()
}

/// Derives the 32-byte public key (EndpointId) from a 32-byte secret key.
#[frb(sync)]
pub fn secret_key_public(secret: Vec<u8>) -> Result<Vec<u8>> {
    let sk = SecretKey::from_bytes(&to_arr32(&secret)?);
    Ok(sk.public().as_bytes().to_vec())
}

/// Signs `msg` with the secret key, returning a 64-byte ed25519 signature.
#[frb(sync)]
pub fn secret_key_sign(secret: Vec<u8>, msg: Vec<u8>) -> Result<Vec<u8>> {
    let sk = SecretKey::from_bytes(&to_arr32(&secret)?);
    Ok(sk.sign(&msg).to_bytes().to_vec())
}

// --- PublicKey / EndpointId (32-byte ed25519 verifying key) ---

/// Validates that 32 bytes form a valid ed25519 public key (curve point). Errors otherwise.
#[frb(sync)]
pub fn public_key_check(public: Vec<u8>) -> Result<()> {
    PublicKey::from_bytes(&to_arr32(&public)?)?;
    Ok(())
}

/// Returns `true` iff `signature` is a valid signature of `msg` under `public`.
#[frb(sync)]
pub fn public_key_verify(public: Vec<u8>, msg: Vec<u8>, signature: Vec<u8>) -> Result<bool> {
    let pk = PublicKey::from_bytes(&to_arr32(&public)?)?;
    let sig = Signature::from_bytes(&to_arr64(&signature)?);
    Ok(pk.verify(&msg, &sig).is_ok())
}

/// z-base-32 encoding of a public key (pkarr alphabet) - iroh's canonical `to_z32`.
#[frb(sync)]
pub fn public_key_to_z32(public: Vec<u8>) -> Result<String> {
    Ok(PublicKey::from_bytes(&to_arr32(&public)?)?.to_z32())
}

/// Parses a public key from its z-base-32 form, returning the 32 raw bytes.
#[frb(sync)]
pub fn public_key_from_z32(z32: String) -> Result<Vec<u8>> {
    Ok(PublicKey::from_z32(&z32)?.as_bytes().to_vec())
}

/// Lowercase-hex encoding of a public key (iroh's `Display`/`FromStr` form).
#[frb(sync)]
pub fn public_key_to_hex(public: Vec<u8>) -> Result<String> {
    Ok(PublicKey::from_bytes(&to_arr32(&public)?)?.to_string())
}

/// Parses a public key from lowercase hex, returning the 32 raw bytes.
#[frb(sync)]
pub fn public_key_from_hex(hex: String) -> Result<Vec<u8>> {
    Ok(PublicKey::from_str(&hex)?.as_bytes().to_vec())
}

/// Short, human-readable rendering of a public key (first bytes in hex) - iroh's `fmt_short`.
#[frb(sync)]
pub fn public_key_fmt_short(public: Vec<u8>) -> Result<String> {
    Ok(PublicKey::from_bytes(&to_arr32(&public)?)?
        .fmt_short()
        .to_string())
}

// --- RelayUrl ---

/// Parses and canonicalises a relay URL string (validates via `url::Url`), returning the
/// canonical form iroh stores.
#[frb(sync)]
pub fn relay_url_parse(url: String) -> Result<String> {
    Ok(RelayUrl::from_str(&url)?.to_string())
}

// --- EndpointAddr ---

/// Wire-shaped view of an [`EndpointAddr`]: the endpoint id plus its relay URLs and direct IP
/// socket addresses. `Custom` transport addresses are intentionally omitted in v1 (the variant is
/// `#[non_exhaustive]`; we never match it exhaustively).
pub struct EndpointAddrParts {
    pub id: Vec<u8>,
    pub relay_urls: Vec<String>,
    pub ip_addrs: Vec<String>,
}

pub(crate) fn build_endpoint_addr(parts: &EndpointAddrParts) -> Result<EndpointAddr> {
    let pk = PublicKey::from_bytes(&to_arr32(&parts.id)?)?;
    let mut addr = EndpointAddr::new(pk);
    for u in &parts.relay_urls {
        addr = addr.with_relay_url(RelayUrl::from_str(u)?);
    }
    for ip in &parts.ip_addrs {
        addr = addr.with_ip_addr(SocketAddr::from_str(ip)?);
    }
    Ok(addr)
}

pub(crate) fn parts_from_endpoint_addr(addr: &EndpointAddr) -> EndpointAddrParts {
    EndpointAddrParts {
        id: addr.id.as_bytes().to_vec(),
        relay_urls: addr.relay_urls().map(|u| u.to_string()).collect(),
        ip_addrs: addr.ip_addrs().map(|a| a.to_string()).collect(),
    }
}

/// Builds an iroh `EndpointAddr` from parts and reads it back through iroh's own accessors -
/// proves construction/accessor fidelity (validates id, relay URLs, and socket addresses).
#[frb(sync)]
pub fn endpoint_addr_round_trip(parts: EndpointAddrParts) -> Result<EndpointAddrParts> {
    Ok(parts_from_endpoint_addr(&build_endpoint_addr(&parts)?))
}

/// Serialises an `EndpointAddr` to postcard bytes (the canonical iroh wire encoding).
#[frb(sync)]
pub fn endpoint_addr_encode(parts: EndpointAddrParts) -> Result<Vec<u8>> {
    Ok(postcard::to_allocvec(&build_endpoint_addr(&parts)?)?)
}

/// Deserialises an `EndpointAddr` from postcard bytes back into parts.
#[frb(sync)]
pub fn endpoint_addr_decode(bytes: Vec<u8>) -> Result<EndpointAddrParts> {
    let addr: EndpointAddr = postcard::from_bytes(&bytes)?;
    Ok(parts_from_endpoint_addr(&addr))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_public_sign_verify_round_trip() {
        let sk = secret_key_generate();
        let pk = secret_key_public(sk.clone()).unwrap();
        let msg = b"hello world".to_vec();
        let sig = secret_key_sign(sk, msg.clone()).unwrap();
        assert_eq!(sig.len(), 64);
        assert!(public_key_verify(pk.clone(), msg.clone(), sig.clone()).unwrap());
        // Tampered message fails.
        assert!(!public_key_verify(pk, b"hello worle".to_vec(), sig).unwrap());
    }

    #[test]
    fn z32_and_hex_round_trip() {
        let pk = secret_key_public(secret_key_generate()).unwrap();
        let z32 = public_key_to_z32(pk.clone()).unwrap();
        assert_eq!(public_key_from_z32(z32).unwrap(), pk);
        let hex = public_key_to_hex(pk.clone()).unwrap();
        assert_eq!(public_key_from_hex(hex).unwrap(), pk);
    }

    #[test]
    fn known_hex_vector() {
        // From iroh-base/src/key.rs tests.
        let hex = "ae58ff8833241ac82d6ff7611046ed67b5072d142c588d0063e942d9a75502b6";
        let bytes = public_key_from_hex(hex.to_string()).unwrap();
        assert_eq!(public_key_to_hex(bytes).unwrap(), hex);
    }

    #[test]
    fn all_zeros_is_valid() {
        assert!(public_key_check(vec![0u8; 32]).is_ok());
    }

    #[test]
    fn endpoint_addr_round_trips() {
        let id = secret_key_public(secret_key_generate()).unwrap();
        let parts = EndpointAddrParts {
            id: id.clone(),
            relay_urls: vec!["https://relay.example.com./".to_string()],
            ip_addrs: vec!["192.168.1.5:7777".to_string()],
        };
        let bytes = endpoint_addr_encode(parts).unwrap();
        let back = endpoint_addr_decode(bytes).unwrap();
        assert_eq!(back.id, id);
        assert_eq!(back.ip_addrs, vec!["192.168.1.5:7777".to_string()]);
        assert_eq!(back.relay_urls.len(), 1);
    }
}
