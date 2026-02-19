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
        unset JJ_SYNC_REMOTE
        unset JJ_SYNC_MACHINE
        unset JJ_SYNC_DOCS
        source "$PROJECT_ROOT/jj-sync"
        load_env

        # Remote should be empty (auto-detected later)
        [[ -z "$JJ_SYNC_REMOTE" ]]
        [[ -n "$JJ_SYNC_MACHINE" ]]
        [[ "$JJ_SYNC_GC_REVS_DAYS" == "7" ]]
        [[ "$JJ_SYNC_GC_DOCS_MAX_CHAIN" == "50" ]]
    )
}

@test "V2: Machine name defaults to hostname" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        unset JJ_SYNC_MACHINE
        source "$PROJECT_ROOT/jj-sync"
        load_env

        # Machine name should be non-empty (derived from hostname)
        [[ -n "$JJ_SYNC_MACHINE" ]]
        # Should only contain valid characters
        [[ "$JJ_SYNC_MACHINE" =~ ^[a-zA-Z0-9_-]+$ ]]
    )
}

@test "V3: Remote override works" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        export JJ_SYNC_REMOTE="other-remote"
        source "$PROJECT_ROOT/jj-sync"
        load_env

        [[ "$JJ_SYNC_REMOTE" == "other-remote" ]]
    )
}

@test "V4: Machine override works" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        export JJ_SYNC_MACHINE="my-custom-machine"
        source "$PROJECT_ROOT/jj-sync"
        load_env

        [[ "$JJ_SYNC_MACHINE" == "my-custom-machine" ]]
    )
}

@test "V5: --docs without JJ_SYNC_DOCS errors" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Run with explicitly empty JJ_SYNC_DOCS
    run env -u JJ_SYNC_DOCS \
        JJ_SYNC_USER="$TEST_USER" \
        JJ_SYNC_MACHINE="$MACHINE_LAPTOP" \
        JJ_SYNC_REMOTE="sync" \
        "$JJ_SYNC" push --docs

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"JJ_SYNC_DOCS"* ]]
}

@test "V6: --both without JJ_SYNC_DOCS errors" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Run with explicitly empty JJ_SYNC_DOCS
    run env -u JJ_SYNC_DOCS \
        JJ_SYNC_USER="$TEST_USER" \
        JJ_SYNC_MACHINE="$MACHINE_LAPTOP" \
        JJ_SYNC_REMOTE="sync" \
        "$JJ_SYNC" push --both

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"JJ_SYNC_DOCS"* ]]
}

@test "V7: JJ_SYNC_DOCS correctly splits into dirs" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        export JJ_SYNC_DOCS="dir1 dir2 dir3"
        source "$PROJECT_ROOT/jj-sync"
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

@test "V8: Empty JJ_SYNC_DOCS with --docs errors" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Run with explicitly empty JJ_SYNC_DOCS
    run env JJ_SYNC_DOCS="" \
        JJ_SYNC_USER="$TEST_USER" \
        JJ_SYNC_MACHINE="$MACHINE_LAPTOP" \
        JJ_SYNC_REMOTE="sync" \
        "$JJ_SYNC" push --docs

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"JJ_SYNC_DOCS"* ]]
}

@test "V9: Auto-detects single remote" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create a WIP change
    make_change "test.txt" "hello" "Auto-detect test"

    # Push without setting JJ_SYNC_REMOTE — should auto-detect "sync" (the only remote)
    run env -u JJ_SYNC_REMOTE \
        JJ_SYNC_USER="$TEST_USER" \
        JJ_SYNC_MACHINE="$MACHINE_LAPTOP" \
        "$JJ_SYNC" push

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Pushed"* ]]

    # Verify bookmark was created
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count" -eq 1 ]]
}

@test "V10: Errors with multiple remotes" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Add a second remote
    git remote add other "$TEST_DIR/remote.git" 2>/dev/null

    make_change "test.txt" "hello" "Multi-remote test"

    # Push without setting JJ_SYNC_REMOTE — should error
    run env -u JJ_SYNC_REMOTE \
        JJ_SYNC_USER="$TEST_USER" \
        JJ_SYNC_MACHINE="$MACHINE_LAPTOP" \
        "$JJ_SYNC" push

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Multiple git remotes"* ]]

    # Clean up
    git remote remove other 2>/dev/null || true
}

@test "V11: Errors with zero remotes" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Remove the only remote
    git remote remove sync 2>/dev/null || true

    make_change "test.txt" "hello" "No-remote test"

    run env -u JJ_SYNC_REMOTE \
        JJ_SYNC_USER="$TEST_USER" \
        JJ_SYNC_MACHINE="$MACHINE_LAPTOP" \
        "$JJ_SYNC" push

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No git remotes"* ]]

    # Re-add so teardown doesn't break
    git remote add sync "$TEST_DIR/remote.git" 2>/dev/null || true
}

