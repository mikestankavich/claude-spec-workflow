#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/git.sh"
source "$SCRIPT_DIR/lib/cleanup.sh"

# /csw:cleanup — Post-merge housekeeping
# Switches to main, deletes merged branches, prunes refs, reports issues

main() {
    # Capture current branch before switching
    local current_branch main_branch feature_branch=""
    current_branch=$(get_current_branch)
    main_branch=$(get_main_branch)

    if [[ "$current_branch" != "$main_branch" ]]; then
        feature_branch="$current_branch"
    fi

    # Step 1: Sync with main
    if [[ -n "$feature_branch" ]]; then
        info "Switching to $main_branch..."
        git checkout "$main_branch"
    fi
    info "Pulling latest changes..."
    git pull origin "$main_branch"

    # Step 2: Prune stale remote refs (before branch cleanup so Method 2 works)
    info "Pruning stale remote refs..."
    git fetch --prune origin

    # Step 3: Delete merged branches
    cleanup_merged_branches "$main_branch"

    # Step 4: Delete remote branch (if we know which one)
    if [[ -n "$feature_branch" ]]; then
        delete_remote_branch "$feature_branch"
    fi

    # Step 5: Detect PR and report issues
    local pr_number=""
    pr_number=$(detect_pr_number "${1:-}" "$feature_branch") || true

    if [[ -n "$pr_number" ]]; then
        info "Detected PR #$pr_number"
        report_github_issues "$pr_number"
        detect_linear_issues "$pr_number"
    fi

    # Summary
    echo ""
    success "Cleanup complete!"
    if [[ -n "$feature_branch" ]]; then
        echo "  Branch: $feature_branch (deleted)"
    fi
    echo "  Now on: $main_branch (up to date)"
}

main "$@"
