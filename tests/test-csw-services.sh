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

  # --- the listening port, resolved through two hops of real bookkeeping ---
  # /proc/net/tcp maps a socket inode to a listening port, /proc/<pid>/fd maps a
  # pid to its inodes. Nothing else in this file exercises that, and the port is
  # the single most useful thing in the report -- it is what a human recognises
  # a stray dev server by.
  portdir=$(mktemp -d); TMPDIRS+=("$portdir")
  portfile="$portdir/port"
  # The kernel picks the port, so this never collides with whatever else is
  # listening on the machine running the suite.
  ( cd "$portdir" && exec python3 -c '
import socket, sys, time
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(1)
with open(sys.argv[1], "w") as fh:
    fh.write(str(s.getsockname()[1]))
time.sleep(300)
' "$portfile" ) & port_pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [ -s "$portfile" ] && break
    sleep 0.1
  done
  bound=$(cat "$portfile" 2>/dev/null)
  reported=$("$SERVICES" json "$portdir" \
    | jq -c --argjson p "$port_pid" '.processes[] | select(.pid == $p) | .ports')
  assert_eq "$reported" "[${bound:-missing}]" \
    "the listening port is reported, resolved through /proc/net/tcp and /proc/<pid>/fd"
  human_port=$(cd / && "$SERVICES" report "$portdir")
  assert_contains "$human_port" ":${bound:-missing}" "the human report names the port"
  kill "$port_pid" 2>/dev/null
  wait "$port_pid" 2>/dev/null

  # --- origin is not only cwd, and not every tie to the tree is an origin ---
  #
  # cwd answers "was this launched from here". Two other things the kernel
  # already records answer questions cwd cannot:
  #
  #   exe -> inside   the running image IS a build artifact of this worktree
  #                   (`air` builds ./tmp/main and execs it, then chdir's away).
  #                   That is origin, so it is stopped.
  #   fd  -> inside   the process is merely *using* a file in the tree -- an
  #                   editor, an LSP, a tail from another terminal. That is use,
  #                   not origin, so it is reported and never signalled.
  #
  # The asymmetry is the point: killing an editor because it had a file open is
  # exactly the blast radius this tool exists not to have.
  wt6=$(mktemp -d); TMPDIRS+=("$wt6")
  out6=$(mktemp -d); TMPDIRS+=("$out6")
  mkdir -p "$wt6/tmp" "$wt6/src"
  cp /bin/sleep "$wt6/tmp/main"
  printf 'seed\n' >"$wt6/src/watched.txt"

  ( cd "$out6" && exec "$wt6/tmp/main" 300 ) >/dev/null 2>&1 & exe_pid=$!
  ( cd "$out6" && exec tail -f "$wt6/src/watched.txt" ) >/dev/null 2>&1 & fd_pid=$!
  sleep 0.6

  six=$("$SERVICES" json "$wt6")
  assert_eq "$(printf '%s' "$six" | jq --argjson p "$exe_pid" '[.processes[].pid] | index($p) != null')" \
    "true" "a binary running from inside the tree is found, though its cwd is elsewhere"
  assert_eq "$(printf '%s' "$six" | jq --argjson p "$fd_pid" '[.processes[].pid] | index($p) != null')" \
    "false" "a process merely holding a file open is not treated as originating here"
  assert_eq "$(printf '%s' "$six" | jq --argjson p "$fd_pid" '[.fdHolders[].pid] | index($p) != null')" \
    "true" "...but it is reported as holding the worktree open"
  holder_report=$(cd / && "$SERVICES" report "$wt6")
  assert_contains "$holder_report" "not stopped" \
    "the report says plainly that fd holders are reported rather than stopped"
  # Not just "left alone" -- removal *breaks* them. The fd goes on pointing at a
  # deleted inode and the inotify watch never fires again, so an editor or LSP
  # holding a file here silently stops working. That consequence is the whole
  # reason the line is worth printing.
  assert_contains "$holder_report" "break" \
    "the report says removal will break the holder, not merely that it was skipped"
  assert_contains "$holder_report" "watched.txt" \
    "the report names the path being held, so the human can tell whose it is"

  "$SERVICES" stop "$wt6" --grace 1 >/dev/null
  sleep 0.4
  assert_eq "$(kill -0 "$exe_pid" 2>/dev/null && printf alive)" "" \
    "the binary running from the tree is stopped"
  assert_eq "$(kill -0 "$fd_pid" 2>/dev/null && printf alive)" "alive" \
    "the fd holder survives teardown -- it was never ours to kill"
  kill "$fd_pid" 2>/dev/null; wait "$fd_pid" 2>/dev/null

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

# --- exclusion 1: supervised units, against a fake proc root ---
# A systemd --user unit is designed to outlive every session, and the test is
# supervision rather than uptime: an 18-hour supervised bridge is correct and a
# 10-hour orphaned container is not, and nothing that only looks at age can tell
# them apart. There is no way to create a real user unit in a test, so the
# classifier is exercised against the bookkeeping it actually reads.
fakeproc=$(mktemp -d); TMPDIRS+=("$fakeproc")
wt5=$(mktemp -d); TMPDIRS+=("$wt5")
printf '99999.0 99999.0\n' >"$fakeproc/uptime"
mkdir -p "$fakeproc/self"

mkproc() { # pid cgroup-leaf
  local d="$fakeproc/$1"
  mkdir -p "$d/fd"
  ln -sfn "$wt5" "$d/cwd"
  # /proc/<pid>/stat with a parenthesised comm that itself contains a space and
  # a ')', which is what breaks a naive whitespace split. Post-comm fields are
  # state, ppid, pgrp, ... with starttime the 20th.
  printf '%s (node (dev) run) S 1 %s 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 100 0 0 0\n' "$1" "$1" >"$d/stat"
  printf 'Name:\tfakeproc\nPPid:\t1\n' >"$d/status"
  printf 'fake\0proc\0' >"$d/cmdline"
  printf '0::/user.slice/user-1000.slice/user@1000.service/%s\n' "$2" >"$d/cgroup"
}
mkproc 4001 "app.slice/bridge.service"          # supervised: systemd owns and restarts it
mkproc 4002 "app.slice/app-vite-1234.scope"     # a session merely launched it

fake_pids=$(CSW_SERVICES_PROC="$fakeproc" CSW_SERVICES_DOCKER=/nonexistent-docker \
  "$SERVICES" json "$wt5" | jq -c '[.processes[].pid]')
assert_eq "$fake_pids" "[4002]" "a supervised .service unit is excluded; a .scope is not"

# ...but a `.service` cgroup is only evidence of supervision when it is somebody
# else's. Processes spawned inside a unit's cgroup INHERIT it, and are not
# themselves supervised units -- killing one is not undone by systemd. So when
# the caller is itself running under a service, everything it spawned shares
# that cgroup and a leaf-only test excludes the entire machine.
#
# That is not hypothetical: GitHub's Actions runner runs as a systemd service,
# so CI saw "nothing running" for every process it had just started, while
# passing locally where the session cgroup is a `.scope`. Any setup whose shell,
# editor or agent runs under a systemd user unit hits the same thing -- and a
# silent empty result reading as "nothing running" is the one answer this tool
# must never give by accident.
fakeproc2=$(mktemp -d); TMPDIRS+=("$fakeproc2")
printf '99999.0 99999.0\n' >"$fakeproc2/uptime"
mkdir -p "$fakeproc2/self"
ours="runner.slice/actions.runner.service"
printf '0::/user.slice/user-1000.slice/user@1000.service/%s\n' "$ours" >"$fakeproc2/self/cgroup"
mkproc2() { # pid cgroup-leaf
  local d="$fakeproc2/$1"
  mkdir -p "$d/fd"
  ln -sfn "$wt5" "$d/cwd"
  printf '%s (node (dev) run) S 1 %s 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 100 0 0 0\n' "$1" "$1" >"$d/stat"
  printf 'Name:\tfakeproc\nPPid:\t1\n' >"$d/status"
  printf 'fake\0proc\0' >"$d/cmdline"
  printf '0::/user.slice/user-1000.slice/user@1000.service/%s\n' "$2" >"$d/cgroup"
}
mkproc2 5001 "$ours"                      # spawned by us, inside our own service cgroup
mkproc2 5002 "app.slice/bridge.service"   # somebody else's supervised unit

shared_pids=$(CSW_SERVICES_PROC="$fakeproc2" CSW_SERVICES_DOCKER=/nonexistent-docker \
  "$SERVICES" json "$wt5" | jq -c '[.processes[].pid]')
assert_eq "$shared_pids" "[5001]" \
  "a process sharing the caller's own .service cgroup is ours, not a supervised unit"

# The parenthesised comm is parsed correctly, so pgrp reads as a pgid rather
# than as some later field entirely.
fake_pgid=$(CSW_SERVICES_PROC="$fakeproc" CSW_SERVICES_DOCKER=/nonexistent-docker \
  "$SERVICES" json "$wt5" | jq -c '.processes[0].pgid')
assert_eq "$fake_pgid" "4002" "a comm containing spaces and parens does not shift the field offsets"

# --- the platform gap is stated, never rendered as an empty result ---
noproc=$(mktemp -d); TMPDIRS+=("$noproc")   # no self/, so host discovery is unsupported
unsupported=$(CSW_SERVICES_PROC="$noproc" CSW_SERVICES_DOCKER=/nonexistent-docker \
  "$SERVICES" report "$wt5")
assert_contains "$unsupported" "not supported" \
  "an unsupported platform says so rather than reporting an empty result"
assert_contains "$unsupported" "lsof" "the unsupported message names the manual equivalent"
supported_flag=$(CSW_SERVICES_PROC="$noproc" CSW_SERVICES_DOCKER=/nonexistent-docker \
  "$SERVICES" json "$wt5" | jq -r '.hostProcessesSupported')
assert_eq "$supported_flag" "false" "the JSON says the host arm did not run"
assert_status 0 "an unsupported platform is not an error" -- \
  env CSW_SERVICES_PROC="$noproc" CSW_SERVICES_DOCKER=/nonexistent-docker \
  "$SERVICES" report "$wt5"

report
