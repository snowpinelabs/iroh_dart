//! Connections & QUIC streams - the 80% use case.
//!
//! `Connection`, `SendStream`, and `RecvStream` are opaque handles. Stream halves are wrapped in
//! `Arc<tokio::sync::Mutex<..>>` so every op can be cloned into the shared tokio runtime
//! (`rt().spawn`) - this gives iroh's I/O reactor and serialises concurrent access to a half. iroh
//! futures borrow `&self` with a lifetime, so we clone the (Arc-backed) `Connection`/stream into
//! each spawned task to satisfy `'static`.

use std::sync::Arc;
use std::sync::Mutex as StdMutex;

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;
use futures::StreamExt;
use iroh::endpoint::{
    Connection as IrohConnection, Incoming as IrohIncoming, RecvStream as IrohRecvStream,
    SendStream as IrohSendStream, VarInt,
};
use tokio::sync::Mutex;

use crate::api::watch::{map_path_event, PathEventInfo};
use crate::frb_generated::StreamSink;
use crate::runtime::rt;

/// An established QUIC connection to a remote endpoint.
#[frb(opaque)]
pub struct Connection {
    pub(crate) inner: IrohConnection,
}

/// The send half of a QUIC stream.
#[frb(opaque)]
pub struct SendStream {
    inner: Arc<Mutex<IrohSendStream>>,
    id: u64,
}

/// The receive half of a QUIC stream.
#[frb(opaque)]
pub struct RecvStream {
    inner: Arc<Mutex<IrohRecvStream>>,
    id: u64,
}

/// An inbound connection that has not yet been accepted. Lets Dart inspect the remote address and
/// choose to `accept`/`refuse`/`retry`/`ignore` - the Dart-driven filter, no Rust->Dart async
/// callback required. The contained `Incoming` is consumed on the first decision; later calls
/// error.
#[frb(opaque)]
pub struct Incoming {
    inner: StdMutex<Option<IrohIncoming>>,
    remote_addr: String,
}

impl Incoming {
    pub(crate) fn wrap(inner: IrohIncoming) -> Self {
        let remote_addr = format!("{:?}", inner.remote_addr());
        Incoming {
            inner: StdMutex::new(Some(inner)),
            remote_addr,
        }
    }

    fn take(&self) -> Result<IrohIncoming> {
        self.inner
            .lock()
            .unwrap()
            .take()
            .ok_or_else(|| anyhow!("incoming connection already consumed"))
    }

    /// A debug rendering of the remote address that initiated this connection.
    #[frb(sync)]
    pub fn remote_addr(&self) -> String {
        self.remote_addr.clone()
    }

    /// Accepts the connection, completing the handshake and returning a [`Connection`].
    pub async fn accept(&self) -> Result<Connection> {
        let inc = self.take()?;
        let conn = rt()
            .spawn(async move {
                let accepting = inc.accept()?;
                let conn = accepting.await?;
                Ok::<_, anyhow::Error>(conn)
            })
            .await
            .map_err(|e| anyhow!("incoming accept task panicked: {e}"))??;
        Ok(Connection::wrap(conn))
    }

    /// Refuses the connection (sends no packet); the peer's connect attempt fails.
    #[frb(sync)]
    pub fn refuse(&self) -> Result<()> {
        let inc = self.take()?;
        let _g = rt().enter();
        inc.refuse();
        Ok(())
    }

    /// Responds with a retry packet (return-routability / anti-amplification). The peer transparently
    /// reconnects, producing a fresh [`Incoming`].
    #[frb(sync)]
    pub fn retry(&self) -> Result<()> {
        let inc = self.take()?;
        let _g = rt().enter();
        inc.retry().map_err(anyhow::Error::new)
    }

    /// Ignores the connection (sends no packet, frees resources).
    #[frb(sync)]
    pub fn ignore(&self) -> Result<()> {
        let inc = self.take()?;
        let _g = rt().enter();
        inc.ignore();
        Ok(())
    }
}

/// A snapshot of a few useful connection counters.
pub struct ConnStats {
    pub udp_tx_datagrams: u64,
    pub udp_tx_bytes: u64,
    pub udp_rx_datagrams: u64,
    pub udp_rx_bytes: u64,
}

