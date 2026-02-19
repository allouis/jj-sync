#!/usr/bin/env bats
# tests/test_docs_merge.bats - Doc merge tests for parallel writes

load test_helper.bash

setup() {
    setup_test_env "$MACHINE_LAPTOP" "$MACHINE_DEV1" "$MACHINE_DEV2"
}

teardown() {
    teardown_test_env
}

@test "M1: Non-overlapping edits merge cleanly" {
    # Laptop creates file1.md
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "docs"
    echo "laptop content" > "docs/file1.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Dev-1 creates file2.md (starting fresh, then adding)
    cd_to_machine "$MACHINE_DEV1"
    mkdir -p "docs"
    echo "dev1 content" > "docs/file2.md"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    # Laptop pulls - should have both files
    cd_to_machine "$MACHINE_LAPTOP"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" pull --docs

    assert_file_exists "docs/file1.md"
    assert_file_exists "docs/file2.md"
    assert_file_equals "docs/file1.md" "laptop content"
    assert_file_equals "docs/file2.md" "dev1 content"
}

@test "M2: Same file from multiple machines - last wins" {
    # When the same file exists on multiple machines without shared history,
    # union merge takes the later tree's version (tree2 wins).
    # This is acceptable - users can resolve by pulling before pushing.

    # Laptop creates initial file
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "docs"
    echo "laptop version" > "docs/shared.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Dev-1 creates same file independently (doesn't pull first)
    cd_to_machine "$MACHINE_DEV1"
    mkdir -p "docs"
    echo "dev1 version" > "docs/shared.md"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    # Laptop pulls - gets merged result
    cd_to_machine "$MACHINE_LAPTOP"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" pull --docs

    # The file should exist (union merge works)
    assert_file_exists "docs/shared.md"

    # One version wins (depends on merge order, either is acceptable)
    local content
    content=$(cat "docs/shared.md")
    [[ "$content" == "laptop version" ]] || [[ "$content" == "dev1 version" ]]
}

@test "M3: Same file with shared history - three-way merge with conflicts" {
    # When machines share history (via pull-then-push), three-way merge can detect conflicts

    # Laptop creates initial file
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "docs"
    echo "original line" > "docs/conflict.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Force a different timestamp so that shared history must come from
    # pull_docs adopting laptop's commit, not from an accidental SHA collision
    sleep 1

    # Dev-1 pulls AND pushes to establish shared history
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" pull --docs
    # Push the same content to establish dev-1's ref based on laptop's history
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    # Now dev-1 modifies
    echo "dev1 version" > "docs/conflict.md"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    # Laptop modifies same line (parallel edit)
    cd_to_machine "$MACHINE_LAPTOP"
    echo "laptop version" > "docs/conflict.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Dev-1 pulls - should have conflict markers since they share history
    cd_to_machine "$MACHINE_DEV1"
    run run_jj_sync_with_docs "$MACHINE_DEV1" "docs" pull --docs

    # Output should warn about conflicts
    [[ "$output" =~ "CONFLICT" ]] || [[ "$output" =~ "conflict" ]]

    # File should have conflict markers
    local content
    content=$(cat "docs/conflict.md")
    [[ "$content" =~ "<<<<<<<" ]] || [[ "$content" =~ "=======" ]] || [[ "$content" =~ ">>>>>>>" ]]
}

@test "M4: One side adds, other modifies different file" {
    # Laptop creates two files
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "docs"
    echo "file1 content" > "docs/file1.md"
    echo "file2 content" > "docs/file2.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Dev-1 pulls, adds file3
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" pull --docs
    echo "file3 content" > "docs/file3.md"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    # Laptop modifies file2 (doesn't know about dev1's changes)
    cd_to_machine "$MACHINE_LAPTOP"
    echo "file2 modified" > "docs/file2.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Dev-1 pulls - should have merged state
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" pull --docs

    # All files should exist after merge
    assert_file_exists "docs/file1.md"
    assert_file_equals "docs/file2.md" "file2 modified"
    assert_file_exists "docs/file3.md"
}

