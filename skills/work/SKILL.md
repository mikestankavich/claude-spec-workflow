---
name: work
description: Dispatch a tracker ticket into an isolated worktree and drive it autonomously to an open pull request, then stop for review. Pass `interactive` to brainstorm the ticket with a human before planning it. Use when asked to work a ticket end-to-end.
when_to_use: "/csw:work 1088", "work ENG-1088", "work 1088 autonomous to PR then hold for review", "take ENG-1088 to a PR", "/csw:work 1088 interactive"
argument-hint: "[ticket-ref] [interactive]"
---

# Work a ticket to a pull request

**Announce at start:** "Using csw:work to take <ticket> to a pull request."

Invocation: $ARGUMENTS

## Step 0: Read the config

```bash
csw-config json
csw-config path
```

If `csw-config path` prints nothing, this repo has no `.claude/csw.json`. Say so, show the
defaults you are about to use, and ask whether to continue or write a config first. Do not
silently guess a validate command.

## Step 1: Resolve the ticket, and the modifier

The invocation is a ticket reference, optionally followed by one modifier word. Split it on
whitespace: the first token is the reference, whatever follows it is the modifier.

```bash
csw-ticket normalize "<the first token of the invocation>"
```

If the invocation carried no reference, ask which ticket. Do not pick one.

If normalisation exits non-zero, report its message and stop — a mistyped reference is
exactly the failure this command exists to prevent.

Then read the modifier:

- **`interactive`** — run **superpowers:brainstorming** against the ticket before the Step 5
  chain. Surface the questions and wait for the answers. Do not run unattended. This is the
  flavour someone reaches for when the ticket is vague, or when the approach has more than one
  defensible shape; answering your own questions is exactly the thing it exists to prevent.
- **No modifier** — autonomous, exactly as the rest of this skill describes. Brainstorming is
  skipped because the ticket is the agreed brief.
- **An unrecognised modifier is not ignored.** Say what was passed, say it is not recognised,
  and ask whether to proceed autonomously — then wait. Silently discarding a word someone
  deliberately typed is how a dispatch does something other than what was asked, and the word
  they were reaching for may well have been `interactive`.

`interactive` changes only how the work is planned. Steps 6 through 9 are untouched: the same
validation, the same gates, the same pull request, the same hard stop. An interactive run
still ends at an open pull request and still never merges.

## Step 1.5: Establish that the environment was already sane

```bash
csw-config get baseline    # empty means the repo declared none — skip this step entirely
```

Run whatever it prints, once, before touching anything.

**Red here is not yours to fix, and that is the point.** It means the machine was broken
before this dispatch started. Report what failed — the command and its output — and ask,
rather than absorbing someone else's breakage into your diff and meeting it again at Step 6
with a day's work on top. Do not take Step 9's draft path either: that path carries work that
exists, and nothing has been built yet. The ticket is not claimed at this point either,
because Step 2 is what sets it In Progress — which is the right outcome for a failure that is
not the ticket's fault.

Green is worth one line — say it passed, and proceed.

**This is not a pre-run of the gate.** Its subject is the environment, not the change — a
stale service, a held port, a dead dependency, a half-applied migration — so it is normally a
much cheaper command than `validate`. Do not report a green baseline as evidence about the
work; it says only that you started from a clean machine.

Dispatched from `/csw:batch` there is **nobody to ask**, so return `failed` with the command
and its output as the reason and let the loop record one row and move on. Do not fall into
that skill's draft path: it is for a ticket whose work exists and did not reach merge-ready,
and this ticket has no work at all. Every ticket in the batch will hit the same red baseline,
and N identical rows naming one machine fault is the correct morning summary — not something
to route around.

A baseline may repair what it finds — sweeping a held port, restarting a stale daemon. That is
it doing its job, not a side effect to avoid. `trackerCommand`'s read-only rule does not
transfer: that one exists because `/csw:batch --dry-run` runs it.

This runs here, in the main checkout, and never inside the worktree Step 4 opens. A fresh
worktree has no installed dependencies, so a baseline run inside one fails for reasons that
say nothing about the environment.

## Step 2: Read the ticket and claim it

Read it from the tracker named by `csw-config get tracker`:

