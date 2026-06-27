# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# QMD - Query Markup Documents

Use Bun for local development (`bun install`, not `npm install`). The codebase is dual-runtime: it runs on Node.js (>=22) and Bun, and CI tests both. The installed `bin/qmd` launcher prefers Node in dist mode for native-module ABI safety.

## Commands

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
qmd embed                         # Generate vector embeddings (uses node-llama-cpp)
qmd query <query>                 # Search with query expansion + reranking (recommended)
qmd search <query>                # Full-text keyword search (BM25, no LLM)
qmd vsearch <query>               # Vector similarity search (no reranking)
qmd bench <fixture.json>          # Run search-quality benchmarks
qmd mcp                           # Start MCP server (stdio transport)
qmd mcp --http [--port N]         # Start MCP server (HTTP, default port 8181)
qmd mcp --http --daemon           # Start as background daemon
qmd mcp stop                      # Stop background MCP daemon
```

## Collection Management

```sh
# List all collections
qmd collection list

# Create a collection with explicit name
qmd collection add ~/Documents/notes --name mynotes --mask '**/*.md'

# Remove a collection
qmd collection remove mynotes

# Rename a collection
qmd collection rename mynotes my-notes

# Show collection details
qmd collection show mynotes

# Set or clear the pre-update hook (runs before re-indexing on `qmd update`)
qmd collection update-cmd mynotes 'git pull --ff-only'
qmd collection update-cmd mynotes            # clear

# Include or exclude from default (unscoped) queries
qmd collection exclude mynotes
qmd collection include mynotes

# List all files in a collection
qmd ls mynotes

# List files with a path prefix
qmd ls journals/2025
qmd ls qmd://journals/2025
```

## Context Management

```sh
# Add context to current directory (auto-detects collection)
qmd context add "Description of these files"

# Add context to a specific path
qmd context add /subfolder "Description for subfolder"

# Add global context to all collections (system message)
qmd context add / "Always include this context"

# Add context using virtual paths
qmd context add qmd://journals/ "Context for entire journals collection"
qmd context add qmd://journals/2024 "Journal entries from 2024"

# List all contexts
qmd context list

# Check for collections or paths without context
qmd context check

# Remove context
qmd context rm qmd://journals/2024
qmd context rm /  # Remove global context
```

## Document IDs (docid)

Each document has a unique short ID (docid) - the first 6 characters of its content hash.
Docids are shown in search results as `#abc123` and can be used with `get` and `multi-get`:

```sh
# Search returns docid in results
qmd search "query" --json
# Output: [{"docid": "#abc123", "score": 0.85, "file": "docs/readme.md", ...}]

# Get document by docid
qmd get "#abc123"
qmd get abc123              # Leading # is optional

# Docids also work in multi-get comma-separated lists
qmd multi-get "#abc123, #def456"
```

## Options

```sh
# Search & retrieval
-c, --collection <name>  # Restrict search to collection(s) (repeatable)
-n <num>                 # Number of results
--all                    # Return all matches
--min-score <num>        # Minimum score threshold
--full                   # Show full document content
--intent <text>          # Describe what you're after to sharpen ranking (query)
--no-rerank              # Skip LLM reranking (faster, lower quality)
--full-path              # Show on-disk paths instead of qmd:// URIs

# Get / multi-get
-l <num>                 # Maximum lines per file
--max-bytes <num>        # Skip files larger than this (default 10KB)
--no-line-numbers        # Disable line numbers (on by default for get/multi-get)

# Output format (search, query, multi-get)
--format <kind>          # cli (default) | json | csv | md | xml | files
                         # legacy --json/--csv/--md/--xml/--files still work as aliases
```

## Development

```sh
bun run qmd <command>          # Run CLI from source (tsx under the hood)
bun src/cli/qmd.ts <command>   # Equivalent direct form
bun link                       # Install globally as 'qmd' for local testing

npm run build                  # node scripts/build.mjs → tsc to dist/ + shebang inject
npm run test:types             # Type-check only (tsc --noEmit)
```

There is **no ESLint / Prettier / Biome and no lint/format script**. TypeScript type-checking (`strict`, `noUncheckedIndexedAccess`) is the only static-quality gate.

## Tests

Tests live in `test/` and run under **two runtimes** against the same suite — both must pass. Vitest runs under Node and ignores the preload; `bun test` requires `--preload ./src/test-preload.ts`. Tests execute serially (`fileParallelism: false`) because they share a SQLite index.

