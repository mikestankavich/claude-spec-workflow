# Implementation Plan: Skill Framework Migration
Generated: 2026-03-23
Specification: spec.md

## Understanding

Modernize CSW from flat command files to Claude Code's native dual-layer
architecture: a `SKILL.md` for autonomous discovery plus colon-namespaced
slash commands (`csw:spec`, `csw:plan`, etc.). Absorb the standalone
`/cleanup` command into `/csw:spec` as a dirty-tree-guarded preamble. Bump
version to 0.4.0. Clean break — no backward compatibility for `cleanup/merged`
branch pattern or old command names.

**Key decisions from clarifying questions:**
1. Version → 0.4.0 (since VERSION is already at 0.3.2)
2. SKILL.md at both scopes: `.claude/skills/csw/SKILL.md`
3. Clean break — remove `cleanup/merged` branch detection entirely
4. `csw:spec.md` describes full flow (dirty-tree guard → cleanup → spec creation)

## Relevant Files

**Reference Patterns** (existing code to follow):
- `csw` (lines 52-141) — install subcommand pattern (copy loop, symlink, reporting)
- `csw` (lines 142-375) — init subcommand pattern (directory creation, file copying)
- `csw` (lines 376-419) — uninstall subcommand pattern (removal loop, reporting)
- `scripts/cleanup.sh` (lines 57-84) — completed spec scanning logic (log.md detection)
- `scripts/lib/git.sh` (lines 81-87) — `ensure_clean_working_tree()` function
- `scripts/plan.sh` (lines 11-73) — branch transition logic

**Files to Create:**
- `skills/csw/SKILL.md` — skill definition for Claude Code discovery
- `commands/csw:spec.md` — renamed + enhanced spec command
- `commands/csw:plan.md` — renamed plan command
- `commands/csw:build.md` — renamed build command
- `commands/csw:check.md` — renamed check command
- `commands/csw:ship.md` — renamed ship command

**Files to Modify:**
- `csw` — install, init, uninstall, migrate, version, usage, cleanup deprecation
- `scripts/spec.sh` — dirty-tree guard + cleanup preamble
- `scripts/cleanup.sh` — replace with deprecation notice
- `scripts/lib/cleanup.sh` — add `cleanup_completed_specs()`
- `scripts/plan.sh` — remove `cleanup/merged` branch handling
- `VERSION` — bump to 0.4.0
- `README.md` — update command names, architecture description
- `CHANGELOG.md` — add 0.4.0 entry
- `TESTING.md` — update test procedures for new names
- `spec/README.md` — update command references

**Files to Delete:**
- `commands/spec.md` — replaced by `commands/csw:spec.md`
- `commands/plan.md` — replaced by `commands/csw:plan.md`
- `commands/build.md` — replaced by `commands/csw:build.md`
- `commands/check.md` — replaced by `commands/csw:check.md`
- `commands/ship.md` — replaced by `commands/csw:ship.md`
- `commands/cleanup.md` — absorbed into csw:spec, deleted

## Architecture Impact
- **Subsystems affected**: CLI script, command markdown, bash scripts/lib, docs
- **New dependencies**: none
- **Breaking changes**: old command names gone, /cleanup deprecated, cleanup/merged branch not detected

## Task Breakdown

### Task 1: Create skills/csw/SKILL.md
**File**: `skills/csw/SKILL.md`
**Action**: CREATE

Create the skill definition file. This is the source file stored in the CSW
repo. `csw install` copies it to `~/.claude/skills/csw/SKILL.md`; `csw init`
copies it to `.claude/skills/csw/SKILL.md` in the target project.

**Implementation**: Write a SKILL.md that describes:
- What CSW is (spec-driven development workflow)
- The five workflow stages (spec → plan → build → check → ship)
- When to trigger (user discusses features, asks about workflow, starts new work)
- Pointers to the five `csw:` slash commands
- Brief description of each command's role

**Validation**: File exists and is valid markdown.

---

### Task 2: Rename command files to colon namespace
**Files**: `commands/*.md` → `commands/csw:*.md`
**Action**: RENAME + DELETE

```bash
git mv commands/spec.md commands/csw:spec.md
git mv commands/plan.md commands/csw:plan.md
git mv commands/build.md commands/csw:build.md
git mv commands/check.md commands/csw:check.md
git mv commands/ship.md commands/csw:ship.md
git rm commands/cleanup.md
```

