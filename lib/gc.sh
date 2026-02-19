# shellcheck shell=bash
# lib/gc.sh - Garbage collection

# Garbage collect old revision bookmarks
gc_revisions() {
    log_info "Cleaning up old revision bookmarks..."

    detect_git_dir

    # Fetch from remote first to get current state
    fetch_remote 2>/dev/null || true

    local all_revs_glob
    all_revs_glob=$(get_all_revs_glob)

    # List all revision bookmarks on remote
    local remote_bookmarks=()
    local ref
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && remote_bookmarks+=("$ref")
    done < <(list_remote_refs "$all_revs_glob")

    if [[ ${#remote_bookmarks[@]} -eq 0 ]]; then
        log_info "No revision bookmarks found on remote"
        return 0
    fi

    local threshold_days="${JJ_SYNC_GC_REVS_DAYS:-7}"
    local threshold_secs=$((threshold_days * 24 * 60 * 60))
    local now
    now=$(date +%s)

    local deleted=0
    local kept=0

    for ref in "${remote_bookmarks[@]}"; do
        # Get the commit for this ref
        local commit
        commit=$(get_remote_commit "$ref" 2>/dev/null) || continue

        # Get commit timestamp
        local commit_time
        commit_time=$(get_commit_timestamp "$commit" 2>/dev/null) || continue

        local age=$((now - commit_time))

        if [[ $age -ge $threshold_secs ]]; then
            verbose "Deleting old bookmark: $ref (age: $((age / 86400)) days)"
            if ! is_dry_run; then
                delete_remote_ref "$ref"
            fi
            ((deleted++)) || true
        else
            ((kept++)) || true
        fi
    done

    if [[ $deleted -gt 0 ]]; then
        log_success "Deleted $deleted old bookmark(s), kept $kept recent one(s)"
    else
        log_info "No old bookmarks to delete (kept $kept)"
    fi
}

# Garbage collect long docs commit chains
gc_docs() {
    log_info "Checking docs commit chain lengths..."

    detect_git_dir

    local all_docs_glob
    all_docs_glob=$(get_all_docs_glob)

    # List all docs bookmarks on remote
    local docs_refs=()
    local ref
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && docs_refs+=("$ref")
    done < <(list_remote_refs "$all_docs_glob")

    if [[ ${#docs_refs[@]} -eq 0 ]]; then
        log_info "No docs bookmarks found on remote"
        return 0
    fi

    local max_chain="${JJ_SYNC_GC_DOCS_MAX_CHAIN:-50}"

    for ref in "${docs_refs[@]}"; do
        local commit
        commit=$(get_remote_commit "$ref" 2>/dev/null) || continue

        # Count chain length
        local chain_length
        chain_length=$(git_cmd rev-list --count "$commit" 2>/dev/null) || continue

        verbose "$ref: chain length $chain_length"

        if [[ $chain_length -gt $max_chain ]]; then
            log_info "$ref: chain length $chain_length exceeds threshold $max_chain"

            if is_dry_run; then
                log_info "[dry-run] Would squash to single commit"
                continue
            fi

            # Squash: create new orphan commit with same tree
            local tree
            tree=$(git_cmd rev-parse "$commit^{tree}" 2>/dev/null)

            local new_commit
            new_commit=$(create_commit "$tree" "jj-sync docs (squashed)")

            # Force push the new commit to refs/jj-sync/ namespace
            git_cmd push --force "$JJ_SYNC_REMOTE" "$new_commit:refs/jj-sync/$ref" 2>/dev/null

            log_success "$ref: squashed from $chain_length commits to 1"
        fi
    done
}

# Remove ALL sync state - nuclear option
clean_all() {
    log_info "Removing all sync state..."

    detect_git_dir

    # List all sync bookmarks on remote
    local all_refs=()
    local ref
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && all_refs+=("$ref")
    done < <(list_remote_refs "${JJ_SYNC_PREFIX}/*")

    if [[ ${#all_refs[@]} -eq 0 ]]; then
        log_info "No sync state found on remote"
        return 0
    fi

    log_warn "Found ${#all_refs[@]} sync bookmark(s) on remote"

    if is_dry_run; then
        log_info "[dry-run] Would delete:"
        for ref in "${all_refs[@]}"; do
            list_item "$ref"
        done
        return 0
    fi

    # Delete each ref
    local deleted=0
    for ref in "${all_refs[@]}"; do
        verbose "Deleting: $ref"
        delete_remote_ref "$ref"
        ((deleted++)) || true
    done

    # Also clean up local refs
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && delete_local_ref "$ref"
    done < <(git_cmd branch --list "${JJ_SYNC_PREFIX}/*" 2>/dev/null | sed 's/^[* ]*//')

    jj git import --quiet 2>/dev/null || true

    log_success "Deleted $deleted sync bookmark(s)"
}

# Show sync status
show_status() {
    detect_git_dir

    section "jj-sync status"

    # Attempt remote resolution non-fatally
    local remote_resolved=true
    if [[ -n "$JJ_SYNC_REMOTE" ]]; then
        if ! git_cmd remote get-url "$JJ_SYNC_REMOTE" >/dev/null 2>&1; then
            remote_resolved=false
        fi
    else
        # Try auto-detect without dying on failure
        local remotes=()
        local name
        while IFS= read -r name; do
            [[ -n "$name" ]] && remotes+=("$name")
        done < <(list_git_remotes 2>/dev/null)

        if [[ ${#remotes[@]} -eq 1 ]]; then
            JJ_SYNC_REMOTE="${remotes[0]}"
        else
            remote_resolved=false
        fi
    fi

    # Remote info
    if [[ "$remote_resolved" == "true" ]]; then
        local remote_url
        remote_url=$(get_remote_url 2>/dev/null) || remote_url="(unknown)"
        kv "Remote" "$JJ_SYNC_REMOTE → $remote_url"
    else
        kv "Remote" "(not configured)"
    fi
    kv "Machine" "$JJ_SYNC_MACHINE"

    # Local revisions
    section "Revisions"
    local rev_count
    rev_count=$(count_sync_revisions)
    kv "Would push" "$rev_count revision(s)"

    if [[ $rev_count -gt 0 ]]; then
        echo ""
        list_sync_revisions | head -10
        if [[ $rev_count -gt 10 ]]; then
            echo "  ... and $((rev_count - 10)) more"
        fi
    fi

    # Remote sections require a resolved remote
    if [[ "$remote_resolved" != "true" ]]; then
        section "Docs"
        if [[ -n "${JJ_SYNC_DOCS:-}" ]]; then
            kv "JJ_SYNC_DOCS" "$JJ_SYNC_DOCS"
            echo ""
            list_doc_dirs
        else
            log_info "Not configured (set JJ_SYNC_DOCS to enable)"
        fi
        return 0
    fi

    # Remote revision state
    local all_revs_glob
    all_revs_glob=$(get_all_revs_glob)
    local remote_revs=()
    local ref
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && remote_revs+=("$ref")
    done < <(list_remote_refs "$all_revs_glob")

    if [[ ${#remote_revs[@]} -gt 0 ]]; then
        echo ""
        log_info "Remote revisions:"

        # Group by machine
        declare -A machine_counts
        for ref in "${remote_revs[@]}"; do
            local machine
            machine=$(echo "$ref" | cut -d'/' -f2)
            machine_counts[$machine]=$(( ${machine_counts[$machine]:-0} + 1 ))
        done

        for machine in "${!machine_counts[@]}"; do
            list_item "$machine: ${machine_counts[$machine]} revision(s)"
        done
    fi

    # Docs section
    section "Docs"
    if [[ -n "${JJ_SYNC_DOCS:-}" ]]; then
        kv "JJ_SYNC_DOCS" "$JJ_SYNC_DOCS"
        echo ""
        list_doc_dirs
    else
        log_info "Not configured (set JJ_SYNC_DOCS to enable)"
    fi

    # Remote docs state
    local all_docs_glob
    all_docs_glob=$(get_all_docs_glob)
    local remote_docs=()
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && remote_docs+=("$ref")
    done < <(list_remote_refs "$all_docs_glob")

    if [[ ${#remote_docs[@]} -gt 0 ]]; then
        echo ""
        log_info "Remote docs:"
        for ref in "${remote_docs[@]}"; do
            list_item "$ref"
        done
    fi
}

# Interactive setup
init_setup() {
    section "jj-sync init"

    # Check prerequisites
    log_info "Checking prerequisites..."

    # Check git version
    local git_version
    git_version=$(git --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local git_major git_minor
    git_major=$(echo "$git_version" | cut -d. -f1)
    git_minor=$(echo "$git_version" | cut -d. -f2)

    if [[ "$git_major" -lt 2 ]] || { [[ "$git_major" -eq 2 ]] && [[ "$git_minor" -lt 38 ]]; }; then
        die "git version must be >= 2.38 (found $git_version)"
    fi
    list_item "git $git_version ✓"

    # Check jj
    if ! command -v jj &>/dev/null; then
        die "jj is not installed"
    fi
    local jj_version
    jj_version=$(jj --version | head -1)
    list_item "$jj_version ✓"

    # Check we're in a jj repo
    if ! jj root &>/dev/null; then
        die "Not in a jj repository"
    fi
    list_item "jj repository ✓"

    echo ""

    # Check if remote already exists
    local remote="${JJ_SYNC_REMOTE:-origin}"
    if git remote get-url "$remote" &>/dev/null; then
        local url
        url=$(git remote get-url "$remote")
        log_info "Remote '$remote' already configured: $url"
    else
        log_info "Remote '$remote' not found."
        echo ""
        echo "To complete setup, add a personal remote:"
        echo ""
        echo "  jj git remote add $remote <your-remote-url>"
        echo ""
        echo "Example:"
        echo "  jj git remote add $remote git@github.com:username/repo-sync.git"
    fi

    echo ""
    log_info "Environment variables to set in your shell profile:"
    echo ""
    echo "  # Required for doc sync"
    echo "  export JJ_SYNC_DOCS=\"ai/docs .claude\""
    echo ""
    echo "  # Optional overrides"
    echo "  export JJ_SYNC_REMOTE=\"$remote\""
    echo "  export JJ_SYNC_MACHINE=\"$(hostname)\""
    echo ""

    log_success "Setup complete!"
}
