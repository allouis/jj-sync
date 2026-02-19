# jj-sync cleanup task list

Work through tasks in order. Each task is one atomic commit.
Dependencies are noted — don't start a blocked task until its blockers are done.

## How to use this file

When starting a new Claude Code session, say:
> Read TASKS.md and work through the next pending task.

Mark tasks `[x]` as you complete them. Update the status line with the commit hash.

---

## Phase 1 — Bug fixes (do first, no dependencies)

### Task 7: Fix pull_docs data loss: extract before deleting
- [ ] **Status:** pending

CRITICAL DATA LOSS BUG: `pull_docs()` in `lib/docs.sh:289-295` deletes all files in doc directories BEFORE extracting the new content at line 299. If `extract_tree` fails (disk full, corrupt git object, interrupted process, git archive error), the user's untracked docs are permanently gone with no recovery path.

**Current dangerous code (lib/docs.sh:289-299):**
```bash
# Remove existing files in doc directories (to handle deletions)
for dir in "${doc_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
        verbose "Cleaning existing files in $dir"
        find "$dir" -type f -delete 2>/dev/null || true
    fi
done

# Extract the docs to working directory
verbose "Extracting docs to working directory"
extract_tree "$final_commit" "."
```

**Fix:** Extract to a temp directory first. Only after successful extraction, delete the old files and move the new ones into place. The pattern:
1. `mktemp -d` a staging directory
2. `extract_tree "$final_commit" "$staging_dir"`
3. If that succeeds, THEN delete old files and move new ones from staging
4. If it fails, leave existing files untouched and error out
5. Clean up staging dir in a trap

**Also consider:** The `find "$dir" -type f -delete 2>/dev/null || true` silently swallows delete errors. At minimum, if deletion fails after successful extraction, warn the user.

**Test:** Add a test that verifies existing doc files survive a failed pull (e.g., pull when remote has no docs, or when doc content is missing). Also verify the happy path still works.

**Before starting, ask the user:**
- On extraction failure, should we: (a) abort entirely and leave old files untouched, or (b) attempt partial extraction? (Recommendation: abort entirely — partial state is worse than old state for untracked data.)

**Completion criteria:**
- All existing tests pass (`bats tests/`)
- `shellcheck jj-sync lib/*.sh` clean
- New test(s) added for the safe extraction behavior
- Manual verification if test coverage isn't sufficient
- Commit following commit message guidelines, then move to next task without asking

---

### Task 8: Fix detect_git_dir failing in subdirectories
- [ ] **Status:** pending

BUG: `detect_git_dir()` in `lib/git-plumbing.sh:11-30` uses `pwd` and only checks the current directory for `.git/` or `.jj/repo/store/git/`. Running jj-sync from a subdirectory (e.g., `cd src && jj-sync push`) fails with "Not in a git repository" even though the repo exists above.

**Current code (lib/git-plumbing.sh:11-30):**
```bash
detect_git_dir() {
    local repo_root
    repo_root="$(pwd)"
    if [[ -d "$repo_root/.git" ]]; then ...
    if [[ -d "$repo_root/.jj/repo/store/git" ]]; then ...
    return 1
}
```

**Fix options (pick simplest):**
1. Use `git rev-parse --show-toplevel` to find repo root, then check for `.jj/` there for non-colocated detection. This handles subdirectories natively.
2. Walk up the directory tree in a loop checking each parent.

Option 1 is simpler and delegates the work to git.

**Before starting, ask the user:**
- Should jj-sync change its working directory to the repo root after detection? Currently some operations (like doc sync) use relative paths from `pwd`. If someone runs `jj-sync push --docs` from a subdirectory, should doc paths be resolved relative to the repo root or relative to `pwd`? (Recommendation: repo root, matching how git/jj behave.)

**Test:** Add a test that runs jj-sync from a subdirectory of a repo and verifies it works. Test both colocated and plain git repos.

