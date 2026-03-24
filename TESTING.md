# Testing Guide

Manual test procedures to validate Claude Spec Workflow functionality.

## Prerequisites
- Claude Code installed and running
- Git installed
- Bash shell (Git Bash on Windows, native on macOS/Linux)

## Installation Tests

### Test 1: Fresh Installation (Unix)
```bash
cd claude-spec-workflow
./csw install
```

**Expected:**
- Skill installed to `~/.claude/skills/csw/SKILL.md`
- Commands (`csw:*.md`) copied to `~/.claude/commands/`
- `~/.local/bin/csw` symlink created
- Success message displayed

**Verify:**
```bash
ls -la ~/.claude/skills/csw/SKILL.md
ls -la ~/.claude/commands/ | grep "csw:"
```

### Test 2: Re-installation (Idempotency)
Run installation script again.

**Expected:**
- No errors
- Commands updated/overwritten
- Warning or confirmation message

### Test 3: Uninstallation
```bash
csw uninstall
```

**Expected:**
- Skill directory `~/.claude/skills/csw/` removed
- All `csw:*.md` commands removed from `~/.claude/commands/`
- Old un-namespaced files removed if present
- `~/.local/bin/csw` symlink removed
- Success message with count
- No errors if already uninstalled

## Project Initialization Tests

### Test 5: Initialize New Project
```bash
mkdir /tmp/test-project
cd /tmp/test-project
git init
csw init .
```

**Expected:**
- `.claude/skills/csw/SKILL.md` installed
- `.claude/commands/csw:*.md` installed
- `spec/` directory created
- `spec/template.md`, `spec/stack.md`, `spec/README.md` copied
- `spec/bootstrap/` created with validation spec
- `spec/csw` symlink created

**Verify:**
```bash
ls -la .claude/skills/csw/
ls -la .claude/commands/
ls -la spec/
```

### Test 6: Initialize with Different Preset
```bash
cd test-project
csw init . python-fastapi
```

**Expected:**
- `spec/stack.md` updated with Python/FastAPI preset
- Contains pytest, ruff commands
- Bootstrap spec created (or skipped with --no-bootstrap-spec)
- Success message displayed
- Prompts for confirmation if files exist

**Verify:**
```bash
cat spec/stack.md | grep "pytest"
cat spec/stack.md | grep "ruff"
```

### Test 7: View Available Presets
```bash
csw init . invalid-preset
```

**Expected:**
- Error message about invalid preset
- Lists all available presets:
  - typescript-react-vite
  - nextjs-app-router
  - python-fastapi
  - go-standard
  - monorepo-go-react
  - shell-scripts

## Command Workflow Tests

### Test 8: /csw:spec Command
In Claude Code:
```
/csw:spec test-feature

[Have a brief conversation about a simple feature]
```

**Expected:**
- Dirty-tree guard checks for uncommitted changes
- Completed specs cleaned automatically
- Claude analyzes conversation
- Generates draft specification
- Asks for confirmation
- Creates `spec/test-feature/spec.md`

**Verify:**
```bash
cat spec/test-feature/spec.md
```

### Test 9: /csw:plan Command
```
/csw:plan spec/test-feature/spec.md
```

**Expected:**
- Claude reads the spec
- Asks clarifying questions
- Generates implementation plan
- Creates `spec/test-feature/plan.md`
- Creates feature branch
- Commits plan

**Verify:**
```bash
cat spec/test-feature/plan.md
git branch | grep "feature/test-feature"
```

### Test 10: /csw:build Command
```
/csw:build spec/test-feature/
```

**Expected:**
- Loads spec and plan
- Executes tasks sequentially
- Creates `spec/test-feature/log.md`
- Runs validation after each change
- Updates log with progress

**Verify:**
```bash
cat spec/test-feature/log.md
```

### Test 11: /csw:check Command (No Stack Config)
In a project without `spec/stack.md`:
```
/csw:check
```

**Expected:**
- Error message: "Stack not configured"
- Suggests running csw init with preset
- Shows available presets
- Does not proceed without stack.md

### Test 12: /csw:check Command (With Stack Config)
In a project with `spec/stack.md`:
```
/csw:check
```

**Expected:**
- Reads stack.md for validation commands
- Runs lint, typecheck, test, build commands
- Shows comprehensive validation report
- Indicates PR readiness status

