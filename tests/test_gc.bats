#!/usr/bin/env bats
# tests/test_gc.bats - Garbage collection tests

load test_helper.bash

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "G1: Old rev bookmarks cleaned" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create and push a change
    make_change "test.txt" "content" "Test change"
    run_jj_sync "$MACHINE_LAPTOP" push

    # Verify bookmark exists
    local count_before
    count_before=$(count_remote_bookmarks "sync/$MACHINE_LAPTOP/revs/*")
    [[ "$count_before" -eq 1 ]]

    # Run GC with 0-day threshold (should delete everything)
    JJ_SYNC_GC_REVS_DAYS=0 run_jj_sync "$MACHINE_LAPTOP" gc

    # Verify bookmark is gone
    local count_after
    count_after=$(count_remote_bookmarks "sync/$MACHINE_LAPTOP/revs/*")
    [[ "$count_after" -eq 0 ]]
}

@test "G2: Recent rev bookmarks kept" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create and push a change
    make_change "test.txt" "content" "Test change"
    run_jj_sync "$MACHINE_LAPTOP" push

    # Verify bookmark exists
    local count_before
    count_before=$(count_remote_bookmarks "sync/$MACHINE_LAPTOP/revs/*")
    [[ "$count_before" -eq 1 ]]

    # Run GC with 30-day threshold (should keep recent)
    JJ_SYNC_GC_REVS_DAYS=30 run_jj_sync "$MACHINE_LAPTOP" gc

    # Verify bookmark still exists
    local count_after
    count_after=$(count_remote_bookmarks "sync/$MACHINE_LAPTOP/revs/*")
    [[ "$count_after" -eq 1 ]]
}

@test "G3: Doc chain squashed when exceeding threshold" {
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "ai/docs"

    # Create many doc pushes to build up chain
    for i in {1..5}; do
        echo "version $i" > "ai/docs/doc.md"
        run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs
    done

    # Get chain length before
    git fetch "$TEST_DIR/remote.git" "refs/jj-sync/sync/$MACHINE_LAPTOP/docs" 2>/dev/null
    local commit
    commit=$(git ls-remote "$TEST_DIR/remote.git" "refs/jj-sync/sync/$MACHINE_LAPTOP/docs" | cut -f1)
    local chain_before
    chain_before=$(git rev-list --count "$commit" 2>/dev/null)
    [[ "$chain_before" -eq 5 ]]

    # Run GC with threshold of 3 (should squash)
    JJ_SYNC_GC_DOCS_MAX_CHAIN=3 run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" gc

    # Get chain length after
    git fetch "$TEST_DIR/remote.git" "refs/jj-sync/sync/$MACHINE_LAPTOP/docs" 2>/dev/null
    commit=$(git ls-remote "$TEST_DIR/remote.git" "refs/jj-sync/sync/$MACHINE_LAPTOP/docs" | cut -f1)
    local chain_after
    chain_after=$(git rev-list --count "$commit" 2>/dev/null)
    [[ "$chain_after" -eq 1 ]]
}

@test "G4: Squashed chain preserves content" {
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "ai/docs"

    # Create several versions, keeping track of final content
    echo "final content" > "ai/docs/doc.md"
    for i in {1..5}; do
        echo "version $i" >> "ai/docs/doc.md"
        run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs
    done

    # Save final content
    local final_content
    final_content=$(cat "ai/docs/doc.md")

    # Run GC with low threshold
    JJ_SYNC_GC_DOCS_MAX_CHAIN=2 run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" gc

    # Pull on dev-1 and verify content
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "ai/docs" pull --docs

    assert_file_equals "ai/docs/doc.md" "$final_content"
}

@test "G5: GC is idempotent" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create and push a change
    make_change "test.txt" "content" "Test change"
    run_jj_sync "$MACHINE_LAPTOP" push

    # Run GC with high threshold (keep everything)
    run run_jj_sync "$MACHINE_LAPTOP" gc
    local output1="$output"

    # Run GC again
    run run_jj_sync "$MACHINE_LAPTOP" gc
    local output2="$output"

    # Both should succeed
    [[ "$status" -eq 0 ]]
}
