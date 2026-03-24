#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/git.sh"
source "$SCRIPT_DIR/lib/cleanup.sh"

# Step 1: Dirty-tree guard
if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    error "Uncommitted changes detected. Commit or stash before starting a new spec."
    exit 1
fi

# Step 2: Clean completed specs from previous cycle
cleanup_completed_specs || true

# Parse arguments
FEATURE="$1"

if [[ -z "$FEATURE" ]]; then
    error "Usage: spec.sh <feature-name>"
    exit 1
fi

# Create directory under spec/ (not spec/active/)
SPEC_DIR="$(get_spec_dir)/$FEATURE"
ensure_directory "$SPEC_DIR"

# Copy template
TEMPLATE="$(get_project_root)/spec/template.md"
check_file_exists "$TEMPLATE" "Template not found"
cp "$TEMPLATE" "$SPEC_DIR/spec.md"

success "Created spec at $SPEC_DIR/spec.md"
