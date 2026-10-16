//! The endpoint lifecycle.
//!
//! `Endpoint` is an opaque handle because it owns iroh runtime resources: sockets, tokio tasks,
//! and relay connections. [`endpoint_bind`] hides `Endpoint::builder(presets::N0)` and the rustls
//! crypto provider from Dart. The `tls-ring` feature supplies that crypto provider. Each async
//! operation runs on the shared tokio runtime (`crate::runtime::rt`).

use std::str::FromStr;

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use futures::StreamExt;
use iroh::endpoint::presets;
use iroh::{Endpoint as IrohEndpoint, RelayMode, RelayUrl, SecretKey, Watcher};

use crate::api::connection::{Connection, Incoming};
use crate::api::key::{build_endpoint_addr, parts_from_endpoint_addr, to_arr32, EndpointAddrParts};
use crate::api::watch::RelayStatusInfo;
use crate::frb_generated::StreamSink;
use crate::runtime::rt;

/// A bound iroh endpoint. This type is an opaque handle. Its methods call iroh on the shared tokio
/// runtime.
#[frb(opaque)]
pub struct Endpoint {
    pub(crate) inner: IrohEndpoint,
}

/// Maps the relay mode number from Dart and the custom relay URLs to an iroh `RelayMode`.
/// The numbers are: 0 = Default, 1 = Disabled, 2 = Staging, 3 = Custom.
/// Returns an error for an unknown number or for a custom relay URL that is not valid.
pub(crate) fn map_relay_mode(kind: i32, custom: Vec<String>) -> Result<RelayMode> {
    Ok(match kind {
        0 => RelayMode::Default,
        1 => RelayMode::Disabled,
        2 => RelayMode::Staging,
        3 => {
            let urls = custom
                .iter()
                .map(|u| RelayUrl::from_str(u).map_err(|e| anyhow!("{e}")))
                .collect::<Result<Vec<RelayUrl>>>()?;
            RelayMode::custom(urls)
        }
        _ => return Err(anyhow!("invalid relay mode discriminant: {kind}")),
    })
}

