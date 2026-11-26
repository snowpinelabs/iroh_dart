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
//!
//! [`PathInfo`] is an owned copy of one iroh `Path` in a `PathList` snapshot. An iroh `Path`
//! borrows its `Connection`, so it cannot cross the FFI boundary.

use flutter_rust_bridge::frb;
use iroh::endpoint::{Path, PathEvent, PathId, PathList};

/// Returns a new token for a reactive stream. Each call returns a different value for the full
/// process, also across Dart isolates. Give this token to the stream function and to
/// [`cancel_stream`].
#[frb(sync)]
pub fn new_stream_token() -> u64 {
    crate::runtime::next_stream_token()
}

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

/// A path lifecycle event of a connection, in flat form. `path_id` and `remote_addr` have a value
/// for `Opened`, `Closed`, and `Selected`. `missed` has a value for `Lagged`. It is the number of
/// events that the stream dropped.
pub struct PathEventInfo {
    pub kind: PathEventKind,
    /// The QUIC path ID. It is equal to [`PathInfo::path_id`] of the same path.
    pub path_id: Option<u32>,
    pub remote_addr: Option<String>,
    pub missed: Option<u64>,
}

/// An open network path of a connection, from one `PathList` snapshot.
pub struct PathInfo {
    /// The QUIC path ID. A path ID is unique in its connection, and iroh does not use it again.
    /// `SendStream::set_affinity` uses this value to select a path.
    pub path_id: u32,
    /// The remote transport address, as debug text.
    pub remote_addr: String,
    /// `true` if the path is a direct IP path.
    pub is_ip: bool,
    /// `true` if the path goes through a relay server.
    pub is_relay: bool,
    /// `true` if the connection uses this path for application data at this time.
    pub is_selected: bool,
    /// The round-trip time estimate of the path, in microseconds.
    pub rtt_micros: u64,
}

/// Converts an iroh `PathId` to its `u32` value.
///
/// `PathId` has no public accessor for its value. Its `Display` form is the decimal `u32` value,
/// and `From<u32>` makes the same `PathId` again. The `path_id_round_trip` test makes sure of this.
pub(crate) fn path_id_to_u32(id: PathId) -> u32 {
    id.to_string()
        .parse()
        .expect("the Display form of a PathId is a u32")
}

/// Converts a `u32` value from Dart to an iroh `PathId`.
pub(crate) fn path_id_from_u32(value: u32) -> PathId {
    PathId::from(value)
}

/// Copies one borrowed iroh `Path` into an owned [`PathInfo`].
pub(crate) fn map_path(path: &Path<'_>) -> PathInfo {
    PathInfo {
        path_id: path_id_to_u32(path.id()),
        remote_addr: format!("{:?}", path.remote_addr()),
        is_ip: path.is_ip(),
        is_relay: path.is_relay(),
        is_selected: path.is_selected(),
        rtt_micros: u64::try_from(path.rtt().as_micros()).unwrap_or(u64::MAX),
    }
}

/// Copies each path of an iroh `PathList` snapshot into an owned [`PathInfo`].
pub(crate) fn map_path_list(paths: &PathList<'_>) -> Vec<PathInfo> {
    paths.iter().map(|path| map_path(&path)).collect()
}

/// Maps the `#[non_exhaustive]` iroh `PathEvent` to a [`PathEventInfo`]. The `..` rest patterns
/// and the last `_` arm keep this function compatible with new minor iroh versions.
pub(crate) fn map_path_event(event: PathEvent) -> PathEventInfo {
    match event {
        PathEvent::Opened {
            id, remote_addr, ..
        } => PathEventInfo {
            kind: PathEventKind::Opened,
            path_id: Some(path_id_to_u32(id)),
            remote_addr: Some(format!("{remote_addr:?}")),
            missed: None,
        },
        PathEvent::Closed {
            id, remote_addr, ..
        } => PathEventInfo {
            kind: PathEventKind::Closed,
            path_id: Some(path_id_to_u32(id)),
            remote_addr: Some(format!("{remote_addr:?}")),
            missed: None,
        },
        PathEvent::Selected {
            id, remote_addr, ..
        } => PathEventInfo {
            kind: PathEventKind::Selected,
            path_id: Some(path_id_to_u32(id)),
            remote_addr: Some(format!("{remote_addr:?}")),
            missed: None,
        },
        PathEvent::Lagged { missed, .. } => PathEventInfo {
            kind: PathEventKind::Lagged,
            path_id: None,
            remote_addr: None,
            missed: Some(missed),
        },
        _ => PathEventInfo {
            kind: PathEventKind::Unknown,
            path_id: None,
            remote_addr: None,
            missed: None,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn path_id_round_trip() {
        for value in [0u32, 1, 7, 255, 65_536, u32::MAX] {
            let id = path_id_from_u32(value);
            assert_eq!(path_id_to_u32(id), value);
            assert_eq!(id, PathId::from(value));
        }
        assert_eq!(path_id_to_u32(PathId::ZERO), 0);
        assert_eq!(path_id_to_u32(PathId::MAX), u32::MAX);
    }
}
