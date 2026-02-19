#!/usr/bin/env bats
# tests/test_docs.bats - Doc sync tests

load test_helper.bash

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "D1: Push packs docs to remote" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create doc directory with files
    create_doc_dir "ai/docs" 3

    # Push docs
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Verify docs bookmark exists on remote
    assert_bookmark_exists_remote "sync/$TEST_USER/$MACHINE_LAPTOP/docs"
}

@test "D2: Pull extracts docs" {
    # Push docs from laptop
    cd_to_machine "$MACHINE_LAPTOP"
    create_doc_dir "ai/docs" 3
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Pull on dev-1
    cd_to_machine "$MACHINE_DEV1"
    mkdir -p ai/docs  # Create the directory structure
    run_jj_sync_with_docs "$MACHINE_DEV1" "ai/docs" pull --docs

    # Verify files exist
    assert_file_exists "ai/docs/doc1.md"
    assert_file_exists "ai/docs/doc2.md"
    assert_file_exists "ai/docs/doc3.md"
}

@test "D3: Subdirectory structure preserved" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create nested structure
    mkdir -p "ai/docs/plans/q1"
    echo "Goals for Q1" > "ai/docs/plans/q1/goals.md"
    echo "Timeline" > "ai/docs/plans/timeline.md"

    # Push
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Pull on dev-1
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "ai/docs" pull --docs

    # Verify nested structure
    assert_file_exists "ai/docs/plans/q1/goals.md"
    assert_file_exists "ai/docs/plans/timeline.md"
    assert_file_equals "ai/docs/plans/q1/goals.md" "Goals for Q1"
}

@test "D4: Multiple doc dirs work" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create multiple doc directories
    create_doc_dir "ai/docs" 2
    create_doc_dir ".claude" 2

    # Push with multiple dirs
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs .claude" push --docs

    # Pull on dev-1
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "ai/docs .claude" pull --docs

    # Verify both directories
    assert_file_exists "ai/docs/doc1.md"
    assert_file_exists ".claude/doc1.md"
}

@test "D5: Empty doc dir - no error" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create empty doc directory
    mkdir -p "ai/docs"

    # Push should succeed (with no files to push)
    run run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs
    [[ "$status" -eq 0 ]]
}

@test "D6: Missing doc dir - skip with warning" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Don't create the directory at all
    # Push should succeed but warn
    run run_jj_sync_with_docs "$MACHINE_LAPTOP" "nonexistent/dir" push --docs
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"not found"* ]] || [[ "$output" == *"No doc files"* ]]
}

@test "D7: Binary files survive roundtrip" {
    cd_to_machine "$MACHINE_LAPTOP"

    mkdir -p "ai/docs"
    # Create a simple binary file (PNG header)
    printf '\x89PNG\r\n\x1a\n' > "ai/docs/image.png"

    # Push
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Pull on dev-1
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "ai/docs" pull --docs

    # Verify binary file
    assert_file_exists "ai/docs/image.png"
    local original_hash expected_hash
    cd_to_machine "$MACHINE_LAPTOP"
    original_hash=$(md5sum "ai/docs/image.png" | cut -d' ' -f1)
    cd_to_machine "$MACHINE_DEV1"
    expected_hash=$(md5sum "ai/docs/image.png" | cut -d' ' -f1)
    [[ "$original_hash" == "$expected_hash" ]]
}

@test "D8: Files with special characters" {
    cd_to_machine "$MACHINE_LAPTOP"

    mkdir -p "ai/docs"
    echo "content" > "ai/docs/file with spaces.md"
    echo "content2" > "ai/docs/über-notes.md"

    # Push
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Pull on dev-1
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "ai/docs" pull --docs

    # Verify files with special chars
    assert_file_exists "ai/docs/file with spaces.md"
    assert_file_exists "ai/docs/über-notes.md"
}

@test "D10: Doc commit has parent chain" {
    cd_to_machine "$MACHINE_LAPTOP"

    # First push
    mkdir -p "ai/docs"
    echo "version 1" > "ai/docs/doc.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Get first commit
    local first_commit
    first_commit=$(git ls-remote "$TEST_DIR/remote.git" "refs/jj-sync/sync/$TEST_USER/$MACHINE_LAPTOP/docs" | cut -f1)

    # Second push
    echo "version 2" > "ai/docs/doc.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Get second commit
    local second_commit
    second_commit=$(git ls-remote "$TEST_DIR/remote.git" "refs/jj-sync/sync/$TEST_USER/$MACHINE_LAPTOP/docs" | cut -f1)

    # Verify different commits
    [[ "$first_commit" != "$second_commit" ]]

    # Verify parent relationship (fetch and check)
    cd_to_machine "$MACHINE_LAPTOP"
    git fetch "$TEST_DIR/remote.git" "$second_commit" 2>/dev/null
    local parent
    parent=$(git log -1 --format=%P "$second_commit")
    [[ "$parent" == "$first_commit" ]]
}

@test "D11: Deleted files sync correctly" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Create initial files
    mkdir -p "ai/docs"
    echo "keep" > "ai/docs/keep.md"
    echo "delete" > "ai/docs/delete.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Pull on dev-1 first
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "ai/docs" pull --docs
    assert_file_exists "ai/docs/delete.md"

    # Delete file on laptop and push again
    cd_to_machine "$MACHINE_LAPTOP"
    rm "ai/docs/delete.md"
    run_jj_sync_with_docs "$MACHINE_LAPTOP" "ai/docs" push --docs

    # Pull on dev-1 again
    cd_to_machine "$MACHINE_DEV1"
    run_jj_sync_with_docs "$MACHINE_DEV1" "ai/docs" pull --docs

    # Verify deleted file is gone
    assert_file_exists "ai/docs/keep.md"
    assert_file_not_exists "ai/docs/delete.md"
}
