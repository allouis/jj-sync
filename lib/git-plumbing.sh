# shellcheck shell=bash
# lib/git-plumbing.sh - Low-level git operations

# GIT_DIR is set by detect_git_dir
GIT_DIR=""
GIT_WORK_TREE=""

# Detect the git directory for the current jj repo
# Sets GIT_DIR and GIT_WORK_TREE
# Works for both colocated (.git/) and non-colocated (.jj/repo/store/git/) repos
detect_git_dir() {
    local repo_root
    repo_root="$(pwd)"

    # Try colocated first
    if [[ -d "$repo_root/.git" ]]; then
        GIT_DIR="$repo_root/.git"
        GIT_WORK_TREE="$repo_root"
        return 0
    fi

    # Try non-colocated
    if [[ -d "$repo_root/.jj/repo/store/git" ]]; then
        GIT_DIR="$repo_root/.jj/repo/store/git"
        GIT_WORK_TREE="$repo_root"
        return 0
    fi

    return 1
}

# Run a git command with the correct GIT_DIR
git_cmd() {
    GIT_DIR="$GIT_DIR" GIT_WORK_TREE="$GIT_WORK_TREE" git "$@"
}

# Check that we're in a jj repository
require_jj_repo() {
    if ! detect_git_dir; then
        die "Not in a jj repository (no .git/ or .jj/repo/store/git/ found)"
    fi

    # Also verify jj recognizes this as a repo
    if ! jj root >/dev/null 2>&1; then
        die "Not in a jj repository (jj root failed)"
    fi
}

# Check that the sync remote exists
require_remote() {
    local remote="$JJ_SYNC_REMOTE"

    if ! git_cmd remote get-url "$remote" >/dev/null 2>&1; then
        cat >&2 <<EOF
Error: Remote '$remote' not found

To set up jj-sync, add a sync remote:
  jj git remote add $remote <your-remote-url>

Example:
  jj git remote add $remote git@github.com:yourusername/myrepo-sync.git
EOF
        exit 1
    fi
}

# Get the URL of the sync remote
get_remote_url() {
    git_cmd remote get-url "$JJ_SYNC_REMOTE"
}

# Create a tree object from files in specified directories
# Usage: create_tree_from_files dir1 dir2 ...
# Outputs: tree SHA
create_tree_from_files() {
    local dirs=("$@")
    local temp_index
    temp_index=$(mktemp -u)  # -u: don't create, just generate name
    # shellcheck disable=SC2064
    trap "rm -f '$temp_index'" RETURN

    # Use a temporary index file (git will create it fresh)
    local old_index="${GIT_INDEX_FILE:-}"
    export GIT_INDEX_FILE="$temp_index"

    # Add all files from each directory
    local dir
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            # Find all files and add them
            while IFS= read -r -d '' file; do
                # Add file to index, bypassing .gitignore with -f
                git_cmd add -f "$file" 2>/dev/null || true
            done < <(find "$dir" -type f -print0)
        fi
    done

    # Write the tree
    local tree
    tree=$(git_cmd write-tree)

    # Restore original index
    if [[ -n "$old_index" ]]; then
        export GIT_INDEX_FILE="$old_index"
    else
        unset GIT_INDEX_FILE
    fi

    echo "$tree"
}

# Create a commit from a tree
# Usage: create_commit <tree> <message> [parent1] [parent2] ...
# Outputs: commit SHA
create_commit() {
    local tree="$1"
    local message="$2"
    shift 2

    local parent_args=()
    for parent in "$@"; do
        parent_args+=("-p" "$parent")
    done

    git_cmd commit-tree "$tree" "${parent_args[@]}" -m "$message"
}

# Get the timestamp of a commit
# Usage: get_commit_timestamp <commit>
# Outputs: Unix timestamp
get_commit_timestamp() {
    local commit="$1"
    git_cmd show -s --format=%ct "$commit"
}

# Check if a ref exists locally
# Usage: ref_exists <refname>
ref_exists_local() {
    local ref="$1"
    git_cmd rev-parse --verify "refs/heads/$ref" >/dev/null 2>&1
}