**Validation**: Old files gone, new files exist. `ls commands/` shows only `csw:*.md`.

---

### Task 3: Update csw:spec.md — add cleanup preamble
**File**: `commands/csw:spec.md`
**Action**: MODIFY

Add a new section before the existing "Process" that describes the preamble
behavior when invoked via `csw spec`:

1. **Dirty-tree guard**: Script checks for uncommitted changes and fails fast
2. **Clean completed specs**: Script scans for and removes spec dirs with `log.md`
3. Then proceeds to existing spec creation flow

Also update:
- Title/header references from `/spec` to `/csw:spec`
- Output paths from `spec/active/{feature}/` to `spec/{feature}/`
- Execution block to use `csw spec` (unchanged — CLI passthrough still works)
- Next step reference from `/plan` to `/csw:plan`

---

### Task 4: Update csw:plan.md — remove /cleanup references
**File**: `commands/csw:plan.md`
**Action**: MODIFY

Remove:
- The entire "Cleanup Shipped Features" section (Process step 2, lines 46-67)
  - Option A/B/C cleanup workflows are no longer relevant
  - Cleanup is now automatic at `/csw:spec` start
- References to `cleanup/merged` branch in "Branch Convention" section
- References to `/cleanup` command throughout

Update:
- All `/plan`, `/build`, `/check`, `/ship`, `/spec` → `/csw:plan`, `/csw:build`, etc.
- Branch Convention: remove `cleanup/merged` line, keep `feature/*` and `main`/`master`
- Execution block comment mentioning "fall back to project-local wrapper" is fine as-is

---

### Task 5: Update remaining command markdowns
**Files**: `commands/csw:build.md`, `commands/csw:check.md`, `commands/csw:ship.md`
**Action**: MODIFY

For each file:
- Update command references: `/plan` → `/csw:plan`, `/build` → `/csw:build`, etc.
- Update paths: `spec/active/{feature}/` → `spec/{feature}/`
- In csw:ship.md: remove SHIPPED.md references (lines 193, 200), remove `/cleanup`
  reference from "Note" at end of PR section
- Update `csw init` references in error messages (these are fine as-is)

---

### Task 6: Add cleanup_completed_specs() to scripts/lib/cleanup.sh
**File**: `scripts/lib/cleanup.sh`
**Action**: MODIFY

Add a new function extracted from `scripts/cleanup.sh` lines 57-84:

```bash
cleanup_completed_specs() {
    # Scan spec/ for directories containing log.md (proof of completion)
    # Skip spec/backlog/
    # Delete completed spec directories
    # Stage and commit as "chore: clean completed specs from previous cycle"
    # Returns 0 if changes committed, 1 if nothing to clean
}
```

Pattern: Follow the existing scan logic from `scripts/cleanup.sh` but:
- No `cleanup/merged` branch creation
- No branch management
- Just find → delete → stage → commit
- Silent if nothing to clean (info message only)

**Validation**: `bash -n scripts/lib/cleanup.sh` passes.

---

### Task 7: Update scripts/spec.sh — dirty-tree guard + cleanup
**File**: `scripts/spec.sh`
**Action**: MODIFY

Current script (25 lines) gets a preamble before the feature name parsing:

```bash
source "$SCRIPT_DIR/lib/git.sh"
source "$SCRIPT_DIR/lib/cleanup.sh"

# Step 1: Dirty-tree guard
if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    error "Uncommitted changes detected. Commit or stash before starting a new spec."
    exit 1
fi

# Step 2: Clean completed specs from previous cycle
cleanup_completed_specs
```

Then existing logic continues (parse feature name, create dir, copy template).

**Validation**: `bash -n scripts/spec.sh` passes.

---

### Task 8: Replace scripts/cleanup.sh with deprecation notice
**File**: `scripts/cleanup.sh`
**Action**: MODIFY (rewrite)

Replace the entire script body with:

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(dirname "$0")"
source "$SCRIPT_DIR/lib/common.sh"

