# 0001 — Dispose of mid-build discoveries before the commit, not after the PR

Date: 2026-09-07
Status: Accepted
Tracking: #116, #114

## Context

`csw:work` Step 5 ran `writing-plans` → `executing-plans` → TDD exactly once and then fell
through to validate, commit, PR, stop. There was no arc back. Anything learned *during* the
build — a missed in-scope item, an adjacent defect, a decision that turned out to need
implementing — had no path into the spec it invalidated. It could only travel forward into the
Step 8 report.

A report is where a finding turns into a cycle. Step 8 runs *after* Step 7 has committed,
pushed and opened the pull request, so a finding surfaced there arrives at the moment the
reader's next move is merge. Its natural expression is "say the word and I'll…", which is a
disposal that did not happen.

### The incident

TRA-1253, 2026-09-06/07. The unattended build was not the problem: one dispatch, about 4.5
hours, one PR, a six-item ticket. The cost was the tail — roughly 08:47 to 10:09, about 1h20m
of review, merge and cleanup — because a six-item ticket became **three** dispatch → review →
merge → cleanup cycles at a ten-minute minimum each. It became three because two items were
each disposed of as a *report* rather than absorbed:

- Item 6 was left with the stated reason *"it's a deletion and I left it"*. A deletion inside
  the ticket's own declared scope is not a discovery; it is the work.
- Item 2 was half-implemented, and the ticket was nevertheless closed as Done at 09:22 with the
  claim *"all six items shipped"*, then closed again at 10:04 after a third PR implemented it.

"Say the word and I'll…" appeared three times in twenty-five minutes, and drew
*"FFS can we quit with the ticket whack-a-mole already?????"*

Nothing in the workflow could have caught the coverage failure. `work` Step 2 said "read the
**whole** description" but never extracted it; Step 6's `validate` and `csw-gates` answer *does
it work*, never *is it all there*; Step 8's report had no slot for what was noticed and not
done; Step 9's draft path is all-or-nothing, and five of six items satisfies every rule for
merge-ready; `cleanup` Step 5 asked a human to confirm closure with no coverage evidence at all.

### The measurement

Over TRA-1141 → TRA-1260: 120 tickets, 2026-08-20 → 2026-09-07, 19 active days.

| Lifetime of the 90 closed tickets | n | share | cumulative |
|---|---|---|---|
| under 10 min | 5 | 6% | 6% |
| 10 min – 1 h | 9 | 10% | 16% |
| 1 h – 8 h | 19 | 21% | 37% |
| 8 h – 24 h | 20 | 22% | **59%** |
| 1 – 3 days | 15 | 17% | 76% |
| over 3 days | 22 | 24% | 100% |

- **53 of 120 tickets (44%) closed within 24 hours of being filed** — a floor on the derivative
  population, since it cannot count derivative tickets still open.
- **94 of 120 (78%) were created within 90 minutes of another creation.** Four days carry 68 of
  the 120 creations.
- Five tickets lived under ten minutes: TRA-1238 (28 seconds, canceled), TRA-1152 (4m 13s),
  TRA-1208 (5m 06s, duplicate), TRA-1176 (5m 37s, canceled), TRA-1175 (6m 35s, canceled). Each
  cost a create, a triage and a close and produced nothing.

Most of this is a working set being written down, not a backlog. That is what makes the change
worth making: it removes a per-discovery cycle tax from work that is already same-session.

The same data sets the brakes. 2026-08-29 created 19 tickets (TRA-1193 → TRA-1211), 11 closed
the same day, five within the hour. Nineteen discoveries in one day is not one pull request
under any reading, so a fold-by-default rule without a size test and an iteration cap would
trade this failure for an unreviewable branch.

## Decision

**Disposal happens before the commit, at the head of Step 6, while the worktree is still open.**

1. **Step 5 collects, and does not act.** A discovery is noted to a running list and the work in
   hand continues. Collecting beats remembering: a pass that runs on recall dispositions
   whatever is still in context, which is never the same set as what was found.
