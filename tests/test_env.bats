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
        source "$PROJECT_ROOT/lib/env.sh"
        load_env

        # Should have defaults
        [[ "$JJ_SYNC_REMOTE" == "sync" ]]
        [[ -n "$JJ_SYNC_MACHINE" ]]
        [[ "$JJ_SYNC_GC_REVS_DAYS" == "7" ]]
        [[ "$JJ_SYNC_GC_DOCS_MAX_CHAIN" == "50" ]]
    )
}

@test "V2: Machine name defaults to hostname" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        unset JJ_SYNC_MACHINE
        source "$PROJECT_ROOT/lib/env.sh"
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
        source "$PROJECT_ROOT/lib/env.sh"
        load_env

        [[ "$JJ_SYNC_REMOTE" == "other-remote" ]]
    )
}

@test "V4: Machine override works" {
    cd_to_machine "$MACHINE_LAPTOP"

    (
        export JJ_SYNC_MACHINE="my-custom-machine"
        source "$PROJECT_ROOT/lib/env.sh"
        load_env

        [[ "$JJ_SYNC_MACHINE" == "my-custom-machine" ]]
    )
}

@test "V5: --docs without JJ_SYNC_DOCS errors" {
    cd_to_machine "$MACHINE_LAPTOP"

    # Run with explicitly empty JJ_SYNC_DOCS
    run env -u JJ_SYNC_DOCS \
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
        source "$PROJECT_ROOT/lib/env.sh"
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
        JJ_SYNC_MACHINE="$MACHINE_LAPTOP" \
        JJ_SYNC_REMOTE="sync" \
        "$JJ_SYNC" push --docs

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"JJ_SYNC_DOCS"* ]]
}
