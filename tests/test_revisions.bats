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
    run_jj_sync "$MACHINE_LAPTOP" push

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
    run_jj_sync "$MACHINE_LAPTOP" push

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
    run_jj_sync "$MACHINE_LAPTOP" push

    # Pull on dev-1
    run_jj_sync "$MACHINE_DEV1" pull

    # Verify dev-1 can see the change
    cd_to_machine "$MACHINE_DEV1"
    jj_has_change "$change_id"
}

@test "R4: Pull leaves remote intact" {
    # Create and push from laptop
    cd_to_machine "$MACHINE_LAPTOP"
    make_change "test.txt" "hello from laptop" "Laptop change"
    run_jj_sync "$MACHINE_LAPTOP" push

    # Pull on dev-1
    run_jj_sync "$MACHINE_DEV1" pull

    # Verify bookmarks still exist on remote (for other machines to pull)
    local bookmark_count
    bookmark_count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$bookmark_count" -eq 1 ]]
}

@test "R7: Empty repo push - no error" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Push with no WIP changes (just the root commit)
    run run_jj_sync "$MACHINE_LAPTOP" push

    # Should succeed
    [[ "$status" -eq 0 ]]
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
    run_jj_sync "$MACHINE_LAPTOP" push

    # Should have 2 bookmarks
    local count_before
    count_before=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count_before" -eq 2 ]]

    # Abandon one change
    jj abandon "$abandon_change" >/dev/null 2>&1

    # Push again — stale bookmark for abandoned change should be removed
    run_jj_sync "$MACHINE_LAPTOP" push

    # Should now have 1 bookmark (the kept change)
    local count_after
    count_after=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count_after" -eq 1 ]]
}
