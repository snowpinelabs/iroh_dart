//! In-process multi-protocol multiplexing - the Dart->Rust `ProtocolHandler` bridge. A Dart async
//! callback handles connections for a given ALPN; iroh's `Router` runs the accept loop and
//! dispatches by ALPN. Use this when one process must serve several protocols concurrently; for the
//! simple case prefer ALPN dispatch over `endpoint.accept()`
//! (see `test/protocol_dispatch_test.dart`).

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

/// A `ProtocolHandler` that forwards each accepted connection to a Dart async callback.
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
        // Clone the Arc so the future doesn't borrow `&self` across the await point.
        let on_accept = self.on_accept.clone();
        on_accept(Connection::wrap(connection)).await;
        Ok(())
    }
}

/// A running multi-protocol router. The router aborts when this handle is dropped; call
/// [`Router::shutdown`] to stop it cleanly.
#[frb(opaque)]
pub struct Router {
    inner: IrohRouter,
}

/// Accumulates ALPN -> Dart-handler registrations, then [`RouterBuilder::spawn`]s the accept loop.
#[frb(opaque)]
pub struct RouterBuilder {
    inner: StdMutex<Option<IrohRouterBuilder>>,
}

/// Starts a [`RouterBuilder`] over `endpoint`.
pub fn router_builder(endpoint: &Endpoint) -> RouterBuilder {
    RouterBuilder {
        inner: StdMutex::new(Some(IrohRouter::builder(endpoint.inner.clone()))),
    }
}

impl RouterBuilder {
    /// Registers `on_accept` as the handler for connections negotiating `alpn`. The Dart callback
    /// receives each accepted [`Connection`] and resolves when it has finished handling it (after
    /// which the connection is dropped unless other clones are held).
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

    /// Spawns the router's accept loop and returns the running [`Router`].
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
    /// Shuts the router down gracefully, stopping its accept loop.
    pub async fn shutdown(&self) -> Result<()> {
        let inner = self.inner.clone();
        rt().spawn(async move { inner.shutdown().await })
            .await
            .map_err(|e| anyhow!("router shutdown task panicked: {e}"))?
            .map_err(|e| anyhow!("router shutdown failed: {e}"))?;
        Ok(())
    }
}