@test "V13: User auto-detected from jj/git config" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Run jj-sync status (which calls load_env) without JJ_SYNC_USER
    # and verify it picks up a user identity
    run env -u JJ_SYNC_USER \
        JJ_SYNC_MACHINE="$MACHINE_LAPTOP" \
        JJ_SYNC_REMOTE="sync" \
        "$JJ_SYNC" status

    [[ "$status" -eq 0 ]]
    # Should NOT show "(not set)" for User — some email was detected
    [[ "$output" != *"(not set)"* ]]
    [[ "$output" == *"User:"* ]]
}

@test "V14: User override works" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        export JJ_SYNC_USER="custom@user.com"
        source "$PROJECT_ROOT/jj-sync"
        load_env

        [[ "$JJ_SYNC_USER" == "custom@user.com" ]]
    )
}

@test "V15: User namespaces refs correctly" {
    cd_to_machine "$MACHINE_LAPTOP"

    make_change "test.txt" "hello" "User namespace test"

    run_jj_sync "$MACHINE_LAPTOP" push

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
    JJ_SYNC_USER="alice@example.com" run_jj_sync "$MACHINE_LAPTOP" push

    # User B pushes (same machine, different user)
    cd_to_machine "$MACHINE_DEV1"
    make_change "test.txt" "user-b content" "User B change"
    JJ_SYNC_USER="bob@example.com" run_jj_sync "$MACHINE_DEV1" push

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
        JJ_SYNC_USER="$TEST_USER" \
        JJ_SYNC_MACHINE="plain-git" \
        JJ_SYNC_REMOTE="sync" \
        JJ_SYNC_DOCS="docs" \
        "$JJ_SYNC" push --docs

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
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Now pull into a plain git repo
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    run env \
        JJ_SYNC_USER="$TEST_USER" \
        JJ_SYNC_MACHINE="plain-git" \
        JJ_SYNC_REMOTE="sync" \
        JJ_SYNC_DOCS="docs" \
        "$JJ_SYNC" pull --docs

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
        JJ_SYNC_USER="$TEST_USER" \
        JJ_SYNC_MACHINE="plain-git" \
        JJ_SYNC_REMOTE="sync" \
        JJ_SYNC_DOCS="docs" \
        "$JJ_SYNC" status

    [[ "$status" -eq 0 ]]
    # Should show docs section
    [[ "$output" == *"Docs"* ]]
    # Should NOT show revisions section (no jj)
    [[ "$output" != *"Revisions"* ]]
}

@test "V21: revs mode errors in a plain git repo" {
    create_plain_git_repo "plain-git"
    cd_to_machine "plain-git"

    run env \
        JJ_SYNC_USER="$TEST_USER" \
        JJ_SYNC_MACHINE="plain-git" \
        JJ_SYNC_REMOTE="sync" \
        "$JJ_SYNC" push

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"Not in a jj repository"* ]]
}

@test "V17: Pull only fetches current user's refs" {
    # User A pushes from laptop
    cd_to_machine "$MACHINE_LAPTOP"
    make_change "test.txt" "alice content" "Alice change"
    local alice_change
    alice_change=$(get_current_change_id)
    JJ_SYNC_USER="alice@example.com" run_jj_sync "$MACHINE_LAPTOP" push

    # User B pushes from dev-1
    cd_to_machine "$MACHINE_DEV1"
    make_change "test2.txt" "bob content" "Bob change"
    local bob_change
    bob_change=$(get_current_change_id)
    JJ_SYNC_USER="bob@example.com" run_jj_sync "$MACHINE_DEV1" push

    # Pull as alice on a third machine — should only get alice's refs
    local machine="dev-2"
    create_jj_repo "$machine" "colocated"
    cd_to_machine "$machine"
    JJ_SYNC_USER="alice@example.com" run_jj_sync "$machine" pull

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

    # Run jj-sync from a subdirectory
    mkdir -p src/nested
    cd src/nested

    run_jj_sync "$MACHINE_LAPTOP" push

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

    # Run jj-sync from a subdirectory
    mkdir -p src/nested
    cd src/nested

    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

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

    # Run jj-sync from a subdirectory
    mkdir -p src/nested
    cd src/nested

    run_jj_sync "$machine" push

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
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Pull on dev-1 from a subdirectory
    cd_to_machine "$MACHINE_DEV1"
    mkdir -p src/nested
    cd src/nested

    run_jj_sync_with_docs "$MACHINE_DEV1" "ai/docs" pull --docs

    # Verify files extracted at repo root, not subdirectory
    cd_to_machine "$MACHINE_DEV1"
    assert_file_exists "ai/docs/doc1.md"
}

@test "V26: --remote without value gives clear error" {
    cd_to_machine "$MACHINE_LAPTOP"

    run run_jj_sync "$MACHINE_LAPTOP" push --remote
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--remote requires a value"* ]]
}

@test "V27: --user without value gives clear error" {
    cd_to_machine "$MACHINE_LAPTOP"

    run run_jj_sync "$MACHINE_LAPTOP" push --user
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--user requires a value"* ]]
}

@test "V28: --machine without value gives clear error" {
    cd_to_machine "$MACHINE_LAPTOP"

    run run_jj_sync "$MACHINE_LAPTOP" push --machine
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"--machine requires a value"* ]]
}
