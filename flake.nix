{
  description = "ref-sync - Sync WIP jj revisions and gitignored docs across machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        ref-sync = pkgs.stdenv.mkDerivation {
          pname = "ref-sync";
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
            cp ref-sync $out/bin/ref-sync
            chmod +x $out/bin/ref-sync

            # Wrap with runtime dependencies in PATH
            wrapProgram $out/bin/ref-sync \
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

            $out/bin/ref-sync completions bash > $out/share/bash-completion/completions/ref-sync
            $out/bin/ref-sync completions zsh  > $out/share/zsh/site-functions/_ref-sync
            $out/bin/ref-sync completions fish > $out/share/fish/vendor_completions.d/ref-sync.fish
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
        packages.default = ref-sync;
        packages.ref-sync = ref-sync;

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
            echo "ref-sync dev shell"
            echo "  bats:       $(bats --version)"
            echo "  shellcheck: $(shellcheck --version | head -2 | tail -1)"
            echo "  shfmt:      $(shfmt --version)"
            echo "  jj:         $(jj --version)"
            echo "  git:        $(git --version)"
            echo ""
            echo "Run 'bats tests/' to run tests"
            echo "Run 'shellcheck ref-sync' to lint"
          '';
        };
      }
    );
}
