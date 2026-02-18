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
            mkdir -p $out/bin $out/share/jj-sync

            # Install library files
            cp -r lib/*.sh $out/share/jj-sync/

            # Install main script with correct paths
            sed "s|^SCRIPT_DIR=.*|LIBDIR=\"$out/share/jj-sync\"|" jj-sync > $out/bin/jj-sync
            sed -i "s|source \"\$SCRIPT_DIR/lib/|source \"\$LIBDIR/|g" $out/bin/jj-sync
            chmod +x $out/bin/jj-sync

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

            # Install completions
            mkdir -p $out/share/bash-completion/completions
            mkdir -p $out/share/zsh/site-functions
            mkdir -p $out/share/fish/vendor_completions.d

            cp completions/jj-sync.bash $out/share/bash-completion/completions/jj-sync
            cp completions/_jj-sync $out/share/zsh/site-functions/_jj-sync
            cp completions/jj-sync.fish $out/share/fish/vendor_completions.d/jj-sync.fish
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
            echo "Run 'shellcheck jj-sync lib/*.sh' to lint"
          '';
        };
      }
    );
}