**Completion criteria:**
- All existing tests pass (`bats tests/`)
- `shellcheck jj-sync lib/*.sh` clean
- New test(s) for subdirectory operation
- Commit following commit message guidelines, then move to next task without asking

---

### Task 9: Fix --remote/--user/--machine crash on missing argument
- [ ] **Status:** pending

BUG: In `jj-sync:89-99`, the `--remote`, `--user`, and `--machine` flags do `shift 2` without validating that `$2` exists. With `set -u` (line 2), if a user runs `jj-sync push --remote` (without a value), bash crashes with an unhelpful "unbound variable" error instead of a clear message.

**Current code (jj-sync:89-99):**
```bash
--remote)
    OPT_REMOTE="$2"
    shift 2
    ;;
--user)
    OPT_USER="$2"
    shift 2
    ;;
--machine)
    OPT_MACHINE="$2"
    shift 2
    ;;
```

**Fix:** Check `$#` before accessing `$2`. Pattern:
```bash
--remote)
    [[ $# -lt 2 ]] && die "--remote requires a value"
    OPT_REMOTE="$2"
    shift 2
    ;;
```

Apply to all three flags. No ambiguities — this task is self-contained and does not require user input to proceed.

**Test:** Add tests that verify `jj-sync push --remote` (no value) produces a clear error with non-zero exit, for each of the three flags.

**Completion criteria:**
- All existing tests pass (`bats tests/`)
- `shellcheck jj-sync lib/*.sh` clean
- New test(s) for missing argument errors
- Commit following commit message guidelines, then move to next task without asking

---

### Task 10: Fix GIT_INDEX_FILE leak in create_tree_from_files
- [ ] **Status:** pending

BUG: `create_tree_from_files()` in `lib/git-plumbing.sh:132-167` sets `GIT_INDEX_FILE` to a temp file at line 141. The restore logic at lines 159-164 runs after `git_cmd write-tree` at line 157. If any git command between lines 141-157 fails, the function exits due to `set -e` and `GIT_INDEX_FILE` remains set to the temp path, corrupting subsequent git operations.

**Current code (lib/git-plumbing.sh:132-167):**
- Line 137: `trap "rm -f '$temp_index'" RETURN` — cleans up the temp file
- Line 141: `export GIT_INDEX_FILE="$temp_index"` — sets the env var
- Lines 145-153: git add loop (errors swallowed with `|| true`)
- Line 157: `tree=$(git_cmd write-tree)` — can fail, exits without restoring
- Lines 159-164: restore logic — only reached on success

**Fix:** Run the git operations in a subshell so GIT_INDEX_FILE doesn't leak:
```bash
create_tree_from_files() {
    local dirs=("$@")
    local temp_index
    temp_index=$(mktemp -u)
    (
        trap "rm -f '$temp_index'" EXIT
        export GIT_INDEX_FILE="$temp_index"
        # ... git add loop ...
        git_cmd write-tree
    )
}
```

No ambiguities — this task is self-contained and does not require user input to proceed. The subshell approach is strictly better and has no behavioral tradeoffs.

**Test:** Verify existing doc push/pull tests still pass (they exercise this code path).

**Completion criteria:**
- All existing tests pass (`bats tests/`)
- `shellcheck jj-sync lib/*.sh` clean
- Commit following commit message guidelines, then move to next task without asking

---

### Task 11: Audit and fix silently swallowed errors
- [ ] **Status:** pending

Several places silently swallow errors that could mask real problems. Audit each `|| true` and `2>/dev/null` and decide: keep (genuinely expected), add warning, or let it fail.

**Locations to audit:**

