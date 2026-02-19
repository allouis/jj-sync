# jj-sync

Sync WIP jj revisions and gitignored docs across multiple development machines using a private git remote.

## Installation

### Nix Flakes

```bash
# Run directly
nix run github:allouis/jj-sync

# Or install to your profile
nix profile install github:allouis/jj-sync
```

To add to a NixOS/home-manager config:

```nix
{
  inputs.jj-sync.url = "github:allouis/jj-sync";
}

# Then in your config:
environment.systemPackages = [ inputs.jj-sync.packages.${system}.default ];
# or for home-manager:
home.packages = [ inputs.jj-sync.packages.${system}.default ];
```

### Manual

```bash
git clone https://github.com/allouis/jj-sync
cd jj-sync
./install.sh  # installs to ~/.local/bin
```

## Quick Start

```bash
# Push your WIP changes (remote auto-detected if repo has one remote)
jj-sync push

# On another machine, pull them
jj-sync pull
```

## Usage

```
$ jj-sync --help
Usage: jj-sync <command> [options]

Sync WIP jj revisions and gitignored docs across machines.

Commands:
  push      Push to sync remote
  pull      Pull from sync remote
  status    Show what would be synced
  gc        Garbage collect stale sync bookmarks and doc chains
  clean     Remove ALL sync state (local + remote)
  init      Interactive setup: configure remote, machine name
  help      Show this help

Flags:
  --docs    Sync docs only (requires JJ_SYNC_DOCS)
  --both    Sync revisions + docs (requires JJ_SYNC_DOCS)
            Default (no flag): sync revisions only

Options:
  --remote <name>   Override sync remote (default: auto-detected or $JJ_SYNC_REMOTE)
  --user <name>     Override user identity (default: jj/git user.email or $JJ_SYNC_USER)
  --machine <name>  Override machine name (default: $JJ_SYNC_MACHINE or hostname)
  --dry-run         Show what would happen without doing it
  --verbose         Show git/jj commands as they run
  --force           Skip confirmation prompts

Environment Variables:
  JJ_SYNC_DOCS              Space-separated directories to sync (required for --docs/--both)
  JJ_SYNC_REMOTE            Git remote name (auto-detected if repo has exactly one remote)
  JJ_SYNC_USER              User identity for ref namespacing (default: jj/git user.email)
  JJ_SYNC_MACHINE           Machine identifier (default: hostname)
  JJ_SYNC_GC_REVS_DAYS      GC threshold for rev bookmarks (default: 7)
  JJ_SYNC_GC_DOCS_MAX_CHAIN GC threshold for doc chain length (default: 50)
```

## Doc Sync

To sync gitignored directories (AI docs, notes, etc.), set `JJ_SYNC_DOCS`:

```bash
export JJ_SYNC_DOCS="ai/docs .claude"

jj-sync push --docs   # sync docs only
jj-sync push --both   # sync revisions + docs
```

## Plain Git Support

Doc sync works in any git repository — jj is not required. This is useful for
syncing gitignored directories in projects that don't use jj.

Revision sync still requires jj.

## Requirements

- git ≥ 2.38
- jj (jujutsu) — only required for revision sync
- bash ≥ 4.0

## License

GPL-3.0 - See [LICENSE](LICENSE) for details.

Copyright (c) 2026 Fabien O'Carroll
