#!/usr/bin/env bats
# tests/test_env.bats - Environment variable tests

load test_helper.bash

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "V1: Defaults work - no env vars needed for basic operation" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Source env.sh and load with clean env
    (
        unset REF_SYNC_REMOTE
        unset REF_SYNC_MACHINE
        unset REF_SYNC_DOCS
        source "$PROJECT_ROOT/ref-sync"
        load_env

        # Remote should be empty (auto-detected later)
        [[ -z "$REF_SYNC_REMOTE" ]]
        [[ -n "$REF_SYNC_MACHINE" ]]
        [[ "$REF_SYNC_GC_REVS_DAYS" == "7" ]]
        [[ "$REF_SYNC_GC_DOCS_MAX_CHAIN" == "50" ]]
    )
}

@test "V2: Machine name defaults to hostname" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        unset REF_SYNC_MACHINE
        source "$PROJECT_ROOT/ref-sync"
        load_env

        # Machine name should be non-empty (derived from hostname)
        [[ -n "$REF_SYNC_MACHINE" ]]
        # Should only contain valid characters
        [[ "$REF_SYNC_MACHINE" =~ ^[a-zA-Z0-9_-]+$ ]]
    )
}

@test "V3: Remote override works" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        export REF_SYNC_REMOTE="other-remote"
        source "$PROJECT_ROOT/ref-sync"
        load_env

        [[ "$REF_SYNC_REMOTE" == "other-remote" ]]
    )
}

@test "V4: Machine override works" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        export REF_SYNC_MACHINE="my-custom-machine"
        source "$PROJECT_ROOT/ref-sync"
        load_env

        [[ "$REF_SYNC_MACHINE" == "my-custom-machine" ]]
    )
}

@test "V5: --docs without REF_SYNC_DOCS errors" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Run with explicitly empty REF_SYNC_DOCS
    run env -u REF_SYNC_DOCS \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push --docs

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"REF_SYNC_DOCS"* ]]
}

@test "V6: --both without REF_SYNC_DOCS errors" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Run with explicitly empty REF_SYNC_DOCS
    run env -u REF_SYNC_DOCS \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push --both

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"REF_SYNC_DOCS"* ]]
}

@test "V7: REF_SYNC_DOCS correctly splits into dirs" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        export REF_SYNC_DOCS="dir1 dir2 dir3"
        source "$PROJECT_ROOT/ref-sync"
        load_env

        local dirs=()
        while IFS= read -r dir; do
            [[ -n "$dir" ]] && dirs+=("$dir")
        done < <(get_docs_dirs)

        [[ ${#dirs[@]} -eq 3 ]]
        [[ "${dirs[0]}" == "dir1" ]]
        [[ "${dirs[1]}" == "dir2" ]]
        [[ "${dirs[2]}" == "dir3" ]]
    )
}

@test "V8: Empty REF_SYNC_DOCS with --docs errors" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Run with explicitly empty REF_SYNC_DOCS
    run env REF_SYNC_DOCS="" \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push --docs

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"REF_SYNC_DOCS"* ]]
}

@test "V9: Auto-detects single remote" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create a WIP change
    make_change "test.txt" "hello" "Auto-detect test"

    # Push without setting REF_SYNC_REMOTE — should auto-detect "sync" (the only remote)
    run env -u REF_SYNC_REMOTE \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        "$REF_SYNC" push

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]

    # Verify bookmark was created
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count" -eq 1 ]]
}

@test "V10: Errors with multiple remotes when none is origin or upstream" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Add a second remote (neither is origin or upstream)
    git remote add other "$TEST_DIR/remote.git" 2>/dev/null

    make_change "test.txt" "hello" "Multi-remote test"

    # Push without setting REF_SYNC_REMOTE — should error
    run env -u REF_SYNC_REMOTE \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        "$REF_SYNC" push

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"none named 'origin' or 'upstream'"* ]]

    # Clean up
    git remote remove other 2>/dev/null || true
}

@test "V11: Errors with zero remotes" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Remove the only remote
    git remote remove sync 2>/dev/null || true

    make_change "test.txt" "hello" "No-remote test"

    run env -u REF_SYNC_REMOTE \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        "$REF_SYNC" push

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No git remotes"* ]]

    # Re-add so teardown doesn't break
    git remote add sync "$TEST_DIR/remote.git" 2>/dev/null || true
}