1. **lib/revisions.sh:144** — `jj git import --quiet 2>/dev/null || true` in `pull_revisions`. If import fails, jj won't see the pulled commits. Silent data loss path.
2. **lib/docs.sh:122** — `fetch_remote 2>/dev/null || true` in `push_docs`. Falls back to orphan commit if fetch fails — arguably OK.
3. **lib/docs.sh:181** — `fetch_remote 2>/dev/null || true` in `pull_docs`. Could result in "No docs found on remote" if fetch fails.
4. **lib/gc.sh:11** — `fetch_remote 2>/dev/null || true` in `gc_revisions`. Stale state if fetch fails.
5. **lib/git-plumbing.sh:150** — `git_cmd add -f "$file" 2>/dev/null || true` in `create_tree_from_files`. Missing files in tree.
6. **lib/git-plumbing.sh:259** — `git_cmd fetch "$JJ_SYNC_REMOTE" "$commit" 2>/dev/null || true` in `get_remote_commit`. Returns SHA but object may not exist locally.
7. **lib/docs.sh:293** — `find "$dir" -type f -delete 2>/dev/null || true` in `pull_docs` delete loop. May be moot after Task 7.

**Before starting, ask the user:**
- What's the preferred error philosophy? Options: (a) Warn on all suppressed errors via `log_warn` (noisier but transparent), (b) Only warn on errors that could cause data loss or incorrect results (quieter), (c) Promote critical swallowed errors to fatal `die` calls. (Recommendation: option b — warn only when the suppressed error leads to incorrect/missing data.)

**Completion criteria:**
- All existing tests pass (`bats tests/`)
- `shellcheck jj-sync lib/*.sh` clean
- Commit following commit message guidelines, then move to next task without asking

---

## Phase 2 — Structure (blocked on Phase 1)

### Task 12: Merge lib/ into single jj-sync script
- [ ] **Status:** pending
- **Blocked by:** Tasks 7, 8, 9, 10, 11

Merge all `lib/*.sh` files into a single `jj-sync` script. The current 7-file split provides no encapsulation (bash `source` is textual concatenation, all globals shared) and makes navigation harder. Total is ~1,750 lines — well within single-file bash norms.

**Files to merge (in this order, matching dependency order):**
1. `lib/ui.sh` (166 lines) — colors, logging, prompts
2. `lib/env.sh` (127 lines) — config loading, ref naming helpers
3. `lib/git-plumbing.sh` (~320 lines) — low-level git operations
4. `lib/revisions.sh` (178 lines) — revision push/pull
5. `lib/docs.sh` (~345 lines) — doc push/pull
6. `lib/gc.sh` (~360 lines) — GC, status, clean, init

**Section order in merged file:**
```
#!/usr/bin/env bash
set -euo pipefail

# === Globals ===
# === UI Helpers ===
# === Environment ===
# === Git Plumbing ===
# === Revision Sync ===
# === Doc Sync ===
# === GC / Cleanup ===
# === Status / Init ===
# === Command Dispatch ===
main "$@"
```

**Before starting, ask the user:**
- Should section headers use a visual separator style like `# ============ UI Helpers ============` or a simpler `# === UI Helpers ===`? Or something else? (Matters for grepability and readability.)
- The `install.sh` copies files — need to check if it copies `lib/`. Should I update it or is it handled separately?

**Steps:**
1. Read all files, concatenate in order into `jj-sync`
2. Replace the `source` lines and `SCRIPT_DIR` logic with section comment headers
3. Keep `#!/usr/bin/env bash` and `set -euo pipefail` at top
4. Delete `lib/` directory entirely
5. Update `install.sh` if it copies lib/ files
6. Run all tests and shellcheck

**Completion criteria:**
- All existing tests pass (`bats tests/`)
- `shellcheck jj-sync` clean (single file now)
- `lib/` directory removed
- `install.sh` updated if needed
- Commit following commit message guidelines, then move to next task without asking

---

### Task 13: Remove dead code
- [ ] **Status:** pending
- **Blocked by:** Task 12

Remove unused functions and test helpers.

**Dead functions in the source:**
1. `ref_exists_local()` — defined but never called anywhere
2. `ref_exists_remote()` — defined but never called anywhere
3. `update_ref()` — defined but never called anywhere
4. `merge_trees()` — defined but never called. Confusing because `pull_docs()` reimplements merge logic inline instead of using this wrapper.

