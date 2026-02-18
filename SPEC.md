# jj-sync — Implementation Plan

## Problem Statement

When working across multiple dev machines (laptop, ephemeral remote envs via SSH), there is no built-in way to sync:

1. **WIP jj revisions** — experimental changes without bookmarks that can't be pushed
2. **Gitignored docs** — AI agent plans, markdown notes in directories like `./ai/docs/` that are gitignored by the team

The tool must work bidirectionally across N machines with minimal per-repo setup, using a single private git remote as the transport layer.

---

## Architecture

### High-Level Design

```
                  ┌─────────────────────┐
                  │   origin (team)      │  ← untouched, only clean branches
                  └─────────────────────┘

   ┌──────────┐    ┌──────────┐    ┌──────────┐
   │  laptop  │    │  dev-1   │    │  dev-2   │
   └────┬─────┘    └────┬─────┘    └────┬─────┘
        │               │               │
        └───────────────┼───────────────┘
                        │
              ┌─────────┴──────────┐
              │   personal remote  │  ← private fork / sync repo
              │                    │     namespaced per-machine
              └────────────────────┘
```

### Transport

Everything uses git push/fetch to a single private remote. No rsync, no syncthing, no extra services. The only per-repo setup is:

```bash
jj git remote add personal <url>
```

### Namespace Convention

All sync state lives under a `refs/jj-sync/` namespace, further namespaced by machine:

```
refs/jj-sync/sync/<machine>/revs/<change_id_prefix>   # WIP revisions
refs/jj-sync/sync/<machine>/docs                       # gitignored doc files
```

**Important**: We use `refs/jj-sync/` instead of regular git branches (`refs/heads/`) to avoid jj importing them as bookmarks. If synced commits were imported as bookmarks, jj would mark them as immutable, defeating the purpose of syncing WIP changes.

The machine name is auto-detected from `hostname` and can be overridden via config.

---

## Component 1: Revision Sync

### Problem

jj changes without bookmarks are dangling git commits. They cannot be pushed. But once a commit exists in a git object store, jj can see it — bookmarks are just transport.

### Push Algorithm

```
1. Query jj for syncable changes:
     mine() & ~empty() & ~immutable_heads() & ~trunk()
2. For each change:
     Set bookmark: sync/<machine>/revs/<change_id[0:12]>
       (jj bookmark set creates if new, moves if existing)
3. Delete any stale sync/<machine>/revs/* bookmarks on remote
   that are NOT in the current set (machine state is replaced atomically)
4. Push all sync/<machine>/revs/* bookmarks to personal remote
     jj git push --remote personal --bookmark "glob:sync/<machine>/revs/*" --allow-new
5. Delete all sync/<machine>/revs/* bookmarks locally
     (changes persist as jj revisions without bookmarks)
```

### Pull Algorithm

```
1. Fetch from personal remote:
     jj git fetch --remote personal
2. All sync/**/revs/* bookmarks arrive → jj sees the commits as changes
3. Delete only the local bookmarks (NOT the remote ones — other machines
   may not have pulled yet)
4. Output summary of received changes
```

### Garbage Collection

Since pull no longer deletes remote bookmarks, stale bookmarks accumulate. The `gc` command handles this:

```
1. List all sync/**/revs/* bookmarks on remote
2. For each, inspect the commit timestamp
3. Delete bookmarks older than threshold (default: 7 days)
4. Push deletions to remote
```

### Edge Cases

- **Same change on multiple machines**: Two machines may both have the same change_id. Each pushes under its own namespace, so no conflict. On pull, jj deduplicates by change_id automatically.
- **Amended changes**: If a change is amended (new commit_id, same change_id), the bookmark is updated on next push. jj reconciles by change_id.
- **Rebased changes**: Same as amended — the bookmark moves to the new commit.
- **Conflicting amends**: Machine A amends change X, machine B amends change X differently. After both push and both pull, jj will see two versions. The user resolves via `jj resolve` or by abandoning one. This is the expected jj workflow.

---

## Component 2: Doc Sync

### Problem

Directories like `./ai/docs/` are in `.gitignore`. Git and jj refuse to track them. We need to transport these files without them ever appearing in the project's commit history.