# Check if a ref exists on the remote
# Usage: ref_exists_remote <refname>
ref_exists_remote() {
    local ref="$1"
    git_cmd ls-remote --heads "$JJ_SYNC_REMOTE" "$ref" | grep -q .
}

# List refs on remote matching a pattern
# Usage: list_remote_refs <pattern>
# Outputs: one ref per line (without refs/jj-sync/ prefix)
# Note: We use refs/jj-sync/ namespace to avoid jj importing them as bookmarks
list_remote_refs() {
    local pattern="$1"
    git_cmd ls-remote "$JJ_SYNC_REMOTE" "refs/jj-sync/$pattern" 2>/dev/null |
        sed 's|.*refs/jj-sync/||'
}

# Fetch refs from remote
# Usage: fetch_remote [refspec...]
fetch_remote() {
    if [[ $# -eq 0 ]]; then
        git_cmd fetch "$JJ_SYNC_REMOTE"
    else
        git_cmd fetch "$JJ_SYNC_REMOTE" "$@"
    fi
}

# Push refs to remote
# Usage: push_remote [--force] <refspec>...
push_remote() {
    local force=""
    if [[ "${1:-}" == "--force" ]]; then
        force="--force"
        shift
    fi

    # shellcheck disable=SC2086
    git_cmd push $force "$JJ_SYNC_REMOTE" "$@"
}

# Delete a ref on the remote
# Usage: delete_remote_ref <refname>
delete_remote_ref() {
    local ref="$1"
    git_cmd push "$JJ_SYNC_REMOTE" ":refs/jj-sync/$ref" 2>/dev/null || true
}

# Get a commit from a remote ref (fetches if needed)
# Usage: get_remote_commit <refname>
# Outputs: commit SHA or empty if not found
get_remote_commit() {
    local ref="$1"

    # First try to get directly from remote
    local commit
    commit=$(git_cmd ls-remote "$JJ_SYNC_REMOTE" "refs/jj-sync/$ref" 2>/dev/null | cut -f1)

    if [[ -n "$commit" ]]; then
        # Fetch the commit object
        git_cmd fetch "$JJ_SYNC_REMOTE" "$commit" 2>/dev/null || true
        echo "$commit"
        return 0
    fi

    return 1
}

# Update a local ref to point to a commit
# Usage: update_ref <refname> <commit>
update_ref() {
    local ref="$1"
    local commit="$2"
    git_cmd update-ref "refs/heads/$ref" "$commit"
}

# Delete a local ref
# Usage: delete_local_ref <refname>
delete_local_ref() {
    local ref="$1"
    git_cmd update-ref -d "refs/heads/$ref" 2>/dev/null || true
}

# Extract files from a tree to the working directory
# Usage: extract_tree <tree-ish> <prefix>
# Extracts files from tree to current directory, preserving paths under prefix
extract_tree() {
    local tree="$1"
    local prefix="${2:-.}"

    # Use git archive to extract
    git_cmd archive "$tree" | tar -x -C "$prefix"
}

# Three-way merge of trees using git merge-tree
# Usage: merge_trees <base> <ours> <theirs>
# Outputs: merged tree SHA
# Returns: 0 if clean merge, 1 if conflicts
merge_trees() {
    local base="$1"
    local ours="$2"
    local theirs="$3"

    local result
    result=$(git_cmd merge-tree --write-tree "$base" "$ours" "$theirs" 2>&1)
    local status=$?

    if [[ $status -eq 0 ]]; then
        echo "$result"
        return 0
    else
        # First line is the tree with conflicts
        echo "$result" | head -1
        return 1
    fi
}

# Find common ancestor of two commits
# Usage: find_merge_base <commit1> <commit2>
# Outputs: common ancestor SHA or empty if none
find_merge_base() {
    local commit1="$1"
    local commit2="$2"
    git_cmd merge-base "$commit1" "$commit2" 2>/dev/null || true
}
