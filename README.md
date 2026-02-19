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

jj-sync uses an existing git remote — no extra server required. If your repo
has exactly one remote, it's auto-detected. Otherwise, set `JJ_SYNC_REMOTE`:

```bash
# If your repo has multiple remotes, tell jj-sync which one to use
export JJ_SYNC_REMOTE="origin"

# Push your WIP changes
jj-sync push

# On another machine, pull them
jj-sync pull

# See what would be synced
jj-sync status
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

## How It Works

jj-sync stores all sync state in git refs under a `refs/jj-sync/` namespace on
the remote. It never touches your branches, bookmarks, or working tree (except
for doc extraction). This makes it safe to use alongside normal git/jj workflows.

### Ref Namespace

All refs follow the pattern:

```
refs/jj-sync/sync/<user>/<machine>/revs/<change-id>   # revision bookmarks
refs/jj-sync/sync/<user>/<machine>/docs                # doc commit chain
```

- **User** — defaults to your `jj`/`git` `user.email`, namespaces refs so
  multiple people sharing a remote don't clobber each other.
- **Machine** — defaults to your hostname, lets you sync between your own
  machines while keeping their states separate.

### Revision Sync

On **push**, jj-sync evaluates the revset:

```
mine() & ~empty() & ~immutable_heads() & ~trunk()
```

This selects your WIP changes — authored by you, non-empty, not yet pushed to a
public branch, and not on trunk. For each matching change, it pushes the commit
SHA directly via `git push` to `refs/jj-sync/...`. Stale bookmarks (for
abandoned or squashed changes) are deleted automatically.

On **pull**, jj-sync fetches all `refs/jj-sync/.../revs/*` refs for the current
user, creates temporary local refs so jj can see the commits, runs `jj git
import`, then cleans up the temporary refs. The commits appear in your jj log
as normal revisions.

Revisions are pushed with force (`+` prefix) so amended changes are always
updated, even when the commit SHA changes non-fast-forward.

### Doc Sync

Doc sync uses git's object model to store directory snapshots without involving
jj at all. This is why it works in plain git repos too.

On **push**, jj-sync:

1. Builds a git tree object from the files in your `JJ_SYNC_DOCS` directories
   using a temporary `GIT_INDEX_FILE` (isolated in a subshell to avoid leaks).
2. Creates a commit object with that tree, parenting it on the previous doc
   commit from this machine (building a linear chain).
3. Force-pushes the commit to `refs/jj-sync/.../docs`.

On **pull**, jj-sync:

1. Fetches all doc refs for the current user (from all machines).
2. If there's a single source, uses it directly.
3. If there are multiple sources (multiple machines pushed docs), merges them:
   - With a common ancestor: three-way merge via `git merge-tree`.
   - Without a common ancestor: union merge (combines both trees).
   - Conflicts are included in files with standard conflict markers.
4. Extracts the final tree to a **staging directory** first, then replaces
   existing files only after extraction succeeds — protecting against data loss
   if extraction fails.

### Garbage Collection

`jj-sync gc` cleans up stale state on the remote:

- **Revision bookmarks** older than `JJ_SYNC_GC_REVS_DAYS` (default: 7) are
  deleted. Recent bookmarks are kept.
- **Doc commit chains** longer than `JJ_SYNC_GC_DOCS_MAX_CHAIN` (default: 50)
  are squashed to a single commit preserving the latest content. This prevents
  unbounded growth in the remote.

### Escape Hatch

If sync state gets corrupted, `jj-sync clean` removes all `refs/jj-sync/` refs
for the current user from both the local repo and the remote. This is a full
reset — you can push again immediately after.

You can also inspect the raw refs with:

```bash
git ls-remote <remote> 'refs/jj-sync/*'
```

## Requirements

- git ≥ 2.38
- jj (jujutsu) — only required for revision sync
- bash ≥ 4.0

## License

GPL-3.0 - See [LICENSE](LICENSE) for details.

Copyright (c) 2026 Fabien O'Carroll
