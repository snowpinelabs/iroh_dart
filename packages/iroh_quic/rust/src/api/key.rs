//! Identity and address functions.
//!
//! These functions are pure data operations and do not use the runtime. The Rust side keeps no
//! state: it receives bytes and returns bytes. The Dart side keeps the bytes in immutable value
//! classes. Each function maps to an `iroh-base` type: `SecretKey`, `PublicKey` (`EndpointId`),
//! `Signature`, `EndpointAddr`, or `RelayUrl`. Thus the bytes that cross the FFI boundary are the
//! same bytes that iroh serializes.

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

/// Makes a new random secret key and returns its 32 raw bytes.
#[frb(sync)]
pub fn secret_key_generate() -> Vec<u8> {
    SecretKey::generate().to_bytes().to_vec()
}

/// Calculates the 32-byte public key, which is the endpoint ID, from a 32-byte secret key.
/// Returns an error if `secret` does not have 32 bytes.
#[frb(sync)]
pub fn secret_key_public(secret: Vec<u8>) -> Result<Vec<u8>> {
    let sk = SecretKey::from_bytes(&to_arr32(&secret)?);
    Ok(sk.public().as_bytes().to_vec())
}

/// Signs `msg` with the secret key and returns a 64-byte ed25519 signature.
/// Returns an error if `secret` does not have 32 bytes.
#[frb(sync)]
pub fn secret_key_sign(secret: Vec<u8>, msg: Vec<u8>) -> Result<Vec<u8>> {
    let sk = SecretKey::from_bytes(&to_arr32(&secret)?);
    Ok(sk.sign(&msg).to_bytes().to_vec())
}

// --- PublicKey / EndpointId (32-byte ed25519 verifying key) ---

/// Makes sure that `public` is a valid ed25519 public key, which is a point on the curve.
/// Returns an error if the key is not valid or does not have 32 bytes.
#[frb(sync)]
pub fn public_key_check(public: Vec<u8>) -> Result<()> {
    PublicKey::from_bytes(&to_arr32(&public)?)?;
    Ok(())
}

/// Returns `true` if `signature` is a valid signature of `msg` for the key `public`. Otherwise
/// returns `false`. Returns an error if `public` is not a valid key or `signature` does not have
/// 64 bytes.
#[frb(sync)]
pub fn public_key_verify(public: Vec<u8>, msg: Vec<u8>, signature: Vec<u8>) -> Result<bool> {
    let pk = PublicKey::from_bytes(&to_arr32(&public)?)?;
    let sig = Signature::from_bytes(&to_arr64(&signature)?);
    Ok(pk.verify(&msg, &sig).is_ok())
}

/// Encodes a public key in z-base-32 with the pkarr alphabet. This is the canonical iroh `to_z32`
/// form.
#[frb(sync)]
pub fn public_key_to_z32(public: Vec<u8>) -> Result<String> {
    Ok(PublicKey::from_bytes(&to_arr32(&public)?)?.to_z32())
}

/// Decodes a public key from its z-base-32 form and returns the 32 raw bytes.
#[frb(sync)]
pub fn public_key_from_z32(z32: String) -> Result<Vec<u8>> {
    Ok(PublicKey::from_z32(&z32)?.as_bytes().to_vec())
}

/// Encodes a public key in lowercase hex. This is the iroh `Display` and `FromStr` form.
#[frb(sync)]
pub fn public_key_to_hex(public: Vec<u8>) -> Result<String> {
    Ok(PublicKey::from_bytes(&to_arr32(&public)?)?.to_string())
}

/// Decodes a public key from lowercase hex and returns the 32 raw bytes.
#[frb(sync)]
pub fn public_key_from_hex(hex: String) -> Result<Vec<u8>> {
    Ok(PublicKey::from_str(&hex)?.as_bytes().to_vec())
}

/// Returns a short, human-readable form of a public key: the first bytes in hex. This is the iroh
/// `fmt_short` form.
#[frb(sync)]
pub fn public_key_fmt_short(public: Vec<u8>) -> Result<String> {
    Ok(PublicKey::from_bytes(&to_arr32(&public)?)?
        .fmt_short()
        .to_string())
}

// --- RelayUrl ---

/// Parses a relay URL string and returns the canonical form that iroh stores. `url::Url` validates
/// the string. Returns an error if the string is not a valid URL.
#[frb(sync)]
pub fn relay_url_parse(url: String) -> Result<String> {
    Ok(RelayUrl::from_str(&url)?.to_string())
}

// --- EndpointAddr ---

/// The wire form of an [`EndpointAddr`]: the endpoint ID, its relay URLs, and its direct IP socket
/// addresses. This type does not include `Custom` transport addresses. The transport address enum
/// is `#[non_exhaustive]`, and this crate never matches it exhaustively.
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

/// Builds an iroh `EndpointAddr` from `parts` and reads it back through the iroh accessors.
/// This function validates the endpoint ID, the relay URLs, and the socket addresses. It also
/// shows that the construction and the accessors keep the data unchanged. Returns an error if a
/// part is not valid.
#[frb(sync)]
pub fn endpoint_addr_round_trip(parts: EndpointAddrParts) -> Result<EndpointAddrParts> {
    Ok(parts_from_endpoint_addr(&build_endpoint_addr(&parts)?))
}

/// Encodes an endpoint address to postcard bytes, which is the canonical iroh wire encoding.
/// Returns an error if a part is not valid.
#[frb(sync)]
pub fn endpoint_addr_encode(parts: EndpointAddrParts) -> Result<Vec<u8>> {
    Ok(postcard::to_allocvec(&build_endpoint_addr(&parts)?)?)
}

/// Decodes an endpoint address from postcard bytes into parts. Returns an error if the bytes are
/// not a valid encoding.
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
        // A changed message fails the verification.
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
        // This vector comes from the tests in `iroh-base/src/key.rs`.
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
