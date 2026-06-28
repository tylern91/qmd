# qmd

Hybrid local document search in a single static binary.

No Node. No Bun. No native-module rebuild per platform. Build once, run anywhere.

## Contents

- [Why Rust](#why-rust)
- [Installation](#installation)
- [Quick start](#quick-start)
- [CLI reference](#cli-reference)
- [Inference backends](#inference-backends)
- [Environment variables](#environment-variables)
- [Workspace layout](#workspace-layout)
- [Crate API](#crate-api)
- [Design decisions](#design-decisions)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

---

## Why Rust

qmd ships as a ~60MB self-contained binary with no runtime dependencies:

- SQLite bundled via `rusqlite` — no system SQLite dependency
- BM25 via Tantivy (pure Rust) — no FTS5 extension
- Vector search via usearch (HNSW, C++ header-only, statically linked)
- Inference via llama-cpp-2 (Metal on macOS, CPU on Linux/Windows)

---

## Installation

### From source (recommended while in development)

Requirements: Rust stable (≥1.78), cmake ≥3.14 (pinned to 3.x — see [Troubleshooting](#troubleshooting)), Xcode Command Line Tools (macOS) or `build-essential` (Linux).

```sh
# Clone the repo
git clone https://github.com/tobilu/qmd
cd qmd

# Development build (fast, debug symbols)
cargo build -p qmd-cli

# Optimized release binary (~60MB, fat LTO + stripped)
cargo build --profile dist -p qmd-cli
# → target/dist/qmd

# Install to ~/.cargo/bin/
cargo install --path qmd-cli --profile dist
```

### With ONNX Runtime backend (CoreML / CUDA / DirectML)

```sh
cargo build --profile dist -p qmd-cli --features ort-backend
```

This downloads the ONNX Runtime library at build time. The resulting binary supports CoreML (Apple Neural Engine on macOS), CUDA (NVIDIA GPU), and DirectML (Windows GPU) in addition to the CPU fallback.

### Linux

```sh
sudo apt-get install cmake build-essential
cargo build -p qmd-cli
```

For a fully static MUSL binary (no glibc dependency):

```sh
rustup target add x86_64-unknown-linux-musl
RUSTFLAGS="-C target-feature=+crt-static" \
  cargo build --profile dist -p qmd-cli --target x86_64-unknown-linux-musl
```

---

## Quick start

```sh
# Index a directory
qmd collection add ~/notes --name notes
qmd context add qmd://notes "Personal notes and ideas"
qmd embed                          # downloads GGUF models on first run (~900MB)

# Search
qmd search "project timeline"      # BM25 keyword
qmd vsearch "deployment process"   # vector similarity
qmd query "quarterly planning"     # hybrid BM25 + vector + rerank (best quality)

# MCP server (for Claude, Cursor, etc.)
qmd mcp                            # stdio transport
qmd mcp --http --port 8181         # Streamable HTTP transport
```

---

## CLI reference

All flags and subcommands are available from the `qmd` binary (`target/dist/qmd`).

| Command | Description |
|---------|-------------|
| `qmd query <text>` | Hybrid search: BM25 + vector + rerank |
| `qmd search <text>` | BM25 keyword search only |
| `qmd vsearch <text>` | Vector similarity only |
| `qmd get <path\|#docid>` | Retrieve document by path or content hash |
| `qmd multi-get <glob>` | Retrieve multiple documents |
| `qmd ls [collection[/path]]` | List collections or files |
| `qmd embed [-c collection]` | Generate embeddings |
| `qmd update [-c collection]` | Re-index collections |
| `qmd status` | Index health and collection summary |
| `qmd doctor` | Diagnose config, index, model, and device issues |
| `qmd bench [-n N]` | Embed throughput benchmark (default: 5 rounds) |
| `qmd eval [--mode bm25\|vec\|hybrid] [--verbose]` | Search quality eval against synthetic fixtures |
| `qmd mcp [--http] [--port N]` | Start MCP server |
| `qmd collection add <path>` | Add a directory as a collection |
| `qmd collection list` | List all collections |
| `qmd collection remove <name>` | Remove a collection |
| `qmd collection rename <old> <new>` | Rename a collection |
| `qmd collection show <name>` | Show collection details |
| `qmd collection update-cmd <name> [cmd]` | Set/clear pre-update hook |
| `qmd collection include/exclude <name>` | Toggle from default queries |
| `qmd context add [path] <text>` | Add context for a path |
| `qmd context list` | List all contexts |
| `qmd context rm <path>` | Remove context |
| `qmd context check` | Find paths missing context |
| `qmd init` | Create a project-local `.qmd` index |

Global flags (before the subcommand):

```
--index-dir <path>       Override index directory ($QMD_INDEX_DIR)
--backend llama|ort      Inference backend ($QMD_INFERENCE_BACKEND)
--ort-ep auto|coreml|cuda|directml|cpu   ORT execution provider ($QMD_ORT_EP)
```

---

## Inference backends

Two backends are available, selected at runtime via env var or `--backend` flag.

### LlamaCppBackend (default)

Uses [llama-cpp-2](https://github.com/utilityai/llama-cpp-rs) to run GGUF models locally.

| Role | Model | Size |
|------|-------|------|
| Embeddings | `ggml-org/embeddinggemma-300M-GGUF` | ~300MB |
| Reranking | `ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF` | ~600MB |

Models are downloaded automatically from HuggingFace on first use and cached at `~/.cache/huggingface/hub/`.

On macOS, llama.cpp uses Metal (Apple GPU) automatically. On Linux, CPU-only unless CUDA is available.

```sh
qmd embed                          # uses LlamaCppBackend by default
qmd --backend llama embed          # explicit
QMD_INFERENCE_BACKEND=llama qmd embed
```

### OrtBackend (`ort-backend` feature)

Uses [ONNX Runtime](https://ort.pyke.io/) with pluggable execution providers. Build with `--features ort-backend`.

| Role | Model | Size |
|------|-------|------|
| Embeddings | `BAAI/bge-base-en-v1.5` (ONNX) | ~440MB |
| Reranking | *(not supported — falls back to LlamaCppBackend)* | — |

Execution providers selected by `--ort-ep` or `QMD_ORT_EP`:

| EP | Flag | Platform | Hardware |
|----|------|----------|----------|
| CoreML | `coreml` | macOS | Apple Neural Engine + GPU |
| CUDA | `cuda` | Linux / Windows | NVIDIA GPU |
| DirectML | `directml` | Windows | Any GPU via DirectML |
| CPU | `cpu` | All | CPU fallback |
| Auto | `auto` (default) | All | CoreML on macOS, CPU elsewhere |

```sh
# CoreML (Apple Neural Engine — fastest for embed-sized models on M-series)
QMD_INFERENCE_BACKEND=ort QMD_ORT_EP=coreml qmd embed
qmd --backend ort --ort-ep coreml embed

# Benchmark both backends back-to-back
qmd bench -n 5
QMD_INFERENCE_BACKEND=ort qmd bench -n 5
```

---

## Environment variables

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `QMD_INDEX_DIR` | path | `~/.cache/qmd-rs/` | Index storage directory |
| `QMD_INFERENCE_BACKEND` | `llama`, `ort` | `llama` | Inference backend |
| `QMD_ORT_EP` | `auto`, `coreml`, `cuda`, `directml`, `cpu` | `auto` | ONNX Runtime EP |
| `QMD_FORCE_CPU` | `1` | *(unset)* | Disable GPU layers in LlamaCppBackend |
| `QMD_CI` | `1` | *(unset)* | Skip model downloads (CI / offline use) |

---

## Workspace layout

```
qmd/                    # repo root = Cargo workspace
├── Cargo.toml          # workspace definition + release/dist profiles
├── .cargo/config.toml  # MUSL static build target config
├── crates/
│   ├── qmd-core/       # engine: search, chunking, store, collections
│   ├── qmd-llm/        # inference backends (LlamaCpp + ORT)
│   ├── qmd-cli/        # CLI entry point (clap)
│   └── qmd-mcp/        # MCP server (rmcp, stdio + HTTP)
├── docs/               # SYNTAX.md and other reference docs
├── assets/             # architecture diagram
└── finetune/           # model fine-tuning pipeline (independent)
```

### Build profiles

| Profile | Command | LTO | Strip | Use |
|---------|---------|-----|-------|-----|
| `dev` | `cargo build` | off | none | development |
| `release` | `cargo build --release` | thin | debuginfo | testing |
| `dist` | `cargo build --profile dist` | fat | symbols | release binary |

---

## Crate API

### `qmd-core`

The search engine. Key public types:

```rust
use qmd_core::{Store, StoreConfig, SearchResult};

// Open (or create) an index
let store = Store::open(&index_dir, backend)?;

// Index a file
store.index_file(&path, &collection_name)?;

// Hybrid search: BM25 + vector + RRF + rerank
let results: Vec<SearchResult> = store.query("search terms", options)?;

// BM25 keyword search
let results = store.search("keyword", options)?;

// Vector similarity search
let results = store.vsearch("semantic query", options)?;
```

### `qmd-llm`

Inference backend abstraction. Implement `InferenceBackend` to add a new backend:

```rust
use qmd_llm::{InferenceBackend, BackendKind, create_backend};

pub trait InferenceBackend: Send {
    fn embed(&mut self, text: &str) -> Result<Vec<f32>>;
    fn embed_batch(&mut self, texts: &[&str]) -> Result<Vec<Vec<f32>>>;
    fn rerank(&mut self, query: &str, docs: &[&str]) -> Result<Vec<f32>>;
    fn generate_constrained(&mut self, prompt: &str, grammar: &str, root: &str) -> Result<String>;
    fn embed_model_name(&self) -> &str;
    fn rerank_model_name(&self) -> &str;
}

// Factory: reads QMD_INFERENCE_BACKEND + QMD_ORT_EP from env
let backend: Box<dyn InferenceBackend> = create_backend(&BackendKind::from_env())?;
```

All embeddings are returned as **unit-normalized f32 vectors** (L2 norm = 1.0). Cosine similarity is therefore equivalent to dot product.

### `qmd-mcp`

MCP server with five tools:

| Tool | Description |
|------|-------------|
| `query` | Hybrid search (recommended) |
| `search` | BM25 keyword search |
| `get` | Retrieve document by path or docid |
| `multi_get` | Retrieve multiple documents by glob |
| `status` | Index health summary |

Start modes:

```sh
qmd mcp                        # stdio (for Claude Desktop, Cursor, etc.)
qmd mcp --http                 # Streamable HTTP on port 8181
qmd mcp --http --port 9000     # custom port
```

---

## Design decisions

| Aspect | Choice |
|--------|--------|
| Search backend | Tantivy (BM25) + usearch (HNSW) |
| Index location | `~/.cache/qmd-rs/` |
| Embed model | embeddinggemma-300M (GGUF, Metal/CPU) |
| Rerank model | Qwen3-Reranker-0.6B (GGUF) |
| ORT backend | ✓ CoreML / CUDA / DirectML (feature-gated) |
| Query expansion | Qwen3-1.7B (optional, not auto-downloaded) |
| MlxBackend | **deferred** — `mlx-rs` `Array: !Send` conflicts with parallel embed pool; will add when `mlx-rs` ships `Send`-able arrays |
| Startup time | ~5ms (no JIT) |

The RRF fusion formula, BM25 field weights, chunking parameters (900 tokens / 15% overlap), and docid scheme (`first 6 hex chars of SHA-256(content)`) match the original qmd design so search quality is preserved.

See [BENCHMARK.md](BENCHMARK.md) for the Phase 0 spike results (inference backend + DB bake-off) that drove the Tantivy+usearch and llama-cpp-2 decisions.

---

## Troubleshooting

### cmake 4.x breaks the llama.cpp build

If you have cmake 4.x installed (e.g. from Homebrew's latest), `llama-cpp-sys-2` fails to compile because llama.cpp's `CMakeLists.txt` specifies `cmake_minimum_required(VERSION 3.14...3.28)` and cmake 4.x changed C compiler verification behavior.

```sh
# macOS fix — install cmake 3.x and put it first on PATH
brew install cmake@3
export PATH="$(brew --prefix cmake@3)/bin:$PATH"
```

On Linux, `apt-get install cmake` typically installs 3.x. The CI workflow pins cmake@3 automatically.

**Do not** add `target-cpu` flags to `.cargo/config.toml` — they change the llama-cpp-sys fingerprint and force a cmake rebuild every time the flag is new. Pass them at build time instead:

```sh
RUSTFLAGS="-C target-cpu=native" cargo build --profile dist -p qmd-cli
```

### Model downloads are slow / fail

Models are fetched from HuggingFace on first `qmd embed`. They are cached at `~/.cache/huggingface/hub/` and reused on subsequent runs.

If you're behind a proxy or in a restricted environment, set `HF_ENDPOINT` or use `HF_HUB_OFFLINE=1` with pre-downloaded models.

### `qmd embed` exits with "generate model not loaded"

This is expected — the query-expansion model (Qwen3-1.7B) is not downloaded by default. `qmd embed` only uses the embed model. Query expansion is only triggered during `qmd query` when the LLM decides it's needed; if the generate model is absent, it falls back to the raw query.

### "OrtBackend: reranking not supported"

`OrtBackend` handles embeddings only. Reranking requires a cross-encoder model (Qwen3-Reranker-0.6B) which runs via `LlamaCppBackend`. When `QMD_INFERENCE_BACKEND=ort`, `qmd query` uses ORT for embeddings and automatically falls back to LlamaCpp for reranking.

---

## Contributing

Before sending a PR:

1. Run `cargo fmt --all` and `cargo clippy --workspace -- -D warnings`
2. Run `cargo test --workspace --lib` (integration tests require downloaded models and are excluded from CI)
3. Check that `cargo build --workspace` and `cargo build -p qmd-cli --features ort-backend` both pass

The search quality gate is `qmd eval` — run it before and after your change and confirm all gates PASS:

```sh
# BM25 quality (no model, fast — run this always)
cargo run -p qmd-cli -- eval --mode bm25 --verbose

# Full hybrid quality (requires models — run before search-path changes)
QMD_INFERENCE_BACKEND=llama cargo run -p qmd-cli -- eval --mode hybrid

# Embed throughput (compare backends)
cargo run -p qmd-cli -- bench -n 5
```

The BM25 eval also runs in CI on every push (no model download needed). Hybrid eval is local-only.
