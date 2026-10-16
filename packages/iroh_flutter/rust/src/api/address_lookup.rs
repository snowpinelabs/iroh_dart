//! Custom address lookup with a Dart implementation.
//!
//! A Dart callback resolves an endpoint ID to its addresses. Thus iroh can connect to peers that
//! it knows only by endpoint ID. This module and `router.rs` contain the two bridges from a Rust
//! async trait to a Dart callback.

use std::net::SocketAddr;
use std::str::FromStr;
use std::sync::Arc;

use anyhow::{anyhow, Result};
use flutter_rust_bridge::{frb, DartFnFuture};
use iroh::address_lookup::{AddressLookup, EndpointData, EndpointInfo, Error as LookupError, Item};
use iroh::endpoint::presets;
use iroh::{Endpoint as IrohEndpoint, EndpointId, RelayUrl, SecretKey, TransportAddr};
use n0_future::boxed::BoxStream;

use crate::api::endpoint::{map_relay_mode, Endpoint};
use crate::api::key::{to_arr32, EndpointAddrParts};
use crate::runtime::rt;

type ResolveFn = Arc<dyn Fn(Vec<u8>) -> DartFnFuture<Option<EndpointAddrParts>> + Send + Sync>;

/// An `AddressLookup` that sends each `resolve` call to a Dart callback.
struct DartAddressLookup {
    resolve: ResolveFn,
}

impl std::fmt::Debug for DartAddressLookup {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("DartAddressLookup")
    }
}

/// Builds an address lookup [`Item`] from the parts that the Dart callback returned: relay URLs
/// and direct IP addresses. Returns an error if a URL or an IP address is not valid.
fn build_item(endpoint_id: EndpointId, parts: &EndpointAddrParts) -> Result<Item> {
    let mut addrs: Vec<TransportAddr> = Vec::new();
    for url in &parts.relay_urls {
        addrs.push(TransportAddr::Relay(RelayUrl::from_str(url)?));
    }
    for ip in &parts.ip_addrs {
        addrs.push(TransportAddr::Ip(SocketAddr::from_str(ip)?));
    }
    let data: EndpointData = addrs.into_iter().collect();
    Ok(Item::new(
        EndpointInfo::from_parts(endpoint_id, data),
        "dart-address-lookup",
        None,
    ))
}

impl AddressLookup for DartAddressLookup {
    fn resolve(&self, endpoint_id: EndpointId) -> Option<BoxStream<Result<Item, LookupError>>> {
        let resolve = self.resolve.clone();
        let id_bytes = endpoint_id.as_bytes().to_vec();
        // This stream has zero or one item. It calls the Dart callback. If the callback returns
        // addresses, the stream yields the built `Item`. If the callback returns `None` or
        // addresses that are not valid, the stream is empty.
        let stream = async_stream::stream! {
            if let Some(item) = resolve(id_bytes)
                .await
                .and_then(|parts| build_item(endpoint_id, &parts).ok())
            {
                yield Ok(item);
            }
        };
        Some(Box::pin(stream))
    }
}

/// Binds an endpoint that uses only a Dart address lookup.
///
/// This function removes the default DNS and pkarr address lookup of the `presets::N0`
/// configuration and uses `resolve` in its place. Thus, when you connect to a peer that you know
/// only by its endpoint ID, the endpoint calls `resolve` to get the addresses of the peer.
/// `resolve` receives the 32-byte endpoint ID. It returns the endpoint address parts, or `None` if
/// it does not know the peer. All other behavior is the same as `endpoint_bind`.
///
/// Returns an error if `relay_mode_kind` is not valid, if `secret_key` does not have 32 bytes, or
/// if the bind fails.
#[frb]
pub async fn endpoint_bind_with_address_lookup(
    secret_key: Option<Vec<u8>>,
    alpns: Vec<Vec<u8>>,
    relay_mode_kind: i32,
    custom_relay_urls: Vec<String>,
    resolve: impl Fn(Vec<u8>) -> DartFnFuture<Option<EndpointAddrParts>> + Send + Sync + 'static,
) -> Result<Endpoint> {
    let relay_mode = map_relay_mode(relay_mode_kind, custom_relay_urls)?;
    let sk = match secret_key {
        Some(bytes) => Some(SecretKey::from_bytes(&to_arr32(&bytes)?)),
        None => None,
    };
    let lookup = DartAddressLookup {
        resolve: Arc::new(resolve),
    };
    let inner = rt()
        .spawn(async move {
            let mut builder = IrohEndpoint::builder(presets::N0)
                .relay_mode(relay_mode)
                .alpns(alpns)
                .clear_address_lookup()
                .address_lookup(lookup);
            if let Some(sk) = sk {
                builder = builder.secret_key(sk);
            }
            let ep = builder.bind().await?;
            Ok::<IrohEndpoint, anyhow::Error>(ep)
        })
        .await
        .map_err(|e| anyhow!("endpoint bind task panicked: {e}"))??;
    Ok(Endpoint { inner })
}
