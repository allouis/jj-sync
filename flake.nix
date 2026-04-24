{
  description = "jj-sync - Sync WIP jj revisions and gitignored docs across machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        jj-sync = pkgs.stdenv.mkDerivation {
          pname = "jj-sync";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];

          # Runtime dependencies
          buildInputs = [
            pkgs.bash
            pkgs.git
            pkgs.jujutsu
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gnutar
          ];

          installPhase = ''
            mkdir -p $out/bin

            # Install the self-contained script
            cp jj-sync $out/bin/jj-sync
            chmod +x $out/bin/jj-sync

            # Fix shebang for NixOS (no /usr/bin/env)
            patchShebangs $out/bin/jj-sync

            # Wrap with runtime dependencies in PATH
            wrapProgram $out/bin/jj-sync \
              --prefix PATH : ${pkgs.lib.makeBinPath [
                pkgs.git
                pkgs.jujutsu
                pkgs.coreutils
                pkgs.findutils
                pkgs.gnugrep
                pkgs.gnutar
              ]}

            # Generate completions from the installed script
            mkdir -p $out/share/bash-completion/completions
            mkdir -p $out/share/zsh/site-functions
            mkdir -p $out/share/fish/vendor_completions.d

            $out/bin/jj-sync completions bash > $out/share/bash-completion/completions/jj-sync
            $out/bin/jj-sync completions zsh  > $out/share/zsh/site-functions/_jj-sync
            $out/bin/jj-sync completions fish > $out/share/fish/vendor_completions.d/jj-sync.fish
          '';

          meta = with pkgs.lib; {
            description = "Sync WIP jj revisions and gitignored docs across machines";
            homepage = "https://github.com/allouis/jj-sync";
            license = licenses.gpl3;
            maintainers = [];
            platforms = platforms.unix;
          };
        };
      in
      {
        packages.default = jj-sync;
        packages.jj-sync = jj-sync;

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.jujutsu
            pkgs.git
            pkgs.bats
            pkgs.bash
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.coreutils
            pkgs.findutils
            pkgs.gnugrep
            pkgs.gnutar
          ];

          shellHook = ''
            echo "jj-sync dev shell"
            echo "  bats:       $(bats --version)"
            echo "  shellcheck: $(shellcheck --version | head -2 | tail -1)"
            echo "  shfmt:      $(shfmt --version)"
            echo "  jj:         $(jj --version)"
            echo "  git:        $(git --version)"
            echo ""
            echo "Run 'bats tests/' to run tests"
            echo "Run 'shellcheck jj-sync' to lint"
          '';
        };
      }
    );
}