2. **Step 6 disposes of the whole list, and of every uncovered acceptance item,** before
   `validate` runs — because absorbed work has to be validated by the run that absorbs it.
3. **Fold is the default and needs no justification.** Spinning out requires naming one of four
   reasons: it cannot be validated here; it is blocked; it is outside this repo; or it is larger
   than the ticket carrying it. **If you cannot name one, you fold it in.** Nothing else is on
   the list.
4. **Reason 4 has a mechanical test — would the pull request have to be retitled?** It is the
   softest of the four and the one protecting review quality, so it gets a check rather than a
   judgement call.
5. **Drop is a first-class disposition and is recorded.** A finding judged not worth doing is a
   decision the next dispatch needs to see, or the same thing is rediscovered and re-filed on
   every run over that code.
6. **Absorbed work gets its own commit**, so rejecting it in review is one revert rather than
   surgery on a diff someone wants to keep. That is what makes absorbing safe unattended.
7. **Absorption stops after three passes.** Overflow is spun out, dropped, or sent to Step 9 as
   a draft.
8. **Scope becomes an enumerated acceptance ledger** — written by `csw:prep` into its
   `**CSW prep**` comment, carried and updated by `csw:work` in a separate `**CSW scope**`
   comment, and read by `csw:cleanup`, which will not propose closure while an item is
   uncovered. An item on the ledger never becomes a new ticket.

## Alternatives rejected

**A discoveries pass at Step 8, with fold / ticket / drop (the design in #114).** Rejected on
placement. Step 8 runs after Step 7 has pushed and opened the PR, so a finding surfaced there
still arrives when the reader's next move is merge — which is the mechanism that produced the
1h20m tail, not a side effect of it. Absorption is free only while the worktree is alive:
context loaded, branch open, `validate` and `csw-gates` wired, marginal cost of one more commit
close to zero.

#114's argument for Step 8 was that a discovery can *be* the ADR, so dispositions should settle
first. That is satisfied by ordering rather than placement: the disposal pass runs at Step 6 and
the ADR question at Step 8, both inside `csw:work`, and a discovery can still become an ADR.

Two of #114's contributions were kept, because #116 lacked them: **collect at Step 5 rather than
recall at the checkpoint**, and **drop as a first-class outcome**. #114 is closed as absorbed
into this work.

**Nudging rather than granting authority.** Rejected on the evidence in #116: `grep` across
`skills/` returned nothing about mid-build discovery, and into that vacuum the base behaviour is
report-don't-act, because acting outside the brief reads as scope creep and every surrounding
rule reinforces staying inside it. A dispatch was correctly declining an authority it had never
been granted. A nudge loses to that discipline every time; the grant has to be explicit and its
exceptions closed.

## Consequences

- **Diffs get larger, and review becomes the filter.** Every absorption is its own commit, so
  the filter is cheap to operate — rejecting one is a revert. `csw:batch` reports absorbed work
  in its own summary section for the same reason ADRs get one: work that merges unnoticed is how
  an absorption default goes wrong.
- **A ticket's closure now depends on an artifact that can be absent.** A ticket with no ledger
  is reported as such rather than silently waved through, so it stays visible that closure is
  resting on recollection rather than evidence.
- **`csw:batch` will dispatch fewer tickets.** A decide-shaped ticket with unanswered questions
  is now skipped and routed to `csw:prep` or `csw:work interactive`. That is the intended trade:
  an unattended dispatch handed a decision will make one, and the expensive version of that is a
  decision recorded as an ADR that the next branch has to correct.

## Success criterion

**80% of same-day discoveries are resolved by the dispatch that found them**, rather than by a
follow-on cycle.

The remaining 20% is accepted as genuinely novel or unanticipated — not a gap to close. The four
spin-out reasons and the three-pass cap exist to route that fifth cleanly. A design that tried
to absorb it too would be the unbounded loop the cap prevents: a dispatch absorbing a discovery,
whose absorption surfaces the next discovery, until the run is its own ancestor.
