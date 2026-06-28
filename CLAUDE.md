# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# QMD - Query Markup Documents

A hybrid local document search engine that ships as a single static binary. No Node, no Bun, no native-module rebuild step.

## Build & test

```sh
# Build all workspace crates (fast debug)
cargo build --workspace

# Build with the ORT (ONNX Runtime / CoreML / CUDA) backend
cargo build -p qmd-cli --features ort-backend

# Run the binary directly from source
cargo run --bin qmd -- <command>

# Optimized release binary (~60MB, fat LTO + stripped)
cargo build --profile dist -p qmd-cli
# → target/dist/qmd

# Check formatting and lints
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings

# Unit tests (no model downloads required)
cargo test --workspace --lib

# Search quality regression gate (BM25, runs in CI, no models)
cargo run --bin qmd -- eval --mode bm25

# Full eval with models (local only, not CI)
cargo run --bin qmd -- eval --mode vec --verbose
cargo run --bin qmd -- eval --mode hybrid --verbose
```

## Crate map

```
crates/
├── qmd-core/   # Engine: chunking, FTS (Tantivy), vector (usearch/HNSW), RRF fusion,
│               # document/collection CRUD, SQLite metadata, .qmd/index.yaml config.
│               # Key entry point: Store::open() / hybridQuery() in src/store.rs.
├── qmd-llm/    # Inference backend abstraction (InferenceBackend trait) + implementations:
│               # LlamaCppBackend (GGUF, Metal/CPU), OrtBackend (ONNX, CoreML/CUDA/DirectML).
│               # Model download via hf-hub; env vars: QMD_INFERENCE_BACKEND, QMD_ORT_EP.
├── qmd-cli/    # CLI (clap): all subcommands + output formats (cli/json/csv/md/xml/files).
│               # Eval harness (no model) embeds 6 fixture docs via include_str!.
└── qmd-mcp/    # MCP server (rmcp 1.8.0): stdio + Streamable HTTP (Axum).
                # Tools: query, search, get, multi_get, status. HTTP port default 8181.
```

## CLI commands

```sh
qmd collection add . --name <n>   # Create/index collection
qmd collection list               # List all collections with details
qmd collection remove <name>      # Remove a collection by name
qmd collection rename <old> <new> # Rename a collection
qmd init                          # Create a project-local .qmd index
qmd ls [collection[/path]]        # List collections or files in a collection
qmd context add [path] "text"     # Add context for path (defaults to current dir)
qmd context list                  # List all contexts
qmd context check                 # Check for collections/paths missing context
qmd context rm <path>             # Remove context
qmd get <file>[:from[:count]]     # Get by path or docid (#abc123); optional line range
qmd multi-get <pattern>           # Get multiple docs by glob or comma-separated list
qmd status                        # Show index status and collections
qmd doctor                        # Diagnose config, index, model, and device issues
qmd update                        # Re-index collections; configured update hooks run first
qmd embed                         # Generate vector embeddings (downloads GGUF models on first run)
qmd query <query>                 # Hybrid search: BM25 + vector + rerank (recommended)
qmd search <query>                # Full-text keyword search (BM25, no LLM)
qmd vsearch <query>               # Vector similarity search (no reranking)
qmd bench [--rounds N]            # Embedding throughput benchmark
qmd eval [--mode bm25|vec|hybrid] # Search quality evaluation
qmd mcp                           # Start MCP server (stdio transport)
qmd mcp --http [--port N]         # Start MCP server (HTTP, default port 8181)
qmd mcp --http --daemon           # Start as background daemon
qmd mcp stop                      # Stop background MCP daemon
```

## Architecture

- **BM25:** Tantivy FTS (field boosts: filepath=1.5, title=4.0, body=1.0)
- **Vector:** usearch HNSW (cosine similarity, f32)
- **Fusion:** Reciprocal Rank Fusion (k=60, original-query weight 2.0, top-rank bonuses)
- **Reranking:** Qwen3-Reranker-0.6B via llama-cpp-2 (cross-encoder, `LlamaPoolingType::Rank`)
- **Embeddings:** embeddinggemma-300M Q8_0 GGUF (dim=768, Metal/CPU)
- **Chunking:** 900 tokens/chunk, 15% overlap, heading-scored break points
- **Model cache:** `~/.cache/huggingface/hub/` (hf-hub, Python-compatible layout)
- **Index location:** `~/.cache/qmd-rs/` (Tantivy + usearch HNSW, SQLite metadata)
- **Config:** `~/.qmd/index.yaml` or project-local `.qmd/index.yaml`

**Query flow** (`hybridQuery` in `crates/qmd-core/src/store.rs`): BM25 probe (strong single top result short-circuits LLM expansion) → query expansion (lex/vec/hyde variants via Qwen3) → Tantivy FTS for lexical expansions + batched vector search for vec/hyde → Reciprocal Rank Fusion → cross-encoder rerank (skip with `--no-rerank`).

## Environment variables

| Variable | Effect |
|---|---|
| `QMD_FORCE_CPU=1` | Disable Metal/CUDA GPU offload for LlamaCpp models |
| `QMD_INFERENCE_BACKEND=llama\|ort` | Select inference backend (default: llama) |
| `QMD_ORT_EP=auto\|coreml\|cuda\|directml\|cpu` | ORT execution provider |
| `QMD_CI=1` | Skip model downloads (CI / offline use) |
| `HF_HUB_OFFLINE=1` | Use only locally cached HF models |

## Important: Do NOT run automatically

- Never run `qmd collection add`, `qmd embed`, or `qmd update` automatically
- Never modify the SQLite metadata database directly
- Never modify Tantivy index files directly (in `~/.cache/qmd-rs/`)
- Write out example commands for the user to run manually

## Do NOT compile incorrectly

- Do not run `cargo build --compile` with bundling — native `.dylib` / `.so` dependencies (llama.cpp, usearch, ort) cannot be statically bundled that way.
- The correct release binary command is: `cargo build --profile dist -p qmd-cli`

## Releasing

Use `/release <version>` to cut a release. Full changelog standards,
release workflow, and git hook setup are documented in the
[release skill](skills/release/SKILL.md).

Key points:
- Add changelog entries under `## [Unreleased]` **as you make changes**
- The release script bumps crate versions, renames `[Unreleased]` → `[X.Y.Z] - date`, and creates a signed tag
- Credit external PRs with `#NNN (thanks @username)`
- CI (`rust.yml`) builds the `dist` binary and uploads it as a GitHub artifact on release branch push
