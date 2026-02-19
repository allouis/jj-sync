# shellcheck shell=bash
# tests/test_helper.bash - Test utilities for bats

# Get the directory containing test_helper.bash
TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get the project root (parent of tests/)
PROJECT_ROOT="$(cd "$TEST_HELPER_DIR/.." && pwd)"

# Path to jj-sync script
JJ_SYNC="$PROJECT_ROOT/jj-sync"

# Test environment directory (set by setup_test_env)
TEST_DIR=""

# Machine names for testing
MACHINE_LAPTOP="laptop"
MACHINE_DEV1="dev-1"
MACHINE_DEV2="dev-2"

# User identity for testing
TEST_USER="test@example.com"

# ============================================================================
# Setup / Teardown
# ============================================================================

# Create a test environment with a bare remote and optional working copies
# Usage: setup_test_env [machine1] [machine2] ...
# If no machines specified, creates laptop and dev-1
setup_test_env() {
    local machines=("$@")
    if [[ ${#machines[@]} -eq 0 ]]; then
        machines=("$MACHINE_LAPTOP" "$MACHINE_DEV1")
    fi

    # Create temp directory
    TEST_DIR=$(mktemp -d)
    export TEST_DIR

    # Create bare "sync remote"
    git init --bare "$TEST_DIR/remote.git" >/dev/null 2>&1

    # Create working copies for each machine
    local machine
    for machine in "${machines[@]}"; do
        create_jj_repo "$machine" "colocated"
    done
}

# Clean up test environment
teardown_test_env() {
    if [[ -n "$TEST_DIR" ]] && [[ -d "$TEST_DIR" ]]; then
        rm -rf "$TEST_DIR"
    fi
}

# ============================================================================
# Repository Creation
# ============================================================================

# Create a jj repository for a machine
# Usage: create_jj_repo <machine_name> [colocated|noncolocated]
create_jj_repo() {
    local machine="$1"
    local type="${2:-colocated}"
    local repo_dir="$TEST_DIR/$machine"

    mkdir -p "$repo_dir"
    cd "$repo_dir" || return 1

    if [[ "$type" == "colocated" ]]; then
        jj git init --colocate >/dev/null 2>&1
    else
        jj git init >/dev/null 2>&1
    fi

    # Add the sync remote
    jj git remote add sync "$TEST_DIR/remote.git" >/dev/null 2>&1

    # Configure git user for commits
    git config user.email "test@example.com"
    git config user.name "Test User"

    cd - >/dev/null || return 1
}

# Create a plain git repository (no jj) for a machine
# Usage: create_plain_git_repo <machine_name>
create_plain_git_repo() {
    local machine="$1"
    local repo_dir="$TEST_DIR/$machine"

    mkdir -p "$repo_dir"
    cd "$repo_dir" || return 1

    git init >/dev/null 2>&1

    # Add the sync remote
    git remote add sync "$TEST_DIR/remote.git" >/dev/null 2>&1

    # Configure git user for commits
    git config user.email "test@example.com"
    git config user.name "Test User"

    cd - >/dev/null || return 1
}

# Switch to a machine's repo directory
# Usage: cd_to_machine <machine_name>
cd_to_machine() {
    local machine="$1"
    cd "$TEST_DIR/$machine" || return 1
}

# ============================================================================
# Change Creation
# ============================================================================

# Create a new file and jj change
# Usage: make_change <filename> <content> [description]
make_change() {
    local filename="$1"
    local content="$2"
    local description="${3:-}"

    # Create directory if needed
    local dir
    dir=$(dirname "$filename")
    if [[ "$dir" != "." ]]; then
        mkdir -p "$dir"
    fi

    # Write file
    echo "$content" > "$filename"

    # Track and describe
    jj file track "$filename" >/dev/null 2>&1

    if [[ -n "$description" ]]; then
        jj describe -m "$description" >/dev/null 2>&1
    fi
}

# Create a new jj revision (empty change on top)
# Usage: new_revision [description]
new_revision() {
    local description="${1:-}"
    jj new >/dev/null 2>&1
    if [[ -n "$description" ]]; then
        jj describe -m "$description" >/dev/null 2>&1
    fi
}

# Create multiple WIP changes for testing
# Usage: create_wip_changes <count>
create_wip_changes() {
    local count="$1"
    local i

    for ((i=1; i<=count; i++)); do
        make_change "file$i.txt" "content $i"
        jj describe -m "WIP change $i" >/dev/null 2>&1
        if [[ $i -lt $count ]]; then
            jj new >/dev/null 2>&1
        fi
    done
}

# ============================================================================
# Doc Directory Helpers
# ============================================================================

# Create a doc directory with files
# Usage: create_doc_dir <dirname> <file_count>
create_doc_dir() {
    local dirname="$1"
    local file_count="${2:-3}"
    local i

    mkdir -p "$dirname"
    for ((i=1; i<=file_count; i++)); do
        echo "Doc content $i" > "$dirname/doc$i.md"
    done
}

# ============================================================================
# Assertions
# ============================================================================

# Assert that a bookmark exists on the remote
# Usage: assert_bookmark_exists_remote <bookmark_name>
assert_bookmark_exists_remote() {
    local bookmark="$1"
    local refs

    refs=$(git ls-remote "$TEST_DIR/remote.git" "refs/jj-sync/$bookmark" 2>/dev/null)
    if [[ -z "$refs" ]]; then
        echo "Expected bookmark '$bookmark' to exist on remote, but it doesn't"
        echo "Remote refs:"
        git ls-remote "$TEST_DIR/remote.git" 2>/dev/null | head -20
        return 1
    fi
}

# Assert that a bookmark does NOT exist on the remote
# Usage: assert_bookmark_not_exists_remote <bookmark_name>
assert_bookmark_not_exists_remote() {
    local bookmark="$1"
    local refs

    refs=$(git ls-remote "$TEST_DIR/remote.git" "refs/jj-sync/$bookmark" 2>/dev/null)
    if [[ -n "$refs" ]]; then
        echo "Expected bookmark '$bookmark' to NOT exist on remote, but it does"
        return 1
    fi
}

# Assert that a bookmark exists locally
# Usage: assert_bookmark_exists_local <bookmark_name>
assert_bookmark_exists_local() {
    local bookmark="$1"

    if ! git rev-parse --verify "refs/heads/$bookmark" >/dev/null 2>&1; then
        echo "Expected bookmark '$bookmark' to exist locally, but it doesn't"
        return 1
    fi
}

# Assert that a bookmark does NOT exist locally
# Usage: assert_bookmark_not_exists_local <bookmark_name>
assert_bookmark_not_exists_local() {
    local bookmark="$1"

    if git rev-parse --verify "refs/heads/$bookmark" >/dev/null 2>&1; then
        echo "Expected bookmark '$bookmark' to NOT exist locally, but it does"
        return 1
    fi
}

# Assert file content equals expected
# Usage: assert_file_equals <filepath> <expected_content>
assert_file_equals() {
    local filepath="$1"
    local expected="$2"

    if [[ ! -f "$filepath" ]]; then
        echo "Expected file '$filepath' to exist, but it doesn't"
        return 1
    fi

    local actual
    actual=$(cat "$filepath")
    if [[ "$actual" != "$expected" ]]; then
        echo "File content mismatch for '$filepath'"
        echo "Expected: $expected"
        echo "Actual: $actual"
        return 1
    fi
}

# Assert file exists
# Usage: assert_file_exists <filepath>
assert_file_exists() {
    local filepath="$1"

    if [[ ! -f "$filepath" ]]; then
        echo "Expected file '$filepath' to exist, but it doesn't"
        return 1
    fi
}

# Assert file does not exist
# Usage: assert_file_not_exists <filepath>
assert_file_not_exists() {
    local filepath="$1"

    if [[ -f "$filepath" ]]; then
        echo "Expected file '$filepath' to NOT exist, but it does"
        return 1
    fi
}

# Assert directory exists
# Usage: assert_dir_exists <dirpath>
assert_dir_exists() {
    local dirpath="$1"

    if [[ ! -d "$dirpath" ]]; then
        echo "Expected directory '$dirpath' to exist, but it doesn't"
        return 1
    fi
}

# Count bookmarks matching a pattern on remote
# Usage: count_remote_bookmarks <pattern>
count_remote_bookmarks() {
    local pattern="$1"
    git ls-remote "$TEST_DIR/remote.git" "refs/jj-sync/$pattern" 2>/dev/null | wc -l | tr -d ' '
}

# ============================================================================
# jj-sync Runners
# ============================================================================

# Run jj-sync with test environment
# Usage: run_jj_sync <machine> [args...]
# Env vars can be passed by setting them before the call
run_jj_sync() {
    local machine="$1"
    shift

    cd "$TEST_DIR/$machine" || return 1

    JJ_SYNC_USER="${JJ_SYNC_USER:-$TEST_USER}" \
    JJ_SYNC_MACHINE="${JJ_SYNC_MACHINE:-$machine}" \
    JJ_SYNC_REMOTE="${JJ_SYNC_REMOTE:-sync}" \
    JJ_SYNC_GC_REVS_DAYS="${JJ_SYNC_GC_REVS_DAYS:-7}" \
    JJ_SYNC_GC_DOCS_MAX_CHAIN="${JJ_SYNC_GC_DOCS_MAX_CHAIN:-50}" \
        "$JJ_SYNC" "$@"
}

# Run jj-sync with docs configured
# Usage: run_jj_sync_with_docs <machine> <docs_dirs> [args...]
run_jj_sync_with_docs() {
    local machine="$1"
    local docs_dirs="$2"
    shift 2

    cd "$TEST_DIR/$machine" || return 1

    JJ_SYNC_USER="${JJ_SYNC_USER:-$TEST_USER}" \
    JJ_SYNC_MACHINE="$machine" \
    JJ_SYNC_REMOTE="sync" \
    JJ_SYNC_DOCS="$docs_dirs" \
        "$JJ_SYNC" "$@"
}

# ============================================================================
# jj Helpers
# ============================================================================

# Get the change ID of the current working copy
get_current_change_id() {
    jj log -r @ --no-graph -T 'change_id.short(12)'
}

# Get the commit ID of the current working copy
get_current_commit_id() {
    jj log -r @ --no-graph -T 'commit_id.short(12)'
}

# Check if jj has a change with given change_id prefix
# Usage: jj_has_change <change_id_prefix>
jj_has_change() {
    local change_id="$1"
    jj log -r "$change_id" --no-graph >/dev/null 2>&1
}

# Count the number of WIP changes (mine, not empty, not immutable)
count_wip_changes() {
    jj log -r 'mine() & ~empty() & ~immutable_heads() & ~trunk()' --no-graph -T 'change_id.short(12) ++ "\n"' 2>/dev/null | grep -c . || echo 0
}

# ============================================================================
# Bats Integration
# ============================================================================

# Standard setup function for bats tests
# Usage: setup() { load_test_helper; setup_test_env; }
load_test_helper() {
    # Load bats support libraries if available
    if [[ -f "$TEST_HELPER_DIR/bats-support/load.bash" ]]; then
        # shellcheck disable=SC1091
        source "$TEST_HELPER_DIR/bats-support/load.bash"
    fi
    if [[ -f "$TEST_HELPER_DIR/bats-assert/load.bash" ]]; then
        # shellcheck disable=SC1091
        source "$TEST_HELPER_DIR/bats-assert/load.bash"
    fi
}