@test "V12a: Auto-detects origin among multiple remotes" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Rename sync to origin, add another remote
    git remote rename sync origin 2>/dev/null
    git remote add other "$TEST_DIR/remote.git" 2>/dev/null

    make_change "test.txt" "hello" "Origin fallback test"

    run env -u REF_SYNC_REMOTE \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        "$REF_SYNC" push

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]

    # Clean up
    git remote remove other 2>/dev/null || true
    git remote rename origin sync 2>/dev/null || true
}

@test "V12b: Auto-detects upstream among multiple remotes" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Add upstream remote, keep sync as-is
    git remote add upstream "$TEST_DIR/remote.git" 2>/dev/null

    make_change "test.txt" "hello" "Upstream fallback test"

    run env -u REF_SYNC_REMOTE \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        "$REF_SYNC" push

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]

    # Clean up
    git remote remove upstream 2>/dev/null || true
}

@test "V12c: Errors when both origin and upstream exist" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Rename sync to origin, add upstream
    git remote rename sync origin 2>/dev/null
    git remote add upstream "$TEST_DIR/remote.git" 2>/dev/null

    make_change "test.txt" "hello" "Both remotes test"

    run env -u REF_SYNC_REMOTE \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        "$REF_SYNC" push

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Both 'origin' and 'upstream'"* ]]

    # Clean up
    git remote remove upstream 2>/dev/null || true
    git remote rename origin sync 2>/dev/null || true
}

@test "V13: User auto-detected from jj/git config" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Run ref-sync status (which calls load_env) without REF_SYNC_USER
    # and verify it picks up a user identity
    run env -u REF_SYNC_USER \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" status

    [[ "$status" -eq 0 ]]
    # Should NOT show "(not set)" for User — some email was detected
    [[ "$output" != *"(not set)"* ]]
    [[ "$output" == *"User:"* ]]
}

@test "V14: User override works" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        export REF_SYNC_USER="custom@user.com"
        source "$PROJECT_ROOT/ref-sync"
        load_env

        [[ "$REF_SYNC_USER" == "custom@user.com" ]]
    )
}

@test "V15: User namespaces refs correctly" {
    cd_to_machine "$MACHINE_LAPTOP"

    make_change "test.txt" "hello" "User namespace test"

    run_ref_sync "$MACHINE_LAPTOP" push

    # Verify refs include user in path
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count" -eq 1 ]]

    # Verify old-style path does NOT exist
    local old_count
    old_count=$(count_remote_bookmarks "sync/$MACHINE_LAPTOP/revs/*")
    [[ "$old_count" -eq 0 ]]
}

@test "V16: Different users don't clobber each other" {
    cd_to_machine "$MACHINE_LAPTOP"

    # User A pushes
    make_change "test.txt" "user-a content" "User A change"
    REF_SYNC_USER="alice@example.com" run_ref_sync "$MACHINE_LAPTOP" push

    # User B pushes (same machine, different user)
    cd_to_machine "$MACHINE_DEV1"
    make_change "test.txt" "user-b content" "User B change"
    REF_SYNC_USER="bob@example.com" run_ref_sync "$MACHINE_DEV1" push

    # Both users' refs should exist
    local alice_count bob_count
    alice_count=$(count_remote_bookmarks "sync/alice@example.com/$MACHINE_LAPTOP/revs/*")
    bob_count=$(count_remote_bookmarks "sync/bob@example.com/$MACHINE_DEV1/revs/*")
    [[ "$alice_count" -eq 1 ]]
    [[ "$bob_count" -eq 1 ]]
}

@test "V18: --docs push works in a plain git repo" {
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    # Create doc files
    mkdir -p docs
    echo "hello from plain git" > docs/note.md

    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="plain-git" \
        REF_SYNC_REMOTE="sync" \
        REF_SYNC_DOCS="docs" \
        "$REF_SYNC" push --docs

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]

    # Verify docs bookmark exists on remote
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/plain-git/docs")
    [[ "$count" -eq 1 ]]
}

@test "V19: --docs pull works in a plain git repo" {
    # First push docs from a jj repo
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p docs
    echo "doc from laptop" > docs/note.md
    run_ref_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Now pull into a plain git repo
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="plain-git" \
        REF_SYNC_REMOTE="sync" \
        REF_SYNC_DOCS="docs" \
        "$REF_SYNC" pull --docs

    [[ "$status" -eq 0 ]]
    assert_file_exists "docs/note.md"
    assert_file_equals "docs/note.md" "doc from laptop"
}

@test "V20: status works in a plain git repo" {
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    mkdir -p docs
    echo "hello" > docs/note.md

    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="plain-git" \
        REF_SYNC_REMOTE="sync" \
        REF_SYNC_DOCS="docs" \
        "$REF_SYNC" status

    [[ "$status" -eq 0 ]]
    # Should show docs section
    [[ "$output" == *"Docs"* ]]
    # Should NOT show revisions section (no jj)
    [[ "$output" != *"Revisions"* ]]
}

