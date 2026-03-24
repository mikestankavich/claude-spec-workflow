#!/bin/bash
# Cleanup operations for shipped features and post-merge housekeeping

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/git.sh"

# --- Spec cleanup (used by /csw:spec preamble) ---

cleanup_spec_directory() {
    local feature="$1"
    local spec_dir
    spec_dir="$(get_spec_dir)/$feature"

    if [[ -d "$spec_dir" ]]; then
        info "Cleaning up spec directory: $spec_dir"
        safe_delete "$spec_dir"
        success "Cleaned up $feature"
    else
        warning "Spec directory not found: $spec_dir"
    fi
}

cleanup_completed_specs() {
    # Scan spec/ for directories containing log.md (proof of completion)
    # Delete completed spec directories, stage, and commit
    # Returns 0 if changes committed, 1 if nothing to clean

    local cleaned_count=0
    local completed_specs
    completed_specs=$(find spec -name "log.md" -type f 2>/dev/null || true)

    if [[ -z "$completed_specs" ]]; then
        info "ℹ️  No completed specs to clean up"
        return 1
    fi

    while IFS= read -r log_file; do
        [[ -z "$log_file" ]] && continue
        local spec_dir
        spec_dir=$(dirname "$log_file")

        # Skip backlog
        if [[ "$spec_dir" =~ spec/backlog/ ]]; then
            continue
        fi

        echo "  ✓ Removing completed spec: $spec_dir (has log.md)"
        rm -rf "$spec_dir"
        cleaned_count=$((cleaned_count + 1))
    done <<< "$completed_specs"

    if [[ $cleaned_count -eq 0 ]]; then
        info "ℹ️  No completed specs to clean up"
        return 1
    fi

    # Stage and commit
    git add spec/ 2>/dev/null || true
    if ! git diff --cached --quiet; then
        git commit -m "chore: clean completed specs from previous cycle"
        success "✅ Cleaned $cleaned_count completed spec(s)"
        return 0
    fi

    return 1
}

auto_tag_release() {
    # Try VERSION file first
    if [[ -f "VERSION" ]]; then
        local version
        version=$(tr -d '[:space:]' < VERSION)
        local tag="v$version"

        if ! git tag | grep -q "^$tag$"; then
            info "Auto-tagging release: $tag"
            git tag "$tag"
            git push --tags
            success "Tagged $tag"
        else
            warning "Tag $tag already exists, skipping"
        fi
        return 0
    fi

    # Try package.json as fallback
    if [[ -f "package.json" ]] && command -v jq &>/dev/null; then
        local version
        version=$(jq -r '.version' package.json)
        if [[ "$version" != "null" ]]; then
            local tag="v$version"

            if ! git tag | grep -q "^$tag$"; then
                info "Auto-tagging release: $tag"
                git tag "$tag"
                git push --tags
                success "Tagged $tag"
            else
                warning "Tag $tag already exists, skipping"
            fi
            return 0
        fi
    fi

    warning "No VERSION or package.json found, skipping auto-tag"
    return 0
}

# --- Post-merge branch cleanup (used by /csw:cleanup) ---

cleanup_merged_branches() {
    # Delete local branches that have been merged to main.
    # Two methods: traditional merge detection + squash/rebase detection
    # via remote tracking branch deletion.
    local main_branch="$1"
    local deleted_count=0

    info "Deleting branches merged to $main_branch..."

    # Method 1: Delete branches merged via traditional merge commit
    local merged_branches
    merged_branches=$(git branch --merged "$main_branch" | grep -v -E '^\*|main|master' || true)

    if [[ -n "$merged_branches" ]]; then
        while IFS= read -r branch; do
            branch=$(echo "$branch" | xargs)  # trim whitespace
            if [[ -n "$branch" ]]; then
                info "Deleting: $branch (merged to $main_branch)"
                git branch -d "$branch" 2>/dev/null || true
                deleted_count=$((deleted_count + 1))
            fi
        done <<< "$merged_branches"
    fi

    # Method 2: Delete branches whose remote tracking branch was deleted
    # (handles squash merges and rebase merges)
    for branch in $(git branch --format='%(refname:short)'); do
        # Skip special branches
        if [[ "$branch" == "main" || "$branch" == "master" ]]; then
            continue
        fi

        # Skip if already deleted by Method 1
        if ! git show-ref --verify --quiet "refs/heads/$branch"; then
            continue
        fi

        # Get remote tracking information
        local remote_branch
        local remote_name
        remote_branch=$(git config --get "branch.$branch.merge" 2>/dev/null | sed 's|refs/heads/||') || true
        remote_name=$(git config --get "branch.$branch.remote" 2>/dev/null) || true

        if [[ -n "$remote_name" && -n "$remote_branch" ]]; then
            # Check if remote branch still exists
            local ls_exit=0
            git ls-remote --exit-code --heads "$remote_name" "$remote_branch" &>/dev/null || ls_exit=$?

            if [[ $ls_exit -eq 0 ]]; then
                # Remote exists, keep branch
                continue
            elif [[ $ls_exit -eq 2 ]]; then
                # Remote doesn't exist (squash/rebase merged), delete branch
                info "Deleting: $branch (remote deleted — likely squash-merged)"
                git branch -D "$branch" 2>/dev/null || true
                deleted_count=$((deleted_count + 1))
            else
                # Network error or auth failure
                warning "Skipping: $branch (could not verify remote status)"
            fi
        fi
    done

    if [[ $deleted_count -eq 0 ]]; then
        info "No merged branches to clean up"
    else
        success "Deleted $deleted_count branch(es)"
    fi
}

