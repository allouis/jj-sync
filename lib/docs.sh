# shellcheck shell=bash
# lib/docs.sh - Doc sync implementation

# Union merge two trees (when there's no common ancestor)
# Combines both trees (tree2 wins on conflicts)
# Usage: union_merge_trees <tree1> <tree2>
# Outputs: merged tree SHA
union_merge_trees() {
    local tree1="$1"
    local tree2="$2"

    verbose "union_merge_trees: tree1=$tree1 tree2=$tree2"

    # Use a temporary index for the merge
    # Note: We use git directly (not git_cmd) because git_cmd doesn't preserve GIT_INDEX_FILE
    local temp_index
    temp_index=$(mktemp)

    # Helper to run git with the temp index
    _git_with_index() {
        GIT_DIR="$GIT_DIR" GIT_INDEX_FILE="$temp_index" git "$@"
    }

    # Clear the index first
    _git_with_index read-tree --empty 2>/dev/null || true

    # Add all entries from tree1
    local count1=0
    while IFS=$'\t' read -r mode_type_sha path; do
        [[ -z "$path" ]] && continue
        local mode _type sha
        read -r mode _type sha <<< "$mode_type_sha"
        verbose "  Adding from tree1: $path"
        _git_with_index update-index --add --cacheinfo "$mode,$sha,$path" 2>/dev/null || true
        ((count1++)) || true
    done < <(git_cmd ls-tree -r "$tree1" 2>/dev/null)
    verbose "  tree1 had $count1 entries"

    # Add all entries from tree2 (overwrites tree1 entries on conflict)
    local count2=0
    while IFS=$'\t' read -r mode_type_sha path; do
        [[ -z "$path" ]] && continue
        local mode _type sha
        read -r mode _type sha <<< "$mode_type_sha"
        verbose "  Adding from tree2: $path"
        _git_with_index update-index --add --cacheinfo "$mode,$sha,$path" 2>/dev/null || true
        ((count2++)) || true
    done < <(git_cmd ls-tree -r "$tree2" 2>/dev/null)
    verbose "  tree2 had $count2 entries"

    # Write the combined tree
    local merged_tree
    merged_tree=$(_git_with_index write-tree 2>/dev/null)
    verbose "  merged_tree=$merged_tree"

    # Debug: show merged tree contents
    local merged_count
    merged_count=$(git_cmd ls-tree -r "$merged_tree" 2>/dev/null | wc -l | tr -d ' ')
    verbose "  merged tree has $merged_count entries"

    # Cleanup
    rm -f "$temp_index"

    echo "$merged_tree"
}

