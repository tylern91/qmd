{
  description = "QMD - on-device hybrid document search (single static binary)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Native build inputs shared between the package and the dev shell.
        #   bindgenHook — libclang, required by llama-cpp-sys-2's bindgen step
        #   cmake       — builds the vendored llama.cpp + usearch C/C++ sources
        #   pkg-config  — locates system libs for the -sys crates
        nativeBuildDeps = [
          pkgs.rustPlatform.bindgenHook
          pkgs.cmake
          pkgs.pkg-config
        ];

      in
      {
        # Reproducible package build.
        #
        # Builds the qmd-cli binary with default features (NO ort-backend, which
        # would download ONNX Runtime at build time). On macOS the llama.cpp Metal
        # backend is built via the embed-library path: the shader source is embedded
        # and compiled at *runtime*, so the sandbox never needs `xcrun metal`. All
        # native C/C++ sources (llama.cpp, usearch, zstd, sqlite) are vendored inside
        # their -sys crates; no submodule or network fetch is required.
        #
        # Usage: nix build  ·  nix run  ·  nix profile install .#default
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "qmd";
          version = "0.1.0";
          src = ./.;

          # Vendor all crates.io deps from the lockfile — no network during build.
          cargoLock.lockFile = ./Cargo.lock;

          # Build only the CLI crate; default features (excludes ort-backend).
          cargoBuildFlags = [ "-p" "qmd-cli" ];

          # Linux: openssl-sys (via hf-hub → reqwest → native-tls) needs the
          # OpenSSL headers (openssl.dev, found by pkg-config) and runtime lib.
          # Darwin: default apple-sdk propagates the frameworks llama.cpp links.
          nativeBuildInputs = nativeBuildDeps
            ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.openssl.dev ];

          buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.openssl
          ];

          # Disable HuggingFace model downloads during build (and any sandbox tests).
          QMD_CI = "1";
          # Accept llama.cpp's cmake_minimum_required(3.14...3.28) under cmake 4.x.
          CMAKE_POLICY_VERSION_MINIMUM = "3.5";

          # Tests require models / network; skip in the sandbox. Run locally with:
          #   cargo test --workspace --lib
          doCheck = false;

          meta = {
            description = "On-device hybrid document search (single static binary)";
            mainProgram = "qmd";
            license = pkgs.lib.licenses.mit;
            platforms = pkgs.lib.platforms.unix;
          };
        };

        apps.default = flake-utils.lib.mkApp {
          drv = self.packages.${system}.default;
        };

        # Development shell: full Rust toolchain + native deps for building qmd.
        # Usage: nix develop
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.rustc
            pkgs.cargo
            pkgs.rustfmt
            pkgs.clippy
          ] ++ nativeBuildDeps
            ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.gcc ]
            ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [ pkgs.darwin.cctools ];

          shellHook = ''
            echo "qmd development shell"
            echo "  cargo build --workspace          — debug build"
            echo "  cargo build --profile dist -p qmd-cli  — release binary → target/dist/qmd"
            echo "  cargo run --bin qmd -- <command> — run from source"
          '';
        };
      }
    );
}