@test "V21: bare push in plain git repo without REF_SYNC_DOCS errors" {
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    run env -u REF_SYNC_DOCS \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="plain-git" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Nothing to sync"* ]]
}

@test "V21b: --revs in plain git repo errors" {
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="plain-git" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push --revs

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Revision sync requires a jj repository"* ]]
}

@test "V17: Pull only fetches current user's refs" {
    # User A pushes from laptop
    cd_to_machine "$MACHINE_LAPTOP"
    make_change "test.txt" "alice content" "Alice change"
    local alice_change
    alice_change=$(get_current_change_id)
    REF_SYNC_USER="alice@example.com" run_ref_sync "$MACHINE_LAPTOP" push

    # User B pushes from dev-1
    cd_to_machine "$MACHINE_DEV1"
    make_change "test2.txt" "bob content" "Bob change"
    local bob_change
    bob_change=$(get_current_change_id)
    REF_SYNC_USER="bob@example.com" run_ref_sync "$MACHINE_DEV1" push

    # Pull as alice on a third machine — should only get alice's refs
    local machine="dev-2"
    create_jj_repo "$machine" "colocated"
    cd_to_machine "$machine"
    REF_SYNC_USER="alice@example.com" run_ref_sync "$machine" pull

    # Alice's change should be visible
    jj_has_change "$alice_change"

    # Bob's change should NOT be visible
    ! jj_has_change "$bob_change"
}