### Approach: Orphan Commits via Git Plumbing

Use git's low-level commands to create standalone commits containing only the doc files. These commits have no parent and are not connected to the repo's DAG. They're invisible to `jj log`, `git log`, and teammates.

### Push Algorithm

```
1. Create a temporary git index file (not the repo's real index)
2. For each configured doc directory:
     Find all files recursively
     `git add -f` each file into the temp index
       (-f bypasses .gitignore)
3. `git write-tree` from the temp index → tree object
4. Fetch current sync/<machine>/docs commit from remote (if exists)
5. `git commit-tree` with parent = previous docs commit (if any)
     If no previous commit exists, create a parentless (orphan) commit
     Commit message: "jj-sync docs <ISO timestamp>"
6. Update ref: sync/<machine>/docs → new commit
7. `jj git import` to make jj aware of the ref
8. Push: jj git push --remote personal --bookmark sync/<machine>/docs --allow-new
9. Clean up locally: delete bookmark + ref + temp index
```

The parent chain is important — it enables three-way merge for parallel writes (see below).

### Pull Algorithm

```
1. Fetch from personal remote (may already have happened during rev pull)
2. Collect all sync/**/docs bookmarks (from all machines)
3. If only one docs bookmark: extract directly via `git archive`
4. If multiple docs bookmarks exist (parallel writes):
     a. Find common ancestor via `git merge-base` (exists because of parent chain)
     b. Attempt `git merge-tree` (three-way merge of the tree objects)
     c. If clean merge: extract the merged tree
     d. If conflicts: extract with conflict markers for text files,
        keep "ours" for binary files, warn the user
5. Extract files into working directory at their original paths
6. Do NOT delete remote bookmarks (other machines may need them)
```

### Parallel Docs Writes — Detailed Design

This is the most complex part. The parent chain on docs commits enables git's merge machinery.

**Scenario**: Machine A and Machine B both started from the same docs state. Both make edits and push.

```
Timeline:
  1. Both machines pull → both have docs commit D0
  2. Machine A edits docs, pushes → sync/laptop/docs = D1 (parent: D0)
  3. Machine B edits docs, pushes → sync/dev-1/docs = D2 (parent: D0)
  4. Machine A pulls → sees D1 and D2, common ancestor D0
     → three-way merge of D0, D1, D2
```

**Merge implementation using git plumbing:**

```bash
# Find common ancestor
base=$(git merge-base $commit_a $commit_b)

# Three-way merge of trees
# git merge-tree (new version in git 2.38+) outputs clean merge or conflicts
result=$(git merge-tree --write-tree $base $commit_a $commit_b)

if [ $? -eq 0 ]; then
    # Clean merge — extract the result tree
    merged_tree="$result"
else
    # Conflicts — result contains the tree with conflict markers
    # Extract it and warn the user
    merged_tree=$(echo "$result" | head -1)
fi
```

**After merge**, create a new docs commit with both D1 and D2 as parents (merge commit). Push this as the new `sync/<machine>/docs` so future pushes from any machine build on the merged state.

**If `git merge-tree` produces conflicts**, extract the tree with conflict markers and warn the user. The user resolves manually and pushes the fixed docs.

**Document types and merge behavior:**

| File Type | Merge Strategy |
|-----------|---------------|
| `.md`, `.txt`, `.yaml`, `.json` | Text three-way merge (conflict markers if needed) |
| Binary files | Last-write-wins (warn user) |
| Deleted files | If deleted on one side and unchanged on other, delete wins |

### Garbage Collection for Docs

The docs commit chain grows over time. The `gc` command should:

```
1. Find the docs commit pointed to by sync/<machine>/docs
2. Walk the parent chain
3. If chain length > threshold (default: 50 commits):
     Squash into a single orphan commit (no parents)
     Force-push the bookmark
```

This keeps the sync repo from growing unboundedly.

---

## Configuration

All configuration is via environment variables. Set them in your shell profile (`~/.bashrc`, `~/.zshrc`, etc.) or per-repo via direnv/similar.

