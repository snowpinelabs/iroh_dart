//! Endpoint lifecycle - the first async surface.
//!
//! `Endpoint` is an **opaque** handle (it owns iroh's runtime resources - sockets, tokio tasks,
//! relay connections). `Endpoint::builder(presets::N0)` + the rustls `CryptoProvider` (installed
//! by the `tls-ring` feature) are hidden entirely behind [`endpoint_bind`]. Every async op runs on
//! the shared tokio runtime (`crate::runtime::rt`).

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

/// A bound iroh endpoint. Opaque handle; methods dispatch into iroh on the shared tokio runtime.
#[frb(opaque)]
pub struct Endpoint {
    pub(crate) inner: IrohEndpoint,
}

/// Maps the Dart-side relay-mode discriminant (+ custom URLs) onto iroh's `RelayMode`.
/// 0 = Default, 1 = Disabled, 2 = Staging, 3 = Custom.
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

/// Binds a new endpoint. Hides `presets::N0` (DNS/pkarr address lookup + relays + crypto provider);
/// `relay_mode_kind`/`custom_relay_urls` override the relay configuration, `alpns` declares the
/// protocols accepted for inbound connections, and `secret_key` (if given) fixes the identity.
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
    /// The endpoint's [`EndpointId`](iroh::EndpointId) (public key) as 32 raw bytes.
    #[frb(sync)]
    pub fn id(&self) -> Vec<u8> {
        self.inner.id().as_bytes().to_vec()
    }

    /// A snapshot of this endpoint's current address (id + known relay URLs + direct IP addrs).
    #[frb(sync)]
    pub fn addr(&self) -> EndpointAddrParts {
        parts_from_endpoint_addr(&self.inner.addr())
    }

    /// The local socket addresses this endpoint is bound to (`host:port`).
    #[frb(sync)]
    pub fn bound_sockets(&self) -> Vec<String> {
        self.inner
            .bound_sockets()
            .iter()
            .map(|s| s.to_string())
            .collect()
    }

    /// Replaces the set of accepted ALPN protocols (affects new inbound connections only).
    #[frb(sync)]
    pub fn set_alpns(&self, alpns: Vec<Vec<u8>>) {
        self.inner.set_alpns(alpns);
    }

    /// Whether the endpoint has been closed.
    #[frb(sync)]
    pub fn is_closed(&self) -> bool {
        self.inner.is_closed()
    }

    /// Connects to a remote endpoint over the given ALPN protocol, returning an established
    /// [`Connection`]. Mirrors `iroh::Endpoint::connect`.
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

    /// Accepts the next inbound connection, collapsing the lazy `Accept -> Incoming -> Accepting ->
    /// Connection` chain. Resolves to `None` once the endpoint is closed.
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

    /// Accepts the next inbound connection as an unaccepted [`Incoming`], letting the caller
    /// inspect the remote address and choose `accept`/`refuse`/`retry`/`ignore`. Resolves to
    /// `None` once the endpoint is closed.
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

    /// Streams snapshots of this endpoint's [`EndpointAddr`](iroh::EndpointAddr) as relay/direct
    /// discovery updates it. `token` lets the Dart subscription cancel the underlying task via
    /// `cancel_stream`, which drops the iroh watcher - no leak.
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

    /// Streams the home-relay connection status (one entry per configured relay) as it changes.
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

    /// Closes the endpoint gracefully, tearing down connections and background tasks.
    pub async fn close(&self) {
        let inner = self.inner.clone();
        // JoinError only if the task panics; closing is best-effort.
        let _ = rt().spawn(async move { inner.close().await }).await;
    }
}
