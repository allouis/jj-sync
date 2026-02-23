#!/usr/bin/env bats
# tests/test_revisions.bats - Revision sync tests

load test_helper.bash

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "R1: Push creates bookmarks on remote" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create a WIP change
    make_change "test.txt" "hello world" "Test change"

    # Push
    run_ref_sync "$MACHINE_LAPTOP" push

    # Verify bookmark exists on remote
    local bookmark_count
    bookmark_count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$bookmark_count" -eq 1 ]]
}

@test "R2: Push cleans local bookmarks" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create a WIP change
    make_change "test.txt" "hello world" "Test change"

    # Push
    run_ref_sync "$MACHINE_LAPTOP" push

    # Verify no sync bookmarks exist locally
    cd_to_machine "$MACHINE_LAPTOP"
    local local_count
    local_count=$(git branch --list "sync/*" 2>/dev/null | wc -l | tr -d ' ')
    [[ "$local_count" -eq 0 ]]
}

@test "R3: Pull receives changes" {
    # Create and push from laptop
    cd_to_machine "$MACHINE_LAPTOP"
    make_change "test.txt" "hello from laptop" "Laptop change"
    local change_id
    change_id=$(get_current_change_id)
    run_ref_sync "$MACHINE_LAPTOP" push

    # Pull on dev-1
    run_ref_sync "$MACHINE_DEV1" pull

    # Verify dev-1 can see the change
    cd_to_machine "$MACHINE_DEV1"
    jj_has_change "$change_id"
}

@test "R4: Pull leaves remote intact" {
    # Create and push from laptop
    cd_to_machine "$MACHINE_LAPTOP"
    make_change "test.txt" "hello from laptop" "Laptop change"
    run_ref_sync "$MACHINE_LAPTOP" push

    # Pull on dev-1
    run_ref_sync "$MACHINE_DEV1" pull

    # Verify bookmarks still exist on remote (for other machines to pull)
    local bookmark_count
    bookmark_count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$bookmark_count" -eq 1 ]]
}

@test "R6: Amended change updates bookmark" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create and push a change
    make_change "test.txt" "version 1" "Original"
    local change_id
    change_id=$(get_current_change_id)
    run_ref_sync "$MACHINE_LAPTOP" push

    # Record the commit SHA on remote
    local sha_before
    sha_before=$(git ls-remote "$TEST_DIR/remote.git" "refs/ref-sync/sync/$TEST_USER/$MACHINE_LAPTOP/revs/$change_id" | cut -f1)
    [[ -n "$sha_before" ]]

    # Amend the change (new content, same change_id)
    echo "version 2" > test.txt

    # Push again
    run_ref_sync "$MACHINE_LAPTOP" push

    # Bookmark should point to a different commit now
    local sha_after
    sha_after=$(git ls-remote "$TEST_DIR/remote.git" "refs/ref-sync/sync/$TEST_USER/$MACHINE_LAPTOP/revs/$change_id" | cut -f1)
    [[ -n "$sha_after" ]]
    [[ "$sha_before" != "$sha_after" ]]
}

@test "R8: --dry-run doesn't modify state" {
    cd_to_machine "$MACHINE_LAPTOP"

    make_change "test.txt" "hello" "Dry run test"

    # Push with --dry-run
    run run_ref_sync "$MACHINE_LAPTOP" push --dry-run
    [[ "$status" -eq 0 ]]

    # No bookmarks should exist on remote
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count" -eq 0 ]]
}

@test "R9: Immutable changes excluded from push" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Set up trunk: add origin remote and push main there
    git remote add origin "$TEST_DIR/remote.git" 2>/dev/null
    make_change "test.txt" "trunk content" "Trunk commit"
    jj bookmark set main >/dev/null 2>&1
    jj git push --remote origin --bookmark main --allow-new >/dev/null 2>&1

    # Create a second WIP change on top (should be synced)
    jj new >/dev/null 2>&1
    make_change "test2.txt" "wip content" "WIP change"

    run_ref_sync "$MACHINE_LAPTOP" push

    # Only the WIP change should be pushed (trunk commit is immutable)
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count" -eq 1 ]]

    # Clean up extra remote
    git remote remove origin 2>/dev/null || true
}

@test "R10: mine() filter excludes other authors" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create a change as a different author
    jj config set --repo user.email "other@example.com" >/dev/null 2>&1
    jj config set --repo user.name "Other User" >/dev/null 2>&1
    jj new >/dev/null 2>&1
    echo "other content" > other.txt
    jj file track other.txt >/dev/null 2>&1
    jj describe -m "Other's change" >/dev/null 2>&1

    # Restore original author and create our change
    jj config set --repo user.email "test@example.com" >/dev/null 2>&1
    jj config set --repo user.name "Test User" >/dev/null 2>&1
    jj new >/dev/null 2>&1
    make_change "mine.txt" "my content" "My change"

    run_ref_sync "$MACHINE_LAPTOP" push

    # Only our change should be pushed (other author excluded by mine())
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count" -eq 1 ]]
}

@test "R11: --both syncs revisions and docs" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create a WIP change
    make_change "test.txt" "hello" "Both test"

    # Create doc files
    mkdir -p docs
    echo "documentation" > docs/note.md

    # Push with --both
    REF_SYNC_DOCS="docs" run_ref_sync "$MACHINE_LAPTOP" push --both

    # Verify revisions were pushed
    local rev_count
    rev_count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$rev_count" -eq 1 ]]

    # Verify docs were pushed
    local doc_count
    doc_count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/docs")
    [[ "$doc_count" -eq 1 ]]
}

@test "R5: Push removes stale bookmarks for abandoned changes" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create two changes
    make_change "test1.txt" "first change" "Change to abandon"
    local abandon_change
    abandon_change=$(get_current_change_id)
    jj new >/dev/null 2>&1
    make_change "test2.txt" "second change" "Change to keep"
    jj new >/dev/null 2>&1

    # Push both
    run_ref_sync "$MACHINE_LAPTOP" push

    # Should have 2 bookmarks
    local count_before
    count_before=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count_before" -eq 2 ]]

    # Abandon one change
    jj abandon "$abandon_change" >/dev/null 2>&1

    # Push again — stale bookmark for abandoned change should be removed
    run_ref_sync "$MACHINE_LAPTOP" push

    # Should now have 1 bookmark (the kept change)
    local count_after
    count_after=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count_after" -eq 1 ]]
}
