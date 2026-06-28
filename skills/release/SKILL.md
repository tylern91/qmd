---
name: release
description: Manage releases for this project. Validates changelog, bumps Rust crate versions, and cuts releases. Use when user says "/release", "release 1.0.5", "cut a release", or asks about the release process. NOT auto-invoked by the model.
disable-model-invocation: true
---

# Release

Cut a release for the qmd Rust workspace: bump crate versions, finalize the
changelog, tag, and let CI build + upload the dist binary.

## Usage

`/release 1.0.5` or `/release patch` (bumps patch from current version).

## Process

When the user triggers `/release <version>`:

1. **Determine the version** — if a semver is provided, use it directly.
   If `patch`/`minor`/`major` is given, read the current version from the
   workspace `Cargo.toml` (or any crate's `Cargo.toml` since all share the
   same version) and compute the bumped version.

2. **Commit outstanding work** — check `git status`. If there are staged,
   modified, or untracked changes that belong in this release, commit them
   first with well-formed conventional commit messages.

3. **Write the changelog** — if `[Unreleased]` in `CHANGELOG.md` is empty,
   write it using `git log <last-tag>..HEAD --oneline` as source material.
   Follow the changelog standard below. After editing, ask the user to
   review before proceeding.

4. **Bump crate versions** — update `version = "X.Y.Z"` in every crate's
   `Cargo.toml`:
   ```sh
   for f in crates/*/Cargo.toml; do
     sed -i '' 's/^version = ".*"/version = "X.Y.Z"/' "$f"
   done
   ```
   Then run `cargo build --workspace` to regenerate `Cargo.lock` and confirm
   the build is still clean.

5. **Finalize changelog** — rename `## [Unreleased]` → `## [X.Y.Z] - YYYY-MM-DD`
   and insert a fresh empty `## [Unreleased]` above it. Commit with:
   ```sh
   git add CHANGELOG.md crates/*/Cargo.toml Cargo.lock
   git commit -m "chore: release vX.Y.Z"
   ```

6. **Tag** — create an annotated, GPG-signed tag:
   ```sh
   git tag -s "vX.Y.Z" -m "Release vX.Y.Z"
   ```

7. **Show summary** — print the new changelog section and the git log since
   the last release. Ask the user to confirm before pushing.

8. **Push** — after explicit confirmation:
   ```sh
   git push origin release --tags
   ```
   This triggers `rust.yml` which builds the `dist` binary and uploads it
   as a GitHub artifact (`qmd-macos-arm64`).

9. **Watch CI** — after the push, watch the `Rust CI` workflow:
   ```sh
   gh run watch $(gh run list --workflow=rust.yml --limit=1 --json databaseId --jq '.[0].databaseId') --exit-status
   ```
   Report the result when it completes.

10. **Check dependency updates** — before cutting a release, run
    `cargo outdated` and report any updates to key deps (`llama-cpp-2`,
    `tantivy`, `usearch`, `rmcp`, `ort`). If updates exist, bump them in
    `Cargo.toml` and re-run the eval gate before proceeding.

If any step fails, stop and explain. Never force-push or skip the build
verification step.

## Quality gates (must pass before tagging)

```sh
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace --lib
cargo run --bin qmd -- eval --mode bm25   # BM25 gate — runs in CI
```

The `vec` and `hybrid` eval modes require downloaded models and are run
locally (not in CI). Run them if you changed `qmd-llm` or `qmd-core`.

## Changelog Standard

The changelog lives in `CHANGELOG.md` and follows [Keep a Changelog](https://keepachangelog.com/) conventions.

### Heading format

- `## [Unreleased]` — accumulates entries between releases
- `## [X.Y.Z] - YYYY-MM-DD` — released versions

### Structure of a release entry

Each version entry has two parts:

**1. Highlights (optional, 1-4 sentences of prose)**

Immediately after the version heading, before any `###` section. The elevator
pitch — what would you tell someone in 30 seconds? Only for significant
releases; skip for small patches.

```markdown
## [1.1.0] - 2026-07-01

qmd now ships with CoreML and CUDA acceleration backends via ONNX Runtime.
Embedding throughput on Apple Silicon is 93 texts/sec via the ANE path,
matching llama.cpp Metal performance with lower power consumption.
```

**2. Detailed changelog (`### Added`, `### Changed`, `### Fixed`)**

```markdown
### Added

- OrtBackend: ONNX Runtime v2 with CoreML (macOS) and CUDA (Linux/Windows)
  execution providers. Select with `QMD_INFERENCE_BACKEND=ort`.

### Fixed

- MCP `query` tool panicked with "Cannot start a runtime from within a runtime"
  when initializing the LlamaCpp backend from inside the async MCP handler.
  Fixed with `tokio::task::block_in_place`. #7
```

### Writing guidelines

- **Explain the why, not just the what.** The changelog is for users.
- **Include numbers.** "93 texts/sec", "12x faster query latency".
- **Group by theme, not by file.** "Performance" not "Changes to store.rs".
- **Don't list every commit.** Aggregate related changes.
- **Credit contributors:** end bullets with `#NNN (thanks @username)` for
  external PRs. No need to credit the repo owner.

### What not to include

- Internal refactors with no user-visible effect
- Dependency bumps (unless fixing a user-facing bug)
- CI/tooling changes (unless affecting the release artifact)
- Test additions (unless validating a fix worth mentioning)

## GitHub Release Notes

Each GitHub release includes the full changelog for the **minor series** back
to x.x.0. Populate the GitHub release body from the `## [X.Y.Z]` section and
all patch entries since `## [X.Y.0]`. The dist binary artifact uploaded by
`rust.yml` should be attached to the release manually (or automate via
`gh release create`).
