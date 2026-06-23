//! Captures the resolved `iroh` version from Cargo.lock at build time and exposes it as the
//! `IROH_CRATE_VERSION` compile-time env var, so `irohdart_iroh_version()` can report the actual
//! iroh version rather than this wrapper crate's own version.

use std::path::Path;

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap_or_default();
    let lock_path = Path::new(&manifest_dir).join("Cargo.lock");
    println!("cargo:rerun-if-changed={}", lock_path.display());

    let version = std::fs::read_to_string(&lock_path)
        .ok()
        .and_then(|lock| iroh_version_from_lock(&lock))
        // Fall back to the major version we pin in Cargo.toml if the lockfile can't be read.
        .unwrap_or_else(|| "1.0".to_string());

    println!("cargo:rustc-env=IROH_CRATE_VERSION={version}");
}

/// Finds the `version` of the `[[package]]` entry named `iroh` in a Cargo.lock file.
fn iroh_version_from_lock(lock: &str) -> Option<String> {
    let mut in_iroh = false;
    for line in lock.lines() {
        let line = line.trim();
        if line == "[[package]]" {
            in_iroh = false;
        } else if line == "name = \"iroh\"" {
            in_iroh = true;
        } else if in_iroh {
            if let Some(rest) = line.strip_prefix("version = \"") {
                return rest.strip_suffix('"').map(str::to_string);
            }
        }
    }
    None
}