- `linear` — the Linear MCP tools. Fetch the issue, then set its state to In Progress.
- `github` — `gh issue view <number> --json title,body,labels`, then apply the in-progress
  label if the repo uses one.
- `none` — ask for the ticket text.

Read the **whole** description, not the title. Ordering constraints and "replace, do not
delete" style requirements live in prose and are invisible to structured queries.

### Then read what `csw:prep` left behind

Fetch the ticket's **comments** as well as its description, and look for one prefixed
`**CSW prep**`:

```bash
# tracker: github
gh issue view <number> --comments
```

For `linear`, list the issue's comments through the Linear MCP tools.

If there is one, it is part of the brief — a first-pass spec, the decisions prep made with the
reasoning behind each, whatever it could not settle, and anything the ticket asserts that the
codebase contradicts. Read the replies underneath it too, because that is where the answers
are:

- **A decision prep recorded is a decision.** It comes with its reasoning so you can see the
  precedent it followed; build on it. Re-deciding it is the same wasted conversation as
  re-opening an answered question. Overturning one takes something the reasoning did not
  account for — say so on the ticket if you find it.
- **`## Open questions` reading `_None._` means nothing is outstanding.** A missing section is
  not the same claim: treat it as an older prep comment and read the questions out of the body.
- **A prep question that has since been answered in the thread is a decision.** Take it and
  move on. Re-opening it spends the dispatch on a conversation that already happened, and the
  answer in the thread outranks whatever the description said before it was asked.
- **A prep question still unanswered is a strong signal this ticket is not ready to run
  unattended.** Say which questions are still open and take Step 9's draft path,
  rather than guessing at an answer and building on the guess. A guessed answer is not visible
  as a guess in the diff — it looks like a decision someone made.

The exception is an `interactive` run, where a human is present to answer: there, prep's open
questions are the agenda for the Step 1 brainstorm rather than a reason to open a draft PR.
Nobody to ask is what makes an unanswered question a blocker.

No prep comment is not a problem. Prep is optional, and a ticket without one is dispatched
exactly as it always was.

### Then read the scope ledger

One more comment, prefixed `**CSW scope**`. It is this command's own, and it carries the
ticket's coverage state rather than its brief:

```markdown
**CSW scope**

## Acceptance
Source: `**CSW prep**` comment | derived by `csw:work` (no prep comment)

1. <item> — covered by <PR or commit> | not covered
2. <item> — covered by #667

## Discoveries
| What | Disposition | Reason |
|---|---|---|
| <finding> | folded | — |
| <finding> | spun out → #123 | outside this repo |
| <finding> | dropped | superseded by item 2 |

## Amendments
- Item 4 removed — larger than the ticket carrying it; the PR title would no longer describe
  the change.
```

The marker `**CSW scope**` is load-bearing and must be exact, for the same reason `**CSW prep**`
is: Step 6 and `csw:cleanup` both search the comments for that string.

- **A ledger exists — read it.** Its `## Acceptance` list is the coverage contract for this
  dispatch. Its `## Discoveries` table is what earlier dispatches already disposed of, so
  nothing there is rediscovered and nothing already dropped is quietly re-filed.
- **No ledger, but a prep comment — copy its `## Acceptance` list into a new one**, marking the
  source as the prep comment.
- **Neither — derive the list from the description yourself**, mark it as derived, and post it.
  Read the whole description, exactly as above: the ordering constraints live in the prose.

**Post it before Step 4 opens the worktree.** A list written after the work is a list shaped by
what got built, which is the one thing it cannot be and still gate anything.

**`csw:work` never edits the `**CSW prep**` comment.** That marker is prep's — prep supersedes
its own comment and relies on being its only author, and its "one comment, not a thread" rule
exists so a human can tell prep's questions from prep's restatements of them. Brief and state
are different artifacts, written by different actors at different times, and they get different
comments.

**One `**CSW scope**` comment per ticket, updated in place.** Several dispatches against one
ticket — a draft, then a re-dispatch — amend the same comment rather than opening a second.

**An acceptance item is amended or removed only with a reason from the same four** that Step 6
uses to spin a discovery out, recorded under `## Amendments`, with the original item text left
visible. Scope does change mid-flight, and the amendment is the review point — a ledger that
can shrink silently is a hole wide enough to drop the original problem through.

