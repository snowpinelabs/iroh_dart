//! Reads the resolved `iroh` version from `Cargo.lock` at build time.
//! The build script gives this version to the compiler as the `IROH_CRATE_VERSION` environment
//! variable. Thus `irohdart_iroh_version()` reports the real iroh version, not the version of this
//! crate.

use std::path::Path;

fn main() {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR").unwrap_or_default();
    let lock_path = Path::new(&manifest_dir).join("Cargo.lock");
    println!("cargo:rerun-if-changed={}", lock_path.display());

    let version = std::fs::read_to_string(&lock_path)
        .ok()
        .and_then(|lock| iroh_version_from_lock(&lock))
        // If the build script cannot read the lockfile, it uses the fixed value "1.4".
        .unwrap_or_else(|| "1.4".to_string());

    println!("cargo:rustc-env=IROH_CRATE_VERSION={version}");
}

/// Finds the `version` of the `[[package]]` entry named `iroh` in a `Cargo.lock` file.
/// Returns `None` if the file has no such entry.
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
