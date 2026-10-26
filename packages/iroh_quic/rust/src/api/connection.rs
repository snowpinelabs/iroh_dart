//! Connections and QUIC streams.
//!
//! `Connection`, `SendStream`, and `RecvStream` are opaque handles. Each stream half is in an
//! `Arc<tokio::sync::Mutex<..>>`, so each operation can move a clone of it into a task on the
//! shared tokio runtime (`rt().spawn`). The runtime supplies the iroh I/O reactor. The mutex
//! serializes concurrent access to a stream half. iroh futures borrow `&self` with a lifetime, but
//! a spawned task must be `'static`. Thus each operation moves a clone of the `Arc`-backed
//! `Connection` or stream half into its task.

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

/// An inbound connection that the endpoint has not accepted yet.
///
/// Dart can examine the remote address and then call `accept`, `refuse`, `retry`, or `ignore`.
/// Thus Dart can filter connections without a callback from Rust to Dart. The first decision
/// consumes the contained iroh `Incoming`. Later calls return an error.
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

    /// Returns a debug form of the remote address that started this connection.
    #[frb(sync)]
    pub fn remote_addr(&self) -> String {
        self.remote_addr.clone()
    }

    /// Accepts the connection, completes the handshake, and returns a [`Connection`].
    /// Returns an error if a decision already occurred or if the handshake fails.
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

    /// Refuses the connection. The endpoint sends a close packet with the `CONNECTION_REFUSED`
    /// error, and the connect attempt of the peer fails. Returns an error if a decision already
    /// occurred.
    #[frb(sync)]
    pub fn refuse(&self) -> Result<()> {
        let inc = self.take()?;
        let _g = rt().enter();
        inc.refuse();
        Ok(())
    }

    /// Sends a retry packet to the peer for address validation. The peer then connects again
    /// automatically, and the endpoint receives a new [`Incoming`]. Returns an error if a retry is
    /// not possible for this connection or if a decision already occurred.
    #[frb(sync)]
    pub fn retry(&self) -> Result<()> {
        let inc = self.take()?;
        let _g = rt().enter();
        inc.retry().map_err(anyhow::Error::new)
    }

    /// Ignores the connection. The endpoint sends no packet and releases the resources of the
    /// connection. Returns an error if a decision already occurred.
    #[frb(sync)]
    pub fn ignore(&self) -> Result<()> {
        let inc = self.take()?;
        let _g = rt().enter();
        inc.ignore();
        Ok(())
    }
}

/// A snapshot of some UDP and QUIC counters of a connection.
pub struct ConnStats {
    pub udp_tx_datagrams: u64,
    pub udp_tx_bytes: u64,
    pub udp_rx_datagrams: u64,
    pub udp_rx_bytes: u64,
    /// QUIC packets sent on all paths. Since iroh 1.4.
    pub sent_packets: u64,
    /// QUIC payload bytes sent on all paths. Since iroh 1.4.
    pub sent_bytes: u64,
    /// QUIC packets lost on all paths.
    pub lost_packets: u64,
    /// QUIC payload bytes lost on all paths.
    pub lost_bytes: u64,
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

    /// Returns the [`EndpointId`](iroh::EndpointId) of the remote peer as 32 raw bytes.
    #[frb(sync)]
    pub fn remote_id(&self) -> Vec<u8> {
        self.inner.remote_id().as_bytes().to_vec()
    }

    /// Returns the ALPN protocol that the two endpoints negotiated for this connection.
    #[frb(sync)]
    pub fn alpn(&self) -> Vec<u8> {
        self.inner.alpn().to_vec()
    }

    /// Returns a stable identifier for this connection. The value does not change during the
    /// life of the connection, also if the peer addresses change.
    #[frb(sync)]
    pub fn stable_id(&self) -> usize {
        self.inner.stable_id()
    }

    /// Returns a snapshot of the connection counters.
    #[frb(sync)]
    pub fn stats(&self) -> ConnStats {
        let s = self.inner.stats();
        ConnStats {
            udp_tx_datagrams: s.udp_tx.datagrams,
            udp_tx_bytes: s.udp_tx.bytes,
            udp_rx_datagrams: s.udp_rx.datagrams,
            udp_rx_bytes: s.udp_rx.bytes,
            sent_packets: s.sent_packets,
            sent_bytes: s.sent_bytes,
            lost_packets: s.lost_packets,
            lost_bytes: s.lost_bytes,
        }
    }