delete_remote_branch() {
    # Delete a remote branch if it still exists
    local branch="$1"

    if git ls-remote --heads origin "$branch" | grep -q "$branch"; then
        info "Deleting remote branch: origin/$branch"
        git push origin --delete "$branch" 2>/dev/null || warning "Could not delete remote branch (may already be deleted)"
    else
        info "Remote branch origin/$branch already deleted"
    fi
}

# --- Issue detection (used by /csw:cleanup) ---

detect_pr_number() {
    # Detect PR number from: argument → merge commit → branch lookup via gh
    # Echoes the PR number if found, empty string otherwise
    local arg="${1:-}"
    local feature_branch="${2:-}"

    # Method 1: Explicit argument
    if [[ -n "$arg" ]] && [[ "$arg" =~ ^[0-9]+$ ]]; then
        echo "$arg"
        return 0
    fi

    # Method 2: Extract from HEAD merge commit
    local pr_num
    pr_num=$(extract_pr_from_commit HEAD 2>/dev/null || true)
    if [[ -n "$pr_num" ]]; then
        echo "$pr_num"
        return 0
    fi

    # Method 3: Look up via gh CLI
    if [[ -n "$feature_branch" ]] && command -v gh &>/dev/null; then
        pr_num=$(gh pr list --head "$feature_branch" --state merged --json number --jq '.[0].number' 2>/dev/null || true)
        if [[ -n "$pr_num" ]]; then
            echo "$pr_num"
            return 0
        fi
    fi

    return 1
}

report_github_issues() {
    # Report status of GitHub issues linked to a PR via Closes/Fixes/Resolves
    local pr_number="$1"

    if ! command -v gh &>/dev/null; then
        return 0
    fi

    local pr_body
    pr_body=$(gh pr view "$pr_number" --json body --jq '.body' 2>/dev/null || true)
    [[ -z "$pr_body" ]] && return 0

    local issue_numbers
    issue_numbers=$(echo "$pr_body" | grep -oiE '(closes|fixes|resolves)\s+#[0-9]+' | grep -oE '[0-9]+' || true)
    [[ -z "$issue_numbers" ]] && return 0

    local open_issues=""
    echo ""
    echo "GitHub Issues:"
    while IFS= read -r issue_num; do
        [[ -z "$issue_num" ]] && continue
        local issue_state issue_title
        issue_state=$(gh issue view "$issue_num" --json state --jq '.state' 2>/dev/null || echo "unknown")
        issue_title=$(gh issue view "$issue_num" --json title --jq '.title' 2>/dev/null || echo "")
        if [[ "$issue_state" == "CLOSED" ]]; then
            echo "  CLOSED #$issue_num: $issue_title"
        else
            echo "  OPEN #$issue_num: $issue_title"
            open_issues="$open_issues $issue_num"
        fi
    done <<< "$issue_numbers"

    open_issues=$(echo "$open_issues" | xargs)
    if [[ -n "$open_issues" ]]; then
        echo ""
        echo "OPEN_GITHUB_ISSUES=$open_issues"
    fi
}

detect_linear_issues() {
    # Scan PR body and comments for Linear-style issue references (TEAM-123)
    # Echoes found references as LINEAR_ISSUES=... for the slash command to parse
    local pr_number="$1"

    if ! command -v gh &>/dev/null; then
        return 0
    fi

    local pr_body pr_comments review_comments all_text
    pr_body=$(gh pr view "$pr_number" --json body --jq '.body' 2>/dev/null || true)
    pr_comments=$(gh api "repos/{owner}/{repo}/pulls/$pr_number/comments" --jq '.[].body' 2>/dev/null || true)
    review_comments=$(gh pr view "$pr_number" --json comments --jq '.comments[].body' 2>/dev/null || true)
    all_text="$pr_body"$'\n'"$pr_comments"$'\n'"$review_comments"

    local linear_refs
    linear_refs=$(echo "$all_text" | grep -oE '[A-Z]{2,}-[0-9]+' | sort -u || true)
    if [[ -n "$linear_refs" ]]; then
        echo ""
        echo "Linear Issues Referenced:"
        echo "$linear_refs" | while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            echo "  - $ref"
        done
        echo ""
        echo "LINEAR_ISSUES=$linear_refs"
    fi
}

