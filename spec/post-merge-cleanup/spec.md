# Feature: Post-Merge Cleanup Command

## Origin
After shipping via `/csw:ship` and merging the PR, there's routine git housekeeping that happens every time: pull main, delete the merged branch, verify issues closed. This was partially covered by the old `/cleanup` command, but its spec-deletion logic was absorbed into `/csw:spec` during the skill framework migration (#62). The git housekeeping didn't land anywhere, leaving a manual gap in the workflow.

## Outcome
Add `/csw:cleanup` as a post-merge command that automates the git housekeeping steps a developer does after every PR merge.

## User Story
As a developer who just merged a PR
I want to run a single command to clean up my local environment
So that I'm back on main with a clean state and ready for the next cycle

## Context

**Discovery**: User noticed they do the same post-merge steps every time — checkout main, pull, delete branch, check issues. The old `/cleanup` covered some of this but was removed because its primary purpose (spec deletion) moved into `/csw:spec`.

**Current state**: After merging a PR, the developer manually runs:
1. `git checkout main && git pull`
2. `git branch -d feature/whatever`
3. Checks GitHub to see if issues auto-closed
4. Optionally prunes stale remote refs

**Desired state**: `/csw:cleanup` handles all of this in one command.

## Technical Requirements

1. **Switch to main and pull**: `git checkout main && git pull origin main`
2. **Delete merged local branch**: Detect the branch we were on (or accept as argument), delete if merged
3. **Delete remote branch**: `git push origin --delete <branch>` if it still exists remotely
4. **Prune stale remote refs**: `git fetch --prune origin`
5. **Report GitHub issue status**: If `gh` CLI is available, check linked GitHub issues from the most recent merge commit and report their state (open/closed)
6. **Close Linear issues**: Scan the merged PR body and comments for Linear issue references (e.g., `ENG-123` or Linear URLs). For any that are still open, offer to transition them to Done via Linear MCP

### What this command does NOT do
- Spec directory cleanup (handled by `/csw:spec` preamble via `cleanup_completed_specs()`)
- Auto-merge PRs (`/csw:ship` creates the PR, user merges manually)
- Auto-tag releases (existing `auto_tag_release()` in lib/cleanup.sh — out of scope)

### Implementation approach
- Add `scripts/cleanup.sh` — the main script
- Add `cleanup` to the router case in `csw` (alongside spec|plan|build|check|ship)
- Add `commands/csw:cleanup.md` — the slash command definition
- Reuse existing helpers from `scripts/lib/git.sh` (`get_main_branch`, `get_current_branch`, `delete_merged_branch`, `sync_with_remote`)

### Behavioral details
- **Must be on a feature branch OR main**: If on main, skip checkout (just pull). If on a feature branch, switch to main first.
- **Branch argument is optional**: If not provided, detect from current branch before switching. If already on main, try to infer from last merge commit.
- **Safe by default**: Only delete branches confirmed merged. Warn (don't error) if remote branch already deleted.
- **gh CLI is optional**: GitHub issue status reporting is best-effort. Skip gracefully if `gh` is not installed or not authenticated.
- **Linear integration is optional**: If Linear MCP is available, scan PR for issue references and offer to close them. If Linear MCP is not configured, skip silently. This runs as part of the `/csw:cleanup` slash command (Claude handles the MCP calls), not the `csw cleanup` CLI script.

### Linear issue detection
- Match patterns: `TEAM-123` (uppercase letters + hyphen + digits), Linear URLs (`linear.app/*/issue/TEAM-123`)
- Scan: PR body and PR comments (via `gh api`)
- Action: For each open Linear issue found, report it and offer to transition to Done
- The script surfaces the issue identifiers; the slash command (`commands/csw:cleanup.md`) instructs Claude to use Linear MCP to check status and offer closure

## Validation Criteria

- [ ] Running `/csw:cleanup` on a feature branch switches to main and pulls
- [ ] Merged feature branch is deleted locally
- [ ] Remote feature branch is deleted (if it exists)
- [ ] Stale remote refs are pruned
- [ ] GitHub issue status is reported when `gh` is available
- [ ] Graceful behavior when `gh` is not available (skip GitHub issue check, no error)
- [ ] Linear issues mentioned in PR body/comments are detected and offered for closure when Linear MCP is available
- [ ] Graceful behavior when Linear MCP is not available (skip Linear check, no error)
- [ ] Running on main (no feature branch) still works — just pulls and prunes
- [ ] Unmerged branches are NOT deleted (safety check)

## Closes
- #63
