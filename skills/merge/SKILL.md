---
name: merge
description: Merge the reviewed pull request for the current branch, then hand straight off to cleanup. Use when a human green-lights an open PR.
when_to_use: "go for merge", "diffs look good", "merge it", "ship it", "land it", "approved, merge"
argument-hint: "[pr-or-ticket-ref]"
---

# Merge a reviewed pull request

**Announce at start:** "Using csw:merge to land PR #<n>."

## Step 1: Resolve the PR

The invocation optionally carries one reference. **Bare `/csw:merge` is unchanged** — it means
the pull request for the current branch:

```bash
gh pr view --json number,title,url,isDraft,mergeable,mergeStateStatus,baseRefName,headRefName
```

**`/csw:merge <ref>` names the pull request, and the reference is not decorative.** Resolve it.
Never fall through to the current branch's PR because the reference was harder to read than
`gh pr view` with no argument.

- **A prefixed reference** — `ENG-92` — is a **ticket**. Resolve it to the PR that closes it,
  below.
- **A bare number, or `#92`, on `tracker: github`** is either an issue or a pull request.
  GitHub numbers both out of one sequence per repository, so the number is never ambiguous
  about which object it names — but you have to ask, and you have to ask about the **PR**:

  ```bash
  gh pr view 92 --json number,title,url,isDraft,mergeable,mergeStateStatus,baseRefName,headRefName
  ```

  It resolves, and 92 is the pull request. It fails with `Could not resolve to a PullRequest
  with the number of 92`, and 92 is an issue — resolve it to its PR below.

  **Do not run `gh issue view` to make this decision.** GitHub models a pull request as a kind
  of issue, so `gh issue view <n>` on a PR number *succeeds* and hands back the PR. Every
  number looks like an issue to it, which is why the discriminating question is the one asked
  above.

- **A bare number on any other tracker** is a PR number. There every ticket reference carries a
  prefix, so a bare number has nothing else it could mean.

### Ticket to pull request

```bash
gh issue view <n> --json closedByPullRequestsReferences
```

That field only sees pull requests linked by a closing keyword. `csw:work` writes `Closes
<TICKET>` **or** `Refs <TICKET>`, and a `Refs` body links nothing at all — so an empty result
is not yet an answer. Search before concluding there is no PR:

```bash
gh pr list --state open --search "<TICKET>" --json number,title,baseRefName,headRefName
```

### Then say which reading you used

Before anything is merged, **say which reading you used** and on what basis — "PR #92, from
issue #92", or "PR #92, named directly". A merge is one-way, and naming the object out loud is
what lets someone stop the run while stopping is still free.

### Stops

- **No PR for the current branch**, on a bare invocation. Say so and stop.
- **No PR for the ticket.** Say so and stop. Do not go looking for a plausible nearby branch.
- **More than one candidate.** List them and ask which to merge. Never pick.
- **The reference resolves to a PR that is not the current branch's PR.** Report both and ask.
  Neither one silently wins. A reference gets stated precisely when several PRs are open, which
  is exactly the situation in which quietly preferring one would do the most damage.
- **The PR is a draft.** Draft means the work told you it was not a merge candidate. Ask
  whether to mark it ready first.

## Step 2: Check that they actually said merge

A merge is one-way. These are green lights:

> go for merge · diffs look good · merge it · ship it · land it · approved, merge that

These are not:

> looks good · nice · that's better · ok · 👍

An ambiguous approval earns one clarifying question — "Merge PR #<n> (<title>) now?" — and
you wait for the answer. Do not merge on a maybe.

## Step 3: Check CI

```bash
gh pr checks --watch --fail-fast
```

- **Red** — stop. Report which checks failed and their output. Red CI ends the merge; it does
  not become a judgment call.
- **Pending** — report what is still running and ask whether to wait or stop. If they say
  wait, re-run `gh pr checks --watch --fail-fast` rather than idling.
- **Green** — continue.
- **No checks configured** — `gh pr checks` finds nothing to report. Absence of checks is not
  the same as passing checks. Say so, and ask before merging.

Also check `mergeStateStatus`:

| Status | Meaning | Action |
|---|---|---|
| `BEHIND` | The base branch moved since this PR was opened | Update the branch, let CI run again |
| `DIRTY` | The PR has merge conflicts | Stop and report them |
| `BLOCKED` | A protection requirement is unmet — typically a missing review | Stop and report what is required. Do not attempt the merge. |
| `UNSTABLE` | A non-required check is failing | Report which check, and ask before merging |
| `HAS_HOOKS`, `UNKNOWN`, or anything unrecognised | Does not map to a known case | Do not guess. Report the state and ask. |

## Step 4: Merge

```bash
gh pr merge <number> --merge --delete-branch
```

**Always `--merge`. Never `--squash`, never `--rebase`.** Cleanup finds stale branches with
`git for-each-ref --merged` (not the porcelain `git branch --merged`, which leaks a synthetic
detached-HEAD pseudo-entry), and a squash-merged branch is invisible to either — squashing here
quietly breaks the sweep that the next phase depends on.

Check whether the command actually succeeded — but do not read a non-zero exit as "the PR is
still open." `--delete-branch` also deletes the *local* branch, which runs `git checkout <base>`
then `git branch -D <branch>`, and this always runs from inside a worktree, where both of those
fail:

```
$ git checkout main
fatal: 'main' is already used by worktree at '/…/m'
$ git branch -D feat/x
error: cannot delete branch 'feat/x' used by worktree
```

So the PR can merge server-side while `gh pr merge` still returns non-zero for an unrelated
local-cleanup failure. Do not assume either outcome from the exit code alone — re-establish
ground truth:

```bash
gh pr view <number> --json state,mergedAt
```

`state: MERGED` means the merge succeeded regardless of what `gh pr merge` returned: proceed to
Step 5. Anything else — still `OPEN`, or `gh pr view` itself failing — means the merge genuinely
did not happen. Stop: report the error, leave the branch and the worktree exactly as they are,
and do not proceed to Step 5.

## Step 5: Chain into cleanup, but only after a confirmed merge

Cleanup is only ever entered after a confirmed merge — that is the invariant the next phase
relies on. If Step 4 did not confirm success, stop there; do not continue into Step 5.

Once the merge is confirmed, roughly always it is followed by cleanup: go straight into
**csw:cleanup** without asking.

The exception is when the human has explicitly said to stay put — "merge but leave the
worktree, I want to check something." Then say plainly that cleanup is being skipped and
that the worktree and branch are still there.

## Red flags

| Thought | Reality |
|---|---|
| "'Looks good' obviously means merge" | It might mean the diff reads well. Ask. |
| "One flaky check, the rest are green" | Red is red. Report it and stop. |
| "Squash keeps history tidy" | Squash breaks `git branch --merged`, which is how cleanup finds stale branches. `--merge`. |
| "I'll skip cleanup, they can do it later" | Later is when it turns into "why are we on this worktree?" Chain into it. |
| "The PR is a draft but the work looks done" | Draft was a deliberate signal. Ask before promoting it. |
| "The merge command ran, I can move on" | Check its exit status. A failed merge followed by cleanup anyway orphans the PR. |
| "No checks means nothing to block on" | Absence of checks isn't a green light. Ask before merging. |
| "They named a PR, but `gh pr view` already found one" | Then the stated reference was decorative and the transcript lies. Resolve what they said. |
| "The number they gave is the branch's PR anyway" | You know that only after resolving it. Resolve it, then say which reading you used. |