## Step 3: Infer the change type

From the ticket's labels and language, pick one conventional-commit type:

| Signal | Type |
|---|---|
| New capability, new surface, "add" | `feat` |
| Broken behaviour, regression, "fix" | `fix` |
| Documentation only | `docs` |
| Restructuring with no behaviour change | `refactor` |
| Tests only | `test` |
| Dependencies, config, tooling | `chore` |

When two fit, take the one a reviewer would put in the PR title. When none fit, use
`csw-config get defaultType`.

## Step 4: Open an isolated workspace

```bash
csw-ticket branch <type> <ticket> "<the ticket title>"
```

Create the worktree with the native **EnterWorktree** tool, passing that branch name. Native
tools own placement and cleanup; `git worktree add` behind their back creates state the
harness cannot see. Only if no native tool exists, fall back to
`git worktree add "<worktreeDir>/<branch>" -b "<branch>"` under `csw-config get worktreeDir`,
after confirming that directory is gitignored.

**Then check the branch name, because EnterWorktree may not have used the one you passed.**
It derives its own — sanitising `/` and prefixing the result — so the branch can land as
`worktree-<type>+<ticket>-<slug>` rather than the name `csw-ticket branch` printed:

```bash
git branch --show-current                       # what you actually got
git branch -m "<the name csw-ticket branch printed>"
```

Rename it if it differs. The generated name is not cosmetic: trackers scan branch names for
ticket ids, `csw:cleanup` finds and deletes branches by that name, and `branchPattern` is a
configured convention that a silently-renamed branch quietly stops following. The worktree
*directory* keeps whatever name the tool gave it, which is fine — it is gitignored and nothing
matches on it.

## Step 5: Do the work, autonomously

Run the superpowers chain in autonomous mode:

1. **superpowers:writing-plans** — the ticket is the spec, and brainstorming is skipped
   unless this run is interactive: an unattended dispatch has nobody to brainstorm with, and
   the ticket is the agreed brief. On an interactive run Step 1 already brainstormed, and the
   answers it surfaced are part of the spec alongside the ticket.
2. **superpowers:executing-plans** — execute it.
3. **superpowers:test-driven-development** — inside every task. Test first, always.

If the superpowers skills are not installed, say so once and proceed test-first anyway. They
are a strong recommendation, not a hard dependency.

Autonomous means: make the ordinary judgment calls yourself, do not stop to confirm each
step. It does not mean skipping the stop in Step 8.

An interactive run is autonomous from here too. The questions were asked in Step 1; once they
are answered, plan, execute, and validate the same way — do not turn the rest of the run into
a series of confirmations.

### When you notice something the plan does not cover — note it and keep going

Adjacent breakage, a loose end, a bad assumption two files over, an
acceptance item the plan missed: write it to a running list and carry on with the task in hand.
Do not act on it here, and do not file it here. Step 6 disposes of the whole list at once.

Collecting beats remembering. A pass that runs on recall dispositions whatever happens to still
be in context when it runs, which is never the same set as what was actually found.

## Step 6: Validate

### Before validating: dispose of what you found

Absorbed work has to be validated by the run that absorbs it, so disposal comes first.

Account for two things: **every acceptance item on the ledger**, and **every discovery Step 5
collected**. An acceptance item nothing covers is a finding, and is disposed of here like any
other.

**The default is fold:**

> **Could it reasonably be in scope? If yes, fold it in.** Spinning it out requires naming which
> of the four reasons below applies. **If you cannot name one, you fold it in.**

That is `csw:prep` Step 4's test turned around — *"if you can mark an option (Recommended), you
have your answer; do not ask, decide"* — and it works the same way: being unable to name a
reason is the answer, not a licence to defer.

Absorption is free for exactly as long as the worktree is alive: context loaded, branch open,
`validate` and `csw-gates` already wired, marginal cost of one more commit close to zero. Once
the worktree is gone the same fix costs a full dispatch, review, merge and cleanup cycle,
whether it rides a new ticket or a re-dispatch.

**Four dispositions, and every one of them is recorded in the ledger:**

