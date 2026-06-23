//! Reactive-stream mirror types.
//!
//! The streaming methods live on the opaque `Endpoint`/`Connection` (in `endpoint.rs`/
//! `connection.rs`); this module holds the Dart-shaped value types they emit and the
//! `#[non_exhaustive]`-safe mapping for `PathEvent` (never matched exhaustively).
//!
//! `PathEvent` is kept **flat** (a unit `PathEventKind` + a struct) rather than a data-carrying
//! enum so FRB does not pull in `freezed`/`build_runner`; the Dart wrapper (`watch.dart`) re-presents
//! it as a proper sealed `PathEvent`.

use flutter_rust_bridge::frb;
use iroh::endpoint::PathEvent;

/// Cancels a reactive stream (watchAddr / homeRelayStatus / pathEvents) by its token. Invoked from
/// the Dart subscription's `onCancel` so a cancelled subscription promptly drops the iroh watcher
/// (no leak, no hang).
#[frb(sync)]
pub fn cancel_stream(token: u64) {
    crate::runtime::abort_stream(token);
}

/// One relay server's connection status (a `homeRelayStatus` update carries a list of these).
pub struct RelayStatusInfo {
    pub url: String,
    pub connected: bool,
    pub last_error: Option<String>,
}

/// Discriminant for [`PathEventInfo`]. `Unknown` absorbs any future `#[non_exhaustive]` variant.
pub enum PathEventKind {
    Opened,
    Closed,
    Selected,
    Lagged,
    Unknown,
}

/// A path lifecycle event on a connection, in flat form. `remote_addr` is set for
/// `Opened`/`Closed`/`Selected`; `missed` is set for `Lagged`.
pub struct PathEventInfo {
    pub kind: PathEventKind,
    pub remote_addr: Option<String>,
    pub missed: Option<u64>,
}

/// Maps iroh's `#[non_exhaustive]` `PathEvent` onto [`PathEventInfo`]. The `..` rest-patterns and the
/// trailing `_` arm keep this forward-compatible across minor iroh bumps.
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
