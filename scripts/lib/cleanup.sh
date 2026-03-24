#!/bin/bash
# Cleanup operations for shipped features

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/git.sh"

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