| Disposition | When | Record |
|---|---|---|
| **Fold** | The default. Absorb it into this branch. | Its own commit, and a ledger row |
| **Spin out** | One of the four reasons applies, and you have named it | A new ticket, and a ledger row naming the reason and the ticket |
| **Drop** | Real, but not worth anyone's time — cosmetic, already known, superseded | A ledger row with the reason |
| **Block** | The discovery stops *this* ticket | Step 9: the question on the ticket, and a draft PR |

**Dropping is written down, never silent.** A finding judged not worth doing is a decision, and
the next dispatch needs to see that it was taken — otherwise the same thing is rediscovered,
re-triaged and re-filed on every run over that code. A dropped row costs one line and stops
that.

**The four spin-out reasons:**

1. **It cannot be validated here.** It needs a gate, an environment, or hardware this branch's
   `validate` cannot run.
2. **It is blocked.** It needs a decision nobody is there to give, or work that has not landed.
3. **It is outside this repo.** `csw:cleanup` Step 5 already searches for exactly these.
4. **It is larger than the ticket carrying it.** The test is mechanical:
   **would the pull request have to be retitled to describe the change?**
   If yes, it is reason 4. That protects what the reason exists to protect — the reviewer's
   headline — without reabsorbing everything the other three excluded.

**Anything else is not on the list.** "It is a deletion", "it is risky", "it is not what I was
asked for" are not reasons. A deletion inside the ticket's own declared scope is not a discovery
at all — it is the work.

Reason 2 and the **Block** disposition are not the same thing. Reason 2 means the *discovery*
cannot proceed, so it becomes a ticket and this ticket carries on. Block means the discovery has
stopped *this* ticket, so the run goes to Step 9.

**Folding in means re-entering the chain, not patching around it.** An in-scope item the plan
missed is a change to the spec, not a note on it. Absorbing anything beyond the trivial means
going back through `writing-plans` → `executing-plans` → TDD with the item added, then returning
here. Autonomous re-entry never includes brainstorming: Step 5 already skips it, and
`superpowers:brainstorming` carries an approval gate nobody is awake to satisfy. **An autonomous
dispatch that finds itself wanting to brainstorm has found a Step 9 stop, not another pass.**

**Absorbed work gets its own commit**, exactly as an ADR does and for the same reason: rejecting
it in review is then one revert rather than surgery on a diff someone wants to keep. That is
what makes absorbing safe unattended — review stays the filter, and the filter stays cheap to
operate.

**Stop after three passes.** A pass is one disposal pass plus one re-entry into Step 5. On the
fourth, absorption is over: everything still outstanding is spun out or dropped, and if an
acceptance item is still uncovered the run goes to Step 9 as a draft naming it. The failure to
design against is a dispatch that absorbs a discovery, whose absorption surfaces the next
discovery, all night — a run that ends up its own ancestor. Natural termination is not a brake
anyone can point at; a number is.

Then validate.

```bash
csw-config get validate            # run whatever this prints; empty means the repo declared none
csw-gates --worktree "<baseBranch>"  # run every line it prints
```

Step 7, not this one, is where `git add -A && git commit` happens. A plain
`csw-gates <baseBranch>` diffs against the merge base and so only sees committed history:
anything written in Step 5 but not yet committed — a new migration file, say — is invisible to
it and no gate fires on it. `--worktree` is the mode for exactly this moment. It unions the
committed diff against `<baseBranch>` with the working tree and reports the gates for the tree
as it will look after Step 7 commits it.

Do not hand-roll that union out of `git status` in the shell. `--worktree` reads git
NUL-delimited precisely because the line-based forms cannot be parsed safely: git C-style-quotes
any path containing a space or a non-ASCII byte, writes a rename on one line as `old -> new`,
and collapses a brand-new untracked directory to the directory alone — so a new
`backend/migrations/0002.sql` arrives as `backend/` and `**/migrations/**` never fires. Each of
those reaches a matcher mangled or not at all, which shows up as a gate that silently did not
run: the exact failure this step exists to prevent.

What comes out is the set of paths that will exist once this commits. Deletions contribute
nothing, since a path that is going away has nothing left to validate. A rename or a copy
contributes its destination only, for the same reason. A path containing a literal newline
cannot be represented in line-based matching at all, so it is a hard error rather than a
skipped gate.

Gates are gates. If one fails, fix it and re-run. If you cannot fix it, you are in Step 9.

