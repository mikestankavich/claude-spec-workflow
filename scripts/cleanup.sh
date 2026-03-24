#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/git.sh"

# --- PR Detection (arg > merge commit > branch lookup) ---

PR_NUMBER=""
FEATURE_BRANCH=""

# Method 1: PR number as argument
if [[ -n "${1:-}" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
    PR_NUMBER="$1"
    info "Using PR #$PR_NUMBER from argument"
fi

# Detect current branch before switching
current_branch=$(get_current_branch)
main_branch=$(get_main_branch)

if [[ "$current_branch" != "$main_branch" ]]; then
    FEATURE_BRANCH="$current_branch"
fi

# --- Step 1: Switch to main and pull ---
if [[ "$current_branch" != "$main_branch" ]]; then
    info "Switching to $main_branch..."
    git checkout "$main_branch"
fi

info "Pulling latest changes..."
git pull origin "$main_branch"

# --- Step 2: Detect PR from merge commit (if not provided) ---
if [[ -z "$PR_NUMBER" ]]; then
    PR_NUMBER=$(extract_pr_from_commit HEAD 2>/dev/null || true)
    if [[ -n "$PR_NUMBER" ]]; then
        info "Detected PR #$PR_NUMBER from merge commit"
    fi
fi

# Method 3: Branch lookup via gh (if still no PR)
if [[ -z "$PR_NUMBER" ]] && [[ -n "$FEATURE_BRANCH" ]] && command -v gh &>/dev/null; then
    PR_NUMBER=$(gh pr list --head "$FEATURE_BRANCH" --state merged --json number --jq '.[0].number' 2>/dev/null || true)
    if [[ -n "$PR_NUMBER" ]]; then
        info "Found PR #$PR_NUMBER from branch $FEATURE_BRANCH"
    fi
fi

# --- Step 3: Delete merged local branch ---
if [[ -n "$FEATURE_BRANCH" ]]; then
    delete_merged_branch "$FEATURE_BRANCH"
fi

# --- Step 4: Delete remote branch ---
if [[ -n "$FEATURE_BRANCH" ]]; then
    if git ls-remote --heads origin "$FEATURE_BRANCH" | grep -q "$FEATURE_BRANCH"; then
        info "Deleting remote branch: origin/$FEATURE_BRANCH"
        git push origin --delete "$FEATURE_BRANCH" 2>/dev/null || warning "Could not delete remote branch (may already be deleted)"
    else
        info "Remote branch origin/$FEATURE_BRANCH already deleted"
    fi
fi

# --- Step 5: Prune stale remote refs ---
info "Pruning stale remote refs..."
git fetch --prune origin

# --- Step 6: Report GitHub issue status ---
if [[ -n "$PR_NUMBER" ]] && command -v gh &>/dev/null; then
    info "Checking GitHub issues linked to PR #$PR_NUMBER..."
    # Get PR body and extract "Closes #N" references
    PR_BODY=$(gh pr view "$PR_NUMBER" --json body --jq '.body' 2>/dev/null || true)
    if [[ -n "$PR_BODY" ]]; then
        ISSUE_NUMBERS=$(echo "$PR_BODY" | grep -oiE '(closes|fixes|resolves)\s+#[0-9]+' | grep -oE '[0-9]+' || true)
        if [[ -n "$ISSUE_NUMBERS" ]]; then
            echo ""
            echo "GitHub Issues:"
            while IFS= read -r issue_num; do
                [[ -z "$issue_num" ]] && continue
                ISSUE_STATE=$(gh issue view "$issue_num" --json state --jq '.state' 2>/dev/null || echo "unknown")
                ISSUE_TITLE=$(gh issue view "$issue_num" --json title --jq '.title' 2>/dev/null || echo "")
                if [[ "$ISSUE_STATE" == "CLOSED" ]]; then
                    echo "  CLOSED #$issue_num: $ISSUE_TITLE"
                else
                    echo "  $ISSUE_STATE #$issue_num: $ISSUE_TITLE"
                fi
            done <<< "$ISSUE_NUMBERS"
        fi
    fi
fi

# --- Step 7: Detect Linear issue references ---
if [[ -n "$PR_NUMBER" ]] && command -v gh &>/dev/null; then
    # Scan PR body + comments for Linear-style references (TEAM-123)
    PR_BODY=$(gh pr view "$PR_NUMBER" --json body --jq '.body' 2>/dev/null || true)
    PR_COMMENTS=$(gh api "repos/{owner}/{repo}/pulls/$PR_NUMBER/comments" --jq '.[].body' 2>/dev/null || true)
    REVIEW_COMMENTS=$(gh pr view "$PR_NUMBER" --json comments --jq '.comments[].body' 2>/dev/null || true)
    ALL_TEXT="$PR_BODY"$'\n'"$PR_COMMENTS"$'\n'"$REVIEW_COMMENTS"

    LINEAR_REFS=$(echo "$ALL_TEXT" | grep -oE '[A-Z]{2,}-[0-9]+' | sort -u || true)
    if [[ -n "$LINEAR_REFS" ]]; then
        echo ""
        echo "Linear Issues Referenced:"
        echo "$LINEAR_REFS" | while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            echo "  - $ref"
        done
        echo ""
        echo "LINEAR_ISSUES=$LINEAR_REFS"
    fi
fi

echo ""
success "Cleanup complete!"
if [[ -n "$FEATURE_BRANCH" ]]; then
    echo "  Branch: $FEATURE_BRANCH (deleted)"
fi
echo "  Now on: $main_branch (up to date)"