```bash
# Space-separated directories to sync as docs (required for --docs/--both)
JJ_SYNC_DOCS="ai/docs .claude plans"

# Which git remote to use for sync (default: personal)
JJ_SYNC_REMOTE=personal

# Machine name override (default: $(hostname))
JJ_SYNC_MACHINE=laptop

# GC threshold for revision bookmarks in days (default: 7)
JJ_SYNC_GC_REVS_DAYS=7

# GC threshold for docs commit chain length (default: 50)
JJ_SYNC_GC_DOCS_MAX_CHAIN=50
```

### Required vs Optional

- `JJ_SYNC_DOCS` — required when using `--docs` or `--both`, otherwise ignored
- All others — optional with sensible defaults

---

## CLI Interface

```
jj-sync <command> [options]

Commands:
  push              Push to personal remote
  pull              Pull from personal remote
  status            Show what would be synced
  gc                Garbage collect stale sync bookmarks and doc chains
  clean             Remove ALL sync state (local + remote) — nuclear option
  init              Interactive setup: configure remote, machine name
  help              Show help

Flags:
  --docs            Sync docs only (requires JJ_SYNC_DOCS)
  --both            Sync revisions + docs (requires JJ_SYNC_DOCS)
                    Default (no flag): sync revisions only

Options:
  --remote <name>   Override sync remote
  --machine <name>  Override machine name
  --dry-run         Show what would happen without doing it
  --verbose         Show git plumbing commands as they run
  --force           Skip confirmation prompts
```

### Flag Behavior

| Command | What syncs |
|---------|-----------|
| `jj-sync push` | Revisions only |
| `jj-sync push --docs` | Docs only |
| `jj-sync push --both` | Revisions + docs |
| `jj-sync pull` | Revisions only |
| `jj-sync pull --docs` | Docs only |
| `jj-sync pull --both` | Revisions + docs |

Using `--docs` or `--both` without `JJ_SYNC_DOCS` set is an error:
```
Error: --docs requires JJ_SYNC_DOCS environment variable
Hint: export JJ_SYNC_DOCS="ai/docs .claude"
```

### Command Details

**`jj-sync init`**:
Interactive first-time setup for a repo. Verifies `git` >= 2.38 and `jj` are installed, prompts for remote URL, creates remote. Prints instructions for setting env vars (`JJ_SYNC_DOCS`, etc.) in shell profile. Fails with a clear error if version requirements are not met.

**`jj-sync status`**:
```
jj-sync status

Remote: personal → git@github.com:fabien/ghost-sync.git
Machine: laptop

Revisions (would push): 4
  kpqvtszo 8a3f1b2c     Experiment with new auth flow
  xrmnwqkl 1d4e5f6a     WIP: refactor email service
  ...

Remote revisions:
  sync/laptop/revs/*     3 bookmarks (last push: 2h ago)
  sync/dev-1/revs/*      7 bookmarks (last push: 1d ago)

Docs (JJ_SYNC_DOCS="ai/docs .claude"):
  ai/docs/     12 files
  .claude/     3 files

Remote docs:
  sync/laptop/docs       last push: 2h ago
  sync/dev-1/docs        last push: 5h ago (diverged — will merge on pull)
```

If `JJ_SYNC_DOCS` is not set, the docs section shows:
```
Docs: not configured (set JJ_SYNC_DOCS to enable)
```

**`jj-sync gc`**:
```
jj-sync gc

Revisions:
  Removing 5 bookmarks older than 7 days from sync/dev-1/revs/*
  Keeping 3 recent bookmarks from sync/laptop/revs/*

Docs:
  sync/laptop/docs: chain length 12 (under threshold of 50)
  sync/dev-1/docs: chain length 67 — squashing to 1 commit
```

---

## File Structure