## Step 7: Commit and open the PR

Conventional commit, subject referencing the ticket:

```bash
git add -A
git commit -m "<type>: <what changed>

<why it changed>

Refs: <TICKET>"
git push -u origin "<branch>"
gh pr create --fill --base "<baseBranch>" \
  --title "<type>: <what changed> (<TICKET>)" \
  --body "<summary, then 'Closes <TICKET>' or 'Refs <TICKET>'>"
```

If `git push` is rejected because the remote moved, pull, rebase, and push again — once. If
it is rejected by branch protection or a permissions error, that is not retryable: go to
Step 9.

If `gh pr create` fails for any reason, go to Step 9. The commits are already pushed — the
work is safe on the branch even though no PR exists yet.

Step 8 needs a real PR URL in hand. No PR means Step 9, not Step 8.

## Step 8: Stop

### Before the stop: did this produce a decision that outlives the ticket?

```bash
csw-config get adrDir
```

**Empty — the default — and none of the rest of this subsection runs.** A repo that keeps no
architecture decision records is never asked the question, and nothing about this dispatch
changes.

**Non-empty, and it names the directory this repo keeps its ADRs in.** Ask once: did this run
produce a decision that outlives its ticket — an approach rejected for a reason, a constraint
discovered the hard way, a rule the next person will otherwise re-break? The PR description is
where that knowledge goes to die; an ADR is where it survives.

**Most tickets produce nothing durable, and that is the expected answer.** An ADR per feature
devalues the practice; the discipline is in the rarity. This is a question, not a deliverable —
asking it is not the same as answering it yes.

Three rules bound what an ADR may do:

1. **An ADR never satisfies an acceptance item.** Where an item asks for a behaviour change,
   the ADR records *why* and the change is still owed. Writing a decision down is not making it
   so, and an item discharged by an ADR alone is an item that did not ship. An ADR is an
   attractive way to close out an item that actually demanded work; that is the trap.
2. **An ADR's follow-through is not a ticket.** The ADR already says what remains — that *is*
   the record, and filing a ticket to restate it is bookkeeping about bookkeeping. The
   follow-through is either absorbed at Step 6 or it is the reason the ticket does not close.
3. **An ADR that asserts a mechanism must verify that mechanism before asserting it.** Read the
   thing you are about to describe, and cite where you read it. Revertibility assumes somebody
   notices; an ADR built on a mechanism that does not exist costs the branch that inherits it,
   not the commit that carried it.

When the answer is genuinely yes, write it and push it onto the PR Step 7 just opened:

1. **Read what is already in that directory** for the local convention and for the next number.
   Where it is empty or absent, the fallback is `<adrDir>/NNNN-kebab-title.md` starting at
   `0001`, carrying `Date:`, `Status:`, and `Tracking:` naming the tickets, then a `## Context`
   section explaining the actual failure, the decision, and its consequences. An unset
   convention is not a reason to skip the question.
2. **Commit it on its own**, never folded into the implementation commit:
   ```bash
   git add "<adrDir>/NNNN-<title>.md"
   git commit -m "docs: record ADR NNNN — <title>"
   ```
   Rejecting an ADR in review is then one revert, rather than surgery on a diff someone wants
   to keep. That is what makes writing it unattended safe.
3. **Re-run the gates for that path, not the whole `validate`:**
   ```bash
   printf '%s\n' "<adrDir>/NNNN-<title>.md" | csw-gates --files
   ```
   Gates are file-triggered, so a repo with a docs gate still gets it. The full suite is a
   different matter — no code changed between the two commits, so re-running it doubles every
   ADR's cost and proves nothing.
4. **Push to the same branch.** The PR is already open; this is a second commit onto it.
5. **Say so where a human is already looking** — in the report below and in the PR body, naming
   the ADR and saying plainly that it is **proposed and revertible**. An ADR that merges
   unnoticed is the one way this goes wrong.

Two dispatches in one night can both claim the same `NNNN`: each branched from the base, and
neither can see the other's unmerged ADR. **Number from the directory at write time and let
review renumber the loser.** A collision is not your error and needs no sequencing machinery.

Where an ADR is warranted, it is worth citing from the README of the code it governs rather
than only from the ADR directory — reachable from where the mistake would be made. That is
advice, not a gate: an ADR written without touching a README has failed nothing.