warning "⚠️  /cleanup is deprecated and will be removed in a future version."
echo ""
echo "Cleanup is now integrated into /csw:spec."
echo "Completed specs are automatically cleaned at the start of each new spec cycle."
echo ""
echo "To clean up now, start a new spec:"
echo "  csw spec <feature-name>"
echo ""
exit 0
```

**Validation**: `bash -n scripts/cleanup.sh` passes.

---

### Task 9: Remove cleanup/merged branch handling from scripts/plan.sh
**File**: `scripts/plan.sh`
**Action**: MODIFY

In `setup_feature_branch()` (lines 31-35), remove the `cleanup/merged` case:

```bash
# REMOVE this block:
if [[ $current_branch == "cleanup/merged" ]]; then
    info "🔄 Renaming cleanup/merged → feature/$feature_name"
    git branch -m "feature/$feature_name"
    success "✅ Branch renamed for new feature"
```

Also in the `else` block (lines 58-70), remove the suggestion to "Run /cleanup":
```bash
# Change this:
warning "⚠️  Recommended: Run /cleanup or switch to $main_branch first"
# To this:
warning "⚠️  Recommended: Switch to $main_branch first"
```

And in the feature branch error message (lines 52-55), remove "/cleanup → /plan":
```bash
# Change option 2 from:
echo "  2. Clean up and start fresh: /cleanup → /plan"
# To:
echo "  2. Switch to main: git checkout $main_branch"
```

Remove option 3 (now redundant with updated option 2).

**Validation**: `bash -n scripts/plan.sh` passes.

---

### Task 10: Update csw — version handling + usage + cleanup deprecation
**File**: `csw`
**Action**: MODIFY

**Version** (line 430): Replace hardcoded version with:
```bash
--version|-v)
    version=$(cat "$CSW_HOME/VERSION" 2>/dev/null || echo "unknown")
    echo "csw $version"
    exit 0
    ;;
```

**Usage function** (lines 17-49): Update to reflect new command names:
- Remove `cleanup` from workflow commands
- Add note about `csw:` namespaced slash commands
- Add `migrate` to bootstrap commands
- Update examples

**Cleanup passthrough** (line 420): Split `cleanup` out of the command list:
```bash
spec|plan|build|check|ship)
    COMMAND="$1"
    shift
    exec "$SCRIPT_DIR/$COMMAND.sh" "$@"
    ;;
cleanup)
    # Deprecation — delegate to script which prints notice
    exec "$SCRIPT_DIR/cleanup.sh"
    ;;
```

**Validation**: `bash -n csw` passes.

---

### Task 11: Update csw — install subcommand
**File**: `csw` (lines 52-141)
**Action**: MODIFY

Changes to install:

1. **Install skill file** (new, before command loop):
```bash
# Install skill
CLAUDE_SKILLS_DIR="$HOME/.claude/skills/csw"
mkdir -p "$CLAUDE_SKILLS_DIR"
cp "$INSTALL_DIR/skills/csw/SKILL.md" "$CLAUDE_SKILLS_DIR/SKILL.md"
echo "   ✓ Installed SKILL.md"
```

2. **Change command source directory** — commands now have `csw:` prefix:
```bash
REPO_COMMANDS_DIR="$INSTALL_DIR/commands"
```
(This stays the same — the files in `commands/` are already renamed to `csw:*.md`)

3. **Detect old un-namespaced files** (after install loop):
```bash
OLD_COMMANDS=("spec.md" "plan.md" "build.md" "check.md" "ship.md" "cleanup.md")
old_found=0
for old_cmd in "${OLD_COMMANDS[@]}"; do
    if [ -f "$CLAUDE_COMMANDS_DIR/$old_cmd" ]; then
        old_found=$((old_found + 1))
    fi
done
if [ $old_found -gt 0 ]; then
    echo ""
    warning "⚠️  Found $old_found old un-namespaced command file(s)"
    echo "   Run: csw migrate"
fi
```

**Validation**: `bash -n csw` passes.

---

### Task 12: Update csw — init subcommand
**File**: `csw` (lines 142-375)
**Action**: MODIFY

After existing file copying (line 287), add skill + command installation
for project scope:

```bash
# Install skill and commands at project scope
echo "📦 Installing Claude skill and commands..."
PROJ_SKILLS_DIR="$PROJECT_DIR/.claude/skills/csw"
PROJ_COMMANDS_DIR="$PROJECT_DIR/.claude/commands"
mkdir -p "$PROJ_SKILLS_DIR"
mkdir -p "$PROJ_COMMANDS_DIR"
cp "$CSW_HOME/skills/csw/SKILL.md" "$PROJ_SKILLS_DIR/SKILL.md"
echo "   ✓ .claude/skills/csw/SKILL.md"
for cmd in "$CSW_HOME/commands"/csw:*.md; do
    if [ -f "$cmd" ]; then
        filename=$(basename "$cmd")
        cp "$cmd" "$PROJ_COMMANDS_DIR/$filename"
        echo "   ✓ .claude/commands/$filename"
    fi
