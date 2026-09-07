---
name: merge
description: Merge the reviewed pull request for the current branch, then hand straight off to cleanup. A sentence of editorial direction alongside the green light is read as a rider. Use when a human green-lights an open PR.
when_to_use: "go for merge", "diffs look good", "merge it", "ship it", "land it", "approved, merge", "go for merge — reviewed the ADR, all good"
argument-hint: "[pr-or-ticket-ref] [editorial rider]"
---

# Merge a reviewed pull request

**Announce at start:** "Using csw:merge to land PR #<n>." Where the invocation carried an
editorial rider — Step 1 — echo it verbatim on that same line: `— rider: "<what they wrote>"`.

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

### Then read what is left over: the rider

**Consume the known tokens first** — the reference Step 1 just resolved, and the phrasing Step 2
checks for. Then read whatever is left, by word count. `csw:work` parses its own invocation the
same way; one grammar, both skills:

| Remainder | Reading |
|---|---|
| Nothing | No rider. |
| **One word** | Suspected typo. Say what was passed, say it is not recognised, and ask. |
| **Two or more words** | An **editorial rider**. Accept it. |

`go for merge — reviewed the ADR, all good` is the shape this exists for: `go for merge` is the
green light Step 2 is looking for, and `reviewed the ADR, all good` is the rider. Splitting on
word count keeps the reading mechanical, and therefore testable — it is not a judgement about
whether something *sounds like* direction.

**A rider is echoed in the announce line, always:**

> Using csw:merge to land PR #92 — rider: "reviewed the ADR, all good"

A rider that quietly changes what a merge does is the failure this must not introduce, and a
merge is one-way. Visible at the top of the run is the price of accepting it at all.

#### A rider is context, never authority

- **It cannot green-light red CI**, skip a gate, or waive validation. **Step 3 is untouched:**
  "CI is flaky, ignore the failing check" is named and refused, exactly as it would be without
  a rider. Red is still red.
- **It cannot substitute for the diff, or for the ticket behind it.** A rider is a note in the
  margin of what was reviewed, not a replacement for it, and it never stands in for reading the
  ticket.
- **It is not the green light.** Step 2 is unchanged: an ambiguous approval still earns its one
  clarifying question, and a rider riding along with a maybe does not turn it into a yes.
- **A rider that contradicts the ticket, or a decision recorded in a `**CSW prep**` comment, is
  named back and asked about** — not silently preferred, and not silently dropped. Prep's
  decisions carry their reasoning precisely so they can be overturned deliberately.

#### What a rider can do: review testimony

A rider is **review testimony**, and that is a real role rather than a consolation prize. It is
the kind of thing a person says at the moment of merging, having just read the diff — and the
ADR acknowledgment in Step 4 is the one gate in this skill whose entire question is *did a human
look at this?*

So a rider that says the ADR was read satisfies that acknowledgment.
**That is its only authority.** Nothing else in this skill takes a rider on trust.

## Step 2: Check that they actually said merge

A merge is one-way. These are green lights:

> go for merge · diffs look good · merge it · ship it · land it · approved, merge that

These are not:

> looks good · nice · that's better · ok · 👍

An ambiguous approval earns one clarifying question — "Merge PR #<n> (<title>) now?" — and
you wait for the answer. Do not merge on a maybe.

## Step 3: Check CI

Pass the number Step 1 resolved. Bare `gh pr checks` reads the *current branch's* PR, which is
the right answer only when nobody named anything — and silently the wrong PR's CI the moment
someone did:

```bash
gh pr checks <number> --watch --fail-fast
```

- **Red** — stop. Report which checks failed and their output. Red CI ends the merge; it does
  not become a judgment call.
- **Pending** — report what is still running and ask whether to wait or stop. If they say
  wait, re-run `gh pr checks <number> --watch --fail-fast` rather than idling.
- **Green** — continue.
- **No checks configured** — `gh pr checks` finds nothing to report. Absence of checks is not
  the same as passing checks. Say so, and ask before merging.

Also check `mergeStateStatus`:

| Status | Meaning | Action |
|---|---|---|
| `BEHIND` | The base branch moved since this PR was opened | Update the branch, let CI run again |
| `DIRTY` | The PR has merge conflicts | Stop and report them |
| `BLOCKED` | A protection requirement is either pending or unmeetable — the status does not say which | Diagnose it, below. Do not merge, and do not ask a question the API can answer. |
| `UNSTABLE` | A non-required check is failing | Report which check, and ask before merging |
| `HAS_HOOKS`, `UNKNOWN`, or anything unrecognised | Does not map to a known case | Do not guess. Report the state and ask. |

### `BLOCKED` is two states, and the API tells you which

`BLOCKED` covers both *a requirement that will be satisfied later* and *a requirement that will
never be satisfied at all*, and the status alone cannot distinguish them. Guessing "typically a
missing review" is how this step used to send someone to a Step 4 that had exactly one command,
which then failed.

Ask what is actually protecting the base branch. Both probes are **read-only** — a speculative
`gh pr merge` is not the diagnosis, because Step 4's gates have not run yet and a probe that
succeeds would land the merge ahead of them:

```bash
gh api repos/:owner/:repo/rules/branches/<baseRefName>
```

That lists every rule applying to the base, each with the `ruleset_id` it came from. For a rule
that names a ruleset, ask who is allowed past it:

```bash
gh api repos/:owner/:repo/rulesets/<ruleset_id> --jq '{name,enforcement,bypass_actors}'
```

The answer sorts the block into one of two shapes, and they are not interchangeable:

- **`--auto` — the requirement is pending.** A review requested but not yet given, a required
  check still queued. Nothing is overridden: GitHub holds the merge and lands it once the
  requirement is met. Offer this when the block is something that arrives on its own, and say
  plainly that the merge will then happen later and unattended, with nobody looking again.
- **`--admin` — the requirement is unmet and no waiting will change that.** Observed merging
  #86: CI green, `required_approving_review_count` 0, no unresolved threads, branch 0 behind.
  The block was a repository ruleset whose only bypass actor was the admin running the merge.
  There was nothing to wait for; the merge either used the bypass or did not happen.
  `bypass_actors` is what tells you this shape apart from the first — if it does not list an
  actor the invoker is, `--admin` will not work either, and the honest report is that this PR
  cannot be merged by this account.

**`--admin` overrides a protection someone configured deliberately.**
**It is never yours to take.**
Report what is blocking, say which of the two shapes it is and on what evidence, and ask.

What the diagnosis buys is a question that can actually be answered — "the `non_fast_forward`
rule blocks this and you are its bypass actor, merge with `--admin`?" rather than "it says
`BLOCKED`, what do you want to do?"

Once the human authorises one, it goes on Step 4's command. `gh` rejects `--auto` and `--admin`
together — they are answers to different questions — and `--admin` is the flag for *not meeting*
the requirements, so it is only ever reached with the rest of Step 3 already green. It silences
the block, not the reason for it.

## Step 4: Merge

### Before the merge: retarget anything stacked on this branch

`--delete-branch` removes the head branch, and **GitHub does not retarget a pull request whose
base branch disappears — it closes it.** Observed merging a PR that had another stacked on it:
the dependent went to `state: CLOSED`, still pointing at a branch that no longer existed, and
reported `CONFLICTING` for a conflict it did not have.

Look for dependents first:

```bash
gh pr list --state open --base "<this PR's headRefName>" --json number,title,headRefName,baseRefName
```

Anything that comes back is stacked on the branch about to be deleted. Retarget each one onto
this PR's own base **before** merging:

```bash
gh pr edit <dependent number> --base "<this PR's baseRefName>"
```

Then say which PRs were retargeted and onto what. A silently rebased stack is the same problem
as a silently chosen PR: correct, and invisible to anyone who would have wanted to disagree.

**This has to happen before the merge, because afterwards it does not work.** Both obvious
repairs refuse while the base branch is missing:

```
$ gh pr edit 558 --base main
GraphQL: Cannot change the base branch of a closed pull request.

$ gh pr reopen 558
API call failed: GraphQL: Could not open the pull request.
```

The PR is closed, so its base cannot be changed; it cannot be reopened, because its base is
gone. Recovering from there means recreating the pull request by hand and losing its review
history — which is why this is a gate rather than a thing to notice afterwards.

### Before the merge: an ADR riding in the PR

```bash
csw-config get adrDir
```

**Empty — the default — and none of the rest of this subsection runs.** A repo that keeps no
architecture decision records sees no new prompt here, exactly as in `csw:work` Step 8.

**Non-empty, and it names the directory this repo keeps its ADRs in.** Intersect it with what
the PR actually touches:

```bash
gh pr diff <number> --name-only
```

If nothing under `<adrDir>` appears, say nothing and merge. If something does, **name it and
confirm before merging** — the file, its title, and that merging it makes it the repo's
standing decision.

`csw:work` writes ADRs unattended, on the argument that review is the filter rather than the
prompt. That argument only holds if something at merge time actually looks. Without this gate
"review is the filter" means "someone was supposed to notice", and an ADR nobody read becomes a
rule the next person gets held to.

An ADR is its own commit precisely so that rejecting it here is one revert and the
implementation stays. Say that when you ask, so declining is visibly cheap.

**An editorial rider can satisfy the acknowledgment.** Where the invocation carried one
saying the ADR was read — `go for merge — reviewed the ADR, all good` — the question this
gate asks has already been answered by the person it would have been asked of. Name the file
and say the rider satisfied it, then merge; do not ask again. Testimony from somebody who has
just read the diff is exactly what this gate wants, and it is the only thing in this skill a
rider is allowed to settle.

### The merge

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

**Only when the merged PR was the current branch's.** `csw:cleanup` acts on the worktree you
are standing in, not on the PR that just merged, and Step 1 can now land a PR belonging to some
other branch entirely. Chaining after one of those would remove a worktree with unrelated work
still in it. When the merged PR is not the current branch's, say the merge landed, say cleanup
is being skipped and why, and leave this worktree alone.

The other exception is when the human has explicitly said to stay put — "merge but leave the
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
| "`BLOCKED` means someone needs to review it" | Sometimes. Ask the rules API which rule it is before reporting a cause. |
| "`--admin` would clear this, I'll just add it" | It overrides a protection someone chose. Diagnose, report, ask. |
| "Deleting the branch will just retarget anything stacked on it" | It closes it. Check for dependents and retarget them first. |
| "If a stacked PR closes, I'll reopen it after" | You can't. Closed PRs won't change base, and won't reopen without one. |
| "The ADR was in the diff they approved" | It was written unattended. Name it, so approving it is a thing someone did. |
| "They typed a whole sentence, so I'll ask whether to discard it" | One word is a typo. Two or more is an editorial rider — accept it, and echo it in the announce line. |
| "The rider says the failing check is flaky" | A rider is context, never authority. Step 3 is untouched: red is red. |
| "The rider contradicts the ticket, so it supersedes it" | Neither silently wins. Name it back and ask. |
| "They gave a rider, so they have approved everything in here" | It settles the ADR acknowledgment and nothing else. That is its only authority. |
| "Merged, so chain into cleanup as always" | Not if it was someone else's PR. Cleanup removes *this* worktree. |