**Dead test helpers in tests/test_helper.bash:**
1. `count_wip_changes()` (line ~361) — defined but never called in any test
2. `create_wip_changes()` (line ~157) — defined but never called in any test

No ambiguities — this task is self-contained and does not require user input to proceed. Just remove the dead code and verify tests pass.

**Completion criteria:**
- All existing tests pass (`bats tests/`)
- `shellcheck jj-sync` clean
- Commit following commit message guidelines, then move to next task without asking

---

### Task 14: Remove redundant detect_git_dir calls
- [ ] **Status:** pending
- **Blocked by:** Task 12

Remove redundant `detect_git_dir` calls. Currently called ~10 times per invocation because each function defensively calls it.

**Call sites to remove (in merged jj-sync, search for `detect_git_dir` calls):**
- `push_docs()` — was docs.sh:115
- `pull_docs()` — was docs.sh:176
- `pull_revisions()` — was revisions.sh:105
- `gc_revisions()` — was gc.sh:8
- `gc_docs()` — was gc.sh:69
- `clean_all()` — was gc.sh:125
- `show_status()` — was gc.sh:171
- `require_remote()` — was git-plumbing.sh:120

**Keep:** `require_git_repo()`, `require_jj_repo()` (entry points), and `init_setup()` (bypasses normal dispatch).

No ambiguities — this task is self-contained and does not require user input to proceed. Just remove the redundant calls, the entry points guarantee GIT_DIR is set before any command function runs.

**Completion criteria:**
- All existing tests pass (`bats tests/`)
- `shellcheck jj-sync` clean
- Commit following commit message guidelines, then move to next task without asking

---

## Phase 3 — Tests (blocked on Phase 2)

### Task 15: Fix tests giving false confidence (G5, R5, V17)
- [ ] **Status:** pending
- **Blocked by:** Task 12

Three tests claim to verify properties they don't actually check.

**1. G5 "GC is idempotent" (tests/test_gc.bats:110-127)**
Current: Captures `output1` and `output2` but never compares them. Only checks `$status -eq 0` on second run.
Fix: After first GC, count remote bookmarks. After second GC, count again and assert they're equal. Assert `$status -eq 0` for both runs.

**2. R5 "Push replaces stale bookmarks" (tests/test_revisions.bats:86-119)**
Current: Creates NEW changes and pushes — never abandons a change. Tests accumulation, not stale removal.
Fix: Create a change, push, abandon it (`jj abandon`), push again. Verify the abandoned change's bookmark is gone from remote.

**3. V17 "Pull only fetches current user's refs" (tests/test_env.bats:358-378)**
Current: Checks alice's change is visible but doesn't check bob's is absent.
Fix: Capture bob's change_id, assert `! jj_has_change "$bob_change"` after alice's pull.

**Before starting, ask the user:**
- For R5: after abandoning and re-pushing, should the stale bookmark count be exactly 0 for the abandoned change? Or is it acceptable if the remote still has it until GC runs? (Need to verify: does `push_revisions` delete stale bookmarks from remote, or only GC does that?) Check `lib/revisions.sh:48-72` — the stale detection loop suggests push does delete them. Confirm this behavior before writing the test.

**Completion criteria:**
- All existing tests pass (`bats tests/`)
- Each fixed test now actually verifies the property its name claims
- Commit following commit message guidelines, then move to next task without asking

---

### Task 16: Add missing critical test coverage
- [ ] **Status:** pending
- **Blocked by:** Task 12

Add tests for SPEC scenarios with zero coverage.

**Must add:**

1. **R6 — Amended changes update bookmark**: Create change, push, amend (modify file, same change_id gets new commit_id), push again. Verify remote bookmark updated. Pull on another machine, verify amended content.

2. **R9 — Immutable changes excluded**: Create a change, push it to main (making it immutable), then run jj-sync push. Verify no sync bookmarks created for immutable change.