A `csw:batch` dispatch does all of this identically. There is nothing here that differs between
a solo run and an unattended one, and nothing to check in order to tell them apart.

### Before the stop: say what this unblocks

A dispatch that takes a ticket to a PR has usually just cleared something out of another
ticket's way. The relation is already in the tracker and nothing reads it back, so the win is
real and invisible: the operator ends the night several tickets deep, without learning that the
objective they started with became runnable an hour ago.

Ask the tracker what this ticket blocks:

```bash
# tracker: github
gh issue view <number> --json blocking
```

For `linear`, `get_issue` with `includeRelations: true`.

`tracker: none`, or a tracker with no relation model at all — **skip the section silently.** No
line, no apology for having none. And the relations come from the tracker's own relation
fields, **never from prose**: `depends on #12` written in a description is a sentence, not a
relation, and a dispatch that reads dependencies out of English reports ones nobody recorded.

**Blocks nothing — print nothing at all.** No "this unblocks nothing" line. Blocking nothing is
the common case, and a line on every dispatch is exactly what trains the reader to skip the
section on the night it matters.

Otherwise read each blocked ticket's own blockers back. **Drop any that is itself
already closed** — the connection carries those too, and a finished ticket is waiting on
nothing. Each node also carries `repository.nameWithOwner`, so one in another repo needs
`--repo`:

```bash
gh issue view <n> --repo <owner/repo> --json number,title,blockedBy
```

**Count only the blockers still open, and leave this ticket out of the count.** `blockedBy`
carries closed blockers too, so a raw `totalCount` reports a ticket as blocked by work that
finished last month — which reads as "still blocked" and buries the completion this section
exists to surface.

Report it as conditional, because it is. **Merging this PR** is what clears the blocker; Step 8
holds an open PR and a ticket nobody has closed:

```
Merging this PR unblocks:
  #667  Measure the wedge rate under load  — no blockers left. Ready to run.
  #671  Retire the old sampler             — still blocked by #669.
```

**"No blockers left" is the whole point.** A partial unblock is worth its one line; a full one is
the thing somebody would change their afternoon over, so it is said in words rather than left to
be worked out from a count.

**Report only. Do not move anything.** No promoting the unblocked ticket out of the backlog, no
re-prioritising, no starting it, no filing the relation that was missing. This pass reads the
tracker and **never modifies** any ticket but the one the dispatch was sent for. A dispatch that
reaches into the tracker and changes the state of a ticket it was not dispatched for is a much
larger and more surprising change than the two lines it was asked for.

**Hold for review is a hard stop, not a checkpoint to talk past.** Report:

- The PR URL
- What changed, in a few lines a reviewer can hold in their head
- **Coverage against the ledger** — every acceptance item, and what covers it
- **What was found and how it was disposed** — folded, spun out with its ticket, or dropped
  with its reason
- Any ADR this run proposed — its path and its title, and that it is proposed, not decided
- **What merging this unblocks** — the tickets this one blocks, and which of them are left with
  no blockers at all. Nothing at all where it blocks nothing.
- What is worth testing on hardware — the parts CI cannot cover

**Nothing arrives here undisposed.** A finding reported at this point without a disposition
is a bug in Step 6, not a note for the reader: the PR is already open, so the reader's next
move is merge, and a finding surfaced now becomes another dispatch instead of another commit.
"Say the word and I'll…" is a disposal that did not happen.

Then stop. Do not merge. Do not run `csw:merge`. Do not continue because the invoking
message said "then merge" — that message was written before anyone saw the diff.

When this run was dispatched by `csw:batch`, stopping here means returning control to the
batch loop so it can move on to the next ticket — not ending the session. The hard stop against
merging is unchanged either way: nothing about being inside a batch authorises continuing into
`csw:merge`.

## Step 9: When it does not reach merge-ready

Failed validation you could not fix, a partial implementation, an approach that ran out of
road, a question only a human can answer, or a commit, push, or PR-create that failed and
would not retry. In every one of those cases:

1. Write the question or the blocker as a comment on the ticket.
2. Push a **draft** PR carrying the work so far: `gh pr create --draft ...`, referencing the
   comment.
