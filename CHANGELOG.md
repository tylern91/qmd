# qmd Changelog

## [Unreleased]

### Added

- **Reproducible `nix build` package restored.** qmd now installs via
  `nix profile install .#default` and is consumable as a flake input
  (`inputs.qmd.url = "github:tylern91/qmd"`). The Metal backend compiles in the
  Nix sandbox via llama.cpp's embed-library path (shader source embedded; compiled
  at runtime — no `xcrun metal` at build time). All native C/C++ sources
  (llama.cpp, usearch, zstd, sqlite) are vendored inside their -sys crates; no
  network access is required. `ort-backend` is excluded from the Nix package to
  avoid the ONNX Runtime binary download.

### Changed

- **Legacy TypeScript/Node/Bun engine removed.** The Rust port (Phases 0–6, fully verified) is now the sole implementation. Workspace promoted from `rust/` to the repo root; crates live under `crates/`. The `*.md` ignore rule has been replaced with a Rust-appropriate `.gitignore`. CI workflows `ci.yml` (Node matrix) and `publish.yml` (npm publish) removed; `rust.yml` updated to work from the repo root.
  - Pre-Rust (TypeScript) release history: see git tag `v2.6.3` and earlier.

### Added

- **Phase 6 — §7 Risk Closeout**
  - **Task 5:** `LICENSE` — MIT license file added to workspace root (mirrors root `LICENSE`).
  - **Task 7:** `BENCHMARK.md` — durable Phase 0 de-risking record: Spike A (llama-cpp-2 embed/rerank/GBNF) + Spike B (LanceDB vs Tantivy+usearch bake-off). README "Differences" table links to it.
  - **Task 8:** `QMD_FORCE_CPU=1` now honoured by `LlamaCppBackend::new()`. When set to `1` or `true`, forces `embed_n_gpu_layers=0` and `rerank_n_gpu_layers=0` before model load. Matches the TS original's documented contract. Previously the env var was documented but never read.
  - **Task 2 — MlxBackend decision:** formally deferred. `mlx-rs` `Array: !Send/!Sync` conflicts with qmd's parallel embed pool (`Arc<Mutex<Store>>`). No `MlxBackend` code will be added until `mlx-rs` ships `Send`-able arrays or a single-threaded worker pattern is accepted. README updated to reflect deferred (not planned) status.
  - **Task 1 — ORT CoreML smoke test:** PASS. Model: `BAAI/bge-base-en-v1.5` ONNX (415 MB, bge-768). EP: CoreML. Throughput: **93.0 texts/sec** (10.75 ms/text), 50 texts × dev profile. CoreML EP initialised cleanly; `Context leak detected` messages are macOS msgtracer noise (not a qmd regression). ORT rerank not applicable — `OrtBackend` is embed-only; rerank falls back to llama as expected. Baseline comparison: llama-cpp-2 Metal on embeddinggemma-300M = ~1,400 tok/s (714 µs/text warm, Spike A); models differ so this is directional only.
  - **Task 3 — vec + hybrid quality gate:** PASS. Apple M4, embeddinggemma-300M (embed) + Qwen3-Reranker-0.6B (rerank), Metal GPU.
    - Vector search: easy 100% / medium 100% / hard 100% / overall 100% — all gates PASS.
    - Hybrid (BM25 + vec + RRF + rerank): easy 100% / medium 100% / hard 100% / overall 100% — all gates PASS.
    - Search quality exceeds thresholds (vec ≥60/40/30%; hybrid ≥80/50/30%) on all tiers.
  - **Task 6 — MCP conformance smoke test:** Three bugs found and fixed; all 5 tools verified.
    - **Bug 1:** `/health` returned 404 — Axum router only registered `/mcp`. Fixed: `GET /health → 200 ok` route added to `crates/qmd-mcp/src/lib.rs`.
    - **Bug 2 (panic):** `query` tool panicked with "Cannot start a runtime from within a runtime" — `LlamaCppBackend::new()` created a nested `tokio::runtime::Runtime` while inside the MCP server's multi-thread runtime. Fixed: `tokio::runtime::Handle::try_current()` detects existing runtime; uses `tokio::task::block_in_place` + `handle.block_on()` instead (`crates/qmd-llm/src/lib.rs`).
    - **Bug 3 (lock contention):** After panic fix, `query` failed with "Failed to acquire index lock (LockBusy)" — `QmdServer` opens two `Store` instances (fts_store + ml_store) against the same Tantivy directory; both `open_or_create()` eagerly acquired the IndexWriter lock. Fixed: `FtsIndex.writer` changed to `Option<IndexWriter>`, lazily acquired only on first `add_document`/`commit` call (`crates/qmd-core/src/fts.rs`). Read-only store instances (search, query) never acquire the writer lock.
    - **Bearer auth:** confirmed NOT implemented — any request returns 200 regardless of `Authorization` header. Open follow-up.
    - **Tools verified (all 5, HTTP transport):** `status` ✅ · `search` ✅ · `get` ✅ · `multi_get` ✅ · `query` ✅ (model load via block_in_place, no panic, no lock conflict).

