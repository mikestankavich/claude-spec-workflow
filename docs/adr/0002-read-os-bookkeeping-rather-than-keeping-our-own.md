# 0002 — Read the bookkeeping the OS already keeps, rather than keeping our own

Date: 2026-09-07
Status: Proposed
Tracking: #119

## Context

`csw:cleanup` removes a worktree and leaves anything running from it still running. The
directory goes; the dev server, the file watcher, the database container and the port bindings
survive it. Cleanup does not merely fail to tidy up — **it is what manufactures these orphans**,
because removing the worktree is the moment those processes stop having a valid home and become
indistinguishable from the live session's.

The cost is not the wasted process. It is that a test run goes green against a backend, frontend
or **database** belonging to a different branch, and every precondition check passes.

### The incident

`trakrf/platform`, 2026-09-07, tracked there as TRA-1260. Three generations of host-process
orphans from two dead sessions plus the live one — three `air` instances racing for `:8080` with
the winner decided by startup order, and a vite that lost `:5173` and silently took `:5174`.

The container case is worse, and is what drove the design:

```
timescaledb   started 2026-09-07T04:22Z (~10h)   5432/tcp -> 0.0.0.0:5432
com.docker.compose.project.working_dir:
  /home/mike/trakrf/platform/.claude/worktrees/fix+tra-1253-…
```

That worktree no longer existed. TRA-1253 merged at 09:21 and `csw:cleanup` removed the
directory; the container stayed up, publishing 5432 on all interfaces. At the same moment the
rest of the stack was *current* — `server` on `:8080` was 9m50s old, `node` on `:5173` was
7m01s, both from the main checkout. **The database both were talking to was ten hours old and
owned by a deleted worktree**, having outlived two full generations of the stack in front of it.

### Why an orphan is permanent

The session owning the live stack was asked to account for it and answered correctly: *"Not
mine, left alone: `timescaledb` — docker, up 10 hours, healthy. It predates me; `just dev`
reused it rather than starting one."*

That is the right call by every reasonable rule. The container was present, healthy and on the
expected port, so the stack attached rather than starting its own, then correctly disclaimed
something it had not started. **Every subsequent session reaches the same conclusion.** A
healthy orphan does not get ignored — it gets *adopted*, and each new stack silently inherits a
database whose provenance nobody checked. The only session that could ever have reaped it was
TRA-1253's, and it was gone.

## Decision

**Before adding a record, check whether the OS, the runtime or the tool already keeps one.**

Everything the teardown needs is already recorded by something that had to record it anyway:

| question | who already answers it | act or report |
|---|---|---|
| was this process launched from the worktree? | the kernel — `/proc/<pid>/cwd` | stop |
| is the running image a build artifact of the worktree? | the kernel — `/proc/<pid>/exe` | stop |
| is something merely holding a file open in it? | the kernel — `/proc/<pid>/fd/*` | **report** |
| which worktree owns this container? | the container runtime — `com.docker.compose.project.working_dir` | stop |
| is this thing supervised, and therefore not ours? | the supervisor — the cgroup leaf systemd writes | never touch |
| what worktrees exist at all? | git itself — `worktree list` | — |

None of it can go stale, because **each record is maintained by the thing it describes**. A
`.csw-services` file we write ourselves is one more record of facts these systems already keep
accurately, and it is the only one that can drift, be skipped, or be left behind.

**Origin and use are different claims, and only origin authorises stopping.** A cwd or an exe
inside the tree says the process *came from here*. An open descriptor says only that it is
*using* what is here — an editor, an LSP, a `tail -f` from another terminal — and killing one
because it had a file open is exactly the blast radius this design exists to avoid.

The holder is still worth a line, because removal **breaks** it, and silently: the descriptor
goes on pointing at a deleted inode, and an inotify watch on a deleted directory never fires
again. Nothing raises an error anywhere. So an orphan survives and is *wrongly adopted*, while a
holder survives and *stops working* — two different harms, and the second has no other warning in
the system.

Two consequences fall out rather than being bolted on:

- **Scope safety is structural.** `bin/csw-services` takes a worktree path and can only report
  what belongs to it. There is no machine-wide acting mode to misuse, so "what might this
  touch" is answerable in one sentence.
- **Adoption is irrelevant.** A later session attaching to a service does not change where the
  service came from, so the reuse case that defeats a ledger resolves itself.

### The mechanisms, and where each was verified

Rule 3 of the ADR discipline: read the thing before asserting it.

- **cwd is the only field that carries the information.** Measured against four live dev
  processes on 2026-09-07: `exe` matched 0/4 (`air` resolves to `~/go/bin/air`, node to fnm's
  install dir, shells to `/usr/bin/dash` — installed tooling lives outside the tree); `cmdline`
  matched 0/4 (`air`, `node scripts/dev-bridge.js`, `pnpm run dev:bridge` — all relative,
  *because* the cwd was already set); `cwd` matched 4/4. So `ps -e -o pid,exe | grep <worktree>`
  finds nothing, and neither does grepping the command line.
