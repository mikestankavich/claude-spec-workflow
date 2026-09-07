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

  # --- stop: the whole process group, and only inside the worktree ---
  wt3=$(mktemp -d); TMPDIRS+=("$wt3")
  keep=$(mktemp -d); TMPDIRS+=("$keep")
  # setsid gives the tree its own process group, which is what a dev server
  # started by another session has. The child is the leaf that would hold the
  # port: signalling only the parent leaves it running, which is the failure
  # this targets.
  setsid bash -c "cd '$wt3' && sleep 300 & sleep 300" >/dev/null 2>&1 &
  ( cd "$keep" && exec sleep 300 ) & keep_pid=$!
  sleep 0.5

  out=$("$SERVICES" stop "$wt3" --grace 1)
  # It names what it is about to interrupt before interrupting it. Unprompted
  # and destructive is only reviewable if it says what it touched.
  assert_contains "$out" "sleep" "stop names the command it interrupted"
  assert_contains "$out" "stopped:" "stop reports a closing summary"
  sleep 0.5
  survivors=""
  for p in $(pgrep -x sleep 2>/dev/null); do
    [ "$(readlink "/proc/$p/cwd" 2>/dev/null)" = "$wt3" ] && survivors="$survivors $p"
  done
  assert_eq "$survivors" "" "stop leaves nothing running from the worktree, leaves included"
  assert_eq "$(kill -0 "$keep_pid" 2>/dev/null && printf alive)" "alive" \
    "stop leaves a process outside the worktree alone"
  kill "$keep_pid" 2>/dev/null; wait "$keep_pid" 2>/dev/null

  # The case that makes signalling the *group* load-bearing rather than
  # decorative: a descendant that chdir'd out of the worktree. Discovery cannot
  # see it -- its cwd names somewhere else entirely -- but it belongs to a tree
  # that originated in the worktree, and it is what would still be holding the
  # port. Signalling the found pids one by one leaves it running.
  wt4=$(mktemp -d); TMPDIRS+=("$wt4")
  elsewhere_dir=$(mktemp -d); TMPDIRS+=("$elsewhere_dir")
  marker="$elsewhere_dir/strayed.pid"
  setsid bash -c "cd '$wt4' && { cd '$elsewhere_dir' && sleep 300 & echo \$! >'$marker'; } && sleep 300" \
    >/dev/null 2>&1 &
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -s "$marker" ] && break
    sleep 0.1
  done
  strayed=$(cat "$marker" 2>/dev/null)
  # It really did chdir away, so discovery genuinely cannot reach it.
  assert_eq "$(readlink "/proc/$strayed/cwd" 2>/dev/null)" "$elsewhere_dir" \
    "the strayed descendant's cwd is outside the worktree"
  seen=$("$SERVICES" json "$wt4" | jq --argjson p "${strayed:-0}" '[.processes[].pid] | index($p)')
  assert_eq "$seen" "null" "discovery cannot see the strayed descendant"

  "$SERVICES" stop "$wt4" --grace 1 >/dev/null
  sleep 0.5
  assert_eq "$(kill -0 "$strayed" 2>/dev/null && printf alive)" "" \
    "the strayed descendant goes with its process group"

  # Stopping nothing is success, and says so rather than passing over in silence.
  quiet=$(mktemp -d); TMPDIRS+=("$quiet")
  assert_status 0 "stopping an empty worktree exits 0" -- "$SERVICES" stop "$quiet"
  assert_contains "$(cd / && "$SERVICES" stop "$quiet")" "nothing" \
    "the empty teardown is reported, not passed over in silence"
  assert_status 2 "--grace needs a number" -- "$SERVICES" stop "$quiet" --grace soon
fi

# --- Arm 2: compose projects, by the label the runtime already keeps ---
# A fake docker, because these assertions are about which containers get
# selected, and a machine with a real docker would make the answer depend on
# whatever happens to be running on it.
fakebin=$(mktemp -d); TMPDIRS+=("$fakebin")
repo2=$(make_repo)
write_config "$repo2" <<'JSON'
{ "worktreeDir": ".claude/worktrees" }
JSON
# The two worktrees are siblings under worktreeDir, which is the real shape --
# one live, one already removed. Using the repo root as the live worktree would
# have nested the dead one inside it and made the subtree match look like a bug.
mkdir -p "$repo2/.claude/worktrees"
live="$repo2/.claude/worktrees/feat+1260-live"
mkdir -p "$live/backend"
gone="$repo2/.claude/worktrees/fix+1253-already-removed"   # deliberately never created