### Test 13: /csw:ship Command
```
/csw:ship spec/test-feature/
```

**Expected:**
- Runs `/csw:check` first
- Commits changes
- Pushes to remote
- Creates pull request (or provides instructions)

**Verify:**
```bash
git log -1
```

### Test 14: Dirty-tree Guard
With uncommitted changes:
```bash
echo "test" > /tmp/test-project/dirty-file.txt
git add dirty-file.txt
csw spec new-feature
```

**Expected:**
- Error: "Uncommitted changes detected"
- Does not proceed to spec creation

### Test 15: Automatic Cleanup at Spec Start
With a completed spec (has log.md) from a previous cycle:
```bash
csw spec next-feature
```

**Expected:**
- Completed specs (with log.md) are deleted automatically
- Commit created: "chore: clean completed specs from previous cycle"
- Then proceeds to create new spec

## Edge Case Tests

### Test 16: Missing spec/ Directory
Run `/csw:plan` in project without spec/ directory.

**Expected:**
- Clear error message
- Suggests running csw init
- Provides correct usage

### Test 17: Invalid Spec Path
```
/csw:plan spec/nonexistent/spec.md
```

**Expected:**
- Error: spec file not found
- Shows path that was tried
- Suggests checking path

### Test 18: Out-of-Order Commands
Try `/csw:build` before `/csw:plan`.

**Expected:**
- Error or warning about missing plan
- Suggests running /csw:plan first

### Test 19: Workspace Detection (Monorepo)
In monorepo with workspace in spec metadata:
```
/csw:build spec/backend-feature/
```

**Expected:**
- Detects "backend" workspace from metadata
- Uses backend-specific validation commands
- Reports workspace being used

## Cross-Platform Tests

### Test 20: Windows Path Handling
On Windows (Git Bash), test with forward slashes:
```
/csw:plan spec/test-feature/spec.md
```

**Expected:**
- Commands work correctly in Git Bash
- Forward slashes handled properly

### Test 21: Symlink Handling (Unix)
```bash
# Test that csw resolves symlinks correctly
ln -s ~/claude-spec-workflow/csw ~/test-csw
~/test-csw install
```

**Expected:**
- Installation works correctly
- csw resolves symlinks and finds its home directory
- Skill and commands installed correctly

### Test 22: Version
```bash
csw --version
```

**Expected:**
- Outputs `csw 0.4.0` (reads from VERSION file)

## Validation Tests

### Test 23: Preset Configuration Accuracy
For each preset, verify commands are correct:

```bash
# Test TypeScript preset
cd typescript-react-project
csw init . typescript-react-vite
npm run lint  # Should work
npm run typecheck  # Should work
npm test  # Should work
```

Repeat for all presets with appropriate projects.

### Test 24: Monorepo Configuration
```bash
cd monorepo-project
csw init . monorepo-go-react
```

**Verify:**
- `spec/stack.md` created with monorepo format
- All three workspaces defined (database, backend, frontend)
- Each workspace has validation commands
- Workspace sections use `## Workspace: [name]` headers
- Bootstrap spec created for monorepo validation

## Regression Tests

### Test 25: Existing Features Still Work
After any changes, verify:
- All installation scripts work
- All commands execute
- Documentation is accurate
- Examples are valid

## Test Checklist Summary

- [ ] Unix installation works (skill + commands)
- [ ] Windows installation works
- [ ] Uninstallation removes skill + commands
- [ ] Migration removes old files
- [ ] Project initialization creates `.claude/` layout
- [ ] Bootstrap spec generation works
- [ ] Fuzzy preset matching works
- [ ] Stack configuration works
- [ ] All commands execute successfully (csw:spec, csw:plan, csw:build, csw:check, csw:ship)
- [ ] Dirty-tree guard rejects dirty working tree
- [ ] Cleanup runs at spec start
- [ ] Cleanup deprecation notice works
- [ ] Version reads from VERSION file
- [ ] Error handling is clear
- [ ] Cross-platform compatibility verified
- [ ] Presets are accurate
- [ ] Documentation matches behavior

## Reporting Issues

If any test fails:
1. Note the test number and name
2. Record exact error message
3. Include OS and shell version
4. Attach relevant logs
5. Open issue at https://github.com/trakrf/claude-spec-workflow/issues