done
echo ""
```

Also update the success message tree display to show `.claude/` layout.

Update next-step hints from `/plan`, `/build` etc. to `/csw:plan`, `/csw:build`.

**Validation**: `bash -n csw` passes.

---

### Task 13: Update csw — uninstall subcommand
**File**: `csw` (lines 376-419)
**Action**: MODIFY

Update the `COMMANDS` array and add skill removal:

```bash
# Remove skill
CLAUDE_SKILLS_DIR="$HOME/.claude/skills/csw"
if [ -d "$CLAUDE_SKILLS_DIR" ]; then
    rm -rf "$CLAUDE_SKILLS_DIR"
    echo "   ✓ Removed skills/csw/"
fi

# Remove namespaced commands
COMMANDS=("csw:spec.md" "csw:plan.md" "csw:build.md" "csw:check.md" "csw:ship.md")
```

Also remove old un-namespaced files if present (belt and suspenders):
```bash
OLD_COMMANDS=("spec.md" "plan.md" "build.md" "check.md" "ship.md" "cleanup.md")
for cmd in "${OLD_COMMANDS[@]}"; do
    cmd_path="$CLAUDE_COMMANDS_DIR/$cmd"
    [ -f "$cmd_path" ] && rm "$cmd_path"
done
```

**Validation**: `bash -n csw` passes.

---

### Task 14: Add csw migrate subcommand
**File**: `csw`
**Action**: MODIFY

Add new case before the `help` case:

```bash
migrate)
    echo "🔄 Migrating Claude Spec Workflow"
    echo ""

    CLAUDE_COMMANDS_DIR="$HOME/.claude/commands"
    OLD_COMMANDS=("spec.md" "plan.md" "build.md" "check.md" "ship.md" "cleanup.md")
    removed=0

    for cmd in "${OLD_COMMANDS[@]}"; do
        cmd_path="$CLAUDE_COMMANDS_DIR/$cmd"
        if [ -f "$cmd_path" ]; then
            rm "$cmd_path"
            echo "   ✓ Removed old $cmd"
            removed=$((removed + 1))
        fi
    done

    if [ $removed -eq 0 ]; then
        echo "ℹ️  No old command files found"
    else
        echo ""
        echo "✅ Removed $removed old command file(s)"
    fi
    echo ""
    echo "💡 Next: Run 'csw install' to install new namespaced commands"
    exit 0
    ;;
```

**Validation**: `bash -n csw` passes.

---

### Task 15: Bump VERSION + fix #48
**Files**: `VERSION`, `CHANGELOG.md`, `TESTING.md`
**Action**: MODIFY

- Set `VERSION` to `0.4.0`
- CHANGELOG.md line 33: historical entry, leave as-is (was true at v0.1.0)
- TESTING.md: will be fully rewritten in Task 16

For #48 specifically: the `.gitignore` was already fixed (no log.md pattern).
The remaining stale references are in TESTING.md which gets overhauled as part
of the documentation update. Close #48 in the PR.

---

### Task 16: Update documentation
**Files**: `README.md`, `CHANGELOG.md`, `TESTING.md`, `spec/README.md`
**Action**: MODIFY

**CHANGELOG.md** — Add `[0.4.0]` section at top (before `[Unreleased]`):
```markdown
## [0.4.0] - 2026-03-23

### Breaking Changes
- Commands renamed to colon namespace: `/spec` → `/csw:spec`, etc.
- `/cleanup` deprecated — cleanup now runs automatically at start of `/csw:spec`
- `cleanup/merged` branch pattern removed
- Requires `csw migrate && csw install` for existing users

### Added
- SKILL.md for Claude Code autonomous discovery
- `csw migrate` subcommand for removing old command files
- Dirty-tree guard at start of `/csw:spec`
- Automatic cleanup of completed specs at start of each new spec cycle
- `csw --version` now reads from VERSION file