```
jj-sync/
├── jj-sync                      # Main entry point (bash)
├── lib/
│   ├── env.sh                   # Env var loading + defaults
│   ├── revisions.sh             # push_revisions, pull_revisions
│   ├── docs.sh                  # push_docs, pull_docs
│   ├── gc.sh                    # Garbage collection, status, clean, init
│   ├── ui.sh                    # Colors, logging, progress
│   └── git-plumbing.sh          # Low-level git operations
├── tests/
│   ├── test_helper.bash         # Test utilities: create temp repos, etc.
│   ├── test_revisions.bats      # Revision sync tests
│   ├── test_docs.bats           # Doc sync tests
│   ├── test_gc.bats             # GC tests
│   ├── test_env.bats            # Env var handling tests
│   └── test_edge_cases.bats     # Error handling, partial failures
├── completions/
│   ├── jj-sync.bash             # Bash completions
│   ├── _jj-sync                 # Zsh completions
│   └── jj-sync.fish             # Fish completions
├── flake.nix                    # Nix flake for dev environment
├── flake.lock                   # Nix flake lockfile
├── .envrc                       # direnv configuration
├── README.md
├── SPEC.md                      # This file
└── install.sh                   # Copy to PATH, setup completions
```

---

## Test Plan

### Test Infrastructure

Each test creates disposable git repos (bare remote + N working copies simulating different machines) in a temp directory. Tests use `bats` (Bash Automated Testing System) as the test runner.

```bash
# Test helper: create a simulated multi-machine environment
setup_test_env() {
    TEST_DIR=$(mktemp -d)

    # Create bare "personal remote"
    git init --bare "$TEST_DIR/remote.git"

    # Create "laptop" working copy with jj (colocated)
    mkdir "$TEST_DIR/laptop"
    cd "$TEST_DIR/laptop"
    jj git init --colocate
    jj git remote add personal "$TEST_DIR/remote.git"
    export JJ_SYNC_MACHINE=laptop

    # Create "dev-1" working copy with jj (non-colocated)
    mkdir "$TEST_DIR/dev-1"
    cd "$TEST_DIR/dev-1"
    jj git init
    jj git remote add personal "$TEST_DIR/remote.git"
    export JJ_SYNC_MACHINE=dev-1
}
```

### Test Cases

#### Revision Sync

| # | Test | Description |
|---|------|-------------|
| R1 | Push creates bookmarks | After push, personal remote has `sync/<machine>/revs/*` refs |
| R2 | Push cleans local bookmarks | After push, no `sync/*` bookmarks exist locally |
| R3 | Pull receives changes | After push on A + pull on B, B has the same jj changes |
| R4 | Pull leaves remote intact | After pull on B, remote still has the bookmarks for A to pull |
| R5 | Push replaces stale bookmarks | Push from A, abandon a change, push again — stale bookmark is gone |
| R6 | Amended changes update | Amend a change on A, push — bookmark points to new commit |
| R7 | Empty repo push | Push with no WIP changes — no error, no bookmarks |
| R8 | Duplicate change on two machines | Same change_id on A and B, both push and pull — jj deduplicates |
| R9 | Immutable changes excluded | Changes on trunk/main are not synced |
| R10 | Respects `mine()` filter | Other authors' changes are not synced |
| R11 | Large number of changes | 100 WIP changes — all sync correctly |

#### Doc Sync — Basic

| # | Test | Description |
|---|------|-------------|
| D1 | Push packs docs | After push, remote has `sync/<machine>/docs` ref with correct files |
| D2 | Pull extracts docs | After push on A + pull on B, B has identical doc files |
| D3 | Subdirectory structure preserved | Nested dirs like `ai/docs/plans/q1/goals.md` survive roundtrip |
| D4 | Multiple doc dirs | Config with 3 doc dirs — all synced |
| D5 | Empty doc dir | Doc dir exists but is empty — no error |
| D6 | Missing doc dir | Configured doc dir doesn't exist — skip with warning |
| D7 | Binary files in docs | Images, PDFs in doc dir — survive roundtrip |
| D8 | Files with special characters | Filenames with spaces, unicode — handled correctly |
| D9 | Large doc set | 500 files totaling 50MB — completes in reasonable time |
| D10 | Doc commit has parent chain | Second push creates commit with parent pointing to first |
| D11 | Deleted files sync | File deleted locally, push, pull on B — file gone on B too |

#### Doc Sync — Parallel Writes (Merge)

