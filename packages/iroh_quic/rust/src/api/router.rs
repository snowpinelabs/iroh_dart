//! This module lets one process serve more than one protocol.
//!
//! This module is the bridge from the iroh `ProtocolHandler` trait to a Dart callback. A Dart
//! callback handles the connections for one ALPN protocol. The iroh `Router` runs the accept loop
//! and sends each connection to the handler for its ALPN. Use the router when one process must
//! serve more than one protocol at the same time. For a simple case, call `endpoint.accept()` and
//! select the handler from the ALPN of the connection. See `test/protocol_dispatch_test.dart`.

use std::sync::{Arc, Mutex as StdMutex};

use anyhow::{anyhow, Result};
use flutter_rust_bridge::{frb, DartFnFuture};
use iroh::endpoint::Connection as IrohConnection;
use iroh::protocol::{
    AcceptError, ProtocolHandler, Router as IrohRouter, RouterBuilder as IrohRouterBuilder,
};

use crate::api::connection::Connection;
use crate::api::endpoint::Endpoint;
use crate::runtime::rt;

type AcceptFn = Arc<dyn Fn(Connection) -> DartFnFuture<()> + Send + Sync>;

/// A `ProtocolHandler` that sends each accepted connection to a Dart callback.
struct DartProtocolHandler {
    on_accept: AcceptFn,
}

impl std::fmt::Debug for DartProtocolHandler {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("DartProtocolHandler")
    }
}

impl ProtocolHandler for DartProtocolHandler {
    async fn accept(&self, connection: IrohConnection) -> Result<(), AcceptError> {
        // Clone the `Arc` so that the future does not borrow `&self` across the `await` point.
        let on_accept = self.on_accept.clone();
        on_accept(Connection::wrap(connection)).await;
        Ok(())
    }
}

/// A router for more than one protocol, with an active accept loop. The router aborts when its
/// handle is released. Call [`Router::shutdown`] to stop it cleanly.
#[frb(opaque)]
pub struct Router {
    inner: IrohRouter,
}

/// Collects the Dart handlers for the ALPN protocols. [`RouterBuilder::spawn`] then starts the
/// accept loop.
#[frb(opaque)]
pub struct RouterBuilder {
    inner: StdMutex<Option<IrohRouterBuilder>>,
}

/// Makes a [`RouterBuilder`] for `endpoint`.
pub fn router_builder(endpoint: &Endpoint) -> RouterBuilder {
    RouterBuilder {
        inner: StdMutex::new(Some(IrohRouter::builder(endpoint.inner.clone()))),
    }
}

impl RouterBuilder {
    /// Registers `on_accept` as the handler for the connections that negotiate `alpn`.
    ///
    /// The Dart callback receives each accepted [`Connection`]. Its future completes when the
    /// callback has finished with the connection. After that, the router does not keep the
    /// connection. Returns an error if [`RouterBuilder::spawn`] already started the router.
    pub fn accept(
        &self,
        alpn: Vec<u8>,
        on_accept: impl Fn(Connection) -> DartFnFuture<()> + Send + Sync + 'static,
    ) -> Result<()> {
        let mut guard = self.inner.lock().unwrap();
        let builder = guard
            .take()
            .ok_or_else(|| anyhow!("router builder already spawned"))?;
        let handler = DartProtocolHandler {
            on_accept: Arc::new(on_accept),
        };
        *guard = Some(builder.accept(alpn, handler));
        Ok(())
    }

    /// Starts the accept loop of the router and returns the [`Router`]. Returns an error if
    /// the router already started.
    pub fn spawn(&self) -> Result<Router> {
        let builder = self
            .inner
            .lock()
            .unwrap()
            .take()
            .ok_or_else(|| anyhow!("router builder already spawned"))?;
        let _guard = rt().enter();
        Ok(Router {
            inner: builder.spawn(),
        })
    }
}

impl Router {
    /// Stops the router and its accept loop cleanly. Returns an error if the shutdown fails.
    pub async fn shutdown(&self) -> Result<()> {
        let inner = self.inner.clone();
        rt().spawn(async move { inner.shutdown().await })
            .await
            .map_err(|e| anyhow!("router shutdown task panicked: {e}"))?
            .map_err(|e| anyhow!("router shutdown failed: {e}"))?;
        Ok(())
    }
}
