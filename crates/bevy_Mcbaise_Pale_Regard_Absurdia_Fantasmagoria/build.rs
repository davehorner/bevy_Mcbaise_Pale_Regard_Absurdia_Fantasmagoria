use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

fn workspace_root(manifest_dir: &Path) -> PathBuf {
    // crates/<this_crate>/Cargo.toml
    // workspace root is ../..
    manifest_dir
        .parent()
        .and_then(|p| p.parent())
        .unwrap_or(manifest_dir)
        .to_path_buf()
}

fn main() -> io::Result<()> {
    // Only generate embedded compressed assets for wasm builds with the burn_human feature.
    let target_arch = env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
    let burn_human = env::var("CARGO_FEATURE_BURN_HUMAN").is_ok();
    if target_arch != "wasm32" || !burn_human {
        return Ok(());
    }

    let manifest_dir = PathBuf::from(env::var("CARGO_MANIFEST_DIR").unwrap());
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());

    let root = workspace_root(&manifest_dir);
    let tensor_path = root.join("assets/model/fullbody_default.safetensors");

    // Re-run if the source tensor changes.
    println!("cargo:rerun-if-changed={}", tensor_path.display());

    let tensor_bytes = fs::read(&tensor_path).map_err(|e| {
        io::Error::new(
            e.kind(),
            format!(
                "failed to read {} (needed for wasm embedding): {e}",
                tensor_path.display()
            ),
        )
    })?;

    // LZ4-compress with prepended uncompressed size for easy decompression.
    let compressed = lz4_flex::compress_prepend_size(&tensor_bytes);

    let out_path = out_dir.join("fullbody_default.safetensors.lz4");
    fs::write(&out_path, compressed)?;

    Ok(())
}
