//! Value types for the reactive streams.
//!
//! The stream methods are on the opaque `Endpoint` type in `endpoint.rs` and on the opaque
//! `Connection` type in `connection.rs`. This module contains the value types that these streams
//! send to Dart. It also contains the conversion for the `#[non_exhaustive]` iroh `PathEvent` enum.
//! This conversion never matches the enum exhaustively.
//!
//! [`PathEventInfo`] is a flat struct with the unit enum [`PathEventKind`]. It is not an enum that
//! carries data, so FRB does not need `freezed` or `build_runner`. The Dart wrapper in
//! `watch.dart` shows the event as a sealed `PathEvent` class.

use flutter_rust_bridge::frb;
use iroh::endpoint::PathEvent;

/// Cancels a reactive stream by its token. The reactive streams are `watchAddr`,
/// `homeRelayStatus`, and `pathEvents`. The `onCancel` handler of the Dart subscription calls this
/// function. The stream task then stops and releases its iroh watcher or event stream
/// immediately. Thus the subscription does not leak resources or hang.
#[frb(sync)]
pub fn cancel_stream(token: u64) {
    crate::runtime::abort_stream(token);
}

/// The connection status of one home relay server. A `homeRelayStatus` update contains a list of
/// these values.
pub struct RelayStatusInfo {
    pub url: String,
    pub connected: bool,
    pub last_error: Option<String>,
    /// The reason that the relay server gave when it denied the authentication of the endpoint.
    /// Retries do not usually fix this failure.
    pub auth_denied_reason: Option<String>,
}

/// The kind of a [`PathEventInfo`]. `Unknown` holds each variant that a future iroh version adds to
/// the `#[non_exhaustive]` iroh enum.
pub enum PathEventKind {
    Opened,
    Closed,
    Selected,
    Lagged,
    Unknown,
}

/// A path lifecycle event of a connection, in flat form. `remote_addr` has a value for `Opened`,
/// `Closed`, and `Selected`. `missed` has a value for `Lagged`. It is the number of events that
/// the stream dropped.
pub struct PathEventInfo {
    pub kind: PathEventKind,
    pub remote_addr: Option<String>,
    pub missed: Option<u64>,
}

/// Maps the `#[non_exhaustive]` iroh `PathEvent` to a [`PathEventInfo`]. The `..` rest patterns
/// and the last `_` arm keep this function compatible with new minor iroh versions.
pub(crate) fn map_path_event(event: PathEvent) -> PathEventInfo {
    match event {
        PathEvent::Opened { remote_addr, .. } => PathEventInfo {
            kind: PathEventKind::Opened,
            remote_addr: Some(format!("{remote_addr:?}")),
            missed: None,
        },
        PathEvent::Closed { remote_addr, .. } => PathEventInfo {
            kind: PathEventKind::Closed,
            remote_addr: Some(format!("{remote_addr:?}")),
            missed: None,
        },
        PathEvent::Selected { remote_addr, .. } => PathEventInfo {
            kind: PathEventKind::Selected,
            remote_addr: Some(format!("{remote_addr:?}")),
            missed: None,
        },
        PathEvent::Lagged { missed, .. } => PathEventInfo {
            kind: PathEventKind::Lagged,
            remote_addr: None,
            missed: Some(missed),
        },
        _ => PathEventInfo {
            kind: PathEventKind::Unknown,
            remote_addr: None,
            missed: None,
        },
    }
}
