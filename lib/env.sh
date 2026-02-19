# shellcheck shell=bash
# lib/env.sh - Environment variable loading and defaults

# Configuration values (populated by load_env)
JJ_SYNC_REMOTE="${JJ_SYNC_REMOTE:-}"
JJ_SYNC_USER="${JJ_SYNC_USER:-}"
JJ_SYNC_MACHINE="${JJ_SYNC_MACHINE:-}"
JJ_SYNC_DOCS="${JJ_SYNC_DOCS:-}"
JJ_SYNC_GC_REVS_DAYS="${JJ_SYNC_GC_REVS_DAYS:-}"
JJ_SYNC_GC_DOCS_MAX_CHAIN="${JJ_SYNC_GC_DOCS_MAX_CHAIN:-}"

# Computed values
JJ_SYNC_PREFIX="sync"

# Sanitize a string for use in a git ref name
# Replaces: spaces, ~ ^ : ? * [ \ control chars
# Collapses .. sequences, strips leading/trailing dots
sanitize_for_ref() {
    local input="$1"
    local result

    # Replace problematic characters: space ~ ^ : ? * [ \ and control chars
    result="${input//[[:space:]~^:?*\[\\]/_}"

    # Collapse .. sequences
    while [[ "$result" == *..* ]]; do
        result="${result//../.}"
    done

    # Strip leading/trailing dots
    result="${result#.}"
    result="${result%.}"

    echo "$result"
}

# Load environment variables with defaults
load_env() {
    JJ_SYNC_REMOTE="${JJ_SYNC_REMOTE:-}"
    JJ_SYNC_MACHINE="${JJ_SYNC_MACHINE:-$(hostname)}"
    JJ_SYNC_DOCS="${JJ_SYNC_DOCS:-}"
    JJ_SYNC_GC_REVS_DAYS="${JJ_SYNC_GC_REVS_DAYS:-7}"
    JJ_SYNC_GC_DOCS_MAX_CHAIN="${JJ_SYNC_GC_DOCS_MAX_CHAIN:-50}"

    # Sanitize machine name (remove characters that would be problematic in refs)
    JJ_SYNC_MACHINE="${JJ_SYNC_MACHINE//[^a-zA-Z0-9_-]/_}"

    # Resolve user identity (don't error if empty — require_user handles that)
    if [[ -z "${JJ_SYNC_USER:-}" ]]; then
        JJ_SYNC_USER=$(jj config get user.email 2>/dev/null) || true
    fi
    if [[ -z "${JJ_SYNC_USER:-}" ]]; then
        JJ_SYNC_USER=$(git config user.email 2>/dev/null) || true
    fi

    # Sanitize user for ref name
    if [[ -n "$JJ_SYNC_USER" ]]; then
        JJ_SYNC_USER=$(sanitize_for_ref "$JJ_SYNC_USER")
    fi
}

# Require JJ_SYNC_USER to be set (called by commands that need it)
require_user() {
    if [[ -z "${JJ_SYNC_USER:-}" ]]; then
        cat >&2 <<EOF
Error: Could not determine user identity

Set one of the following:
  jj config set --user user.email "you@example.com"
  git config --global user.email "you@example.com"
  export JJ_SYNC_USER="you@example.com"
EOF
        exit 1
    fi
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
    echo "${JJ_SYNC_PREFIX}/${JJ_SYNC_USER}/${JJ_SYNC_MACHINE}/revs"
}

# Get the bookmark name for this machine's docs
get_docs_bookmark() {
    echo "${JJ_SYNC_PREFIX}/${JJ_SYNC_USER}/${JJ_SYNC_MACHINE}/docs"
}

# Get the glob pattern for all machines' revision bookmarks (current user)
get_all_revs_glob() {
    echo "${JJ_SYNC_PREFIX}/${JJ_SYNC_USER}/*/revs/*"
}

# Get the glob pattern for all machines' docs bookmarks (current user)
get_all_docs_glob() {
    echo "${JJ_SYNC_PREFIX}/${JJ_SYNC_USER}/*/docs"
}
