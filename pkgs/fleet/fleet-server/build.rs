//! Points `FLEET_WEB_DIST` (the embedded frontend, see `src/embed.rs`) at `../web/dist` when
//! it is unset, creating a placeholder `index.html` there for `cargo test` and dev builds
//! before the frontend has been built. If that directory can't be written (a read-only
//! source tree), the placeholder goes under `OUT_DIR` instead.

use std::path::{Path, PathBuf};

const PLACEHOLDER: &str = "<!doctype html><div id=\"app\"></div>\n";

fn write_placeholder(dir: &Path) -> std::io::Result<PathBuf> {
    std::fs::create_dir_all(dir)?;
    let index = dir.join("index.html");
    if !index.exists() {
        std::fs::write(&index, PLACEHOLDER)?;
    }
    dir.canonicalize()
}

fn main() {
    println!("cargo:rerun-if-changed=build.rs");
    println!("cargo:rerun-if-env-changed=FLEET_WEB_DIST");
    if let Some(dist) = std::env::var_os("FLEET_WEB_DIST") {
        println!("cargo:rerun-if-changed={}", PathBuf::from(dist).display());
        return;
    }
    let manifest = PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let out = PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    let dist = write_placeholder(&manifest.join("../web/dist"))
        .or_else(|_| write_placeholder(&out.join("web-dist")))
        .expect("creating a placeholder web dist");
    println!("cargo:rerun-if-changed={}", dist.display());
    println!("cargo:rustc-env=FLEET_WEB_DIST={}", dist.display());
}
