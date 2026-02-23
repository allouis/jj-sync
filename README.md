# ref-sync

Sync WIP jj revisions and gitignored docs across machines via git refs.

## Install

ref-sync is a single bash script. It needs bash 4.0+, git 2.38+, and
optionally jj for revision sync.

> macOS ships bash 3.2 — run `brew install bash` if `bash --version` shows
> a version older than 4.0.

**Copy the script:**

```bash
curl -o ~/.local/bin/ref-sync https://raw.githubusercontent.com/allouis/jj-sync/main/ref-sync
chmod +x ~/.local/bin/ref-sync
```

**Nix flake:**

```bash
nix profile install github:allouis/jj-sync
```

Or add to your NixOS/home-manager config:

```nix
{
  inputs.jj-sync.url = "github:allouis/jj-sync";
}

# Then:
home.packages = [ inputs.jj-sync.packages.${system}.default ];
```

<details>
<summary>Shell completions</summary>

Add one of the following to your shell config:

**Bash** (`~/.bashrc`):

```bash
eval "$(ref-sync completions bash)"
```

**Zsh** (`~/.zshrc`):

```zsh
eval "$(ref-sync completions zsh)"
```

**Fish** (`~/.config/fish/config.fish`):

```fish
ref-sync completions fish | source
```

Nix flake users get completions automatically.

</details>

## Quick start

```bash
ref-sync push ./ai-docs .claude      # push these directories
ref-sync pull                        # pull them on another machine
```

In a jj repo, this also syncs your WIP revisions automatically. In a plain
git repo, only the directories are synced.

To avoid repeating directories, set `REF_SYNC_DOCS`:

```bash
export REF_SYNC_DOCS="ai-docs .claude"

ref-sync push    # pushes revisions (jj) + docs
ref-sync pull    # pulls whatever was pushed
```

Use `--dry-run` to preview without making changes. Use `--revs` or `--docs`
to override auto-detection.

ref-sync auto-detects your remote. If you have multiple remotes, it looks for
`origin` or `upstream`. If it can't figure it out, it'll tell you what to do.

## Commands

```
Usage: ref-sync <command> [dir...] [options]

Sync WIP jj revisions and gitignored docs across machines.
(Doc sync works in any git repo; revision sync requires jj.)

Commands:
  push         Push to sync remote
  pull         Pull from sync remote
  status       Show what would be synced
  gc           Garbage collect stale sync bookmarks and doc chains
  clean        Remove ALL sync state (local + remote)
  completions  Print shell completions (bash, zsh, fish)
  help         Show this help

Flags:
  --revs           Sync revisions only (requires jj)
  --docs [dir...]  Sync docs only (dirs override REF_SYNC_DOCS)
  --both [dir...]  Sync revisions + docs (dirs override REF_SYNC_DOCS)
                   Default: auto-detect from repo type and REF_SYNC_DOCS

Options:
  --remote <name>   Override sync remote (default: auto-detected or $REF_SYNC_REMOTE)
  --user <name>     Override user identity (default: jj/git user.email or $REF_SYNC_USER)
  --machine <name>  Override machine name (default: $REF_SYNC_MACHINE or hostname)
  --dry-run         Show what would happen without doing it
  --verbose         Show git/jj commands as they run
  --force           Skip confirmation prompts

Environment Variables:
  REF_SYNC_DOCS              Space-separated directories to sync
  REF_SYNC_REMOTE            Git remote name (auto-detected from origin/upstream)
  REF_SYNC_USER              User identity for ref namespacing (default: jj/git user.email)
  REF_SYNC_MACHINE           Machine identifier (default: hostname)
  REF_SYNC_GC_REVS_DAYS      GC threshold for rev bookmarks (default: 7)
  REF_SYNC_GC_DOCS_MAX_CHAIN GC threshold for doc chain length (default: 50)

Examples:
  ref-sync push ./ai-docs .claude      # Push these directories (+ revs in jj)
  ref-sync pull                        # Pull whatever was pushed
  ref-sync push                        # Auto-detect from repo type and REF_SYNC_DOCS
  ref-sync push --revs                 # Force revision-only sync
  ref-sync push --docs                 # Force docs-only (uses REF_SYNC_DOCS)
  ref-sync status                      # Show sync status
```

## Doc sync

Some workflows produce files that are gitignored but still useful across
machines -- AI context, local notes, generated docs. Doc sync handles these.

Pass directories after the command:

```bash
ref-sync push ./ai-docs .claude      # push directories (+ revs in jj)
ref-sync pull                        # pull whatever was pushed
```

Or set `REF_SYNC_DOCS` so you don't have to repeat them:

```bash
export REF_SYNC_DOCS="ai-docs .claude"

ref-sync push   # includes docs automatically (alongside revs in a jj repo)
ref-sync pull   # pulls whatever was pushed
```

Positional directories and `--docs` inline arguments both override
`REF_SYNC_DOCS` when present. Use `--docs` to force docs-only mode
(skipping revisions in a jj repo).

Doc sync works in plain git repos too -- jj is only needed for revision sync.

## How it works

ref-sync stores everything in git refs under `refs/ref-sync/` on the remote.
These refs don't show up as bookmarks or branches in jj, and git ignores them
too. They're completely separate from your normal workflow.

The ref structure:

```
refs/ref-sync/sync/<user>/<machine>/revs/<change-id>
refs/ref-sync/sync/<user>/<machine>/docs
```

Refs are namespaced by user email and machine hostname, so multiple people (or
machines) sharing the same remote don't step on each other.

For revisions, ref-sync pushes commit SHAs directly to these refs and fetches
them back with `jj git import`. For docs, it stores file snapshots as git
commits and extracts them on pull.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `REF_SYNC_REMOTE` | auto-detected | Git remote to sync with |
| `REF_SYNC_USER` | auto-detected from jj or git config | Namespaces refs per user |
| `REF_SYNC_MACHINE` | hostname | Namespaces refs per machine |
| `REF_SYNC_DOCS` | (unset) | Space-separated directories for doc sync |
| `REF_SYNC_GC_REVS_DAYS` | 7 | Delete revision refs older than this |
| `REF_SYNC_GC_DOCS_MAX_CHAIN` | 50 | Squash doc chains longer than this |

Command-line flags (`--remote`, `--user`, `--machine`) override the
corresponding variables. Use `--verbose` on any command to see the git/jj
commands being run. Use `--dry-run` to preview without making changes.

## Troubleshooting

**Inspect sync state on the remote:**

```bash
git ls-remote <remote> 'refs/ref-sync/*'
```

**"No WIP revisions to push" but I have changes:**
Check that your changes aren't empty, aren't on a pushed branch, and are
authored by the email in your current `user.email` config.

**Push fails:**
Use `--verbose` to see the exact git commands. Check that the remote is
reachable and you have write access.

**Docs missing after pull:**
Make sure you're using the same directory names on both machines. A `./`
prefix is fine (`./ai-docs` and `ai-docs` are equivalent).

**Something is broken:**

```bash
ref-sync clean --force  # wipes all sync state for current user
ref-sync push           # start fresh
```

## Limitations

- Revision sync is last-write-wins. If you amend the same change on two
  machines and push from both, the second push overwrites the first.
- Doc sync merges on pull, not push. Conflicts show up as git conflict markers.
- You can't sync a subset of revisions.
- Directory names in `REF_SYNC_DOCS` can't contain spaces.

## License

GPL-3.0 - See [LICENSE](LICENSE) for details.

Copyright (c) 2026 Fabien O'Carroll