cat >"$fakebin/docker" <<EOF
#!/usr/bin/env bash
# Four containers: one from the worktree under test, one from a subdirectory of
# it (a compose file under backend/ is still that worktree's), one carrying no
# compose label at all, and one whose working_dir is a worktree that no longer
# exists.
if [ "\$1" = "ps" ]; then
  printf '%s\t%s\t%s\t%s\t%s\n' "db"       "$live"          "timescaledb" "Up 10 hours" "0.0.0.0:5432->5432/tcp"
  printf '%s\t%s\t%s\t%s\t%s\n' "api"      "$live/backend"  "backendapi"  "Up 9 hours"  "0.0.0.0:8080->8080/tcp"
  printf '%s\t%s\t%s\t%s\t%s\n' "buildkit" ""               ""            "Up 3 days"   ""
  printf '%s\t%s\t%s\t%s\t%s\n' "olddb"    "$gone"          "tra1253"     "Up 10 hours" "0.0.0.0:5433->5432/tcp"
  exit 0
fi
printf 'fake docker: unexpected args: %s\n' "\$*" >&2
exit 1
EOF
chmod +x "$fakebin/docker"
wt2="$live"

proj=$(CSW_SERVICES_DOCKER="$fakebin/docker" "$SERVICES" json "$wt2" | jq -c '[.composeProjects[].project]')
assert_eq "$proj" '["backendapi","timescaledb"]' "compose projects rooted in the worktree, subdirectories included, are selected"
case "$proj" in
  *buildkit*)
    assert_eq "unlabelled-container-selected" "not-selected" \
      "a container with no worktree label is left alone" ;;
  *) PASSES=$((PASSES + 1)) ;;
esac
case "$proj" in
  *tra1253*)
    assert_eq "other-worktree-container-selected" "not-selected" \
      "a container from a different worktree is left alone" ;;
  *) PASSES=$((PASSES + 1)) ;;
esac

# The human report names the container and its ports, so an unprompted teardown
# stays reviewable.
compose_report=$(CSW_SERVICES_DOCKER="$fakebin/docker" "$SERVICES" report "$wt2")
assert_contains "$compose_report" "timescaledb" "the report names the compose project"
assert_contains "$compose_report" "5432" "the report names the published port"

# The orphan report: provably ours by origin, abandoned, and reported rather
# than acted on -- nothing owns that worktree any more, so nothing may tear it
# down on its own authority.
orph=$(in_dir "$repo2" env CSW_SERVICES_DOCKER="$fakebin/docker" "$SERVICES" orphans)
assert_contains "$orph" "tra1253" "an orphaned compose project under worktreeDir is reported"
assert_contains "$orph" "no longer exists" "the orphan line says why it is an orphan"
case "$orph" in
  *timescaledb*)
    assert_eq "live-worktree-reported-as-orphan" "not-reported" \
      "a project whose worktree still exists is not an orphan" ;;
  *) PASSES=$((PASSES + 1)) ;;
esac
assert_status 0 "reporting orphans exits 0" -- \
  in_dir "$repo2" env CSW_SERVICES_DOCKER="$fakebin/docker" "$SERVICES" orphans
assert_status 2 "orphans takes no arguments" -- \
  in_dir "$repo2" env CSW_SERVICES_DOCKER="$fakebin/docker" "$SERVICES" orphans "$wt2"

# A container outside worktreeDir is not an orphan however dead its directory
# is: it is not provably CSW's, so it is somebody else's business.
cat >"$fakebin/docker-elsewhere" <<'EOF'
#!/usr/bin/env bash
[ "$1" = "ps" ] || exit 1
printf '%s\t%s\t%s\t%s\t%s\n' "x" "/nonexistent/somewhere/else" "elsewhere" "Up 1 hour" ""
EOF
chmod +x "$fakebin/docker-elsewhere"
elsewhere=$(in_dir "$repo2" env CSW_SERVICES_DOCKER="$fakebin/docker-elsewhere" "$SERVICES" orphans)
assert_contains "$elsewhere" "no orphaned compose projects" \
  "a dead working_dir outside worktreeDir is not reported as ours"

# Docker present but not answering is "unknown", never "absent" -- csw-sweep
# draws the same line between a clean sweep and a sweep that did not run.
cat >"$fakebin/docker-down" <<'EOF'
#!/usr/bin/env bash
printf 'Cannot connect to the Docker daemon at unix:///var/run/docker.sock.\n' >&2
exit 1
EOF
chmod +x "$fakebin/docker-down"
down=$(in_dir "$repo2" env CSW_SERVICES_DOCKER="$fakebin/docker-down" "$SERVICES" report "$wt2")
assert_contains "$down" "unknown, not absent" \
  "a docker that will not answer is reported as unknown, not as nothing running"
assert_status 0 "a docker that will not answer is not an error" -- \
  in_dir "$repo2" env CSW_SERVICES_DOCKER="$fakebin/docker-down" "$SERVICES" report "$wt2"

report
