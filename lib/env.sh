# shellcheck shell=bash
# lib/env.sh - Environment variable loading and defaults

# Configuration values (populated by load_env)
JJ_SYNC_REMOTE="${JJ_SYNC_REMOTE:-}"
JJ_SYNC_MACHINE="${JJ_SYNC_MACHINE:-}"
JJ_SYNC_DOCS="${JJ_SYNC_DOCS:-}"
JJ_SYNC_GC_REVS_DAYS="${JJ_SYNC_GC_REVS_DAYS:-}"
JJ_SYNC_GC_DOCS_MAX_CHAIN="${JJ_SYNC_GC_DOCS_MAX_CHAIN:-}"

# Computed values
JJ_SYNC_PREFIX="sync"

# Load environment variables with defaults
load_env() {
    JJ_SYNC_REMOTE="${JJ_SYNC_REMOTE:-sync}"
    JJ_SYNC_MACHINE="${JJ_SYNC_MACHINE:-$(hostname)}"
    JJ_SYNC_DOCS="${JJ_SYNC_DOCS:-}"
    JJ_SYNC_GC_REVS_DAYS="${JJ_SYNC_GC_REVS_DAYS:-7}"
    JJ_SYNC_GC_DOCS_MAX_CHAIN="${JJ_SYNC_GC_DOCS_MAX_CHAIN:-50}"

    # Sanitize machine name (remove characters that would be problematic in refs)
    JJ_SYNC_MACHINE="${JJ_SYNC_MACHINE//[^a-zA-Z0-9_-]/_}"
}

# Require JJ_SYNC_DOCS to be set (called when --docs or --both is used)
require_docs_env() {
    if [[ -z "${JJ_SYNC_DOCS:-}" ]]; then
        cat >&2 <<EOF
Error: --docs requires JJ_SYNC_DOCS environment variable
Hint: export JJ_SYNC_DOCS="ai/docs .claude"
EOF
        exit 1
    fi

    # Validate that it's not just whitespace
    local trimmed
    trimmed="${JJ_SYNC_DOCS// /}"
    if [[ -z "$trimmed" ]]; then
        cat >&2 <<EOF
Error: JJ_SYNC_DOCS is empty
Hint: export JJ_SYNC_DOCS="ai/docs .claude"
EOF
        exit 1
    fi
}

# Parse JJ_SYNC_DOCS into an array and echo each directory
# Usage: while IFS= read -r dir; do ... done < <(get_docs_dirs)
get_docs_dirs() {
    local dir
    # shellcheck disable=SC2086
    for dir in $JJ_SYNC_DOCS; do
        echo "$dir"
    done
}

# Get the bookmark prefix for this machine's revisions
get_revs_prefix() {
    echo "${JJ_SYNC_PREFIX}/${JJ_SYNC_MACHINE}/revs"
}

# Get the bookmark name for this machine's docs
get_docs_bookmark() {
    echo "${JJ_SYNC_PREFIX}/${JJ_SYNC_MACHINE}/docs"
}

# Get the glob pattern for all machines' revision bookmarks
get_all_revs_glob() {
    echo "${JJ_SYNC_PREFIX}/*/revs/*"
}

# Get the glob pattern for all machines' docs bookmarks
get_all_docs_glob() {
    echo "${JJ_SYNC_PREFIX}/*/docs"
}
