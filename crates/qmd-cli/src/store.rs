use anyhow::{Context, Result};
use qmd_core::{Store, StoreConfig};
use qmd_llm::{no_backend, BackendKind, create_backend};
use std::path::{Path, PathBuf};

/// Resolve the index directory:
///   1. `--index-dir` flag / `QMD_INDEX_DIR` env
///   2. `.qmd/` in the current directory (project-local)
///   3. `~/.cache/qmd-rs/` (global default)
pub fn resolve_index_dir(override_path: Option<&str>) -> Result<PathBuf> {
    if let Some(p) = override_path {
        return Ok(PathBuf::from(p));
    }

    // Project-local .qmd/ takes precedence over global
    let local = PathBuf::from(".qmd");
    if local.join("index.sqlite").exists() {
        return Ok(local);
    }

    // Global default
    let home = dirs::cache_dir()
        .or_else(dirs::home_dir)
        .context("cannot determine home directory")?;
    Ok(home.join("qmd-rs"))
}

pub fn store_config(index_dir: &Path) -> StoreConfig {
    std::fs::create_dir_all(index_dir).ok();
    StoreConfig {
        db_path: index_dir.join("index.sqlite"),
        tantivy_dir: index_dir.join("tantivy"),
        hnsw_path: index_dir.join("hnsw.usearch"),
    }
}

/// Open a store without the inference backend (for FTS-only commands).
pub fn open_store_no_backend(index_dir: &Path) -> Result<Store> {
    Store::open(store_config(index_dir), no_backend())
}

/// Open a store with the inference backend selected by `QMD_INFERENCE_BACKEND`
/// (or the provided override). Downloads models on first run.
pub fn open_store_with_backend(index_dir: &Path) -> Result<Store> {
    open_store_with_backend_kind(index_dir, &BackendKind::from_env())
}

/// Open a store with an explicit backend kind (used when CLI flags override env).
pub fn open_store_with_backend_kind(index_dir: &Path, kind: &BackendKind) -> Result<Store> {
    let backend = create_backend(kind).context("failed to initialize inference backend")?;
    Store::open(store_config(index_dir), backend)
}