impl SendStream {
    pub(crate) fn wrap(inner: IrohSendStream) -> Self {
        let id: u64 = inner.id().into();
        SendStream {
            inner: Arc::new(Mutex::new(inner)),
            id,
        }
    }
}

impl RecvStream {
    pub(crate) fn wrap(inner: IrohRecvStream) -> Self {
        let id: u64 = inner.id().into();
        RecvStream {
            inner: Arc::new(Mutex::new(inner)),
            id,
        }
    }
}

impl Connection {
    pub(crate) fn wrap(inner: IrohConnection) -> Self {
        Connection { inner }
    }

    /// The remote peer's [`EndpointId`](iroh::EndpointId) as 32 raw bytes.
    #[frb(sync)]
    pub fn remote_id(&self) -> Vec<u8> {
        self.inner.remote_id().as_bytes().to_vec()
    }

    /// The negotiated ALPN protocol for this connection.
    #[frb(sync)]
    pub fn alpn(&self) -> Vec<u8> {
        self.inner.alpn().to_vec()
    }

    /// A process-stable identifier for this connection.
    #[frb(sync)]
    pub fn stable_id(&self) -> usize {
        self.inner.stable_id()
    }

    /// Connection counters snapshot.
    #[frb(sync)]
    pub fn stats(&self) -> ConnStats {
        let s = self.inner.stats();
        ConnStats {
            udp_tx_datagrams: s.udp_tx.datagrams,
            udp_tx_bytes: s.udp_tx.bytes,
            udp_rx_datagrams: s.udp_rx.datagrams,
            udp_rx_bytes: s.udp_rx.bytes,
        }
    }