```sh
npm test                                             # Full suite: typecheck + Vitest(Node) + Bun + smoke
npm run test:node                                    # Vitest under Node only
npm run test:bun                                     # Bun runner only

# Run everything directly:
npx vitest run --reporter=verbose test/
bun test --preload ./src/test-preload.ts test/

# Run a single file or single test by name:
npx vitest run test/cli.test.ts
npx vitest run test/cli.test.ts -t "name substring"
bun test --preload ./src/test-preload.ts test/cli.test.ts
```

## Architecture

- SQLite FTS5 for full-text search (BM25)
- sqlite-vec for vector similarity search
- node-llama-cpp for embeddings (embeddinggemma), reranking (qwen3-reranker), and query expansion (Qwen3)
- Reciprocal Rank Fusion (RRF) for combining results
- Smart chunking: 900 tokens/chunk with 15% overlap, prefers markdown headings as boundaries
- AST-aware chunking: use `--chunk-strategy auto` to chunk code files (.ts/.js/.py/.go/.rs) at function/class/import boundaries via tree-sitter. Default is `regex` (existing behavior). Markdown and unknown file types always use regex chunking.

### Codebase layout

The codebase is deliberately flat and framework-light — most logic lives in a few large top-level files in `src/`. Navigate by grep / symbol, not full reads.

- `src/store.ts` (~5400 lines) — core engine: chunking, FTS5 + vector search, RRF fusion, query expansion, reranking, document/collection CRUD, and the SQLite schema (migrations gated on `PRAGMA user_version`). The search orchestrator is `hybridQuery()`; `vectorSearchQuery()` backs `vsearch`.
- `src/llm.ts` (~2000 lines) — all node-llama-cpp integration: model resolution/download (cache at `~/.cache/qmd/models`), embeddings, reranking, query-expansion generation, GPU mode resolution (`QMD_FORCE_CPU` / `--no-gpu` forces CPU).
- `src/db.ts` — cross-runtime SQLite layer (bun:sqlite vs better-sqlite3), WAL + busy-timeout setup, `loadSqliteVec()`. Vector features degrade gracefully: BM25 still works if sqlite-vec is unavailable.
- `src/collections.ts` — `.qmd/index.yaml` config file management, collections, contexts.
- `src/cli/qmd.ts` — CLI entry; no CLI framework, uses Node's `util.parseArgs` and a single `switch` on the first positional. `src/cli/formatter.ts` handles output formats (cli/json/csv/md/xml/files).
- `src/mcp/server.ts` — MCP server (`@modelcontextprotocol/sdk`), stdio + Streamable-HTTP transports.
- `src/ast.ts` — tree-sitter AST chunking for code files. `src/index.ts` — public library API.

**Query flow** (`hybridQuery` in `store.ts`): BM25 probe (a strong single top result short-circuits LLM expansion) → query expansion (lex/vec/hyde variants) → FTS5 for lexical expansions + batched vector search for vec/hyde → Reciprocal Rank Fusion → cross-encoder rerank (skip with `--no-rerank`).

## Important: Do NOT run automatically

- Never run `qmd collection add`, `qmd embed`, or `qmd update` automatically
- Never modify the SQLite database directly
- Write out example commands for the user to run manually
- Index is stored at `~/.cache/qmd/index.sqlite`

## Do NOT compile

- Never run `bun build --compile` — it overwrites the `bin/qmd` launcher and breaks sqlite-vec (native modules cannot be bundled into a single compiled binary).
- `bin/qmd` is a **Node.js launcher** (the `bin` entry in `package.json`), not a shell script. It picks a runtime and runs `dist/cli/qmd.js` (or `src/` in a git checkout). Do not replace it.
- `npm run build` runs `node scripts/build.mjs`, which compiles TypeScript to `dist/` via `tsc -p tsconfig.build.json` and injects the `#!/usr/bin/env node` shebang.

## Releasing

Use `/release <version>` to cut a release. Full changelog standards,
release workflow, and git hook setup are documented in the
[release skill](skills/release/SKILL.md).

Key points:
- Add changelog entries under `## [Unreleased]` **as you make changes**
- The release script renames `[Unreleased]` → `[X.Y.Z] - date` at release time
- Credit external PRs with `#NNN (thanks @username)`
- GitHub releases roll up the full minor series (e.g. 1.2.0 through 1.2.3)
