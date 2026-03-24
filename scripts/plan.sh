#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/git.sh"
source "$SCRIPT_DIR/lib/cleanup.sh"

# /plan command - Git setup and planning workflow
# Handles branch creation/renaming and commits planning artifacts

setup_feature_branch() {
    local spec_file="$1"
    local spec_dir
    local feature_name
    local current_branch
    local main_branch

    # Extract feature name from spec path
    # Example: spec/auth/spec.md → feature_name="auth"
    # Example: spec/frontend/auth/spec.md → feature_name="frontend-auth"
    spec_dir=$(dirname "$spec_file")
    feature_name=$(echo "$spec_dir" | sed 's|^spec/||' | tr '/' '-')

    current_branch=$(get_current_branch)
    main_branch=$(get_main_branch)

    info "Setting up feature branch for: $feature_name"
    echo ""

    # Branch transition logic
    if [[ $current_branch == "$main_branch" ]] || [[ $current_branch == "master" ]]; then
        # Standard path - create new branch from main
        info "🌿 Creating feature/$feature_name from $current_branch"
        git checkout -b "feature/$feature_name"
        success "✅ Feature branch created"

    elif [[ $current_branch == feature/* ]]; then
        # Already on a feature branch - check if it's for this feature
        if [[ $current_branch == "feature/$feature_name" ]]; then
            info "ℹ️  Already on feature/$feature_name"
        else
            warning "⚠️  Currently on: $current_branch"
            error "❌ Cannot create plan - already on a different feature branch"
            echo ""
            echo "Options:"
            echo "  1. Finish current feature: /csw:build → /csw:ship → merge PR"
            echo "  2. Switch to main: git checkout $main_branch"
            exit 1
        fi

    else
        # Unknown branch - warn user
        warning "⚠️  Currently on: $current_branch"
        warning "⚠️  Recommended: Switch to $main_branch first"
        echo ""
        read -p "Create feature/$feature_name from current branch anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            error "❌ Planning cancelled"
            exit 1
        fi
        git checkout -b "feature/$feature_name"
    fi

    echo ""
}

commit_planning_artifacts() {
    local spec_file="$1"
    local spec_dir
    local feature_name

    spec_dir=$(dirname "$spec_file")
    feature_name=$(basename "$spec_dir")

    info "💾 Committing planning artifacts..."

    # Stage the planning artifacts
    git add "$spec_dir/spec.md" "$spec_dir/plan.md" 2>/dev/null || true

    # Commit if there are changes
    if ! git diff --cached --quiet; then
        git commit -m "plan: $feature_name implementation"
        success "✅ Planning artifacts committed"
    else
        info "ℹ️  No changes to commit (artifacts already committed)"
    fi
}

main() {
    local spec_file="${1:-}"

    if [[ -z "$spec_file" ]]; then
        # No spec file provided - list all available specs for Claude to choose
        SPEC_DIR="$(get_spec_dir)"
        mapfile -t ALL_SPECS < <(find "$SPEC_DIR" -name "spec.md" 2>/dev/null || true)

        # Output each spec path
        for spec in "${ALL_SPECS[@]}"; do
            echo "$spec"
        done

        # Exit with count for easy detection
        exit "${#ALL_SPECS[@]}"
    fi

    # Spec file provided - do git setup and commit
    if [[ ! -f "$spec_file" ]]; then
        error "❌ Spec file not found: $spec_file"
        exit 1
    fi

    # Clean completed specs from previous cycle (same as /csw:spec preamble)
    cleanup_completed_specs || true

    setup_feature_branch "$spec_file"
    commit_planning_artifacts "$spec_file"
}

main "$@"
