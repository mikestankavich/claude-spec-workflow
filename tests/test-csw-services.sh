#!/usr/bin/env bash
# csw-services finds and stops what originated in one worktree -- and nothing else.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

if ! command -v python3 >/dev/null 2>&1; then
  printf 'skip: python3 not available\n'
  exit 0
fi

SERVICES="$BIN/csw-services"

# --- usage ---
assert_status 2 "no subcommand is a usage error" -- "$SERVICES"
assert_status 2 "unknown subcommand is a usage error" -- "$SERVICES" frobnicate /tmp
assert_status 2 "report without a worktree path is a usage error" -- "$SERVICES" report

# Everything in Arm 1 needs /proc. The compose arm does not, so this file skips
# only the host-process assertions rather than exiting.
have_proc=0
[ -d /proc/self ] && have_proc=1

if [ "$have_proc" = "1" ]; then
  wt=$(mktemp -d); TMPDIRS+=("$wt")
  outside=$(mktemp -d); TMPDIRS+=("$outside")

  # A process whose cwd is inside the worktree, and one whose cwd is not.
  ( cd "$wt" && exec sleep 300 ) & inside_pid=$!
  ( cd "$outside" && exec sleep 300 ) & outside_pid=$!
  # Wait for the exec to settle so /proc/<pid>/cwd is the final one.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(readlink "/proc/$inside_pid/cwd" 2>/dev/null)" = "$wt" ] && break
    sleep 0.1
  done

  pids=$("$SERVICES" json "$wt" | jq -c '[.processes[].pid]')
  assert_contains "$pids" "$inside_pid" "a process cwd'd into the worktree is found"
  case "$pids" in
    *"$outside_pid"*)
      assert_eq "outside-process-found" "not-found" \
        "a process cwd'd outside the worktree must not be found" ;;
    *) PASSES=$((PASSES + 1)) ;;
  esac

  # The caller is never a candidate. csw:cleanup runs this from *inside* the
  # worktree it is about to remove, so the calling session's own tree matches
  # the cwd test; without the exclusion the tool's first act is to kill its
  # caller.
  self_seen=$(cd "$wt" && "$SERVICES" json "$wt" | jq --argjson p "$$" '[.processes[].pid] | index($p)')
  assert_eq "$self_seen" "null" "the calling shell is never reported as a candidate"

  # The human report names what it found, so an unprompted teardown stays reviewable.
  human=$(cd / && "$SERVICES" report "$wt")
  assert_contains "$human" "$inside_pid" "the report names the pid"
  assert_contains "$human" "sleep" "the report names the command"

  kill "$inside_pid" "$outside_pid" 2>/dev/null
  wait "$inside_pid" "$outside_pid" 2>/dev/null

  # Finding nothing is information, not an error -- csw-sweep's rule.
  empty=$(mktemp -d); TMPDIRS+=("$empty")
  assert_status 0 "an empty worktree exits 0" -- "$SERVICES" report "$empty"
  assert_contains "$(cd / && "$SERVICES" report "$empty")" "nothing" \
    "an empty result says so rather than printing nothing at all"
fi

report
