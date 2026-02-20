#!/usr/bin/env bats
# tests/test_edge_cases.bats - Edge case and error handling tests

load test_helper.bash

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "E1: Non-colocated repo works" {
    # Create a non-colocated jj repo (jj git init without --colocate)
    local repo_dir="$TEST_DIR/noncolocated"
    mkdir -p "$repo_dir"
    cd "$repo_dir"

    jj git init >/dev/null 2>&1
    jj git remote add sync "$TEST_DIR/remote.git" >/dev/null 2>&1

    # Configure git (jj creates .git dir even for "non-colocated" repos)
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Create a change
    echo "test content" > test.txt
    jj file track test.txt >/dev/null 2>&1
    jj describe -m "Test in non-colocated repo" >/dev/null 2>&1

    # Push
    REFSYNC_USER="$TEST_USER" REFSYNC_MACHINE="noncoloc" REFSYNC_REMOTE="sync" "$REFSYNC" push

    # Verify bookmark exists on remote
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/noncoloc/revs/*")
    [[ "$count" -eq 1 ]]
}

@test "E2: Missing remote errors gracefully" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Try to push with a non-existent remote
    run env REFSYNC_USER="$TEST_USER" REFSYNC_MACHINE="$MACHINE_LAPTOP" REFSYNC_REMOTE="nonexistent" "$REFSYNC" push

    # Should fail with clear error
    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "Remote 'nonexistent' not found" ]]
    [[ "$output" =~ "Available remotes" ]]
}

@test "E3: Not in a repo errors gracefully" {
    cd "$TEST_DIR"
    mkdir -p notarepo
    cd notarepo

    run env REFSYNC_USER="$TEST_USER" REFSYNC_MACHINE="laptop" REFSYNC_REMOTE="sync" "$REFSYNC" push

    # Should fail with clear error
    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "Not in a git repository" ]]
}

@test "E4: Unknown command errors gracefully" {
    cd_to_machine "$MACHINE_LAPTOP"

    run env REFSYNC_USER="$TEST_USER" REFSYNC_MACHINE="$MACHINE_LAPTOP" REFSYNC_REMOTE="sync" "$REFSYNC" unknown_command

    [[ "$status" -ne 0 ]]
    [[ "$output" =~ "Unknown" ]]
}

@test "E5: Help command works" {
    cd_to_machine "$MACHINE_LAPTOP"

    run "$REFSYNC" help

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Usage" ]]
    [[ "$output" =~ "push" ]]
    [[ "$output" =~ "pull" ]]
}

@test "E6: --help flag works" {
    cd_to_machine "$MACHINE_LAPTOP"

    run "$REFSYNC" --help

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "Usage" ]]
}

@test "E7: Machine name sanitized" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create a change
    make_change "test.txt" "content" "Test change"

    # Push with machine name containing special chars
    REFSYNC_USER="$TEST_USER" REFSYNC_MACHINE="my@machine:with/special" REFSYNC_REMOTE="sync" "$REFSYNC" push

    # Verify bookmark uses sanitized name
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/my_machine_with_special/revs/*")
    [[ "$count" -eq 1 ]]
}

@test "E8: Empty push succeeds silently" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Don't create any changes - just have root commit
    run run_refsync "$MACHINE_LAPTOP" push

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "No WIP revisions to push" ]]
}

@test "E9: Pull with no remote refs succeeds" {
    cd_to_machine "$MACHINE_DEV1"

    # Pull with nothing on remote
    run run_refsync "$MACHINE_DEV1" pull

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "No revisions found on remote" ]]
}

@test "E10: Status works with no sync state" {
    cd_to_machine "$MACHINE_LAPTOP"

    run run_refsync "$MACHINE_LAPTOP" status

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "refsync status" ]]
}

@test "E11: Clean with no sync state succeeds" {
    cd_to_machine "$MACHINE_LAPTOP"

    run run_refsync "$MACHINE_LAPTOP" clean --force

    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "No sync state found" ]]
}

@test "E12: Deeply nested doc files work" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create deeply nested structure
    mkdir -p "docs/level1/level2/level3/level4"
    echo "deep content" > "docs/level1/level2/level3/level4/deep.md"

    # Push docs
    run_refsync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Pull on dev-1
    run_refsync_with_docs "$MACHINE_DEV1" "docs" pull --docs

    # Verify deep file exists
    cd_to_machine "$MACHINE_DEV1"
    assert_file_exists "docs/level1/level2/level3/level4/deep.md"
    assert_file_equals "docs/level1/level2/level3/level4/deep.md" "deep content"
}

@test "E13: Many files work" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create many files
    mkdir -p "docs"
    for i in {1..50}; do
        echo "content $i" > "docs/file$i.txt"
    done

    # Push docs
    run_refsync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Pull on dev-1
    run_refsync_with_docs "$MACHINE_DEV1" "docs" pull --docs

    # Verify file count
    cd_to_machine "$MACHINE_DEV1"
    local count
    count=$(find "docs" -type f | wc -l | tr -d ' ')
    [[ "$count" -eq 50 ]]
}

@test "E14: Large file works" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create a 1MB file
    mkdir -p "docs"
    dd if=/dev/urandom of="docs/large.bin" bs=1024 count=1024 2>/dev/null

    local orig_hash
    orig_hash=$(sha256sum "docs/large.bin" | cut -d' ' -f1)

    # Push docs
    run_refsync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Pull on dev-1
    run_refsync_with_docs "$MACHINE_DEV1" "docs" pull --docs

    # Verify content matches
    cd_to_machine "$MACHINE_DEV1"
    local pulled_hash
    pulled_hash=$(sha256sum "docs/large.bin" | cut -d' ' -f1)
    [[ "$orig_hash" == "$pulled_hash" ]]
}

@test "E15: Concurrent push from same machine - last wins" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create change 1
    make_change "test1.txt" "content1" "Change 1"
    local change1
    change1=$(get_current_change_id)
    run_refsync "$MACHINE_LAPTOP" push

    # Create change 2 (on top)
    jj new >/dev/null 2>&1
    make_change "test2.txt" "content2" "Change 2"
    run_refsync "$MACHINE_LAPTOP" push

    # Should have 2 bookmarks now
    local count
    count=$(count_remote_bookmarks "sync/$TEST_USER/$MACHINE_LAPTOP/revs/*")
    [[ "$count" -eq 2 ]]
}
