//! The single, process-wide multi-threaded tokio runtime that drives iroh's async surface.
//!
//! iroh is tokio-based (sockets, timers, `tokio::spawn`), so every async FFI call runs its work
//! on this runtime via `rt().spawn(..).await`. Driving the future on a real tokio runtime - rather
//! than FRB's default executor - guarantees iroh's I/O reactor is present. The runtime is
//! created once on first use and lives for the process; FRB/Dart owns no part of it.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use tokio::runtime::{Builder, Runtime};
use tokio::task::AbortHandle;

/// Returns the shared multi-threaded tokio runtime, creating it on first call.
pub(crate) fn rt() -> &'static Runtime {
    static RT: OnceLock<Runtime> = OnceLock::new();
    RT.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .thread_name("irohdart-tokio")
            .build()
            .expect("failed to build the irohdart tokio runtime")
    })
}

/// Registry of live FRB stream tasks, keyed by a Dart-supplied token. iroh watcher/path-event
/// streams block in `next().await` indefinitely (a watcher lives until the last `Endpoint` clone
/// drops), so a cancelled Dart subscription cannot be observed through `StreamSink::add` alone.
/// Instead, the Dart subscription's `onCancel` calls the `cancel_stream` FFI function, which calls
/// [`abort_stream`] to abort the task - the task drops its `StreamSink`, completing the Dart stream
/// cleanly.
fn stream_registry() -> &'static Mutex<HashMap<u64, AbortHandle>> {
    static R: OnceLock<Mutex<HashMap<u64, AbortHandle>>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Records the abort handle for a stream task under `token`.
pub(crate) fn register_stream(token: u64, handle: AbortHandle) {
    stream_registry().lock().unwrap().insert(token, handle);
}

/// Removes `token` from the registry (called when a stream task ends naturally).
pub(crate) fn unregister_stream(token: u64) {
    stream_registry().lock().unwrap().remove(&token);
}

/// Aborts the stream task registered under `token`, if any.
pub(crate) fn abort_stream(token: u64) {
    if let Some(handle) = stream_registry().lock().unwrap().remove(&token) {
        handle.abort();
    }
}