- **The ` (deleted)` suffix.** The kernel appends it to `/proc/<pid>/cwd` once the directory is
  unlinked, which is precisely the orphan case. Stripped in `read_link()` in `bin/csw-services`;
  covered by the discovery tests in `tests/test-csw-services.sh`.
- **`/proc/<pid>/stat` is parsed from the last `)`.** Field 2 is `comm`, parenthesised and free
  to contain spaces and parentheses; a whitespace split mis-numbers every field after it and
  silently turns a process-group id into some other number. `proc_stat_fields()`, guarded by a
  fixture whose comm is literally `(node (dev) run)`.
- **Supervision is a cgroup leaf, not an uptime.** A `systemd --user` unit lands under
  `user@<uid>.service/…` with a `.service` leaf; a process a session merely launched lands on a
  `.scope`. `is_supervised()` reads what systemd itself wrote, so it costs nothing per pid and
  cannot disagree with what systemd thinks. The test is supervision, not age: an 18-hour
  supervised BLE bridge on `:25153` is *correct*, and a 10-hour orphaned container is not, and
  nothing that only looks at uptime can tell them apart.
- **The process group, not the pid.** Observed trees run 5–7 levels deep (`pnpm` → `node` →
  `sh` → `node` → `sh` → `node` → `node`) and the leaf is what holds the port. Discovery only
  sees processes whose cwd is *still* in the worktree, so a descendant that `chdir`'d away is
  invisible to it and would survive per-pid signalling. `tests/test-csw-services.sh` asserts
  exactly that case, and it fails when the group arm is removed.

## Alternatives rejected

### A `.csw-services` ledger written by `csw:work`

The first design had `csw:work` Step 5 record every long-running process it started into a
per-worktree file, and cleanup read it back. Today's evidence rules it out as the primary
mechanism:

- **It cannot reach a reused service.** No dispatch started the orphaned container; a later one
  adopted it. A ledger of what was *started* is structurally blind to exactly the case that
  caused the harm.
- **It requires cooperation from every dispatch.** A rule that depends on a dispatch remembering
  to append to a file before carrying on fails silently when skipped — and base behaviour beats
  good intentions.
- **It needs pid-recycling verification** — recorded command and start time compared on read —
  which discovery gets for free, because a live cwd or label *is* the proof of identity.

Discovery is both cheaper and more complete. Nothing is written, nothing goes stale, and
`csw:work` is untouched.

### A machine-wide orphan reaper

The neutron-bomb version scans the whole machine and reaps whatever looks repo-adjacent. It
would take out a supervised bridge and a shared build container alongside the real zombies. The
opposite failure — scanning and never removing anything — leaves cleanup manufacturing orphans
exactly as it does today. Both halves are needed: teardown *is* destructive and unprompted, with
a blast radius of exactly one worktree.

## Consequences

- **The rule is preventive, and only preventive.** It stops new orphans being created. It cannot
  reach one whose worktree is already gone, because no future cleanup run owns that worktree —
  nothing will ever be "cleaning up after itself" with respect to it. The container observed
  above is exactly that case and stays running until a human stops it.
- **One report-only exception.** A compose project whose `working_dir` names a path that does not
  exist under this repo's configured `worktreeDir` is provably a worktree CSW created and
  removed. `csw-sweep` reports these and never touches them, because what makes teardown safe
  elsewhere is that a live run owns the worktree, and here nothing does. Without that line the
  design would be silent about every orphan created before it shipped, including the one that
  prompted it.
- **Two shapes leave no origin trace, and both are accepted gaps.** An *interpreted* process that
  daemonised and `chdir`'d away, classically to `/` — a compiled one is still caught by `exe`,
  which is what closes the `air` case the issue flagged; and a container started with plain
  `docker run`, which carries no `working_dir` label. These are the cases a written ledger would have covered, and
  they are the honest cost of dropping it. Both are rare in dev tooling — the observed stack had
  neither — and neither justifies asking every dispatch to self-report on every run. Revisit
  only if they show up in practice.
- **This repo cannot dogfood it.** CSW runs no services, so `tests/test-csw-services.sh` covers
  the selection rules against fixtures and the real validation is a session in a repo with a
  live stack. Recorded in CONTRIBUTING.md rather than left to be discovered.

## Success criterion

No session finds a service whose `working_dir` or `cwd` names a worktree that a `csw:cleanup`
run removed after this shipped. Orphans predating it are expected, and are what the sweep's
report-only line exists to surface.
