# Implementation Plan: Post-Merge Cleanup Command
Generated: 2026-03-24
Specification: spec.md

## Understanding

Add `/csw:cleanup` as the missing post-merge step in the CSW lifecycle. After a developer merges a PR via GitHub, this command handles all git housekeeping (checkout main, pull, delete branch, prune refs) plus issue tracking integration (report GitHub issue status, offer to close Linear issues). The bash script handles git operations and issue detection; the slash command instructs Claude to use Linear MCP for issue closure.

Key design decisions from clarifying questions:
- **PR detection priority**: CLI argument → merge commit message → branch name lookup
- **Linear issues**: Always ask before closing (never auto-close)
- **Docs**: Update lifecycle diagram and command table to show cleanup as a post-merge step

## Relevant Files

**Reference Patterns** (existing code to follow):
- `scripts/spec.sh` — pattern for a workflow script (source libs, guard checks, main logic)
- `scripts/lib/git.sh` (lines 7-52) — branch helpers to reuse (`get_main_branch`, `get_current_branch`, `delete_merged_branch`, `sync_with_remote`)
- `scripts/lib/git.sh` (lines 62-73) — `extract_pr_from_commit()` for PR detection from merge commits
- `commands/csw:ship.md` — pattern for a slash command definition (persona, process, output format)
- `commands/csw:spec.md` — pattern for execution block at bottom of command

**Files to Create**:
- `scripts/cleanup.sh` — main cleanup script (git operations + issue detection)
- `commands/csw:cleanup.md` — slash command definition (orchestrates script + Linear MCP)

**Files to Modify**:
- `csw` (line 465) — add `cleanup` to router case
- `csw` (lines 29-34) — add cleanup to usage help
- `README.md` (lines 241-296) — add to command table, lifecycle diagram, and lifecycle description
- `spec/README.md` (lines 104-157) — add to command reference table and workflow diagram
- `skills/csw/SKILL.md` (lines 14-18) — add cleanup to workflow stages and quick start
- `CHANGELOG.md` — add entry for new command

## Architecture Impact
- **Subsystems affected**: CSW scripts, commands, CLI router, documentation
- **New dependencies**: None
- **Breaking changes**: None — purely additive

## Task Breakdown

### Task 1: Update extract_pr_from_commit() to handle squash merges
**File**: `scripts/lib/git.sh`
**Action**: MODIFY
**Pattern**: Extend existing function at lines 62-73

The current function only matches `Merge pull request #123`. GitHub squash merges produce `feat: some message (#123)`. Add a fallback pattern.

**Implementation**:
```bash
extract_pr_from_commit() {
    local commit="${1:-HEAD}"
    local message
    message=$(git log -1 --format=%s "$commit")

    # Match "Merge pull request #123"
    if [[ "$message" =~ Merge\ pull\ request\ \#([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # Match squash merge "some message (#123)"
    if [[ "$message" =~ \(#([0-9]+)\)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}
```

**Validation**: `bash -n scripts/lib/git.sh` passes.

### Task 2: Create scripts/cleanup.sh
**File**: `scripts/cleanup.sh`
**Action**: CREATE
**Pattern**: Follow `scripts/spec.sh` structure (source libs, main logic)

**Implementation**:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/git.sh"

# --- PR Detection (arg → merge commit → branch lookup) ---

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
            echo "📋 Linked GitHub Issues:"
            while IFS= read -r issue_num; do
                [[ -z "$issue_num" ]] && continue
                ISSUE_STATE=$(gh issue view "$issue_num" --json state --jq '.state' 2>/dev/null || echo "unknown")
                ISSUE_TITLE=$(gh issue view "$issue_num" --json title --jq '.title' 2>/dev/null || echo "")
                if [[ "$ISSUE_STATE" == "CLOSED" ]]; then
                    echo "  ✅ #$issue_num: $ISSUE_TITLE (closed)"
                else
                    echo "  ⚠️  #$issue_num: $ISSUE_TITLE ($ISSUE_STATE)"
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
        echo "🔗 Linear Issues Referenced:"
        echo "$LINEAR_REFS" | while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            echo "  - $ref"
        done
        echo ""
        echo "LINEAR_ISSUES=$LINEAR_REFS"
    fi
fi

echo ""
success "✅ Cleanup complete!"
if [[ -n "$FEATURE_BRANCH" ]]; then
    echo "  Branch: $FEATURE_BRANCH (deleted)"
fi
echo "  Now on: $main_branch (up to date)"
```

**Validation**: `bash -n scripts/cleanup.sh` passes.

### Task 3: Create commands/csw:cleanup.md
**File**: `commands/csw:cleanup.md`
**Action**: CREATE
**Pattern**: Follow `commands/csw:ship.md` structure (persona, process, output format, execution block)

**Implementation**: The slash command should:

1. Run the bash script to handle git operations
2. Parse script output for Linear issue references (look for `LINEAR_ISSUES=` line)
3. If Linear MCP is available and Linear issues were found:
   - For each issue, use `mcp__linear-server__get_issue` to check status
   - If any are still open, present them to the user and ask if they should be closed
   - On confirmation, use `mcp__linear-server__save_issue` to transition to Done
4. If Linear MCP is not available, skip silently

Key sections:
- Persona: DevOps Engineer (efficient, safe, automation-focused)
- Process: Run script → parse output → Linear MCP integration → summary
- Error handling: Graceful degradation at every step
- Execution block: `csw cleanup "$@"` (same pattern as other commands)

**Validation**: File exists and follows command format.

### Task 4: Add cleanup to csw CLI router and usage
**File**: `csw`
**Action**: MODIFY

**Change 1 — Usage help** (after line 34, add cleanup to Workflow Commands):
```
  cleanup                Post-merge housekeeping (branch cleanup, issue check)
