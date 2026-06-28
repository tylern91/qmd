{
  description = "QMD - on-device hybrid document search (single static binary)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    {
      # Home Manager module — installs qmd into the user environment.
      homeModules.default = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.programs.qmd;
        in
        {
          options.programs.qmd = {
            enable = mkEnableOption "QMD - on-device search engine for markdown notes";

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              defaultText = literalExpression "inputs.qmd.packages.\${pkgs.stdenv.hostPlatform.system}.default";
              description = "The qmd package to use.";
            };
          };

          config = mkIf cfg.enable {
            home.packages = [ cfg.package ];
          };
        };
    } //
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Native build inputs needed to compile qmd (llama-cpp-2 uses CMake + C/C++).
        nativeBuildDeps = [
          pkgs.rustc
          pkgs.cargo
          pkgs.rustfmt
          pkgs.clippy
          # cmake 3.x — llama.cpp CMakeLists.txt requires VERSION 3.14..3.28
          pkgs.cmake
          pkgs.pkg-config
        ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
          pkgs.gcc
        ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
          pkgs.darwin.apple_sdk.frameworks.Metal
          pkgs.darwin.apple_sdk.frameworks.Foundation
          pkgs.darwin.apple_sdk.frameworks.Accelerate
          pkgs.darwin.cctools
        ];

        # --------------------------------------------------------------------
        # Release package (best-effort; llama-cpp-2 CMake + sandbox is tricky)
        # NOTE: cargoHash must be updated after any Cargo.lock change.
        #       Run `nix build 2>&1 | grep 'got:'` to get the new hash.
        # --------------------------------------------------------------------
        qmd = pkgs.rustPlatform.buildRustPackage {
          pname = "qmd";
          version = "0.1.0";

          src = pkgs.lib.cleanSource ./.;

          # Workspace: build the CLI crate only.
          buildAndTestSubpackage = "qmd-cli";

          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = nativeBuildDeps;

          buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.darwin.apple_sdk.frameworks.Metal
            pkgs.darwin.apple_sdk.frameworks.Foundation
            pkgs.darwin.apple_sdk.frameworks.Accelerate
          ];

          # Disable model downloads in the Nix sandbox.
          QMD_CI = "1";

          meta = with pkgs.lib; {
            description = "On-device hybrid search engine (BM25 + vector + rerank)";
            homepage = "https://github.com/tobi/qmd";
            license = licenses.mit;
            mainProgram = "qmd";
            platforms = platforms.unix;
          };
        };

      in
      {
        packages = {
          default = qmd;
          qmd = qmd;
        };

        apps.default = {
          type = "app";
          program = "${qmd}/bin/qmd";
        };

        # Development shell: full Rust toolchain + native deps for building qmd.
        # Usage: nix develop
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = nativeBuildDeps;

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
