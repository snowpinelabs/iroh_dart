//! The shared tokio runtime: one multi-threaded tokio runtime for the full process.
//!
//! iroh uses tokio for sockets, timers, and `tokio::spawn`. Thus each async FFI function runs its
//! work on this runtime with `rt().spawn(..).await`. The default FRB executor does not supply the
//! tokio I/O reactor that iroh needs, but this runtime does. The crate makes the runtime on first
//! use, and the runtime stays until the process stops. FRB and Dart do not own the runtime.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use tokio::runtime::{Builder, Runtime};
use tokio::task::AbortHandle;

/// Returns the shared tokio runtime. The first call makes the runtime.
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

/// Returns the registry of live FRB stream tasks. The key of each entry is the token from Dart.
///
/// An iroh watcher stream waits in `next().await` until the last `Endpoint` clone drops.
/// A path event stream waits until the connection closes. Thus a stream task cannot see a
/// cancelled Dart subscription through `StreamSink::add` alone. The `onCancel` handler of the Dart
/// subscription calls the `cancel_stream` FFI function instead. That function calls
/// [`abort_stream`], which aborts the task. The task then drops its `StreamSink`, and the Dart
/// stream closes cleanly.
fn stream_registry() -> &'static Mutex<HashMap<u64, AbortHandle>> {
    static R: OnceLock<Mutex<HashMap<u64, AbortHandle>>> = OnceLock::new();
    R.get_or_init(|| Mutex::new(HashMap::new()))
}

/// Records the abort handle of a stream task under `token`.
pub(crate) fn register_stream(token: u64, handle: AbortHandle) {
    stream_registry().lock().unwrap().insert(token, handle);
}

/// Removes `token` from the registry. A stream task calls this function when it ends normally.
pub(crate) fn unregister_stream(token: u64) {
    stream_registry().lock().unwrap().remove(&token);
}

/// Aborts the stream task under `token`. If no task has this token, the function does nothing.
pub(crate) fn abort_stream(token: u64) {
    if let Some(handle) = stream_registry().lock().unwrap().remove(&token) {
        handle.abort();
    }
}
