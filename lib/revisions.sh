# shellcheck shell=bash
# lib/revisions.sh - Revision sync implementation

# The revset for changes we want to sync
# mine() - authored by current user
# ~empty() - not empty
# ~immutable_heads() - not immutable (pushed/tagged)
# ~trunk() - not on trunk/main
SYNC_REVSET='mine() & ~empty() & ~immutable_heads() & ~trunk()'

# Push WIP revisions to the sync remote
push_revisions() {
    log_info "Pushing revisions..."

    local revs_prefix
    revs_prefix=$(get_revs_prefix)

    # Get list of changes to sync
    local changes=()
    local change_id
    while IFS= read -r change_id; do
        [[ -n "$change_id" ]] && changes+=("$change_id")
    done < <(jj log -r "$SYNC_REVSET" --no-graph -T 'change_id.short(12) ++ "\n"' 2>/dev/null)

    local change_count=${#changes[@]}

    if [[ $change_count -eq 0 ]]; then
        log_info "No WIP revisions to push"
        return 0
    fi

    verbose "Found $change_count changes to sync"

    # Prepare bookmark names (don't actually create jj bookmarks - we push directly)
    local bookmarks_to_push=()
    for change_id in "${changes[@]}"; do
        local bookmark_name="$revs_prefix/$change_id"
        bookmarks_to_push+=("$bookmark_name")
    done

    # Get list of current bookmarks on remote for this machine
    local remote_bookmarks=()
    local ref
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && remote_bookmarks+=("$ref")
    done < <(list_remote_refs "$revs_prefix/*")

    # Find stale bookmarks (on remote but not in current set)
    local stale_bookmarks=()
    for ref in "${remote_bookmarks[@]}"; do
        local is_current=false
        for bookmark in "${bookmarks_to_push[@]}"; do
            if [[ "$ref" == "$bookmark" ]]; then
                is_current=true
                break
            fi
        done
        if [[ "$is_current" == "false" ]]; then
            stale_bookmarks+=("$ref")
        fi
    done

    # Delete stale bookmarks from remote
    if [[ ${#stale_bookmarks[@]} -gt 0 ]]; then
        verbose "Deleting ${#stale_bookmarks[@]} stale bookmarks from remote"
        for ref in "${stale_bookmarks[@]}"; do
            verbose "Deleting remote: $ref"
            if ! is_dry_run; then
                delete_remote_ref "$ref"
            fi
        done
    fi

    # Push all bookmarks
    if [[ ${#bookmarks_to_push[@]} -gt 0 ]]; then
        verbose "Pushing ${#bookmarks_to_push[@]} bookmarks to remote"

        if ! is_dry_run; then
            # Get commit SHAs for each change and push directly via git
            # Push to refs/jj-sync/ namespace to avoid jj importing them as bookmarks
            # (which would make commits immutable)
            for bookmark in "${bookmarks_to_push[@]}"; do
                # Extract change_id from bookmark name
                local change_id="${bookmark##*/}"

                # Get the commit SHA for this change
                local commit_sha
                commit_sha=$(jj log -r "$change_id" --no-graph -T 'commit_id' 2>/dev/null) || continue

                verbose "Pushing: $bookmark ($commit_sha)"
                git_cmd push "$JJ_SYNC_REMOTE" "$commit_sha:refs/jj-sync/$bookmark" 2>/dev/null || {
                    log_warn "Failed to push bookmark: $bookmark"
                }
            done
        fi
    fi

    log_success "Pushed $change_count revision(s)"
}

# Pull WIP revisions from the sync remote
pull_revisions() {
    log_info "Pulling revisions..."

    detect_git_dir

    # Get the glob pattern for all machines' revision bookmarks
    local all_revs_glob
    all_revs_glob=$(get_all_revs_glob)

    # List all sync refs on remote
    local remote_refs=()
    local ref
    while IFS= read -r ref; do
        [[ -n "$ref" ]] && remote_refs+=("$ref")
    done < <(list_remote_refs "$all_revs_glob")

    if [[ ${#remote_refs[@]} -eq 0 ]]; then
        log_info "No revisions found on remote"
        return 0
    fi

    if is_dry_run; then
        log_info "[dry-run] Would fetch ${#remote_refs[@]} revision(s)"
        return 0
    fi

    # Fetch each ref and create temporary local bookmark refs so jj can see them
    verbose "Fetching commits from $JJ_SYNC_REMOTE"
    local temp_bookmarks=()
    for ref in "${remote_refs[@]}"; do
        local commit
        commit=$(git_cmd ls-remote "$JJ_SYNC_REMOTE" "refs/jj-sync/$ref" 2>/dev/null | cut -f1)
        if [[ -n "$commit" ]]; then
            verbose "Fetching: $ref ($commit)"
            # Create a temporary local branch so jj git import can see the commit
            local temp_bookmark="jj-sync-import/${ref//\//-}"
            git_cmd fetch "$JJ_SYNC_REMOTE" "$commit:refs/heads/$temp_bookmark" 2>/dev/null || true
            temp_bookmarks+=("$temp_bookmark")
        fi
    done

    # Import the fetched commits into jj (jj sees refs/heads/* as bookmarks)
    jj git import --quiet 2>/dev/null || true

    # Clean up temporary bookmarks (jj has already seen the commits)
    for temp_bookmark in "${temp_bookmarks[@]}"; do
        jj bookmark delete "$temp_bookmark" --quiet 2>/dev/null || true
    done
    jj git export --quiet 2>/dev/null || true

    # Group by machine for display
    # Ref format: sync/<user>/<machine>/revs/<change_id>
    declare -A machine_counts
    for ref in "${remote_refs[@]}"; do
        local machine
        machine=$(echo "$ref" | cut -d'/' -f3)
        machine_counts[$machine]=$(( ${machine_counts[$machine]:-0} + 1 ))
    done

    # Display summary
    log_info "Found revisions from ${#machine_counts[@]} machine(s):"
    for machine in "${!machine_counts[@]}"; do
        list_item "$machine: ${machine_counts[$machine]} revision(s)"
    done

    log_success "Pulled revisions from ${#machine_counts[@]} machine(s)"
}

# List WIP revisions that would be synced
list_sync_revisions() {
    jj log -r "$SYNC_REVSET" --no-graph -T 'change_id.short(12) ++ " " ++ commit_id.short(8) ++ "  " ++ if(description, description.first_line(), "(no description)") ++ "\n"' 2>/dev/null
}

# Count WIP revisions
count_sync_revisions() {
    jj log -r "$SYNC_REVSET" --no-graph -T 'change_id.short(12) ++ "\n"' 2>/dev/null | grep -c . || true
}