    /// Opens a new bidirectional stream.
    ///
    /// Note: the peer does not see the stream until the first write on the returned
    /// [`SendStream`]. Write data before you wait for data from the peer.
    pub async fn open_bi(&self) -> Result<(SendStream, RecvStream)> {
        let conn = self.inner.clone();
        let (s, r) = rt()
            .spawn(async move { conn.open_bi().await.map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("open_bi task panicked: {e}"))??;
        Ok((SendStream::wrap(s), RecvStream::wrap(r)))
    }

    /// Opens a new unidirectional stream. This stream can only send.
    pub async fn open_uni(&self) -> Result<SendStream> {
        let conn = self.inner.clone();
        let s = rt()
            .spawn(async move { conn.open_uni().await.map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("open_uni task panicked: {e}"))??;
        Ok(SendStream::wrap(s))
    }

    /// Accepts the next bidirectional stream that the peer opens.
    pub async fn accept_bi(&self) -> Result<(SendStream, RecvStream)> {
        let conn = self.inner.clone();
        let (s, r) = rt()
            .spawn(async move { conn.accept_bi().await.map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("accept_bi task panicked: {e}"))??;
        Ok((SendStream::wrap(s), RecvStream::wrap(r)))
    }

    /// Accepts the next unidirectional stream that the peer opens. This stream can only receive.
    pub async fn accept_uni(&self) -> Result<RecvStream> {
        let conn = self.inner.clone();
        let r = rt()
            .spawn(async move { conn.accept_uni().await.map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("accept_uni task panicked: {e}"))??;
        Ok(RecvStream::wrap(r))
    }

    /// Sends an unreliable, unordered datagram. Returns an error if the datagram is too large or
    /// if the peer does not support datagrams.
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

    /// Sends a batch of unreliable, unordered datagrams in one call. Returns the number of
    /// datagrams that iroh queued. If one datagram is too large, iroh rejects the full batch.
    #[frb(sync)]
    pub fn send_many_datagrams(&self, datagrams: Vec<Vec<u8>>) -> Result<usize> {
        let batch: Vec<bytes::Bytes> = datagrams.into_iter().map(bytes::Bytes::from).collect();
        self.inner
            .send_many_datagrams(&batch)
            .map_err(anyhow::Error::new)
    }

    /// Receives a batch of application datagrams from the peer, in arrival order. Waits until
    /// at least one datagram is available, then returns at most `max_count` datagrams. If
    /// `max_count` is zero, returns an empty list immediately.
    pub async fn read_many_datagrams(&self, max_count: usize) -> Result<Vec<Vec<u8>>> {
        let conn = self.inner.clone();
        rt().spawn(async move {
            let mut out = vec![bytes::Bytes::new(); max_count];
            let n = conn
                .read_many_datagrams(&mut out)
                .await
                .map_err(anyhow::Error::new)?;
            Ok::<Vec<Vec<u8>>, anyhow::Error>(out[..n].iter().map(|d| d.to_vec()).collect())
        })
        .await
        .map_err(|e| anyhow!("read_many_datagrams task panicked: {e}"))?
    }

    /// Waits until the connection closes and returns the close reason in human-readable form.
    pub async fn closed(&self) -> String {
        let conn = self.inner.clone();
        match rt().spawn(async move { conn.closed().await }).await {
            Ok(reason) => reason.to_string(),
            Err(e) => format!("closed task panicked: {e}"),
        }
    }

    /// Closes the connection immediately with an application error code and a reason.
    #[frb(sync)]
    pub fn close(&self, error_code: u32, reason: Vec<u8>) {
        self.inner.close(VarInt::from_u32(error_code), &reason);
    }

    /// Sends the path lifecycle events of this connection to `sink`. The events are `Opened`,
    /// `Closed`, `Selected`, and `Lagged`. A `Selected` event shows a change between the relay path
    /// and a direct path. The stream ends when the connection closes.
    ///
    /// `token` identifies the stream. The Dart subscription calls `cancel_stream` with this token
    /// to stop the task.
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
    /// Returns the QUIC stream ID.
    #[frb(sync)]
    pub fn id(&self) -> u64 {
        self.id
    }

    /// Writes all of `data` to the stream. If flow control limits the stream, the function waits
    /// until it can send.
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

    /// Finishes the stream cleanly. The peer receives an end-of-data signal.
    pub async fn finish(&self) -> Result<()> {
        let inner = self.inner.clone();
        rt().spawn(async move { inner.lock().await.finish().map_err(anyhow::Error::new) })
            .await
            .map_err(|e| anyhow!("finish task panicked: {e}"))??;
        Ok(())
    }

    /// Resets the stream with the given error code. The stream stops the transmission of data
    /// that the peer did not acknowledge.
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
    /// Returns the QUIC stream ID.
    #[frb(sync)]
    pub fn id(&self) -> u64 {
        self.id
    }

    /// Reads at most `max_len` bytes. Returns the bytes that it read, or `None` at the end of the
    /// stream.
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

    /// Reads exactly `len` bytes. Returns an error if the stream ends before `len` bytes arrive.
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

    /// Reads all data until the end of the stream. Returns an error if the data is longer than
    /// `size_limit` bytes.
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

    /// Tells the peer to stop the transmission on this stream, with the given error code.
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