| # | Test | Description |
|---|------|-------------|
| M1 | Non-overlapping edits | A edits file1.md, B edits file2.md — both present after merge |
| M2 | Same file, different sections | A edits top of file, B edits bottom — clean merge |
| M3 | Same file, conflicting edits | A and B edit same line — conflict markers in file, warning to user |
| M4 | One side adds, other deletes | A adds file, B deletes different file — both operations apply |
| M5 | Add same new file | A and B both add `notes.md` with different content — conflict |
| M6 | Three machines diverged | A, B, C all push — pull merges all three (sequential pairwise merge) |
| M7 | Merge creates proper parent chain | After merge, new docs commit has correct parents |
| M8 | Subsequent push after merge | After pulling merged docs, next push builds on merge commit |
| M9 | No common ancestor (first push) | Two machines push docs for first time — falls back to union merge |
| M10 | Binary file conflict | Both sides modify same binary — keep last-pushed, warn user |

#### Garbage Collection

| # | Test | Description |
|---|------|-------------|
| G1 | Old rev bookmarks cleaned | Bookmarks older than threshold are removed |
| G2 | Recent rev bookmarks kept | Bookmarks within threshold are preserved |
| G3 | Doc chain squashed | Chain exceeding max length is squashed to single commit |
| G4 | Squashed chain preserves content | After squash, doc content is identical |
| G5 | GC is idempotent | Running gc twice produces same result |

#### Environment Variables

| # | Test | Description |
|---|------|-------------|
| V1 | Defaults work | No env vars — uses default remote, hostname for machine |
| V2 | Machine name from hostname | Without `JJ_SYNC_MACHINE`, uses `$(hostname)` |
| V3 | Remote override | `JJ_SYNC_REMOTE=other` uses different remote |
| V4 | Machine override | `JJ_SYNC_MACHINE=mybox` overrides hostname |
| V5 | Docs flag without env | `--docs` without `JJ_SYNC_DOCS` — clear error |
| V6 | Both flag without env | `--both` without `JJ_SYNC_DOCS` — clear error |
| V7 | Docs dirs parsed | `JJ_SYNC_DOCS="a b c"` correctly splits into 3 dirs |
| V8 | Empty docs env | `JJ_SYNC_DOCS=""` with `--docs` — clear error |

#### Error Handling

| # | Test | Description |
|---|------|-------------|
| E1 | No jj repo | Running outside jj repo — clear error |
| E2 | No personal remote | Remote not configured — clear error with setup instructions |
| E3 | Remote unreachable | Network error on push/pull — clear error, no partial state |
| E4 | Non-colocated repo | jj repo without `.git/` — detects `.jj/repo/store/git/` and works |
| E5 | Push interrupted | Kill during push — clean state on retry |
| E6 | Concurrent push | Two machines push simultaneously — no corruption |
| E7 | Partial fetch failure | Fetch gets some refs but not all — report what succeeded |
| E8 | Disk full during extract | Graceful failure, clear message |
| E9 | Git version too old | git < 2.38 detected — clear error with upgrade instructions |

---

## Implementation Order

### Phase 1: Core (MVP)

Get the basic push/pull loop working for a two-machine case.

1. `lib/env.sh` — env var loading + defaults
2. `lib/ui.sh` — logging, colors
3. `lib/revisions.sh` — push_revisions, pull_revisions (per-machine namespace)
4. `lib/docs.sh` — push_docs, pull_docs (single-machine, no merge yet)
5. `lib/git-plumbing.sh` — helpers for tree/commit creation, ref management
6. `jj-sync` — main entry point, command routing, flag parsing
7. `tests/test_revisions.sh` — tests R1–R8
8. `tests/test_docs.sh` — tests D1–D8
9. `tests/test_env.sh` — tests V1–V8

**Exit criteria**: Can push from laptop, pull on dev box, and vice versa. Revisions and docs both work (with `--docs` or `--both`). Docs are last-write-wins.

### Phase 2: Multi-Machine

Add proper multi-machine support with doc merging.

1. Update pull to NOT delete remote bookmarks
2. Add doc merge logic to `lib/docs.sh` using `git merge-tree`
3. `tests/test_docs_merge.sh` — tests M1–M10
4. `tests/test_multi_machine.sh` — full N-machine simulation