3. Leave the ticket In Progress.
4. Report what stopped you.
5. Run the unblock pass above and report it here too. A draft closes nothing, so name what
   **would be unblocked** once this ticket lands rather than what is unblocked now — that is
   the context somebody uses to decide whether to push the draft over the line.

Draft is load-bearing. Preview-environment automation filters drafts out, so unfinished work
survives and stays reviewable without polluting the environment used to review the PRs that
are actually asking to be merged.

## Red flags

| Thought | Reality |
|---|---|
| "The diff is obviously fine, I'll just merge it" | The stop is the whole point. Someone else looks at it. |
| "They said 'autonomous to PR then merge'" | Then they said PR. Stop at the PR. |
| "Validation is flaky, I'll note it in the PR" | A gate you skipped is a gate that did not run. Fix it or go to Step 9. |
| "It's 90% done, I'll open a normal PR and flag the gap" | Not merge-ready means draft. Step 9. |
| "I'll create the worktree with git, it's faster" | Use EnterWorktree. Bypassing it strands state the harness cannot clean up. |
| "The title tells me enough about the ticket" | Read the description. The ordering constraints are in the prose. |
| "The description is the brief, I don't need the comments" | A `**CSW prep**` comment is part of the brief, and the answers under it are the decisions. |
| "Prep's question is unanswered but I can infer the answer" | Then the diff carries a guess that looks like a decision. Step 9, draft. |
| "No config file, I'll infer the validate command" | Ask. A wrong validate command means a green run that proves nothing. |
| "The baseline is red but my change will probably fix it" | It was red before you started. Report it and ask — that is the whole reason Step 1.5 runs before anything exists to suspect. |
| "The baseline was green, so the gate is half done" | Different subject. A green baseline says the machine was clean, and nothing at all about the change. |
| "They typed a word I don't recognise, I'll get on with the ticket" | An unrecognised modifier is a question, not noise. Name it back and ask. |
| "It's interactive, so someone is watching — I can merge it" | `interactive` changes planning only. Step 8 is the same hard stop. |
| "It's interactive, I'll confirm each step as I go" | The questions belong in Step 1. After that it runs like any other dispatch. |
| "I'll note this in the report and let them decide" | "Say the word and I'll…" is a disposal that did not happen. Dispose of it at Step 6, while the worktree is still open. |
| "It's adjacent, so it's a new ticket" | Fold is the default. A new ticket needs one of the four named reasons; if you cannot name one, absorb it. |
| "It's a deletion, so I left it" | Not a reason. A deletion inside the ticket's declared scope is not a discovery at all — it is the work. |
| "It's too small to be worth a ledger row" | A dropped finding nobody wrote down is rediscovered, re-triaged and re-filed on every future run over that code. |
| "One more absorption and I'll be done" | Three passes, then stop. A run that keeps absorbing what its own absorptions surface becomes its own ancestor. |
| "Five of six items shipped, that's merge-ready" | An uncovered acceptance item is a finding. Dispose of it at Step 6, or take the draft path. |
| "This ticket taught me something, that's an ADR" | Most tickets produce nothing durable. The bar is a decision that outlives the ticket, not a good day's work. |
| "The ADR records the decision, so the item is done" | An ADR never satisfies an acceptance item. The change is still owed. |
| "The ADR's follow-through needs its own ticket" | The ADR is already the record. Absorb it, or let it be why the ticket does not close. |
| "Nobody is watching, an ADR needs a human to agree" | Write it. Review rejects it — that is where the rarity is enforced, and it is one revert because the ADR is its own commit. |
| "The ADR may as well ride the implementation commit" | Then rejecting it is surgery on a diff someone wants to keep. Its own commit, always. |
| "My ADR number collides with another branch's" | Not your error. Number from the directory, say so, and let review renumber it. |
| "It blocks nothing, I'll say so for completeness" | Blocking nothing prints nothing. A line on every dispatch is what trains the reader to skip the section on the night it matters. |
| "It unblocks something, so I'll move that ticket along" | Report only. Changing the state of a ticket nobody dispatched you for is a much larger change than the line you were asked for. |
| "The description says it depends on #12, that's a relation" | It is a sentence. Relations come from the tracker's relation fields or the section does not run. |