/// Binds a new endpoint with the `presets::N0` configuration. This preset supplies the DNS and
/// pkarr address lookup, the relay servers, and the crypto provider.
///
/// `relay_mode_kind` and `custom_relay_urls` replace the relay configuration. `alpns` sets the ALPN
/// protocols that the endpoint accepts for inbound connections. If you give `secret_key`, it sets
/// the identity of the endpoint. If you do not give it, iroh makes a random secret key.
///
/// Returns an error if `relay_mode_kind` is not valid, if `secret_key` does not have 32 bytes, or
/// if the bind fails.
#[frb]
pub async fn endpoint_bind(
    secret_key: Option<Vec<u8>>,
    alpns: Vec<Vec<u8>>,
    relay_mode_kind: i32,
    custom_relay_urls: Vec<String>,
) -> Result<Endpoint> {
    let relay_mode = map_relay_mode(relay_mode_kind, custom_relay_urls)?;
    let sk = match secret_key {
        Some(bytes) => Some(SecretKey::from_bytes(&to_arr32(&bytes)?)),
        None => None,
    };
    let inner = rt()
        .spawn(async move {
            let mut builder = IrohEndpoint::builder(presets::N0)
                .relay_mode(relay_mode)
                .alpns(alpns);
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

impl Endpoint {
    /// Returns the [`EndpointId`](iroh::EndpointId) of this endpoint as 32 raw bytes. The endpoint
    /// ID is the public key of the endpoint.
    #[frb(sync)]
    pub fn id(&self) -> Vec<u8> {
        self.inner.id().as_bytes().to_vec()
    }

    /// Returns a snapshot of the current endpoint address of this endpoint. The address contains
    /// the endpoint ID, the known relay URLs, and the direct IP addresses.
    #[frb(sync)]
    pub fn addr(&self) -> EndpointAddrParts {
        parts_from_endpoint_addr(&self.inner.addr())
    }

    /// Returns the local socket addresses of this endpoint in `host:port` form.
    #[frb(sync)]
    pub fn bound_sockets(&self) -> Vec<String> {
        self.inner
            .bound_sockets()
            .iter()
            .map(|s| s.to_string())
            .collect()
    }

    /// Replaces the list of accepted ALPN protocols. The change applies only to new inbound
    /// connections. The order sets the preference: if a peer offers more than one ALPN, the first
    /// match in this list wins. If the endpoint is closed, iroh ignores the request.
    #[frb(sync)]
    pub fn set_alpns(&self, alpns: Vec<Vec<u8>>) {
        self.inner.set_alpns(alpns);
    }

    /// Returns `true` if the endpoint is closed.
    #[frb(sync)]
    pub fn is_closed(&self) -> bool {
        self.inner.is_closed()
    }

    /// Connects to a remote endpoint with the given ALPN protocol and returns an established
    /// [`Connection`]. This function is the same as `iroh::Endpoint::connect`.
    /// Returns an error if `addr` is not valid or if the connection fails.
    pub async fn connect(&self, addr: EndpointAddrParts, alpn: Vec<u8>) -> Result<Connection> {
        let target = build_endpoint_addr(&addr)?;
        let ep = self.inner.clone();
        let conn = rt()
            .spawn(async move {
                let conn = ep.connect(target, &alpn).await?;
                Ok::<_, anyhow::Error>(conn)
            })
            .await
            .map_err(|e| anyhow!("connect task panicked: {e}"))??;
        Ok(Connection::wrap(conn))
    }

    /// Accepts the next inbound connection and returns it after the handshake.
    ///
    /// This function does all the steps of the iroh chain
    /// `Accept -> Incoming -> Accepting -> Connection`. Returns `None` after the endpoint closes.
    /// Returns an error if the handshake fails.
    pub async fn accept(&self) -> Result<Option<Connection>> {
        let ep = self.inner.clone();
        let maybe = rt()
            .spawn(async move {
                let Some(incoming) = ep.accept().await else {
                    return Ok::<Option<Connection>, anyhow::Error>(None);
                };
                let connecting = incoming.accept()?;
                let conn = connecting.await?;
                Ok(Some(Connection::wrap(conn)))
            })
            .await
            .map_err(|e| anyhow!("accept task panicked: {e}"))??;
        Ok(maybe)
    }

    /// Waits for the next inbound connection and returns it as an [`Incoming`] that is not
    /// accepted yet. The caller can examine the remote address and then call `accept`, `refuse`,
    /// `retry`, or `ignore`. Returns `None` after the endpoint closes.
    pub async fn accept_incoming(&self) -> Result<Option<Incoming>> {
        let ep = self.inner.clone();
        let maybe = rt()
            .spawn(async move {
                Ok::<Option<iroh::endpoint::Incoming>, anyhow::Error>(ep.accept().await)
            })
            .await
            .map_err(|e| anyhow!("accept_incoming task panicked: {e}"))??;
        Ok(maybe.map(Incoming::wrap))
    }

    /// Sends a snapshot of the [`EndpointAddr`](iroh::EndpointAddr) of this endpoint to `sink`
    /// each time the address changes. The address changes when the endpoint finds relay servers or
    /// direct addresses.
    ///
    /// `token` identifies the stream. The Dart subscription calls `cancel_stream` with this token.
    /// This call stops the task and drops the iroh watcher, so no resource leak occurs.
    pub fn watch_addr(&self, token: u64, sink: StreamSink<EndpointAddrParts>) {
        let watcher = self.inner.watch_addr();
        let handle = rt().spawn(async move {
            let mut stream = watcher.stream();
            while let Some(addr) = stream.next().await {
                if sink.add(parts_from_endpoint_addr(&addr)).is_err() {
                    break;
                }
            }
            crate::runtime::unregister_stream(token);
        });
        crate::runtime::register_stream(token, handle.abort_handle());
    }

    /// Sends the connection status of the home relay servers to `sink` each time it changes.
    ///
    /// Each update has one entry for each home relay server with a known URL. The list is empty if
    /// no relay servers are configured, or before the endpoint selects a home relay server.
    /// `token` identifies the stream for `cancel_stream`.
    pub fn home_relay_status(&self, token: u64, sink: StreamSink<Vec<RelayStatusInfo>>) {
        let watcher = self.inner.home_relay_status();
        let handle = rt().spawn(async move {
            let mut stream = watcher.stream();
            while let Some(statuses) = stream.next().await {
                let mapped: Vec<RelayStatusInfo> = statuses
                    .iter()
                    .map(|s| RelayStatusInfo {
                        url: s.url().to_string(),
                        connected: s.is_connected(),
                        last_error: s.last_error().map(|e| e.to_string()),
                        auth_denied_reason: s.auth_denied_reason().map(str::to_string),
                    })
                    .collect();
                if sink.add(mapped).is_err() {
                    break;
                }
            }
            crate::runtime::unregister_stream(token);
        });
        crate::runtime::register_stream(token, handle.abort_handle());
    }

    /// Closes the endpoint cleanly. This stops its connections and its background tasks.
    pub async fn close(&self) {
        let inner = self.inner.clone();
        // The task returns a `JoinError` only if it panics. The close is best-effort, so the
        // function ignores this error.
        let _ = rt().spawn(async move { inner.close().await }).await;
    }
}