**Exit criteria**: Three simulated machines can all push and pull without data loss. Parallel doc edits merge cleanly or produce conflict markers.

### Phase 3: Lifecycle Management

1. `lib/gc.sh` — garbage collection for revs and docs
2. `jj-sync gc` command
3. `jj-sync clean` command (nuclear option)
4. `jj-sync status` with remote state inspection
5. `jj-sync init` interactive setup
6. `tests/test_gc.sh` — tests G1–G5
7. `tests/test_edge_cases.sh` — tests E1–E8

**Exit criteria**: Long-running usage doesn't accumulate unbounded state. Setup is frictionless.

### Phase 4: Polish

1. `--dry-run` support across all commands
2. `--verbose` mode showing git plumbing commands
3. Shell completions (bash, zsh, fish)
4. `install.sh`
5. `README.md` with usage guide
6. Man page (optional)

---

## Dependencies

### Required

- `jj` (any recent version with `bookmark` subcommand)
- `git` >= 2.38 (required for `git merge-tree --write-tree`)
- `bash` >= 4.0
- Standard Unix tools: `find`, `tar`, `mktemp`, `date`, `hostname`

The `init` command should verify minimum versions and fail with a clear message if not met.

### For Development

- `nix` with flakes enabled (provides reproducible development environment)
- `direnv` (optional, for automatic shell activation)

### For Testing

- `bats-core` (Bash Automated Testing System)
- `shellcheck` (shell script linting)
- `shfmt` (shell script formatting)
- `jj` and `git` (obviously)
- Temp filesystem access

---

## Development Setup

The project uses Nix flakes to provide a reproducible development environment with all required tools.

### Quick Start

```bash
# Enter the development shell
nix develop

# Or with direnv (automatic activation)
echo "use flake" > .envrc
direnv allow
```

### Available Tools in Dev Shell

- `bats` - Test runner for bash
- `shellcheck` - Shell script linter
- `shfmt` - Shell script formatter
- `jj` - Jujutsu VCS
- `git` - Git (obviously)

### Running Tests

```bash
# Run all tests
bats tests/

# Run a specific test file
bats tests/test_revisions.bats

# Run with verbose output
bats tests/ --verbose-run
```

### Linting

```bash
shellcheck jj-sync lib/*.sh
```

### Formatting

```bash
shfmt -w jj-sync lib/*.sh
```

---

## Resolved Decisions

1. **`jj bookmark set` creates or moves** — no need for a separate `create` call. Use `set` everywhere.

2. **Non-colocated repos supported** — the git plumbing works identically, just with a different `GIT_DIR`. Detection logic:
   - Colocated: `GIT_DIR=<repo_root>/.git`
   - Non-colocated: `GIT_DIR=<repo_root>/.jj/repo/store/git`
   - Check colocated first, fall back to non-colocated, error if neither exists.

3. **Docs push uses full replacement** — each push packs the complete doc directory into a commit. The merge-tree approach handles conflict resolution on pull, not on push. This keeps push simple and fast.

4. **Merge commit author** — use the pulling machine's git user config. Not important.

5. **`jj-sync init` does not create remote repos** — user creates the repo manually. Out of scope.

6. **Single email across machines** — `mine()` revset works without override. Drop the `JJ_SYNC_REVSET` config option.

---

## Implementation Status

### Completed (Phase 1 + Partial Phase 2 + Phase 3 + Phase 4)

- Core revision sync (push/pull)
- Core doc sync (push/pull, no merge)
- All environment variable handling
- Garbage collection for revisions and docs
- `status`, `clean`, `init` commands
- `--dry-run` and `--verbose` flags
- Shell completions (bash, zsh)
- Install script
- Comprehensive test suite (44 tests)
- Nix flakes + direnv setup

### Remaining (Phase 2 Partial)

- Doc merge logic for parallel writes
- Multi-machine doc merge tests

The core functionality is complete and usable. Doc merge for parallel writes is the main missing feature — currently docs use "last write wins" semantics.
