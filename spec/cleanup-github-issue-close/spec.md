# Feature: Cleanup GitHub Issue Close Prompt

## Metadata
**Type**: fix

## Origin
Follow-on from `/csw:cleanup` (PR #64). During first real usage, we noticed the command only reports GitHub issue status but doesn't offer to close open issues — the confirmation-then-act pattern was only implemented for Linear.

## Outcome
`/csw:cleanup` prompts the user to close open GitHub issues referenced by the merged PR, symmetrically with how it already handles Linear issues.

## User Story
As a developer running `/csw:cleanup` after merging a PR
I want to be prompted to close any open GitHub issues the PR references (via Closes/Fixes/Resolves)
So that issue housekeeping is handled in one pass without switching to the browser

## Context
**Discovery**: First live run of `/csw:cleanup` showed `CLOSED #63` in output — but if the issue had been open, there was no prompt to close it. Linear had the full confirm-then-act flow; GitHub only had reporting.
**Current**: `report_github_issues()` reports state but doesn't surface open issues for action. Command definition has no GitHub close step.
**Desired**: Script emits `OPEN_GITHUB_ISSUES=<numbers>`, command parses it, prompts user, runs `gh issue close` on confirmation.

## Technical Requirements
- `report_github_issues()` in `scripts/lib/cleanup.sh` emits `OPEN_GITHUB_ISSUES=<space-separated numbers>` when any referenced issues are still open
- `commands/csw:cleanup.md` includes a step to parse `OPEN_GITHUB_ISSUES=`, present them to the user, and on confirmation run `gh issue close <number>`
- Step numbering in the command is updated (now 5 steps total)
- Graceful degradation: if `gh` is not available, skip silently (same as before)

## Changes (mostly complete)
- [x] `scripts/lib/cleanup.sh` — `report_github_issues()` emits `OPEN_GITHUB_ISSUES=`
- [x] `commands/csw:cleanup.md` — new step 2 for GitHub issue closing with user confirmation
- [x] `commands/csw:cleanup.md` — renumbered steps 3-5
- [ ] Verify no edge cases in the parseable output format
- [ ] Manual test of the prompt flow with an open issue

## Validation Criteria
- [ ] Running `/csw:cleanup` on a PR that references an open issue shows a prompt offering to close it
- [ ] Confirming the prompt runs `gh issue close` and reports success
- [ ] Declining the prompt skips closing without error
- [ ] Already-closed issues are reported as CLOSED with no prompt
- [ ] Missing `gh` CLI skips the entire flow silently

## Conversation References
- User feedback: "no prompt for closing github issue? did we only apply the confirmation to linear?"
- User intent: "i am expecting a prompt like 'PR says close #xx, please confirm', i select yes, claude code calls `gh issue close`"
- Design principle: GitHub issues via `gh issue close`, Linear issues via Linear MCP — symmetric confirm-then-act pattern
