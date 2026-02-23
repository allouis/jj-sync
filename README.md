# jj-sync

Sync WIP jj revisions and gitignored docs across machines via any git remote.

## Requirements

- bash 4.0+ (macOS ships 3.2 -- `brew install bash` and make sure `bash --version` shows 4.0+)
- git 2.38+
- jj -- only needed for revision sync, not doc sync

## Install

jj-sync is a single bash script.

**Copy the script:**

```bash
curl -o ~/.local/bin/jj-sync https://raw.githubusercontent.com/allouis/jj-sync/main/jj-sync
chmod +x ~/.local/bin/jj-sync
```

<details>
<summary>Nix flake</summary>

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

</details>

### Shell completions

Add one of the following to your shell config:

**Bash** (`~/.bashrc`):

```bash
eval "$(jj-sync completions bash)"
```

**Zsh** (`~/.zshrc`):

```zsh
eval "$(jj-sync completions zsh)"
```

**Fish** (`~/.config/fish/config.fish`):

```fish
jj-sync completions fish | source
```

Nix flake users get completions automatically.

## Quick start

On your laptop:

```bash
jj-sync push
```

On your other machine:

```bash
jj-sync pull
```

Your changes show up in `jj log` as normal revisions. Use `--dry-run` to
preview what would happen without changing anything.

For docs (AI context, local notes, anything gitignored):

```bash
jj-sync push --docs ai/docs .claude
jj-sync pull --docs ai/docs .claude
```

jj-sync auto-detects your remote. If you have multiple remotes, it looks for
`origin` or `upstream`. If it can't figure it out, it'll tell you what to do.

## Commands

```
Usage: jj-sync <command> [options]

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
  --docs [dir...]  Sync docs only (dirs override JJ_SYNC_DOCS)
  --both [dir...]  Sync revisions + docs (dirs override JJ_SYNC_DOCS)
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
  JJ_SYNC_REMOTE            Git remote name (auto-detected from origin/upstream)
  JJ_SYNC_USER              User identity for ref namespacing (default: jj/git user.email)
  JJ_SYNC_MACHINE           Machine identifier (default: hostname)
  JJ_SYNC_GC_REVS_DAYS      GC threshold for rev bookmarks (default: 7)
  JJ_SYNC_GC_DOCS_MAX_CHAIN GC threshold for doc chain length (default: 50)

Examples:
  jj-sync push                        # Push WIP revisions
  jj-sync push --docs ai/docs .claude # Push specific doc directories
  jj-sync push --both                 # Push revisions and docs
  jj-sync pull --docs                 # Pull only docs
  jj-sync status                      # Show sync status
```

## Doc sync

Some workflows produce files that are gitignored but still useful across
machines -- AI context, local notes, generated docs. Doc sync handles these.

Pass directories directly on the command line:

```bash
jj-sync push --docs ai/docs .claude
jj-sync pull --docs ai/docs .claude
```

Or set `JJ_SYNC_DOCS` to avoid repeating them:

```bash
export JJ_SYNC_DOCS="ai/docs .claude"

jj-sync push --docs   # uses directories from JJ_SYNC_DOCS
jj-sync push --both   # revisions + docs
```

Inline arguments override the environment variable when both are present.

Doc sync works in plain git repos too -- jj is only needed for revision sync.

## How it works

jj-sync stores everything in git refs under `refs/jj-sync/` on the remote.
These refs don't show up as bookmarks or branches in jj, and git ignores them
too. They're completely separate from your normal workflow.

The ref structure:

```
refs/jj-sync/sync/<user>/<machine>/revs/<change-id>
refs/jj-sync/sync/<user>/<machine>/docs
```

Refs are namespaced by user email and machine hostname, so multiple people (or
machines) sharing the same remote don't step on each other.

For revisions, jj-sync pushes commit SHAs directly to these refs and fetches
them back with `jj git import`. For docs, it stores file snapshots as git
commits and extracts them on pull.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `JJ_SYNC_REMOTE` | auto-detected | Git remote to sync with |
| `JJ_SYNC_USER` | auto-detected from jj or git config | Namespaces refs per user |
| `JJ_SYNC_MACHINE` | hostname | Namespaces refs per machine |
| `JJ_SYNC_DOCS` | (unset) | Space-separated directories for doc sync |
| `JJ_SYNC_GC_REVS_DAYS` | 7 | Delete revision refs older than this |
| `JJ_SYNC_GC_DOCS_MAX_CHAIN` | 50 | Squash doc chains longer than this |

Command-line flags (`--remote`, `--user`, `--machine`) override the
corresponding variables. Use `--verbose` on any command to see the git/jj
commands being run. Use `--dry-run` to preview without making changes.

## Troubleshooting

**Inspect sync state on the remote:**

```bash
git ls-remote <remote> 'refs/jj-sync/*'
```

**"No WIP revisions to push" but I have changes:**
Check that your changes aren't empty, aren't on a pushed branch, and are
authored by the email in your current `user.email` config.

**Push fails:**
Use `--verbose` to see the exact git commands. Check that the remote is
reachable and you have write access.

**Docs missing after pull:**
Make sure you're using the same directory names on both machines. Paths must
match exactly (`ai/docs` vs `./ai/docs` are different).

**Something is broken:**

```bash
jj-sync clean --force  # wipes all sync state for current user
jj-sync push           # start fresh
```

## Limitations

- Revision sync is last-write-wins. If you amend the same change on two
  machines and push from both, the second push overwrites the first.
- Doc sync merges on pull, not push. Conflicts show up as git conflict markers.
- You can't sync a subset of revisions.
- Directory names in `JJ_SYNC_DOCS` can't contain spaces.

## License

GPL-3.0 - See [LICENSE](LICENSE) for details.

Copyright (c) 2026 Fabien O'Carroll
