# refsync

Sync WIP revisions and gitignored docs across machines via git refs.

## Requirements

- bash 4.0+ (macOS ships 3.2 -- `brew install bash` and make sure `bash --version` shows 4.0+)
- git 2.38+
- jj -- only needed for revision sync, not doc sync

## Install

refsync is a single bash script.

**Copy the script:**

```bash
curl -o ~/.local/bin/refsync https://raw.githubusercontent.com/allouis/jj-sync/main/refsync
chmod +x ~/.local/bin/refsync
```

**Clone and install:**

```bash
git clone https://github.com/allouis/jj-sync
cd jj-sync
./install.sh  # copies to ~/.local/bin
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

## Quick start

**Doc sync** (works in any git repo):

```bash
refsync push --docs ai/docs .claude   # push gitignored docs
refsync pull --docs                    # pull on another machine
```

**Revision sync** (requires jj):

```bash
refsync push    # pushes WIP jj revisions
refsync pull    # pulls them on another machine
```

Your changes show up in `jj log` as normal revisions. Use `--dry-run` to
preview what would happen without changing anything.

refsync auto-detects your remote. If you have multiple remotes, it looks for
`origin` or `upstream`. If it can't figure it out, it'll tell you what to do.

## Smart defaults

When you don't specify `--docs`, `--revs`, or `--both`, refsync picks the
right mode automatically:

| Context | Default mode |
|---|---|
| jj repo with `REFSYNC_DOCS` set | `--both` (revisions + docs) |
| jj repo without `REFSYNC_DOCS` | `--revs` (revisions only) |
| Plain git repo with `REFSYNC_DOCS` set | `--docs` (docs only) |
| Plain git repo without `REFSYNC_DOCS` | Error (nothing to sync) |

## Commands

```
Usage: refsync <command> [options]

Sync WIP revisions and gitignored docs across machines via git refs.
(Doc sync works in any git repo; revision sync requires jj.)

Commands:
  push      Push to sync remote
  pull      Pull from sync remote
  status    Show what would be synced
  gc        Garbage collect stale sync bookmarks and doc chains
  clean     Remove ALL sync state (local + remote)
  help      Show this help

Flags:
  --docs [dir...]  Sync docs only (dirs override REFSYNC_DOCS)
  --revs           Sync revisions only (requires jj)
  --both [dir...]  Sync revisions + docs (dirs override REFSYNC_DOCS)

  Default (no flag): docs in git repos, revisions in jj repos,
  both in jj repos with REFSYNC_DOCS set.

Options:
  --remote <name>   Override sync remote (default: auto-detected or $REFSYNC_REMOTE)
  --user <name>     Override user identity (default: jj/git user.email or $REFSYNC_USER)
  --machine <name>  Override machine name (default: $REFSYNC_MACHINE or hostname)
  --dry-run         Show what would happen without doing it
  --verbose         Show git/jj commands as they run
  --force           Skip confirmation prompts

Environment Variables:
  REFSYNC_DOCS              Space-separated directories to sync
  REFSYNC_REMOTE            Git remote name (auto-detected from origin/upstream)
  REFSYNC_USER              User identity for ref namespacing (default: jj/git user.email)
  REFSYNC_MACHINE           Machine identifier (default: hostname)
  REFSYNC_GC_REVS_DAYS      GC threshold for rev bookmarks (default: 7)
  REFSYNC_GC_DOCS_MAX_CHAIN GC threshold for doc chain length (default: 50)

Examples:
  refsync push                        # Smart default (see above)
  refsync push --docs ai/docs .claude # Push specific doc directories
  refsync push --revs                 # Push jj revisions only
  refsync push --both                 # Push revisions and docs
  refsync pull --docs                 # Pull only docs
  refsync status                      # Show sync status
```

## Doc sync

Some workflows produce files that are gitignored but still useful across
machines -- AI context, local notes, generated docs. Doc sync handles these.

Pass directories directly on the command line:

```bash
refsync push --docs ai/docs .claude
refsync pull --docs ai/docs .claude
```

Or set `REFSYNC_DOCS` to avoid repeating them:

```bash
export REFSYNC_DOCS="ai/docs .claude"

refsync push --docs   # uses directories from REFSYNC_DOCS
refsync push --both   # revisions + docs
refsync push          # in a jj repo, auto-detects --both since REFSYNC_DOCS is set
```

Inline arguments override the environment variable when both are present.

Doc sync works in plain git repos too -- jj is only needed for revision sync.

## How it works

refsync stores everything in git refs under `refs/refsync/` on the remote.
These refs don't show up as bookmarks or branches in jj, and git ignores them
too. They're completely separate from your normal workflow.

The ref structure:

```
refs/refsync/sync/<user>/<machine>/revs/<change-id>
refs/refsync/sync/<user>/<machine>/docs
```

Refs are namespaced by user email and machine hostname, so multiple people (or
machines) sharing the same remote don't step on each other.

For revisions, refsync pushes commit SHAs directly to these refs and fetches
them back with `jj git import`. For docs, it stores file snapshots as git
commits and extracts them on pull.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `REFSYNC_REMOTE` | auto-detected | Git remote to sync with |
| `REFSYNC_USER` | auto-detected from jj or git config | Namespaces refs per user |
| `REFSYNC_MACHINE` | hostname | Namespaces refs per machine |
| `REFSYNC_DOCS` | (unset) | Space-separated directories for doc sync |
| `REFSYNC_GC_REVS_DAYS` | 7 | Delete revision refs older than this |
| `REFSYNC_GC_DOCS_MAX_CHAIN` | 50 | Squash doc chains longer than this |

Command-line flags (`--remote`, `--user`, `--machine`) override the
corresponding variables. Use `--verbose` on any command to see the git/jj
commands being run. Use `--dry-run` to preview without making changes.

## Troubleshooting

**Inspect sync state on the remote:**

```bash
git ls-remote <remote> 'refs/refsync/*'
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
refsync clean --force  # wipes all sync state for current user
refsync push           # start fresh
```

## Limitations

- Revision sync is last-write-wins. If you amend the same change on two
  machines and push from both, the second push overwrites the first.
- Doc sync merges on pull, not push. Conflicts show up as git conflict markers.
- You can't sync a subset of revisions.
- Directory names in `REFSYNC_DOCS` can't contain spaces.

## License

GPL-3.0 - See [LICENSE](LICENSE) for details.

Copyright (c) 2026 Fabien O'Carroll