@test "M5: Shared history enables three-way merge" {
    # When machines share history (pull then push), git merge-tree can do proper 3-way merge

    # Create base state
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "docs"
    echo "base" > "docs/base.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Dev-1 pulls and pushes to establish shared history
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" pull --docs
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    # Laptop adds new file
    cd_to_machine "$MACHINE_LAPTOP"
    echo "laptop's notes" > "docs/notes.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Dev-1 adds different file (no conflict since different paths)
    cd_to_machine "$MACHINE_DEV1"
    echo "dev1's file" > "docs/dev1.md"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    # Laptop pulls - should have both new files via three-way merge
    cd_to_machine "$MACHINE_LAPTOP"
    run run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" pull --docs

    [[ "$status" -eq 0 ]]

    # Both files should exist
    assert_file_exists "docs/base.md"
    assert_file_exists "docs/notes.md"
    assert_file_exists "docs/dev1.md"
}

@test "M6: Three machines diverged - sequential merge" {
    # Laptop creates initial state
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "docs"
    echo "initial" > "docs/shared.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # All machines pull base state
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" pull --docs

    cd_to_machine "$MACHINE_DEV2"
    run_jj_sync_with_docs "$MACHINE_DEV2" "docs" pull --docs

    # Each machine makes unique changes
    cd_to_machine "$MACHINE_LAPTOP"
    echo "laptop file" > "docs/laptop.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    cd_to_machine "$MACHINE_DEV1"
    echo "dev1 file" > "docs/dev1.md"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    cd_to_machine "$MACHINE_DEV2"
    echo "dev2 file" > "docs/dev2.md"
    run_jj_sync_with_docs "$MACHINE_DEV2" "docs" push --docs

    # Laptop pulls all changes
    cd_to_machine "$MACHINE_LAPTOP"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" pull --docs

    # Should have all files from all machines
    assert_file_exists "docs/shared.md"
    assert_file_exists "docs/laptop.md"
    assert_file_exists "docs/dev1.md"
    assert_file_exists "docs/dev2.md"
}

@test "M7: Merge preserves parent chain" {
    # Create initial state on laptop
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "docs"
    echo "v1" > "docs/file.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Dev-1 pulls and modifies
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" pull --docs
    echo "v2 from dev1" > "docs/file.md"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    # Laptop modifies (parallel)
    cd_to_machine "$MACHINE_LAPTOP"
    echo "v2 from laptop" > "docs/other.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Dev-1 pulls (merge happens)
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" pull --docs

    # Check that the merge commit has multiple parents
    local commit
    commit=$(git ls-remote "$TEST_DIR/remote.git" "refs/jj-sync/sync/$TEST_USER/$MACHINE_DEV1/docs" 2>/dev/null | cut -f1)
    git fetch "$TEST_DIR/remote.git" "$commit" 2>/dev/null

    local parent_count
    parent_count=$(git log -1 --format=%P "$commit" | wc -w | tr -d ' ')

    # Should have 2 parents (merge commit)
    [[ "$parent_count" -eq 2 ]]
}

@test "M8: Subsequent push after merge builds on merge commit" {
    # Create diverged state
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "docs"
    echo "laptop" > "docs/laptop.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    cd_to_machine "$MACHINE_DEV1"
    mkdir -p "docs"
    echo "dev1" > "docs/dev1.md"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    # Laptop pulls (merge)
    cd_to_machine "$MACHINE_LAPTOP"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" pull --docs

    # Laptop makes new change after merge
    echo "new from laptop" > "docs/new.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    # Dev-1 pulls - should get all three files
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" pull --docs

    assert_file_exists "docs/laptop.md"
    assert_file_exists "docs/dev1.md"
    assert_file_exists "docs/new.md"
}

@test "M9: No common ancestor - union merge" {
    # Both machines create docs independently (no shared history)
    cd_to_machine "$MACHINE_LAPTOP"
    mkdir -p "docs"
    echo "laptop only" > "docs/laptop.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" push --docs

    cd_to_machine "$MACHINE_DEV1"
    mkdir -p "docs"
    echo "dev1 only" > "docs/dev1.md"
    run_jj_sync_with_docs "$MACHINE_DEV1" "docs" push --docs

    # Laptop pulls - should union both (no common ancestor)
    cd_to_machine "$MACHINE_LAPTOP"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "docs" pull --docs

    assert_file_exists "docs/laptop.md"
    assert_file_exists "docs/dev1.md"
}