```

**Change 2 — Router** (line 465, add `cleanup` to the case):
```bash
    spec|plan|build|check|ship|cleanup)
```

**Validation**: `bash -n csw` passes. `csw cleanup --help` routes correctly.

### Task 5: Update documentation
**Action**: MODIFY multiple files

**5a. README.md** — Command table (line 247), lifecycle (lines 255, 274-276, 280-287, 296):
- Add row: `| /csw:cleanup | **Clean up** - Post-merge branch cleanup + issue check | After merging PR |`
- Update lifecycle: `... → csw:ship → <merge> → csw:cleanup → repeat`
- Update mermaid diagram: add Cleanup node between Merge and Next
- Update cycle description: add step 7 for cleanup
- Update prose at line 296

**5b. spec/README.md** — Command reference table (line 110) and workflow diagram (lines 144-157):
- Add row: `| /csw:cleanup | Post-merge housekeeping | Cleans branches, checks issues |`
- Update sequenceDiagram: add cleanup step after merge

**5c. skills/csw/SKILL.md** — Workflow stages (line 18) and quick start (lines 23-27):
- Add stage 6: `6. **Cleanup** (\`/csw:cleanup\`) — Post-merge branch cleanup and issue check`
- Add to quick start: `/csw:cleanup              # Clean up after merge`
- Add to CLI line: `csw cleanup`

**5d. CHANGELOG.md** — Add entry at top for new version

**Validation**: All markdown renders correctly. Command table has consistent formatting.

### Task 6: Update TESTING.md
**File**: `TESTING.md`
**Action**: MODIFY

Add test cases:
- Test: `/csw:cleanup` from feature branch (switches to main, deletes branch)
- Test: `/csw:cleanup` from main (just pulls and prunes)
- Test: `/csw:cleanup 42` with explicit PR number
- Test: Unmerged branch safety (branch NOT deleted)
- Test: Without `gh` CLI (graceful skip of issue checks)

**Validation**: Test numbering is sequential, format matches existing tests.

### Task 7: Commit and validate
**Action**: Stage all changes, commit with conventional commit format.

**Validation**: `bash -n scripts/cleanup.sh && bash -n scripts/lib/git.sh && bash -n csw` all pass.

## Risk Assessment

- **Risk**: `extract_pr_from_commit` regex change could break existing callers
  **Mitigation**: Additive change only (new fallback pattern). Existing `Merge pull request #N` pattern still matched first. Only `scripts/lib/git.sh` defines this function; `scripts/cleanup.sh` is the only caller.

- **Risk**: Linear issue regex `[A-Z]{2,}-[0-9]+` matches non-Linear identifiers (e.g., `PR-123`, `WIP-1`)
  **Mitigation**: Acceptable false-positive rate for an interactive prompt. Claude will verify via Linear MCP before offering to close — if the identifier isn't a real Linear issue, the MCP call will fail gracefully.

- **Risk**: `git push origin --delete` could fail if branch is protected or already deleted
  **Mitigation**: Wrapped in `|| warning` — warns but doesn't exit. Pre-checked with `git ls-remote`.

## VALIDATION GATES (MANDATORY)

After EVERY code change, validate:
- Gate 1: `bash -n scripts/cleanup.sh` (syntax check)
- Gate 2: `bash -n scripts/lib/git.sh` (syntax check)
- Gate 3: `bash -n csw` (syntax check)

No lint/typecheck/test commands in `spec/stack.md` for this project (it's a bash tooling project), so syntax checks are the primary gate.

## Validation Sequence

After each task: `bash -n` on modified shell scripts
Final validation: Run `csw cleanup` in a test scenario

## Plan Quality Assessment

**Complexity Score**: 3/10 (LOW)
**Confidence Score**: 9/10 (HIGH)

**Confidence Factors**:
- ✅ Clear requirements from spec + clarifying questions
- ✅ Identical patterns exist for all file types (`spec.sh`, `csw:ship.md`, router)
- ✅ Existing git helpers cover most operations (`delete_merged_branch`, `sync_with_remote`, `extract_pr_from_commit`)
- ✅ Linear MCP integration is well-scoped (slash command only, not bash)
- ✅ No new dependencies
- ⚠️ Linear issue regex may need tuning based on real-world use

**Assessment**: Straightforward additive feature following established patterns. All building blocks exist.

**Estimated one-pass success probability**: 92%

**Reasoning**: Every file to create/modify has a direct reference pattern. The only uncertainty is the Linear issue regex matching quality, which is acceptable for an interactive (ask-first) workflow.