    /// Opens a new bidirectional stream. Note the lazy-stream footgun: the peer does not observe
    /// the stream until the first write on the returned [`SendStream`].
    pub async fn open_bi(&self) -> Result<(SendStream, RecvStream)> {
        let conn = self.inner.clone();
        let (s, r) = rt()
            .spawn(async move { conn.open_bi().await.map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("open_bi task panicked: {e}"))??;
        Ok((SendStream::wrap(s), RecvStream::wrap(r)))
    }

    /// Opens a new unidirectional (send-only) stream.
    pub async fn open_uni(&self) -> Result<SendStream> {
        let conn = self.inner.clone();
        let s = rt()
            .spawn(async move { conn.open_uni().await.map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("open_uni task panicked: {e}"))??;
        Ok(SendStream::wrap(s))
    }

    /// Accepts the next incoming bidirectional stream from the peer.
    pub async fn accept_bi(&self) -> Result<(SendStream, RecvStream)> {
        let conn = self.inner.clone();
        let (s, r) = rt()
            .spawn(async move { conn.accept_bi().await.map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("accept_bi task panicked: {e}"))??;
        Ok((SendStream::wrap(s), RecvStream::wrap(r)))
    }

    /// Accepts the next incoming unidirectional (receive-only) stream from the peer.
    pub async fn accept_uni(&self) -> Result<RecvStream> {
        let conn = self.inner.clone();
        let r = rt()
            .spawn(async move { conn.accept_uni().await.map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("accept_uni task panicked: {e}"))??;
        Ok(RecvStream::wrap(r))
    }

    /// Sends an unreliable, unordered datagram. Errors if too large or unsupported.
    #[frb(sync)]
    pub fn send_datagram(&self, data: Vec<u8>) -> Result<()> {
        self.inner
            .send_datagram(bytes::Bytes::from(data))
            .map_err(anyhow::Error::new)
    }

    /// Receives the next application datagram from the peer.
    pub async fn read_datagram(&self) -> Result<Vec<u8>> {
        let conn = self.inner.clone();
        let data = rt()
            .spawn(async move { conn.read_datagram().await.map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("read_datagram task panicked: {e}"))??;
        Ok(data.to_vec())
    }

    /// Waits until the connection is closed and returns the human-readable close reason.
    pub async fn closed(&self) -> String {
        let conn = self.inner.clone();
        match rt().spawn(async move { conn.closed().await }).await {
            Ok(reason) => reason.to_string(),
            Err(e) => format!("closed task panicked: {e}"),
        }
    }

    /// Closes the connection immediately with an application error code and reason.
    #[frb(sync)]
    pub fn close(&self, error_code: u32, reason: Vec<u8>) {
        self.inner.close(VarInt::from_u32(error_code), &reason);
    }

    /// Streams path lifecycle events (`Opened`/`Closed`/`Selected`/`Lagged`) for this connection;
    /// the relay-vs-direct transition is observable via `Selected`. `token` lets the Dart
    /// subscription cancel the underlying task via `cancel_stream`.
    pub fn path_events(&self, token: u64, sink: StreamSink<PathEventInfo>) {
        let stream = self.inner.path_events();
        let handle = rt().spawn(async move {
            let mut stream = stream;
            while let Some(event) = stream.next().await {
                if sink.add(map_path_event(event)).is_err() {
                    break;
                }
            }
            crate::runtime::unregister_stream(token);
        });
        crate::runtime::register_stream(token, handle.abort_handle());
    }
}

impl SendStream {
    /// The QUIC stream id.
    #[frb(sync)]
    pub fn id(&self) -> u64 {
        self.id
    }

    /// Writes all of `data` to the stream, applying backpressure as needed.
    pub async fn write_all(&self, data: Vec<u8>) -> Result<()> {
        let inner = self.inner.clone();
        rt().spawn(async move {
            inner
                .lock()
                .await
                .write_all(&data)
                .await
                .map_err(anyhow::Error::new)
        })
        .await
        .map_err(|e| anyhow!("write_all task panicked: {e}"))??;
        Ok(())
    }

    /// Finishes the stream cleanly (signals end-of-data to the peer).
    pub async fn finish(&self) -> Result<()> {
        let inner = self.inner.clone();
        rt().spawn(async move { inner.lock().await.finish().map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("finish task panicked: {e}"))??;
        Ok(())
    }

    /// Resets the stream, abandoning unacknowledged data with the given error code.
    pub async fn reset(&self, error_code: u32) -> Result<()> {
        let inner = self.inner.clone();
        rt().spawn(async move {
            inner
                .lock()
                .await
                .reset(VarInt::from_u32(error_code))
                .map_err(anyhow::Error::new)
        })
        .await
        .map_err(|e| anyhow!("reset task panicked: {e}"))??;
        Ok(())
    }
}

impl RecvStream {
    /// The QUIC stream id.
    #[frb(sync)]
    pub fn id(&self) -> u64 {
        self.id
    }

    /// Reads up to `max_len` bytes. Returns the bytes read, or `None` at end-of-stream.
    pub async fn read(&self, max_len: usize) -> Result<Option<Vec<u8>>> {
        let inner = self.inner.clone();
        rt().spawn(async move {
            let mut buf = vec![0u8; max_len];
            let n = inner
                .lock()
                .await
                .read(&mut buf)
                .await
                .map_err(anyhow::Error::new)?;
            Ok::<Option<Vec<u8>>, anyhow::Error>(n.map(|n| {
                buf.truncate(n);
                buf
            }))
        })
        .await
        .map_err(|e| anyhow!("read task panicked: {e}"))?
    }

    /// Reads exactly `len` bytes, erroring if the stream ends early.
    pub async fn read_exact(&self, len: usize) -> Result<Vec<u8>> {
        let inner = self.inner.clone();
        rt().spawn(async move {
            let mut buf = vec![0u8; len];
            inner
                .lock()
                .await
                .read_exact(&mut buf)
                .await
                .map_err(anyhow::Error::new)?;
            Ok::<Vec<u8>, anyhow::Error>(buf)
        })
        .await
        .map_err(|e| anyhow!("read_exact task panicked: {e}"))?
    }

    /// Reads to end of stream, up to `size_limit` bytes.
    pub async fn read_to_end(&self, size_limit: usize) -> Result<Vec<u8>> {
        let inner = self.inner.clone();
        rt().spawn(async move {
            inner
                .lock()
                .await
                .read_to_end(size_limit)
                .await
                .map_err(anyhow::Error::new)
        })
        .await
        .map_err(|e| anyhow!("read_to_end task panicked: {e}"))?
    }

    /// Asks the peer to stop sending on this stream with the given error code.
    pub async fn stop(&self, error_code: u32) -> Result<()> {
        let inner = self.inner.clone();
        rt().spawn(async move {
            inner
                .lock()
                .await
                .stop(VarInt::from_u32(error_code))
                .map_err(anyhow::Error::new)
        })
        .await
        .map_err(|e| anyhow!("stop task panicked: {e}"))??;
        Ok(())
    }
}