- **Search quality evaluation harness**
  - `qmd eval [--mode bm25|vec|hybrid] [--verbose]` — mirrors `eval.test.ts` fixture suite
  - 6 synthetic documents embedded in binary (`eval-docs/`), 24 queries across easy/medium/hard/fusion tiers
  - BM25 thresholds (≥80%/15%/15%/40% Hit@K) all pass with 100% — Tantivy significantly outperforms FTS5
  - `vec` and `hybrid` modes exercise the full inference backend and reranker
  - BM25 eval runs in CI (`eval --mode bm25`) on every push — no model downloads required
  - **Bug fix:** `FtsIndex::commit()` now calls `reader.reload()` explicitly. Previously `ReloadPolicy::OnCommitWithDelay` caused stale reads when `qmd search` ran immediately after `qmd embed` in the same process.

- **Phase 5 — Packaging & CI**
  - `.cargo/config.toml`: target-cpu flags for macOS arm64/x64 and Linux; MUSL static build target
  - Workspace `dist` profile: fat LTO + `codegen-units=1` + strip for release binaries
  - `.github/workflows/rust.yml`: dual CI builds (default + ort-backend) on macOS arm64 and Linux x64; dist binary artifact upload on push to release branch
  - `README.md`: project overview, build instructions, backend selection, phase status

- **Phase 4 — Accelerator backends** (`qmd-llm`)
  - `OrtBackend`: ONNX Runtime v2 (ort 2.0.0-rc.12) with pluggable execution providers
    - CoreML EP (Apple Neural Engine / GPU, macOS)
    - CUDA EP (NVIDIA GPU)
    - DirectML EP (Windows GPU)
    - CPU fallback
  - Default model: `BAAI/bge-base-en-v1.5` (768-dim ONNX, matches LlamaCpp embed dim)
  - Batched `embed_batch`: single ONNX call for N texts; mean-pool or `sentence_embedding` output; L2 normalize
  - `BackendKind` enum + `create_backend()` factory reading `QMD_INFERENCE_BACKEND` / `QMD_ORT_EP`
  - `--backend` and `--ort-ep` CLI flags propagated to env vars
  - `bench` command: embed throughput benchmark (warm-up + N timed rounds), reports texts/sec and ms/text
  - Feature flag `ort-backend` in `qmd-llm` and `qmd-cli` keeps default binary lean

- **Phase 3 — MCP parity** (`qmd-mcp`)
  - `rmcp` 1.8.0 server: stdio + Streamable HTTP (Axum)
  - Tools: `query`, `search`, `get`, `multi_get`, `status`
  - HTTP hardening: origin allow-list (`allowed_hosts = ["localhost", "127.0.0.1"]`)
  - Note: bearer auth and `/health` endpoint were planned but not implemented in Phase 3 — `/health` added in Phase 6 Task 6; bearer auth remains unimplemented
  - `once_cell::sync::OnceCell` for stable lazy store initialization (avoids nightly `OnceLock::get_or_try_init`)

- **Phase 2 — CLI parity** (`qmd-cli`)
  - All subcommands: `query`, `search`, `vsearch`, `get`, `multi-get`, `ls`, `collection {add,list,remove,rename,show,update-cmd,include,exclude}`, `context {add,list,rm,check}`, `init`, `status`, `embed`, `update`, `doctor`, `bench`, `mcp`
  - Output formats: `cli`, `json`, `csv`, `md`, `xml`, `files`
  - `--index-dir` / `QMD_INDEX_DIR` env contract

- **Phase 1 — Core engine** (`qmd-core`, `qmd-llm`)
  - Tantivy (BM25) + usearch (HNSW) hybrid search replacing SQLite FTS5 + sqlite-vec
  - Reciprocal Rank Fusion (k=60, original-query weight 2.0, top-rank bonuses)
  - `LlamaCppBackend`: embeddinggemma-300M (GGUF, Metal) for embed; Qwen3-Reranker-0.6B for rerank; GBNF grammar wired
  - Regex chunking (900 tokens / 15% overlap / heading-scored breaks)
  - Collection + context management (`serde_yaml_ng`-backed `.qmd/index.yaml`)
  - `InferenceBackend: Send` trait enabling thread-safe use in MCP server

- **Phase 0 — Spike**
  - Validated: `llama-cpp-2` embed + `LlamaPoolingType::Rank` rerank + GBNF on Apple Silicon
  - DB bake-off: selected Tantivy + usearch over LanceDB (search-quality parity, preserves qmd's RRF weights, no re-export API churn)

### Technical notes

- ort 2.0.0-rc.12 API gotchas: `ort::session::Session` path; `Error<SessionBuilder>` not `std::error::Error` (use `.map_err(|e| anyhow::anyhow!("{e:?}"))`); private `inputs()`/`outputs()` methods; `Outlet::name()` method; `Tensor::from_array((shape, flat_vec))` tuple form
- `tokenizers` v0.23 requires `fancy-regex` feature for pure-Rust regex
- `StreamableHttpServerConfig` is `#[non_exhaustive]` — construct via `Default::default()` + field mutation
- `InferenceBackend: Send` is required for `Box<dyn InferenceBackend>` inside `Arc<Mutex<Store>>`