# Push gitignored docs to the sync remote
push_docs() {
    log_info "Pushing docs..."

    # Get docs directories
    local docs_dirs=()
    local dir
    while IFS= read -r dir; do
        [[ -n "$dir" ]] && docs_dirs+=("$dir")
    done < <(get_docs_dirs)

    if [[ ${#docs_dirs[@]} -eq 0 ]]; then
        log_warn "No doc directories configured"
        return 0
    fi

    # Check which directories exist and have files
    local valid_dirs=()
    local total_files=0
    for dir in "${docs_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local count
            count=$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$count" -gt 0 ]]; then
                valid_dirs+=("$dir")
                total_files=$((total_files + count))
                verbose "Found $count files in $dir"
            else
                verbose "Directory $dir is empty, skipping"
            fi
        else
            log_warn "Doc directory not found: $dir"
        fi
    done

    if [[ ${#valid_dirs[@]} -eq 0 ]]; then
        log_info "No doc files to push"
        return 0
    fi

    verbose "Total: $total_files files in ${#valid_dirs[@]} directories"

    if is_dry_run; then
        log_info "[dry-run] Would push $total_files files from: ${valid_dirs[*]}"
        return 0
    fi

    # Ensure git dir is detected
    detect_git_dir

    # Get the docs bookmark name
    local docs_bookmark
    docs_bookmark=$(get_docs_bookmark)

    # Fetch from remote to see latest state
    fetch_remote 2>/dev/null || true

    # Try to get OUR OWN previous docs commit (for parent chain)
    # Each machine maintains its own independent doc chain - merge happens on pull
    # Do NOT use other machines' docs as parent (that creates false ancestry)
    local parent_commit=""
    if parent_commit=$(get_remote_commit "$docs_bookmark" 2>/dev/null); then
        verbose "Found previous docs commit: $parent_commit"
    else
        verbose "No previous docs commit found (first push)"
    fi

    # Create tree from local doc files
    # Each machine pushes its own current state - merge happens on pull
    verbose "Creating tree from local doc files"
    local tree
    tree=$(create_tree_from_files "${valid_dirs[@]}")

    if [[ -z "$tree" ]]; then
        die "Failed to create tree from doc files"
    fi
    verbose "Created tree: $tree"

    # Create the docs commit
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local message="jj-sync docs $timestamp"

    local commit
    if [[ -n "$parent_commit" ]]; then
        commit=$(create_commit "$tree" "$message" "$parent_commit")
    else
        commit=$(create_commit "$tree" "$message")
    fi

    if [[ -z "$commit" ]]; then
        die "Failed to create docs commit"
    fi
    verbose "Created commit: $commit"

    # Push to remote using refs/jj-sync/ namespace (force push since we may replace the parent chain)
    verbose "Pushing docs to remote"
    if ! git_cmd push --force "$JJ_SYNC_REMOTE" "$commit:refs/jj-sync/$docs_bookmark" 2>/dev/null; then
        die "Failed to push docs"
    fi

    log_success "Pushed $total_files doc file(s)"
}

# Pull gitignored docs from the sync remote
pull_docs() {
    log_info "Pulling docs..."

    # Ensure git dir is detected
    detect_git_dir

    # Fetch from remote first
    verbose "Fetching from $JJ_SYNC_REMOTE"
    if ! is_dry_run; then
        fetch_remote 2>/dev/null || true
    fi

    # Get the glob pattern for all machines' docs bookmarks
    local all_docs_glob
    all_docs_glob=$(get_all_docs_glob)

    # List all docs bookmarks and get their commits
    local docs_refs=()
    local docs_commits=()
    local ref
    while IFS= read -r ref; do
        if [[ -n "$ref" ]]; then
            local commit
            commit=$(get_remote_commit "$ref" 2>/dev/null) || continue
            docs_refs+=("$ref")
            docs_commits+=("$commit")
        fi
    done < <(list_remote_refs "$all_docs_glob")

    if [[ ${#docs_refs[@]} -eq 0 ]]; then
        log_info "No docs found on remote"
        return 0
    fi

    verbose "Found ${#docs_refs[@]} docs bookmark(s): ${docs_refs[*]}"

    if is_dry_run; then
        log_info "[dry-run] Would pull docs from: ${docs_refs[*]}"
        return 0
    fi

    local final_commit
    local had_conflicts=false

    if [[ ${#docs_commits[@]} -eq 1 ]]; then
        # Single source - just use it directly
        final_commit="${docs_commits[0]}"
        verbose "Single docs source: ${docs_refs[0]}"
    else
        # Multiple sources - need to merge
        log_info "Merging docs from ${#docs_commits[@]} machines..."

        # Start with the first commit
        final_commit="${docs_commits[0]}"
        verbose "Starting merge with: ${docs_refs[0]}"

        # Merge in each subsequent commit
        for ((i=1; i<${#docs_commits[@]}; i++)); do
            local other_commit="${docs_commits[$i]}"
            local other_ref="${docs_refs[$i]}"

            verbose "Merging: $other_ref"

            # Find common ancestor
            local base
            base=$(find_merge_base "$final_commit" "$other_commit")

            local merged_tree
            if [[ -z "$base" ]]; then
                # No common ancestor - do a union merge by combining both trees
                verbose "No common ancestor with $other_ref, performing union merge"

                local tree_ours tree_theirs
                tree_ours=$(git_cmd rev-parse "$final_commit^{tree}" 2>/dev/null)
                tree_theirs=$(git_cmd rev-parse "$other_commit^{tree}" 2>/dev/null)

                merged_tree=$(union_merge_trees "$tree_ours" "$tree_theirs")
            else
                # Have common ancestor - use proper three-way merge
                # git merge-tree --write-tree takes just 2 commits and finds base automatically
                local merge_output
                if merge_output=$(git_cmd merge-tree --write-tree "$final_commit" "$other_commit" 2>&1); then
                    merged_tree="$merge_output"
                    verbose "Clean merge with $other_ref"
                else
                    # Conflicts - first line is tree SHA
                    merged_tree=$(echo "$merge_output" | head -1)
                    log_warn "Conflicts detected merging $other_ref"
                    had_conflicts=true
                fi
            fi

            # Create merge commit with both parents
            local timestamp
            timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            local message="jj-sync docs merge $timestamp"
            final_commit=$(create_commit "$merged_tree" "$message" "$final_commit" "$other_commit")
        done
    fi

    # Get list of files in the tree
    local tree_files
    tree_files=$(git_cmd ls-tree -r --name-only "$final_commit" 2>/dev/null)

    # Get the doc directories from the tree (top-level dirs)
    local doc_dirs=()
    local seen_dirs=""
    local file
    while IFS= read -r file; do
        local top_dir
        top_dir=$(echo "$file" | cut -d'/' -f1)
        if [[ ! "$seen_dirs" =~ (^|:)"$top_dir"(:|$) ]]; then
            doc_dirs+=("$top_dir")
            seen_dirs="${seen_dirs}:${top_dir}"
        fi
    done <<< "$tree_files"

    # Remove existing files in doc directories (to handle deletions)
    for dir in "${doc_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            verbose "Cleaning existing files in $dir"
            find "$dir" -type f -delete 2>/dev/null || true
        fi
    done

    # Extract the docs to working directory
    verbose "Extracting docs to working directory"
    extract_tree "$final_commit" "."

    # If we merged, push the merged state as our new docs
    if [[ ${#docs_commits[@]} -gt 1 ]]; then
        local our_docs_bookmark
        our_docs_bookmark=$(get_docs_bookmark)
        verbose "Pushing merged docs as $our_docs_bookmark"
        git_cmd push --force "$JJ_SYNC_REMOTE" "$final_commit:refs/jj-sync/$our_docs_bookmark" 2>/dev/null || true
    fi

    # Show what was extracted
    local extracted_files
    extracted_files=$(git_cmd ls-tree -r --name-only "$final_commit" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$had_conflicts" == "true" ]]; then
        log_warn "Pulled $extracted_files doc file(s) with CONFLICTS - check files for conflict markers"
    else
        log_success "Pulled $extracted_files doc file(s)"
    fi
}

# List doc directories and their file counts
list_doc_dirs() {
    local dir
    while IFS= read -r dir; do
        if [[ -d "$dir" ]]; then
            local count
            count=$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
            echo "$dir: $count files"
        else
            echo "$dir: (not found)"
        fi
    done < <(get_docs_dirs)
}

# Count total doc files
count_doc_files() {
    local total=0
    local dir
    while IFS= read -r dir; do
        if [[ -d "$dir" ]]; then
            local count
            count=$(find "$dir" -type f 2>/dev/null | wc -l | tr -d ' ')
            total=$((total + count))
        fi
    done < <(get_docs_dirs)
    echo "$total"
}
