# Implementation Plan: Cleanup GitHub Issue Close Prompt
Generated: 2026-03-24
Specification: spec.md

## Understanding
`/csw:cleanup` should prompt the user to close open GitHub issues referenced by the merged PR (via `Closes/Fixes/Resolves` keywords), then run `gh issue close` on confirmation. This makes GitHub issue handling symmetric with the existing Linear issue confirm-then-act flow. Most changes are already in the working tree.

## Relevant Files

**Files to Modify** (already modified in working tree):
- `scripts/lib/cleanup.sh` (lines 227-264) — `report_github_issues()` now emits `OPEN_GITHUB_ISSUES=`
- `commands/csw:cleanup.md` (lines 47-61) — new step 2 for GitHub issue close prompt

## Task Breakdown

### Task 1: Review existing changes to `scripts/lib/cleanup.sh`
**File**: `scripts/lib/cleanup.sh`
**Action**: REVIEW (already modified)

Verify `report_github_issues()` correctly:
- Tracks open issues in `open_issues` variable
- Prints `OPEN #NN: Title` for open issues (parseable by command)
- Emits `OPEN_GITHUB_ISSUES=<space-separated numbers>` at end

**Validation**: `shellcheck scripts/lib/cleanup.sh`

### Task 2: Review existing changes to `commands/csw:cleanup.md`
**File**: `commands/csw:cleanup.md`
**Action**: REVIEW (already modified)

Verify:
- Step 2 instructs Claude to parse `OPEN_GITHUB_ISSUES=` from script output
- Step 2 instructs Claude to present open issues and prompt for confirmation
- Step 2 instructs Claude to run `gh issue close <number>` on confirmation
- Steps 3-5 are correctly renumbered
- Output format section mentions GitHub issue closing in the summary example

### Task 3: Update Output Format section in command
**File**: `commands/csw:cleanup.md`
**Action**: MODIFY

The Output Format section (line 111-121) still shows `[Linear issue handling if applicable]` but doesn't mention GitHub issue handling. Update to reflect the new flow.

**Validation**: Read through the full command and verify consistency.

## VALIDATION GATES (MANDATORY)

After all tasks:
```bash
find . -name "*.sh" -not -path "*/\.*" -exec shellcheck {} +
```

No typecheck or test runner for this stack — shellcheck is the primary gate.

## Risk Assessment
- **Risk**: Edge case where `OPEN_GITHUB_ISSUES=` line could be confused with similar text in script output
  **Mitigation**: The line is emitted by controlled code, always on its own line with exact prefix. Low risk.

## Plan Quality Assessment

**Complexity Score**: 1/10 (LOW)
**Confidence Score**: 10/10 (HIGH)

**Confidence Factors**:
✅ Changes are already 90% complete in working tree
✅ Existing pattern to follow (Linear issue flow in same command)
✅ Simple parseable output format
✅ No new dependencies

**Estimated one-pass success probability**: 98%

**Reasoning**: Nearly all code is written. Remaining work is review, one small update to the output format section, and validation.
