#!/bin/bash
# Git operations

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Branch operations
get_current_branch() {
    git branch --show-current
}

get_main_branch() {
    # Detect main or master
    if git show-ref --verify --quiet refs/heads/main; then
        echo "main"
    elif git show-ref --verify --quiet refs/heads/master; then
        echo "master"
    else
        error "Could not find main or master branch"
        return 1
    fi
}

is_branch_merged() {
    local branch="$1"
    local main_branch
    main_branch=$(get_main_branch)
    git fetch origin >/dev/null 2>&1
    git branch -r --merged "origin/$main_branch" | grep -q "$branch"
}

create_feature_branch() {
    local feature="$1"
    local branch="feature/$feature"

    if git show-ref --verify --quiet "refs/heads/$branch"; then
        warning "Branch $branch already exists"
        git checkout "$branch"
    else
        info "Creating branch: $branch"
        git checkout -b "$branch"
    fi
}

delete_merged_branch() {
    local branch="$1"
    if is_branch_merged "$branch"; then
        info "Deleting merged branch: $branch"
        git branch -d "$branch" 2>/dev/null || git branch -D "$branch"
    else
        warning "Branch $branch is not fully merged, skipping delete"
    fi
}

# Merge detection
is_merge_commit() {
    local commit="${1:-HEAD}"
    local parents
    parents=$(git rev-list --parents -n 1 "$commit" | wc -w)
    [[ $parents -gt 2 ]]
}

extract_pr_from_commit() {
    local commit="${1:-HEAD}"
    local message
    message=$(git log -1 --format=%s "$commit")

    # Extract PR number from "Merge pull request #123"
    if [[ "$message" =~ Merge\ pull\ request\ \#([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # Extract PR number from squash merge "some message (#123)"
    if [[ "$message" =~ \(#([0-9]+)\)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

get_merge_commit_hash() {
    local commit="${1:-HEAD}"
    git rev-parse --short "$commit"
}

# Repository state
ensure_clean_working_tree() {
    if [[ -n $(git status --porcelain) ]]; then
        error "Working tree has uncommitted changes"
        git status --short
        return 1
    fi
}

sync_with_remote() {
    local branch="${1:-$(get_current_branch)}"
    info "Syncing with origin/$branch"
    git fetch origin
    git pull origin "$branch"
}

# High-level workflow
handle_branch_transition() {
    local new_feature="$1"
    local current_branch
    local main_branch

    current_branch=$(get_current_branch)
    main_branch=$(get_main_branch)

    if [[ "$current_branch" != "$main_branch" ]]; then
        # We're on a feature branch
        if is_branch_merged "$current_branch"; then
            info "Detected merged branch: $current_branch"
            # Archive will be called by plan.sh if needed
        fi

        info "Switching to $main_branch"
        git checkout "$main_branch"
        sync_with_remote "$main_branch"
        delete_merged_branch "$current_branch"
    else
        # Already on main, just sync
        sync_with_remote "$main_branch"
    fi

    create_feature_branch "$new_feature"
}
