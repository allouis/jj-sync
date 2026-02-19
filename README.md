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

jj-sync auto-detects your remote if the repo has exactly one. If you have
multiple remotes, set `JJ_SYNC_REMOTE` to tell it which one to use.

## Commands

### `jj-sync push`

Pushes your in-progress changes to the remote. Only non-empty, mutable,
unpushed changes are synced (the revset is
`mine() & ~empty() & ~immutable_heads() & ~trunk()`). Stale refs for
abandoned or squashed changes are cleaned up automatically.

With `--docs`, pushes gitignored directories instead. With `--both`, pushes
revisions and docs together.

### `jj-sync pull`

Fetches WIP revisions from the remote and imports them into jj. The changes
show up in `jj log` as normal revisions.

With `--docs`, pulls and extracts doc directories. If multiple machines have
pushed docs, they get merged automatically. Conflicts produce standard git
conflict markers.

### `jj-sync status`

Shows what would be synced: local revisions, what's on the remote, doc
directory sizes, and current configuration.

### `jj-sync gc`

Cleans up old sync state. Revision refs older than 7 days get deleted. Doc
commit chains longer than 50 get squashed down to one commit. Both thresholds
are configurable (see [Configuration](#configuration)).

### `jj-sync clean`

Removes all sync state for the current user, both locally and on the remote.
If anything gets into a weird state, `clean --force` wipes the slate and you
can push again immediately.

### `jj-sync init`

Optional. Walks you through configuring the remote and machine name. You don't
need to run this -- jj-sync works out of the box with sensible defaults.

## Doc sync

Some workflows produce files that are gitignored but still useful across
machines -- AI context, local notes, generated docs. Doc sync handles these.
Set `JJ_SYNC_DOCS` to a space-separated list of directories:

```bash
export JJ_SYNC_DOCS="ai/docs .claude"

jj-sync push --docs   # docs only
jj-sync push --both   # revisions + docs
```

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
Make sure `JJ_SYNC_DOCS` is set to the same directory names on both machines.
Paths must match exactly (`ai/docs` vs `./ai/docs` are different).

**Something is broken:**

```bash
jj-sync clean --force  # wipes all sync state for current user
jj-sync push           # start fresh
```

## Limitations

- Revision sync is last-write-wins. If you amend the same change on two
  machines and push from both, the second push overwrites the first.
- Doc sync merges on pull, not push. Conflicts show up as git conflict markers.
- You can choose revisions, docs, or both, but you can't sync a subset of
  revisions or a single doc directory.
- Directory names in `JJ_SYNC_DOCS` can't contain spaces.

## License

GPL-3.0 - See [LICENSE](LICENSE) for details.

Copyright (c) 2026 Fabien O'Carroll