@test "V22: Push works from a subdirectory (colocated)" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create a change
    make_change "src/main.rs" "fn main() {}" "Initial code"
    jj new >/dev/null 2>&1

    # Run ref-sync from a subdirectory
    mkdir -p src/nested
    cd src/nested

    run_ref_sync "$MACHINE_LAPTOP" push

    # Verify bookmark was pushed
    cd_to_machine "$MACHINE_LAPTOP"
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/*")
    [[ "$count" -gt 0 ]]
}

@test "V23: Doc push works from a subdirectory" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create doc files at repo root
    create_doc_dir "ai/docs" 2

    # Run ref-sync from a subdirectory
    mkdir -p src/nested
    cd src/nested

    run_ref_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Verify docs were pushed
    assert_bookmark_exists_remote "sync/$TEST_USER/$MACHINE_LAPTOP/docs"
}

@test "V24: Push works from a subdirectory (non-colocated)" {
    # Create a non-colocated repo
    local machine="noncoloc"
    create_jj_repo "$machine" "noncolocated"
    cd_to_machine "$machine"

    # Create a change
    make_change "src/main.rs" "fn main() {}" "Initial code"
    jj new >/dev/null 2>&1

    # Run ref-sync from a subdirectory
    mkdir -p src/nested
    cd src/nested

    run_ref_sync "$machine" push

    # Verify bookmark was pushed
    cd_to_machine "$machine"
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/$machine/*")
    [[ "$count" -gt 0 ]]
}

@test "V25: Doc pull works from a subdirectory" {
    # Push docs from laptop at repo root
    cd_to_machine "$MACHINE_LAPTOP"
    create_doc_dir "ai/docs" 2
    run_ref_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Pull on dev-1 from a subdirectory
    cd_to_machine "$MACHINE_DEV1"
    mkdir -p src/nested
    cd src/nested

    run_ref_sync_with_docs "$MACHINE_DEV1" "ai/docs" pull --docs

    # Verify files extracted at repo root, not subdirectory
    cd_to_machine "$MACHINE_DEV1"
    assert_file_exists "ai/docs/doc1.md"
}

@test "V26: --remote without value gives clear error" {
    cd_to_machine "$MACHINE_LAPTOP"

    run run_ref_sync "$MACHINE_LAPTOP" push --remote
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--remote requires a value"* ]]
}

@test "V27: --user without value gives clear error" {
    cd_to_machine "$MACHINE_LAPTOP"

    run run_ref_sync "$MACHINE_LAPTOP" push --user
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--user requires a value"* ]]
}

@test "V28: --machine without value gives clear error" {
    cd_to_machine "$MACHINE_LAPTOP"

    run run_ref_sync "$MACHINE_LAPTOP" push --machine
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--machine requires a value"* ]]
}

@test "V29: --docs with inline dirs overrides env var" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create two sets of doc directories
    mkdir -p ai/docs .claude
    echo "ai doc" > ai/docs/note.md
    echo "claude doc" > .claude/note.md
    mkdir -p other/docs
    echo "other doc" > other/docs/note.md

    # Set REF_SYNC_DOCS to other/docs, but pass ai/docs inline
    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        REF_SYNC_DOCS="other/docs" \
        "$REF_SYNC" push --docs ai/docs

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]

    # Pull on another machine — should only have ai/docs, not other/docs
    cd_to_machine "$MACHINE_DEV1"
    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_DEV1" \
        REF_SYNC_REMOTE="sync" \
        REF_SYNC_DOCS="ai/docs" \
        "$REF_SYNC" pull --docs

    [[ "$status" -eq 0 ]]
    assert_file_exists "ai/docs/note.md"
    assert_file_not_exists "other/docs/note.md"
}

@test "V30: --docs with multiple inline dirs" {
    cd_to_machine "$MACHINE_LAPTOP"

    mkdir -p ai/docs .claude
    echo "ai doc" > ai/docs/note.md
    echo "claude doc" > .claude/note.md

    run env -u REF_SYNC_DOCS \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push --docs ai/docs .claude

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]
}

@test "V31: --docs stops consuming at flags" {
    cd_to_machine "$MACHINE_LAPTOP"

    mkdir -p ai/docs
    echo "doc" > ai/docs/note.md

    # --dry-run should not be consumed as a directory
    run env -u REF_SYNC_DOCS \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push --docs ai/docs --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"dry-run"* ]]
}

@test "V32: --docs with no inline args falls back to env var" {
    cd_to_machine "$MACHINE_LAPTOP"

    mkdir -p ai/docs
    echo "doc" > ai/docs/note.md

    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        REF_SYNC_DOCS="ai/docs" \
        "$REF_SYNC" push --docs

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]
}

@test "V33: --docs with no inline args and no env var errors" {
    cd_to_machine "$MACHINE_LAPTOP"

    run env -u REF_SYNC_DOCS \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push --docs

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No doc directories specified"* ]]
    [[ "$output" == *"ref-sync push ./ai-docs .claude"* ]]
}

@test "V34: Doc sync skips git-tracked files" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create .claude directory with a tracked file
    mkdir -p .claude
    echo '{"key": "laptop-value"}' > .claude/settings.json
    echo "*.local.json" > .claude/.gitignore

    # Commit both settings.json and .gitignore so they're tracked
    jj file track .claude/settings.json .claude/.gitignore >/dev/null 2>&1
    jj commit -m "Add settings.json and .gitignore" >/dev/null 2>&1

    # Add a gitignored (untracked) file in the same directory
    echo "local notes" > .claude/settings.local.json

    # Push docs — should only include settings.local.json (not tracked files)
    run_ref_sync_with_docs "$MACHINE_LAPTOP" ".claude" push --docs

    # Pull on another machine that has its own tracked settings.json
    cd_to_machine "$MACHINE_DEV1"
    mkdir -p .claude
    echo '{"key": "dev1-value"}' > .claude/settings.json
    echo "*.local.json" > .claude/.gitignore
    jj file track .claude/settings.json .claude/.gitignore >/dev/null 2>&1
    jj commit -m "Add settings.json on dev1" >/dev/null 2>&1

    # Add a local untracked file that should be cleaned up by pull
    echo "old local" > .claude/old-untracked.md

    run_ref_sync_with_docs "$MACHINE_DEV1" ".claude" pull --docs

    # Tracked file should still have dev1's content (not overwritten)
    assert_file_equals ".claude/settings.json" '{"key": "dev1-value"}'

    # Tracked .gitignore should also be preserved
    assert_file_exists ".claude/.gitignore"

    # Untracked file from laptop should have been pulled
    assert_file_exists ".claude/settings.local.json"
    assert_file_equals ".claude/settings.local.json" "local notes"

    # Pre-existing untracked file not in snapshot should be deleted
    assert_file_not_exists ".claude/old-untracked.md"
}

@test "V36: Positional dirs in plain git repo triggers docs mode" {
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    mkdir -p docs
    echo "positional doc" > docs/note.md

    run env -u REF_SYNC_DOCS \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="plain-git" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push docs

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]

    # Verify docs bookmark exists on remote
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/plain-git/docs")
    [[ "$count" -eq 1 ]]
}

@test "V37: Multiple positional dirs" {
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    mkdir -p ai/docs .claude
    echo "ai doc" > ai/docs/note.md
    echo "claude doc" > .claude/note.md

    run env -u REF_SYNC_DOCS \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="plain-git" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push ai/docs .claude

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]
}

@test "V38: Positional dirs stop at flags" {
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    mkdir -p ai/docs
    echo "doc" > ai/docs/note.md

    # --dry-run should not be consumed as a directory
    run env -u REF_SYNC_DOCS \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="plain-git" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push ai/docs --dry-run

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"dry-run"* ]]
}

@test "V39: Positional dirs on status command errors" {
    cd_to_machine "$MACHINE_LAPTOP"

    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" status ai/docs

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unexpected arguments"* ]]
}

@test "V40: Positional dirs with no command errors" {
    cd_to_machine "$MACHINE_LAPTOP"

    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_LAPTOP" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" ai/docs

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Unknown option"* ]]
}

@test "V41: Positional dirs override REF_SYNC_DOCS env var" {
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    mkdir -p ai/docs other/docs
    echo "ai doc" > ai/docs/note.md
    echo "other doc" > other/docs/note.md

    # Set REF_SYNC_DOCS to other/docs but pass ai/docs as positional arg
    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="plain-git" \
        REF_SYNC_REMOTE="sync" \
        REF_SYNC_DOCS="other/docs" \
        "$REF_SYNC" push ai/docs

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]

    # Pull on another machine — should only have ai/docs
    cd_to_machine "$MACHINE_DEV1"
    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_DEV1" \
        REF_SYNC_REMOTE="sync" \
        REF_SYNC_DOCS="ai/docs" \
        "$REF_SYNC" pull --docs

    [[ "$status" -eq 0 ]]
    assert_file_exists "ai/docs/note.md"
    assert_file_not_exists "other/docs/note.md"
}

@test "V42: Dot-slash prefixed dirs work the same as bare dirs" {
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    mkdir -p ai-docs
    echo "doc content" > ai-docs/note.md

    # Push with ./ prefix
    run env -u REF_SYNC_DOCS \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="plain-git" \
        REF_SYNC_REMOTE="sync" \
        "$REF_SYNC" push ./ai-docs

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]

    # Pull on another machine (without ./ prefix) — should still get the files
    cd_to_machine "$MACHINE_DEV1"
    run env \
        REF_SYNC_USER="$TEST_USER" \
        REF_SYNC_MACHINE="$MACHINE_DEV1" \
        REF_SYNC_REMOTE="sync" \
        REF_SYNC_DOCS="ai-docs" \
        "$REF_SYNC" pull --docs

    [[ "$status" -eq 0 ]]
    assert_file_exists "ai-docs/note.md"
    assert_file_equals "ai-docs/note.md" "doc content"
}

@test "V35: Doc sync skips nested tracked files" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create nested structure with tracked files at multiple levels
    mkdir -p .claude/config/profiles
    echo '{"global": true}' > .claude/config/settings.json
    echo '{"profile": "default"}' > .claude/config/profiles/default.json
    echo "ignored-pattern" > .claude/.gitignore

    # Commit the tracked files
    jj file track .claude/config/settings.json .claude/config/profiles/default.json .claude/.gitignore >/dev/null 2>&1
    jj commit -m "Add nested tracked files" >/dev/null 2>&1

    # Add gitignored untracked files at various nesting levels
    echo "*.local.*" >> .claude/.gitignore
    echo "local config" > .claude/config/settings.local.json
    echo "local profile" > .claude/config/profiles/custom.local.json

    # Push docs
    run_ref_sync_with_docs "$MACHINE_LAPTOP" ".claude" push --docs

    # Pull on another machine with its own tracked files
    cd_to_machine "$MACHINE_DEV1"
    mkdir -p .claude/config/profiles
    echo '{"global": false}' > .claude/config/settings.json
    echo '{"profile": "dev1"}' > .claude/config/profiles/default.json
    echo "ignored-pattern" > .claude/.gitignore
    jj file track .claude/config/settings.json .claude/config/profiles/default.json .claude/.gitignore >/dev/null 2>&1
    jj commit -m "Add nested tracked files on dev1" >/dev/null 2>&1

    run_ref_sync_with_docs "$MACHINE_DEV1" ".claude" pull --docs

    # Nested tracked files should keep dev1's content
    assert_file_equals ".claude/config/settings.json" '{"global": false}'
    assert_file_equals ".claude/config/profiles/default.json" '{"profile": "dev1"}'

    # Untracked files from laptop should have been pulled
    assert_file_exists ".claude/config/settings.local.json"
    assert_file_equals ".claude/config/settings.local.json" "local config"
    assert_file_exists ".claude/config/profiles/custom.local.json"
    assert_file_equals ".claude/config/profiles/custom.local.json" "local profile"
}