### Changed
- `csw install` now installs skill + namespaced commands
- `csw init` now installs `.claude/skills/` and `.claude/commands/` at project scope
- `csw uninstall` removes both skill and namespaced commands

### Removed
- Standalone `/cleanup` command (prints deprecation notice)
- `cleanup/merged` branch detection in `/csw:plan`
- Old un-namespaced command file installation
- SHIPPED.md references (already retired)

### Fixed
- `csw --version` was hardcoded to 0.2.2, now reads VERSION file
- Stale `spec/active/` path references in command docs (#48)
```

**README.md** — Update:
- Command table: `/spec` → `/csw:spec`, remove `/cleanup`
- Installation section: mention skill + commands dual architecture
- Quick start: update command names
- Remove `/cleanup` workflow section

**TESTING.md** — Update all test procedures:
- Test 1: verify `csw:*.md` files + `skills/csw/SKILL.md`
- Test 3: uninstall removes skill dir + namespaced commands
- Test 4: init creates `.claude/` layout
- Remove SHIPPED.md references
- Update all `spec/active/` paths to `spec/`
- Add Test: `csw migrate` removes old files
- Add Test: dirty-tree guard rejects dirty working tree
- Add Test: cleanup runs at spec start
- Update test checklist

**spec/README.md** — Update:
- Command Reference table: `/plan` → `/csw:plan`, etc.
- Remove `/cleanup` from lifecycle section
- Update workflow diagram: remove cleanup branch, show cleanup as part of `/csw:spec`
- Update "Zero-Arg Sequential Workflow" example
- Fix any remaining `spec/active/` references

**Validation**: All docs are valid markdown, no broken references.

## Risk Assessment

- **Risk**: Colon in filenames may cause issues on some platforms
  **Mitigation**: This is a well-established Claude Code community convention
  (spec-kit uses it). Works fine on macOS/Linux/WSL. Only raw Windows cmd.exe
  has issues, but CSW already requires bash.

- **Risk**: Users with old command files get confused by both old and new
  **Mitigation**: `csw install` detects old files and warns. `csw migrate`
  provides clean removal path.

- **Risk**: Breaking change disrupts existing workflow
  **Mitigation**: Only known users are Mike and Nick. Mike is driving this
  change. Nick will be notified.

## Integration Points
- No new dependencies
- No environment variables
- No config file changes beyond `.claude/` layout

## VALIDATION GATES (MANDATORY)

After EVERY script change, validate with:
- `bash -n <file>` — syntax check
- `shellcheck <file>` — lint (if available)

After all changes:
- `bash -n csw` — main script syntax
- `bash -n scripts/spec.sh` — spec script
- `bash -n scripts/cleanup.sh` — deprecation script
- `bash -n scripts/plan.sh` — plan script
- `bash -n scripts/lib/cleanup.sh` — cleanup lib

**Do not proceed to next task until current task validates.**

## Validation Sequence

After each task: `bash -n` on modified files

Final validation:
```bash
# Syntax check all scripts
for f in csw scripts/*.sh scripts/lib/*.sh; do
    bash -n "$f" && echo "✅ $f" || echo "❌ $f"
done

# Verify file layout
ls commands/          # Should show only csw:*.md
ls skills/csw/        # Should show SKILL.md
cat VERSION           # Should show 0.4.0

# Verify no old references
grep -r '/cleanup' commands/ --include="*.md" | grep -v deprecated | grep -v csw:spec
grep -r 'spec/active/' commands/ --include="*.md"
grep -r 'cleanup/merged' scripts/
```

## Plan Quality Assessment

**Complexity Score**: 5/10 (MEDIUM — formula inflated by file count, most work is mechanical)
**Confidence Score**: 9/10 (HIGH)

**Confidence Factors**:
✅ Clear requirements from spec + 4 clarifying questions answered
✅ All existing patterns fully understood (read every file)
✅ Community precedent (spec-kit uses identical pattern)
✅ Small codebase (~600 lines of bash)
✅ Most tasks are renames or mechanical updates
✅ No new dependencies or external integrations
⚠️ SKILL.md is new content (but just markdown, low risk)

**Assessment**: High-confidence mechanical migration with one creative task (SKILL.md authoring).

**Estimated one-pass success probability**: 90%

**Reasoning**: The only real risk is typos or missed references in documentation
updates. All structural changes follow existing patterns exactly. The SKILL.md
is new but low-risk since it's just descriptive markdown.
