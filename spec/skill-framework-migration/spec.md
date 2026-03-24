# Feature: Skill Framework Migration

## Metadata
**Type**: refactor
**Issues**: #52, #59, #60
**Closes**: #49

## Outcome
CSW uses Claude Code's native integration patterns — a SKILL.md for autonomous
discovery plus colon-namespaced slash commands — replacing the current flat
command file layout. The standalone `/cleanup` command is absorbed into
`/csw:spec` as a dirty-tree-guarded preamble.

## User Story
As a CSW user
I want commands namespaced under `csw:` with a skill file for autonomous invocation
So that CSW integrates cleanly with Claude Code's discovery system and doesn't
collide with other tools' command names.

## Context
**Current**: Six flat command files (`spec.md`, `plan.md`, etc.) installed to
`~/.claude/commands/`. No skill file. Cleanup is a standalone command that
requires a separate manual step between features. Version string in `csw`
script (0.2.2) is out of sync with VERSION file (0.3.2).

**Desired**: Dual-layer architecture — `SKILL.md` for autonomous/manual
invocation + five `csw:*.md` namespaced commands. Cleanup absorbed into spec
start. Version bumped to 0.3.0 everywhere.

**Discovery**: Claude Code discovers skills from `.claude/skills/*/SKILL.md`
automatically. Colon namespacing (`csw:plan`) is the community convention
for grouped commands (Claude Command Suite pattern).

## Technical Requirements

### 1. Create SKILL.md
- Path: `skills/csw/SKILL.md` (source), installed to `~/.claude/skills/csw/SKILL.md`
  or `.claude/skills/csw/SKILL.md` (project scope)
- Content: workflow description, trigger patterns, and pointers to the five
  slash commands
- Claude Code auto-discovers this and can invoke the full workflow or
  individual steps

### 2. Rename commands to colon namespace
| Old | New |
|-----|-----|
| `commands/spec.md` | `commands/csw:spec.md` |
| `commands/plan.md` | `commands/csw:plan.md` |
| `commands/build.md` | `commands/csw:build.md` |
| `commands/check.md` | `commands/csw:check.md` |
| `commands/ship.md` | `commands/csw:ship.md` |
| `commands/cleanup.md` | **(deleted)** |

### 3. Absorb cleanup into /csw:spec (from #59)
At the start of `/csw:spec`, before any spec creation:

**Step 1 — Dirty-tree guard:**
```bash
if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
    error "Uncommitted changes detected. Commit or stash before starting a new spec."
    exit 1
fi
```

**Step 2 — Clean completed specs:**
- Scan `spec/` for directories containing `log.md` (proof `/csw:build` completed)
- Skip `spec/backlog/`
- Delete completed spec directories, stage, commit as
  `chore: clean completed specs from previous cycle`

**Step 3 — Proceed with existing spec creation logic.**

Implementation:
- Extract `cleanup_completed_specs()` into `scripts/lib/cleanup.sh`
- Call from `scripts/spec.sh` after dirty-tree guard, before spec creation
- Replace `scripts/cleanup.sh` body with deprecation notice

### 4. Update `csw` CLI

**install** — Install skill + namespaced commands:
- Copy `skills/csw/SKILL.md` → `~/.claude/skills/csw/SKILL.md`
- Copy `commands/csw:*.md` → `~/.claude/commands/csw:*.md`
- Detect old un-namespaced files, warn user to run `csw migrate`

**init** — Project-scope install:
- Copy skill + commands to `.claude/` in target project
- `spec/` directory setup unchanged

**uninstall** — Remove both layers:
- Remove `~/.claude/skills/csw/` directory
- Remove `~/.claude/commands/csw:*.md` files
- Remove `~/.local/bin/csw` symlink

**migrate** — New subcommand:
- Remove old un-namespaced command files from `~/.claude/commands/`
  (`spec.md`, `plan.md`, `build.md`, `check.md`, `ship.md`, `cleanup.md`)
- Report what was removed

**cleanup** (CLI passthrough) — Print deprecation notice:
- "cleanup is now integrated into /csw:spec. Run csw spec instead."

### 5. Version
- Bump VERSION to 0.3.0
- Fix `csw --version` to read from VERSION file instead of hardcoded string

### 6. What's NOT carried forward from /cleanup
- `cleanup_merged_branches` — git housekeeping, not spec lifecycle
- `cleanup/merged` staging branch pattern — no longer needed
- `git fetch --prune` / `git pull` — user's responsibility
- `SHIPPED.md` removal — retired artifact

### 7. Documentation
- Update README.md: new command names, dual architecture
- Update CHANGELOG.md: v0.3.0 entry with breaking changes
- Update spec/README.md template: reference `csw:` commands
- Fix log.md gitignore documentation (#48)
- Fix version inconsistency (was #44)

## Validation Criteria
- [ ] `csw install` installs SKILL.md to `~/.claude/skills/csw/SKILL.md`
- [ ] `csw install` installs `csw:*.md` to `~/.claude/commands/`
- [ ] `csw install` warns if old un-namespaced files detected
- [ ] `csw migrate` removes old command files cleanly
- [ ] `csw init <dir>` installs skill + commands at project scope
- [ ] `csw uninstall` removes skill dir + namespaced commands
- [ ] `csw --version` outputs `csw 0.3.0`
- [ ] `/csw:spec` rejects dirty working tree
- [ ] `/csw:spec` cleans completed specs (those with log.md) before creating new spec
- [ ] `/csw:spec` skips `spec/backlog/` during cleanup
- [ ] `csw cleanup` prints deprecation notice
- [ ] No old command file references remain in codebase
- [ ] shellcheck passes on all modified scripts

## Success Metrics
- [ ] Clean install on fresh system works end-to-end
- [ ] Existing user can `csw migrate && csw install` without manual steps
- [ ] All six validation criteria for cleanup absorption pass
- [ ] `csw init` in a new project creates working `.claude/` layout

## References
- Issue #52: Skill framework migration (parent)
- Issue #59: Cleanup absorption
- Issue #60: v0.3.0 release checklist
- Issue #48: log.md gitignore documentation
- Issue #49: Plan command rename (resolved by namespace)
- Issue #51: Autonomous pipeline (skill framework portion)