3. **R10 — `mine()` filter**: This requires creating a change authored by someone else. In jj, you can set a different author via config. Verify only `mine()` changes are pushed.

4. **--dry-run doesn't modify state**: Push with `--dry-run`, verify no remote bookmarks. Pull with `--dry-run`, verify no files extracted.

5. **--both syncs revisions + docs**: Push `--both`, verify both rev bookmarks and doc bookmark on remote. Pull `--both` on other machine, verify both received.

**Before starting, ask the user:**
- For R9 (immutable changes): what's the simplest way to create an immutable change in the test environment? Options: (a) create a bookmark on main and push to the test remote, (b) use `jj new main` then commit on main. Need to verify the test infrastructure supports this. If unclear, investigate the jj docs or existing test patterns.
- For R10 (mine() filter): should I use `jj --config-toml 'user.email="other@example.com"'` to create a change as a different author? Or is there a simpler approach?

**Also clean up duplicates:**
- V12 and E2 test the same scenario (nonexistent remote). Remove the duplicate.
- R7 and E8 test the same scenario (empty push). Remove the duplicate.

**Completion criteria:**
- All tests pass (`bats tests/`)
- `shellcheck` clean
- Each new test verifies a distinct SPEC property
- Commit following commit message guidelines, then move to next task without asking

---

## Phase 4 — Documentation (blocked on Phase 2)

### Task 17: Add "How it works" section to README
- [ ] **Status:** pending
- **Blocked by:** Task 12

Add a "How it works" section to README.md explaining the mechanism so users can evaluate safety.

**Add after Quick Start, before Usage. Content should cover:**
- `refs/jj-sync/` namespace — invisible to git log, jj log, teammates
- Revision sync mechanism — temp bookmark-like refs pushed then cleaned up
- Doc sync mechanism — orphan commits via git plumbing, disconnected from repo DAG
- Safety guarantees — never writes refs/heads/, never modifies working copy commits
- Namespace format — `refs/jj-sync/sync/<user>/<machine>/...`
- Escape hatch — `jj-sync clean`

**Also expand Quick Start** to include remote setup step (currently assumes remote exists).

**Before starting, ask the user:**
- How technical should the "How it works" section be? Options: (a) High-level for end users — "uses custom git refs, invisible to normal operations" without mentioning plumbing commands, (b) Medium detail — mentions refs/jj-sync/, orphan commits, but not specific git commands, (c) Full detail — mentions git write-tree, commit-tree, etc. for users who want to audit. (Recommendation: option b — enough to build trust without overwhelming.)
- Should we include the ASCII architecture diagram from SPEC.md showing the personal remote model? It's quite good for understanding the overall flow.

**Completion criteria:**
- README.md updated with How it works section
- Quick Start expanded
- Commit following commit message guidelines, then move to next task without asking

---

### Task 18: Document limitations and troubleshooting
- [ ] **Status:** pending
- **Blocked by:** Task 17

Add limitations, prerequisites details, and troubleshooting to README.md.

**1. Limitations section:**
- Doc sync uses "last write wins" — no three-way merge yet
- `JJ_SYNC_DOCS` is space-separated, no support for dirs with spaces

**2. Prerequisites clarifications:**
- macOS ships bash 3.2, need >= 4.0 via Homebrew or Nix
- jj >= 0.22.0 for `bookmark` subcommand
- Why git >= 2.38 (`git merge-tree --write-tree`)

**3. Troubleshooting section:**
- `jj-sync status` for diagnostics
- `jj-sync clean --force` as escape hatch
- Common error messages and fixes

**Before starting, ask the user:**
- Should the macOS bash warning be prominent (in Requirements) or a note in Troubleshooting? macOS users hitting this will see confusing syntax errors.
- Is there a minimum jj version we've actually tested against? The task assumes 0.22.0 based on when `bookmark` was introduced, but should verify.
- Any other known issues or FAQs from real usage to include?

**Completion criteria:**
- README.md and SPEC.md updated
- Commit following commit message guidelines, then move to next task without asking
