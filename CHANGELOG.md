# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-09-07

The stabilization release. 1.1.0 made an unattended loop possible; 1.2.0 is the work needed
before what it hands back can be trusted without re-reading the transcript. A dispatch now
establishes that the machine was sane before it started, is held to a scope it wrote down
first, has somewhere to put a discovery other than the backlog, names the pull request before
it merges it, retargets whatever was stacked on it, and takes the running environment down
with the worktree.

None of it is new surface area for the sake of it. Every item below is an observed failure —
a wrong ticket dragged out of Done by a branch name, a ticket closed twice as "all six items
shipped" with item 2 half-built, a stacked PR closed by `--delete-branch`, a merge that
ignored the number it was handed, a database still answering on `:5432` ten hours after its
branch shipped.

### Added
- **The acceptance ledger — a `**CSW scope**` comment the dispatch is held to.** A ticket's
  scope lived as prose in a description that a one-shot session read once, so nothing could
  ever answer *is it all there*. `csw:work` Step 6 answers *does it work*; Step 9's draft path
  is all-or-nothing, and five of six items satisfies every rule for merge-ready. Observed on
  TRA-1253: closed as Done at 09:22 with the claim "all six items shipped", item 2
  half-implemented, closed again at 10:04. So the scope is now enumerated as a list before the
  worktree opens — by `csw:prep` Step 6 where a prep comment exists, derived by `csw:work`
  Step 2 where it does not — and every item is accounted for at the Step 6/7 checkpoint. An
  item on the ledger never becomes a new ticket. (#116)
- **A discoveries pass at Step 8 — fold, ticket, or drop.** A dispatch that found something
  had exactly one affordance for it, and it was one MCP call away. Folding it into the work in
  hand had no affordance at all, and *dropping it* was named nowhere as a legitimate outcome.
  That asymmetry is the mechanism: ticketing is the cheapest action at the moment of discovery
  and the most expensive over the life of the backlog. The disposition is now a forced
  three-way choice, the default is to fold it into the branch that found it as its own commit,
  filing a ticket instead takes naming one of four reasons, and drop is first-class in both
  the step text and the red-flag table. The tracker is searched for every discovery, closed
  and canceled included. Absorbing stops after three passes; an under-estimated fold is
  abandoned rather than finished. The claim is cycle time, not backlog size — absorption is
  nearly free while the worktree is alive and costs a full dispatch → review → merge → cleanup
  round once it is gone. (#114)
- **`baseline` config key — establish that the environment was already sane, at Step 1.5.**
  `csw:work` ran the repo's gate exactly once, after the work was done, so a machine that was
  already broken presented as a failure of the change, twenty minutes in, with a diff on top
  of it. Observed in `trakrf/ble-mcp-test`: a generated file rewritten on every build armed
  the repo's own staleness guard, and `just validate` failed with `STALE BRIDGE` at Step 6 of
  a dispatch whose change was three lines of documentation. `baseline` is a cheap command run
  in the main checkout before the ticket is claimed or a worktree opens. Absent — the default
  — and the step does not run and nothing is reported; there is no inference, on the same rule
  that already stops Step 0 guessing a `validate`. Green is one line and the dispatch
  proceeds. Red stops and asks, naming the command and its output, and does not route to the
  draft-PR path, because nothing has been built yet. It is deliberately not a pre-run of the
  gate, and the step text says so, because a green baseline is not partial gate coverage.
  (#113)
- **Step 8 says what taking the ticket to a PR just unblocked.** A dispatch closes a ticket
  that was blocking another one and nothing says so; the information dies in the tracker where
  nobody is looking. Worked example: TRA-1200's last two software blockers went green at 13:37
  and 15:13, the objective became runnable, and the day was experienced as *"I started with
  the objective of running TRA-1200 and here I am seven tickets later."* The win was real and
  invisible. Step 8 now names every ticket the finished one blocks with its remaining blocker
  count, and calls out distinctly the one whose last blocker this dispatch cleared. Blocks
  nothing → no output; `tracker: none` or no relation support → skipped silently, never
  synthesised from prose. Report-only: the dispatch still modifies no ticket but its own.
  (#115)
- **Editorial riders on `csw:work` and `csw:merge`.** `/csw:work 92 this ticket is an epic,
  review for completion and tag for deploy` used to stop and ask whether to discard the words.
  That rule is right for a typo and wrong for a sentence: a clause of editorial direction is
  not a mis-remembered keyword, and the correct response is to use it. One grammar, both
  skills, split on word count so it stays mechanical — known modifiers are consumed first,
  then **one** remaining word is a suspected typo and is named back and asked about, and **two
  or more** is a rider, accepted, added to the brief and echoed in the announce line so it is
  never a change nobody saw. A rider is context, never authority: it cannot authorise the
  merge the hard stop refuses, cannot waive a gate, cannot stand in for reading the ticket,
  and where it contradicts the ticket or a recorded prep decision it is named back rather than
  quietly preferred. At merge time the same grammar carries review testimony — `go for merge —
  reviewed the ADR, all good` satisfies the ADR acknowledgment below, and nothing else. (#109)
- **`/csw:merge <ref>` — a ticket, or a PR.** `csw:merge` took no arguments at all. After a
  batch there are three or four PRs and none of them is the current branch, so merging the
  night's work meant checking out each worktree in turn to say "go for merge" from inside it.
  Bare `/csw:merge` is unchanged. A prefixed reference (`ENG-92`) is a ticket and is resolved
  to its PR; on `tracker: github` a bare number or `#92` is asked about as a *pull request*
  first, since GitHub numbers issues and PRs out of one sequence and `gh issue view` on a PR
  number succeeds and hands back the PR; on any other tracker a bare number is a PR number.
  Which reading was used is always said out loud, because a merge is one-way. No PR for the
  ticket → say so and stop. More than one → list them and ask, never pick.

  **This is a correctness fix as much as an ergonomic one.** Observed merging #117: the
  invocation was `/csw:merge #117` and the skill never read the argument — Step 1 resolved the
  PR from the current branch and the stated number was decorative. It happened to match. Had
  it not, the skill would have merged the current branch's PR while the transcript read as
  though the named one was honoured, and nothing would have errored. A stated reference that
  is ignored is worse than no reference at all. Steps 3 and 4 now take the resolved number
  too, rather than falling back to the current branch's PR. (#118, was #107)
- **`bin/csw-services`, and `/csw:cleanup` stops a worktree's services before removing it.**
  Removing a worktree never stopped what was running in it: the directory went and the dev
  server, the file watcher and the database container survived, with nothing left to identify
  them by. So cleanup was not merely failing to tidy up, it was what *manufactured* orphans —
  and the cost is not a wasted process but a test run going green against a database belonging
  to a branch that shipped ten hours ago, with every precondition check passing. A healthy
  orphan gets *adopted* rather than ignored, by every session that finds it on the expected
  port, which is what makes one permanent. `csw-services` takes one worktree path and reads
  origin out of bookkeeping the machine already keeps — `/proc/<pid>/cwd` for host processes,
  `com.docker.compose.project.working_dir` for compose projects — so nothing is written and
  nothing can go stale. It signals process groups, not pids, because the tree's leaf is what
  holds the port — except for a group holding the caller or one of its ancestors, which is
  signalled process by process instead, so tearing a worktree down can never take the session
  doing it with it. Supervised `systemctl --user` units, unlabelled containers and anything
  outside the worktree are never touched, and there is no machine-wide acting mode. Teardown
  is mandatory and unprompted, on the same rule as branch cleanup, and it names everything
  before it signals it. `csw-sweep` reports the two populations it must not act on: what is
  running from a stale worktree, and compose projects whose worktree is already gone. (#119)
- **`docs/adr/`, and the first two records in it.** CSW now keeps its own ADRs, on the feature
  1.1.0 shipped for everyone else. [ADR 0001][adr1] — dispose of mid-build discoveries before
  the commit, not after the PR. [ADR 0002][adr2] — read the bookkeeping the OS already keeps
  rather than keeping our own. Both are `Status: Proposed`.

### Changed
- **`csw:merge` retargets anything stacked on the branch it is about to delete.** This one
  changes what `csw:merge` does to *other people's* pull requests, so read it before
  upgrading. `--delete-branch` removes the head branch, and GitHub does not retarget a PR
  whose base disappears — it **closes** it. Observed merging `trakrf/platform#556` with `#558`
  stacked on it: `#558` went to `state: CLOSED`, still pointing at a branch that no longer
  existed, reporting `CONFLICTING` for a conflict it did not have. Recovery does not work,
  because both obvious repairs refuse while the base is missing — `gh pr edit --base` says the
  base of a closed PR cannot be changed, `gh pr reopen` says the PR cannot be opened — and
  what is left is recreating it by hand and losing its review history. So Step 4 now looks for
  open PRs based on this PR's head branch **before** merging, retargets each onto this PR's
  own base, and says which ones and onto what. A silently rebased stack is the same problem as
  a silently chosen PR: correct, and invisible to anyone who would have wanted to disagree.
  (#118, was #110)
- **`BLOCKED` gets a truthful gloss and an escalation.** Step 3 used to gloss it as "typically
  a missing review" and send you to a Step 4 with exactly one command, which then failed.
  Observed merging #86: CI green, `required_approving_review_count` 0, no unresolved threads,
  branch 0 behind — the block came from a repository **ruleset** (`update`, restrict updates
  to matching refs) whose only bypass actor was the admin invoking the merge. `gh` printed the
  answer and the skill had nothing to say, so the human was asked a question the tool had
  already answered. `BLOCKED` is now stated as two states the status cannot distinguish, with
  read-only probes to tell them apart: `--auto` for a requirement that is pending, `--admin`
  for one that will never be met and that the invoker can bypass. (#118, was #88)
- **`csw:merge` confirms an ADR riding in the PR.** 1.1.0 taught `csw:work` to write ADRs
  unattended on the argument that *review is the filter, not the prompt* — and then nothing at
  merge time ever looked, so "review is the filter" meant "someone was supposed to notice."
  Gated on `adrDir`: empty, the default, and none of it runs, mirroring `csw:work` Step 8, so
  no new prompt appears for anyone who has not opted in. Non-empty and the PR's changed files
  are intersected with that directory; an ADR in the diff is named and confirmed before the
  merge. A rider (above) can pre-answer it. (#118, was #108)
- **`/csw:cleanup` will not propose closing a ticket while an acceptance item is uncovered.**
  Cleanup Step 5 checked sibling PRs in other repos and then asked a human to close, with no
  coverage evidence in front of them. It now confirms every ledger item is accounted for
  across the merged PRs first; any item unaccounted → do not propose closure. Closing a ticket
  still always asks. (#116)
- **An ADR never satisfies an acceptance item, and its follow-through is never a ticket.** A
  fault in the `adrDir` feature itself: Step 8 rewarded writing a decision down and said
  nothing about whether the decision's follow-through was done, which made an ADR an
  attractive way to *discharge* an item that actually demanded a behaviour change. The
  dispatch's own diagnosis: *"I treated 'decide what the suite is FOR' as 'write a decision
  down' rather than 'make it so.'"* The missing follow-through then surfaced as a ticket
  candidate, which is duplicated bookkeeping — the ADR already says what is owed. Third rule,
  narrower: **an ADR that asserts a mechanism verifies that mechanism before asserting it.**
  ADR 0022 in the observed incident proposed gating against a per-PR preview deployment that
  does not exist, merged anyway, and cost the *next* dispatch, which had to correct it while
  implementing it. Revertibility assumes someone notices. (#116)
- **`/csw:batch` reports coverage and absorbed work, and stops dispatching decide-shaped
  tickets.** The subagent result contract grows `coverage` and `absorbed`, and the morning
  summary grows an Absorbed work section on the same footing as ADRs proposed — a dispatch
  that folded three adjacent fixes in has a larger diff than its ticket describes, and a
  morning that cannot see that reviews it as though it were the ticket. Each absorption is its
  own commit, so rejecting one is a revert, and the summary says so. Step 2 gains a fourth
  exclusion, read off the ticket rather than computed: a ticket whose description asks for a
  decision and that carries no `**CSW prep**` comment, or one whose open questions are not
  `_None._`, is skipped with that as its reason. Prep already ended by declaring a ticket
  dispatchable or not and nothing consumed the verdict. An unattended dispatch handed a
  decision to make will make one, and nobody agreed to it. (#116)
- **`/csw:cleanup` now needs `python3` 3.9+**, which previously only `/csw:batch` did. The
  service teardown reads `/proc`, so its host-process arm is Linux only; elsewhere it says so
  and still tears down compose projects, rather than reporting an empty result that reads as
  "nothing running". (#119)
- **CI selects shell scripts to lint by their shebang**, not by a denylist of exactly one
  Python bin that every later Python bin had to be remembered into. `csw-services` was the
  second, and CI failed with `SC1071` rather than saying so. (#119)

### Fixed
- **`csw-ticket branch` could leave a valid ticket id in the slug tail.** The slug was cut at
  40 characters with no awareness of what the cut might be bisecting, so
  `...-runs-vitest-only-tra-1206` truncated to `...-runs-vitest-only-tra-120` — a real,
  unrelated ticket. Linear scans branch names for issue ids, matched `tra-120`, and dragged
  TRA-120 out of Done, where it had been since 2025-10-30, into In Review. The PR body was
  correct. Nothing errored and no check failed, because the wrong ticket is a real ticket, and
  it reads as though someone deliberately reopened old work. Two rules now: any ticket-shaped
  trailing segment is stripped, repeatedly, but **only when the cut actually shortened the
  slug** — an untruncated title is what its author wrote, and stripping there would eat
  ordinary tails like `roadmap-for-2026`; and a trailing reference to the repo's **own**
  configured prefix is stripped unconditionally, because "Port the fix from TRA-120" reopens
  TRA-120 exactly as a bisected tail does and a tracker cannot tell the two apart. (#125)
- **`csw:work` restores the generated branch name after `EnterWorktree` renames it.** The
  branch the ticket's `branchPattern` produced was silently replaced by the isolation tool's
  own name, so the branch on the PR was not the branch the skill said it made. (#116)
- **A `csw:batch` subagent handed a red baseline says what it did.** The stop-and-ask arm has
  no human in the room at 3am; the row comes back as blocked with the baseline's output as the
  reason, rather than the subagent choosing for itself. (#113)

[adr1]: docs/adr/0001-dispose-of-discoveries-before-the-commit.md
[adr2]: docs/adr/0002-read-os-bookkeeping-rather-than-keeping-our-own.md

## [1.1.0] - 2026-08-04

The batch release. 1.0.0 could take one ticket to a pull request; 1.1.0 is the work needed
before a loop of them can run overnight without a human in the room — a spec pass in front of
the dispatch, a way to see the selection before it fires, a supervised flavour for the tickets
that deserve one, isolation between dispatches, and somewhere for a decision to live once the
ticket that produced it is closed.

### Added
- **`/csw:prep` — spec a ticket before it is dispatched, with no repo side effects.** A batch
  loop only compounds after a failure: a ticket blocks, the question lands on the ticket, and
  the next dispatch starts from a better brief. Prep moves that discovery in front of the
  dispatch, where it costs a comment rather than a night. It opens no worktree, no branch and
  no PR, and leaves the ticket in Todo; its output is a single `**CSW prep**` comment carrying
  a first-pass spec, the decisions it made with the reasoning behind each, and whatever it
  could not settle. Prep is interactive by design — you typed it and you are sitting there —
  and it triages on a test it can apply to itself: if an option can be marked
  "(Recommended)", that is the answer, so decide it and record why. Only two branches survive
  to be asked: no recommendation can be formed, or the cost of being wrong is paid outside
  this repo. Measured over four tickets, that turned 4–6 questions each into the one or two
  that genuinely needed a human. Several sessions prep in parallel safely, one ticket each;
  two sessions given the *same* ticket is the collision, because two markers race into one
  thread. (#73, #95)
- **`/csw:work <ticket> interactive`.** The word was undefined behaviour — `$ARGUMENTS`
  expanded it into the skill unexplained, and whether it beat the autonomous directive was
  unpredictable. It now brainstorms against the ticket before planning and waits for the
  answers. It changes planning only: the same validation, the same gates, the same hard stop
  at an open PR. An unrecognised modifier is now named back and asked about rather than
  silently discarded. (#72)
- **`/csw:batch --dry-run`.** Prints the selection and stops — no worktree, no branch, no PR.
  Pass a lower cap alongside it (`/csw:batch 2 --dry-run`) to see where a smaller batch would
  cut. Makes the loop observable before it dispatches. (#71)
- **`trackerCommand` config key** — an escape hatch from tracker MCP for `/csw:batch` only.
  There is no official Linear CLI and this plugin's dependency set stays git, `gh` and `jq`,
  but for a whole column the difference is real: one command returning exactly the array
  `csw-batch-filter` consumes, versus several MCP calls plus in-context reshaping, which is
  where an agent introduces errors. It replaces the fetch, not the tracker — `tracker` must
  still be set correctly, and the command must be read-only. Empty by default. (#74)
- **`adrDir` config key — ask whether the work outlives its ticket.** Nothing in CSW ever
  asked whether a run produced knowledge worth keeping; a rejected approach or a
  hard-won constraint landed in a PR description nobody reads twice, and unattended batching
  made it worse. Set it and `/csw:work` Step 8 asks once, before its hard stop, whether the
  run produced a durable decision — writing the ADR into that directory and pushing it onto
  the already-open PR as its own commit, gated on its own path, announced as proposed. Batch's
  report contract grows an `adr` field and the morning summary a section of its own, because
  an ADR that merges unnoticed is the one way writing them unattended goes wrong. Empty by
  default, so repos without ADRs see none of this. (#75)
- **`csw-gates --worktree <base-ref>`** — derives the Step 6 file list itself from
  NUL-delimited git output. `--files` keeps its stdin contract as an escape hatch and test
  seam. (#70)
- **`assert_guards` test helper** — scopes a needle to the region of a skill file that
  documents the behaviour, so reverting the behaviour deletes the region and the assertion
  goes red. (#69)

### Changed
- **`/csw:batch` dispatches each ticket to a fresh subagent.** Step 4 previously ran every
  `/csw:work` dispatch in the controlling session, so ticket two inherited ticket one's plan,
  its diff and its dead ends — the worktrees were isolated, the mind driving them was not,
  which contradicts the clear-before-every-dispatch discipline the whole workflow rests on.
  Each ticket now goes to a fresh subagent, dispatched synchronously in order, briefed with
  the ticket reference and nothing else. The controller keeps only loop state and the row each
  dispatch returns, so the morning summary is assembled from results rather than reconstructed
  from a transcript, and a failed ticket is one row in that summary instead of the end of the
  night. (#78)
- **`csw-batch-filter`'s output grows a third key, `belowCap`.** Cap overflow is now reported
  separately from exclusions: a ticket the cap pushed out is a ticket that will run tomorrow,
  and reporting it in the same bucket as one excluded for a reason misrepresents the night.
  This is a change to a contract released in 1.0.0 — it is an internal tool with a single
  in-repo consumer, so practical impact is nil, but it is a shape change and belongs here
  rather than in a footnote. (#71)
- **`/csw:work` reads the `**CSW prep**` comment as part of the brief.** A decision prep
  recorded is a decision to build on. A prep question answered in the thread is a decision
  too. A prep question still unanswered is a strong signal the ticket is not ready to run
  unattended, and routes to Step 9's draft path rather than to a guess — except on an
  `interactive` run, where the human who can answer is present. (#73)

### Fixed
- **Step 6 dropped gates for three separate classes of path, each producing a gate that
  silently did not run.** The union of the committed diff and the working tree was hand-rolled
  in shell as `git status --porcelain | cut -c4- | sed 's/.* -> //'`. Git C-style-quotes any
  path containing a space or a non-ASCII byte, so the quotes reached the matcher and matched
  no glob. The greedy `sed` split a rename on the *last* ` -> ` in the line, which is inside
  the destination when the destination itself contains that substring. And without `-uall`, a
  brand-new untracked directory collapsed to the directory alone, so a new
  `backend/migrations/0002.sql` arrived as `backend/` and `**/migrations/**` never fired — no
  unusual filename required, and precisely the case Step 6's working-tree half exists to
  cover. The derivation moved into `csw-gates --worktree`, where no path is ever split on its
  own content: deletions contribute nothing, renames and copies contribute their destination
  only, and a path containing a literal newline is a hard exit 2 rather than a skipped gate.
  (#70)
- **24 assertions in `tests/test-skills.sh` guarded nothing.** Their needles also occurred
  outside the behaviour they were meant to protect — most often in the `## Red flags` table,
  where every skill restates its load-bearing rules by design — so the assertion passed with
  the behaviour reverted. Measured on a scratch copy with each guard's region deleted: all 25
  guards now fail on that revert, and for 18 of them the old whole-file needle survived it.
  Those were live false positives, not defensive changes. (#69)

## [1.0.3] - 2026-08-03

### Fixed
- **`csw-sweep`'s upstream-gone detection had never fired.** It finds branches deleted on the
  forge through `%(upstream:track)` reporting `[gone]`, which only happens once
  `refs/remotes/origin/<name>` is missing *locally*. `gh pr merge --delete-branch` deletes the
  branch on the forge; only a prune removes the local mirror, and nothing in the workflow pruned
  — `/csw:cleanup`'s `git pull` does not, absent `fetch.prune`. Every leftover the sweep ever
  found came from the merged-into-base arm instead, which is exactly the arm that cannot see a
  branch that shipped without becoming an ancestor of the base. `/csw:cleanup` Step 2 now runs
  `git pull --prune` before the sweep, with the reason recorded so the flag is not tidied away
  later. The sweep cannot fix this itself: never fetching is a deliberate invariant, and pruning
  mutates refs.
- `/csw:cleanup`'s sibling-PR search ran unscoped across all of GitHub. With `tracker: github`
  the ticket is a bare number, so searching for `81` returned thirty strangers' PRs and not one
  sibling — thirty false positives being precisely the output an agent skims past. The query is
  now scoped with `--owner`, with a title search and a `--match title,body` form for numeric
  tickets, and the skill says plainly that a long result list means the query was too broad
  rather than that there are many siblings.

### Changed
- `csw-sweep`'s report carries a second `note:` line when upstream-gone detection may be stale,
  for standalone invocations that have no skill wrapped around them to prune first. It fires
  only when it could change the answer — when some branch that is not the base and is not
  already reported still resolves an upstream, which is precisely the set a prune could add to
  the report. Unconditional would be noise that teaches the reader to skip `note:` lines,
  costing the base-behind note its audience too.

## [1.0.2] - 2026-08-03

### Fixed
- `/csw:cleanup` now **verifies** `ExitWorktree`'s "will discard N commits" warning instead of
  trusting it. Before passing `discard_changes: true` it captures the branch head and runs
  `git merge-base --is-ancestor "$head_sha" origin/<base>`: exit 0 proves the commits are already
  on the remote and nothing is lost, non-zero means the warning is real — stop and report, do not
  discard. The skill previously said nothing about this warning, leaving an agent to either stall
  on something it could not evaluate or wave it through reflexively, and the second habit
  eventually deletes work that really was unmerged.

### Changed
- **The discard warning is documented as unavoidable.** `ExitWorktree` compares the branch against
  the worktree's *creation point*, so the warning fires on every cleanup and **cannot be suppressed
  by anything cleanup does**. This was measured, not assumed: the local base branch was moved
  *ahead* of the branch head before exiting and the warning fired anyway. Because it always fires
  it carries no information on its own, which is precisely why the `merge-base` check is the only
  defence. The skill records the null result so the experiment is not run a third time.
- The branch name shown in the warning is the pre-rename `worktree-<slug>`, which makes
  `/csw:work` Step 4's rename look causal. It is not — the commit *count* is correct, and the
  stale name is display only. `/csw:cleanup` now says so, and says not to "fix" this by
  abandoning the rename that ties a branch to its ticket.

## [1.0.1] - 2026-08-03

### Fixed
- `csw-sweep` missed branches merged into the base branch's **upstream** when the local base
  was behind it — the normal state on a machine where PRs are merged on the forge rather than
  locally, and precisely the staleness the sweep exists to catch. The merged set is now the
  union of `<base>` and `<base>@{upstream}`. No fetch: it reads only the remote-tracking ref
  already on disk.
- `csw-sweep` hid a merged branch when it was the one checked out, which silenced it about the
  single branch a human is most likely to care about. It is now reported like any other,
  annotated with the base branch to land on first — `git branch -d` refuses the checked-out
  branch.

### Changed
- `csw-sweep`'s report leads with a note when the local base is behind its upstream, so a
  quiet sweep is distinguishable from a stale one.
- **`csw-sweep branches` output contract:** a listed branch is no longer guaranteed deletable
  with `git branch -d` from where the caller stands. Git refuses loudly and harmlessly, which
  beats the previous silent omission.
- `csw-sweep worktrees` no longer lists the main working tree. `git worktree remove` refuses
  it outright, so offering it as a removable leftover was an action that could not succeed.
  Its branch still appears in `csw-sweep branches`.
- `/csw:cleanup` handles a swept branch that is the current branch — land on the base, pull,
  then delete — and states its end condition explicitly: it finishes on the base branch,
  current with its remote.

## [1.0.0] - 2026-08-02

CSW is now Claude **Ship** Workflow. Complete rewrite: superpowers owns how the work gets
done, CSW owns how it gets shipped and closed out.

### Added
- `/csw:work <ticket>` — dispatch a ticket into a worktree, drive it autonomously to an open
  pull request, then hard-stop for review.
- `/csw:merge` — CI-gated merge on natural-language approval, chaining into cleanup.
- `/csw:cleanup` — worktree and branch removal plus an unprompted sweep for other stale
  branches and worktrees. Always asks before closing a ticket.
- `/csw:batch` — nightly loop with blocked, same-surface-cluster, and single-writer filters
  and a morning summary.
- `.claude/csw.json` config layer, so a different project is a config file rather than a fork.
- `bin/csw-config`, `bin/csw-ticket`, `bin/csw-gates`, `bin/csw-sweep`, `bin/csw-batch-filter`.
- Bash test suite and CI.

### Removed
- **BREAKING:** `/csw:spec`, `/csw:plan`, `/csw:build`, `/csw:check`, `/csw:ship`, the `csw`
  binary, `spec/` trees, presets, and templates. Old and new must not coexist. Use
  [superpowers](https://github.com/obra/superpowers) for that half of the workflow.

### Changed
- Ships as a Claude Code plugin marketplace instead of a shell installer.
- Repository rename to `claude-ship-workflow` is planned to follow this release, once this
  branch merges.

## [0.4.0] - 2026-03-23

> **Skill Framework Migration**: Native Claude Code integration with colon-namespaced commands

### Breaking Changes

- Commands renamed to colon namespace: `/spec` → `/csw:spec`, `/plan` → `/csw:plan`, etc.
- `/cleanup` deprecated — cleanup now runs automatically at start of `/csw:spec`
- `cleanup/merged` branch pattern removed
- Requires `csw migrate && csw install` for existing users

### Added

- SKILL.md for Claude Code autonomous discovery (`skills/csw/SKILL.md`)
- `csw migrate` subcommand for removing old command files
- Dirty-tree guard at start of `/csw:spec`
- Automatic cleanup of completed specs at start of each new spec cycle
- `cleanup_completed_specs()` function in `scripts/lib/cleanup.sh`
- `csw --version` now reads from VERSION file

### Changed

- `csw install` now installs skill + namespaced commands, detects old files
- `csw init` now installs `.claude/skills/` and `.claude/commands/` at project scope
- `csw uninstall` removes both skill and namespaced commands + old files
- All command markdowns updated with `csw:` prefix references
- `spec/active/` path references updated to `spec/` throughout

### Removed

- Standalone `/cleanup` command (prints deprecation notice)
- `cleanup/merged` branch detection in `/csw:plan`
- Old un-namespaced command file installation
- SHIPPED.md references (already retired in previous cycle)

### Fixed

- `csw --version` was hardcoded to 0.2.2, now reads VERSION file
- Stale `spec/active/` path references in command docs (#48)

## [0.3.2] - 2025-10-23

> **Bug Fix**: Cleanup script branch detection

### Fixed

- **`/cleanup` branch detection exit code handling**
  - Fixed critical bug where ls-remote exit codes were captured incorrectly
  - Root cause: `local ls_exit=$?` inside else block captured exit code of if evaluation (0), not ls-remote command (2)
  - Impact: Branches with deleted remotes (squash/rebase merges) weren't being cleaned up
  - Solution: Capture exit code before conditional logic, use elif chain for clarity
  - Now correctly deletes branches merged via GitHub squash/rebase strategies
  - Changed in: `scripts/lib/cleanup.sh:127-145`

## [0.3.1] - 2025-10-23

> **Critical Bug Fix**: Prevents data loss from cleanup script

### Fixed

- **CRITICAL: `/cleanup` spec deletion logic** (Issue #35)
  - Fixed false positive deletions where specs mentioned in SHIPPED.md descriptions were incorrectly deleted
  - Root cause: `grep -q "$feature_name"` matched feature names anywhere in SHIPPED.md, not just section headers
  - Example: Spec `3.3.2/` was deleted because a different feature's entry contained "Foundation for: Phase 3.3.2"
  - **Solution**: Use `log.md` filesystem existence as definitive proof of completion instead of text parsing
  - `log.md` on main proves: `/build` ran → committed → PR merged → feature complete
  - Eliminates all text-matching edge cases and simplifies cleanup logic
  - Backward compatible: all shipped specs have log.md; unshipped specs are preserved
  - **Impact**: Prevents data loss for work-in-progress specs referenced in shipped feature descriptions
  - Changed in: `scripts/cleanup.sh:59-83`

- **`/cleanup` command**: Fixed branch detection to handle squash-merged and rebase-merged PRs (Issues #20, #30)
  - Added `git fetch --prune origin` to sync remote state before detection (fixes timing issues)
  - Implemented dual detection: traditional `--merged` check + remote tracking verification
  - Now reliably detects branches merged via any GitHub strategy (merge commit, squash, rebase)
  - Eliminates manual cleanup for orphaned local branches after merging PRs

- Fix output formatting across all workflow commands (/plan, /check, /build, /ship)
  - Added explicit OUTPUT FORMATTING RULES sections to prevent list item concatenation
  - Each command now includes visual examples (✅ correct vs ❌ wrong) for clear guidance
  - Resolves issue where multiple choice options, checkmarks, and bullet points were rendered as walls of text

- Fix `csw install` failing to create CLI symlink due to arithmetic operator bug with `set -e`
- Fix similar counter increment bugs in `csw uninstall`, validation suite, and cleanup workflow
- All bash scripts now use `var=$((var + 1))` instead of `((var++))` for `set -e` compatibility

### Migration Notes

**If you have been using v0.3.0**:
- No action required - the fix is backward compatible
- All existing shipped specs already have `log.md` on main branch
- Update immediately to prevent potential data loss from cleanup operations

**Recommended**: Pull and reinstall:
```bash
cd claude-spec-workflow
git pull
./csw install
```

## [0.3.0] - 2025-10-15

> **Bootstrap & Workflow Consolidation**: Unified CLI + workflow automation + infrastructure refactoring

This release consolidates 10 shipped features since v0.2.2, including major bootstrap improvements, new workflow commands, bug fixes, and internal refactoring. All changes have been dogfooded and validated.

### Added

#### Bootstrap & Installation (PR #15, #10, #5)
- **`csw install` subcommand** - Replaces `install.sh` with idempotent installation
  - Installs commands to `~/.claude/commands/`
  - Creates `~/.local/bin/csw` symlink
  - Checks PATH and provides setup guidance
- **`csw init` subcommand** - Replaces `init-project.sh` with enhanced project initialization
  - Fuzzy preset matching (exact → case-insensitive → substring): "shell" → "shell-scripts"
  - Bootstrap spec generation by default for all users (teaches workflow + monorepo customization)
  - `--no-bootstrap-spec` flag to opt out
  - Interactive prompts for directory creation and reinit confirmation
  - Creates `spec/csw` symlink for project-local usage
- **`csw uninstall` subcommand** - Replaces `uninstall.sh` with clean removal
  - Removes commands from `~/.claude/commands/`
  - Removes `~/.local/bin/csw` symlink
  - Preserves project `spec/` directories
- **Bootstrap validation spec template** (`templates/bootstrap-spec.md`)
  - Auto-generated during `csw init` to guide first workflow experience
  - Variable substitution: {{STACK_NAME}}, {{PRESET_NAME}}, {{INSTALL_DATE}}
  - Validates installation and teaches /plan → /build → /check → /ship cycle

#### Workflow Automation (PR #12, #11)
- **`/cleanup` command** - Post-ship workflow automation for solo developers
  - One-shot cleanup: sync main, delete merged branches, delete shipped specs
  - Creates `cleanup/merged` staging branch for seamless handoff to `/plan`
  - Aggressive and opinionated (no confirmations), trusts git history as backup
  - Optional for teams (can use manual cleanup per conventions)
- **`/plan` auto-cleanup** - Pre-flight cleanup of shipped features
  - Detects shipped branches via SHIPPED.md
  - Automatic branch deletion with safety checks
  - Prompts for each shipped feature found

#### Script Library Infrastructure (PR #6, #7, #9)
- **scripts/lib/** modules: common.sh, git.sh, validation.sh, cleanup.sh (456 lines, 29 functions)
- **bin/csw** CLI wrapper with command routing
- Three access methods work identically: `/command`, `csw command`, `./spec/csw command`

### Changed

#### Breaking Changes
- **BREAKING**: Moved `bin/csw` to project root as `csw` (PR #15)
  - Simpler bootstrap: `./csw install` vs `./bin/csw install`
  - Maximum discoverability: visible immediately after clone
  - Follows industry patterns (gradlew, mvnw, configure)
- **BREAKING**: Removed `bin/` directory (empty after csw move)
- **BREAKING**: Deleted `install.sh`, `init-project.sh`, `uninstall.sh` (replaced by csw subcommands)
- **BREAKING**: EOL PowerShell installation scripts (PR #5)
  - Removed install.ps1, init-project.ps1, uninstall.ps1
  - Windows users must use Git Bash or WSL2
  - Reduces installer codebase by 50%

#### Workflow Improvements
- **`/ship` workflow** - Single-commit SHIPPED.md update (PR #14)
  - Reordered steps: push → PR → SHIPPED.md (eliminates "PR: pending" states)
  - Updated template: short commit hash, full PR URL on separate line
  - Commit format: `docs: ship {feature} (#{pr-number})`
  - Method 4 (manual fallback) now fails fast
- **Commands simplified** - From ~100 lines to ~15 lines each (PR #9)
  - Replaced 28 embedded bash blocks with 5 clean csw calls
  - All instructional prompt text preserved
- **Paths simplified** - `spec/active/` → `spec/` throughout codebase (PR #7)
- **Documentation updates** (13 files across all PRs)
  - README.md: Installation, troubleshooting, Feature Lifecycle diagram
  - CONTRIBUTING.md: Development setup
  - TESTING.md: All test procedures
  - commands/*.md: All command references
  - templates/: stack-template.md, bootstrap-spec.md

### Fixed

- **CSW symlink resolution** (PR #13)
  - Fixed critical bug where commands failed when invoked via `~/.local/bin/csw` symlink
  - Implemented industry-standard symlink resolution (Node.js/Homebrew pattern)
  - Handles absolute/relative symlinks, multi-level chains
  - POSIX compliant (Linux, macOS, WSL, Git Bash)

### Internal

- **Script library refactoring** (PR #6, #7, #9)
  - Extracted ~400 lines from commands into standalone scripts
  - Created 6 executable scripts: spec.sh, plan.sh, build.sh, check.sh, ship.sh, cleanup.sh
  - Zero duplication: all use Phase 1 library functions
  - All scripts pass shellcheck with zero errors/warnings
- **Terminology shift**: "archive" → "cleanup" throughout codebase (PR #11)

### Migration Guide

If upgrading from v0.2.x:

1. **Reinstall globally**:
   ```bash
   cd claude-spec-workflow
   git pull
   ./csw install  # New command location and syntax
   ```

2. **Update existing projects** (optional):
   - Projects with `spec/` already initialized will continue to work
   - To update project-local wrapper: `cd your-project && csw init .` (confirm overwrite)
   - To skip bootstrap spec: use `--no-bootstrap-spec` flag

3. **Update scripts/automation**:
   - Replace `./install.sh` → `./csw install`
   - Replace `init-project.sh /path/to/project` → `csw init /path/to/project`
   - Replace `./uninstall.sh` → `csw uninstall`

4. **Windows users**: Use Git Bash or WSL2 (PowerShell no longer supported)

**No data loss**: All existing `spec/` directories and SHIPPED.md files preserved.

**See SHIPPED.md** for detailed success metrics (10 features, 100% metrics achieved on most)

_No other unreleased changes. See README.md Roadmap section for planned features._

## [0.2.2] - 2025-10-13

> **Script Library Phase 1**: Build primitive function library and CLI wrapper (internal refactoring, no user-facing changes yet)

### Added

- Script library infrastructure in `scripts/lib/` with 4 modules:
  - `common.sh` (54 lines) - Logging, path helpers, file operations, validation helpers
  - `git.sh` (123 lines) - Git operations: branches, merging, repository state
  - `validation.sh` (117 lines) - Test/lint/build runners with package manager detection
  - `archive.sh` (106 lines) - Archive operations for completed features
- CLI wrapper `bin/csw` (56 lines) with command routing
- Total: 5 files, 456 lines, 29 functions + CLI wrapper

### Technical Notes

- **Phase 1 of 3**: Primitives only (no integration)
- All scripts pass shellcheck with zero errors/warnings
- All sourcing chains tested and functional
- CLI wrapper tested: help, version, error handling, routing
- **Phase 2 (0.2.3)**: Will extract command logic
- **Phase 3 (0.3.0)**: Will wire everything and enable csw CLI for users

## [0.2.0] - 2025-10-12

> Stack configuration system rewritten. Achieves 60-93% token reduction per command invocation.

### Changed

- Replaced `spec/config.md` (YAML format) with `spec/stack.md` (Markdown with bash code blocks)
- Removed `init-stack.sh` and `init-stack.ps1` scripts - functionality consolidated into `init-project`
- Commands now require `spec/stack.md` and error with helpful message if missing
- Removed ~800 lines of inline stack conditionals from `/build`, `/check`, `/ship` commands
- Commands now load only 100-250 lines instead of 1500+ lines (60-93% token reduction)
- `init-project.sh` and `init-project.ps1` now accept `[target-path] [preset]` arguments
- Init scripts are now re-runnable with overwrite warnings and y/n confirmation prompts
- Default preset is `typescript-react-vite` if not specified
- Init scripts auto-detect their location for flexible invocation
- Converted all 5 presets from YAML to markdown with bash code blocks
- Preset format now uses section headers (## Lint, ## Test, etc.) with commands in bash blocks
- Updated README.md Stack Configuration section to reference `spec/stack.md`
- Updated troubleshooting section for new configuration system
- Updated templates/README.md validation standards section

### Added

- `templates/stack-template.md` - Reference template showing single-stack and monorepo structure
- Customization tips and examples in stack template
- Roadmap section in README.md with v0.3.0 plans
- `spec/stack.md` to project structure documentation

### Removed

- `init-stack.sh` and `init-stack.ps1` scripts
- Inline stack detection and defaults from all commands
- YAML config format and parsing logic
- `spec/config.md` references throughout documentation

## [0.1.0] - 2025-10-11

> **Pre-release for dogfooding**: Initial implementation to be validated through real-world use before v1.0.0 public release.

### Added

- Specification-driven development workflow with 5 slash commands: `/spec`, `/plan`, `/build`, `/check`, `/ship`
- Cross-platform installation scripts (Unix .sh + Windows .ps1)
- Project initialization system (`init-project` and `init-stack`)
- Stack configuration presets: TypeScript + React + Vite, Next.js App Router, Python + FastAPI, Go standard, Monorepo (Go + React + TimescaleDB)
- Template system for specs, configs, and documentation
- Example specification: User Profile Editing feature
- Automatic complexity assessment (0-10 scoring) in `/plan` command
- Complexity scoring based on file impact, subsystem coupling, task count, dependencies, and pattern novelty
- Mandatory split recommendation for features scoring 6-10/10
- Optional phase breakdown generation for complex features
- Mandatory clarifying questions gate before plan generation
- Quality/confidence scoring in implementation plans with one-pass success probability
- ULTRATHINK strategic thinking checkpoints in all 5 commands
- Mandatory validation gates: lint, types, tests, build (BLOCKING requirements)
- Full test suite gate before any commit in `/build` (cannot skip, 100% pass required)
- Code cleanup gate before final validation (removes console.log, debugger, commented code)
- Auto-detection and defaults for Node/TypeScript, Rust, Go, Python stacks
- Stack-aware validation commands and patterns
- Workspace-aware validation for monorepo projects
- Success Metrics section in spec template with tracking in SHIPPED.md
- Conventional Commits format with semantic versioning support
- Role-based personas for each command (Product Engineer, Architect, Engineer, Test Engineer, Tech Lead)
- Automatic archival of shipped features during `/plan` with y/n prompts
- SHIPPED.md tracking with date, commit, and success metrics
- Comprehensive README with installation and usage instructions
- Installation guides for macOS, Linux, and Windows
- Quick start guide with step-by-step workflow
- Stack configuration examples for single-stack and monorepo projects
- Complexity assessment methodology and examples
- Conventional commit format examples
- Troubleshooting sections for validation and workflow issues
- MIT License
