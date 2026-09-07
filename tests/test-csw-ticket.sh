#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

repo=$(make_repo)
write_config "$repo" <<'JSON'
{ "ticketPrefix": "TRA", "branchPattern": "<type>/<ticket>-<slug>" }
JSON
cd "$repo" || exit 1

assert_eq "$("$BIN/csw-ticket" normalize 1088)" "TRA-1088" "bare number gets the prefix"
assert_eq "$("$BIN/csw-ticket" normalize tra-1088)" "TRA-1088" "lowercase prefixed"
assert_eq "$("$BIN/csw-ticket" normalize TRA-1088)" "TRA-1088" "already normalised"
assert_eq "$("$BIN/csw-ticket" normalize tra1088)" "TRA-1088" "missing dash"
assert_eq "$("$BIN/csw-ticket" normalize ' TRA-1088 ')" "TRA-1088" "surrounding whitespace"
assert_eq "$("$BIN/csw-ticket" number tra-1088)" "1088" "number strips the prefix"

assert_status 2 "unparseable reference exits 2" -- "$BIN/csw-ticket" normalize "not a ticket"
assert_status 2 "empty reference exits 2" -- "$BIN/csw-ticket" normalize ""

assert_eq "$("$BIN/csw-ticket" slug 'Add nav vocabulary')" "add-nav-vocabulary" "basic slug"
assert_eq "$("$BIN/csw-ticket" slug 'Fix: the "Named Instance" audit!')" "fix-the-named-instance-audit" "punctuation collapses"
assert_eq "$("$BIN/csw-ticket" slug '  Leading and trailing  ')" "leading-and-trailing" "trims to no stray dashes"
long=$("$BIN/csw-ticket" slug 'replace the deprecated dsn setting rather than deleting it outright')
assert_eq "${#long}" "40" "long slug truncates to 40 characters"
case "$long" in *-) assert_eq "trailing-dash" "none" "truncated slug has no trailing dash" ;; *) PASSES=$((PASSES + 1)) ;; esac

# --- Truncation must not bisect a ticket reference into the slug tail (#125) ---
#
# Observed on trakrf/platform PR #614: the 40-character cut landed inside a
# trailing "tra-1206" and left "...-tra-120". Linear scans branch names for
# issue ids, matched TRA-120 -- a real, unrelated ticket closed months earlier
# -- and dragged it out of Done into In Review. Nothing errored and no check
# failed, because the wrong ticket is a real ticket; the PR body was innocent
# (`Refs TRA-1206`), so the branch name is the only place the tell exists.
bisected=$("$BIN/csw-ticket" slug 'The soak driver runs vitest only TRA-1206')
assert_eq "$bisected" "the-soak-driver-runs-vitest-only" \
  "a ticket id bisected by the cut is dropped from the tail, not left valid"
if printf '%s' "$bisected" | grep -q -- '-[a-z][a-z]*-[0-9][0-9]*$'; then
  assert_eq "ticket-shaped tail" "none" "the truncated slug retains no ticket-shaped tail at all"
else
  PASSES=$((PASSES + 1))
fi

# The leading reference is what carries meaning to the trackers, and it is
# never at risk from the cut. Stripping the tail must not touch it.
assert_eq "$("$BIN/csw-ticket" branch feat TRA-1206 'The soak driver runs vitest only TRA-1206')" \
  "feat/tra-1206-the-soak-driver-runs-vitest-only" \
  "the leading reference survives; only the tail is stripped"

# The rule strips ticket references, not every trailing number. A version tail
# has no dash between its letters and its digits, so it is not ticket-shaped
# even when the cut lands right on it.
assert_eq "$("$BIN/csw-ticket" slug 'Migrate whole ingest pipeline to apis v2 today')" \
  "migrate-whole-ingest-pipeline-to-apis-v2" \
  "a truncated -v2 tail is not a ticket reference and is left alone"

# Scoped to slugs the cut actually shortened. Firing unconditionally would eat
# ordinary English tails -- "roadmap for 2026" is not a ticket reference, and
# neither is any short title that happens to end in one.
assert_eq "$("$BIN/csw-ticket" slug 'Roadmap for 2026')" "roadmap-for-2026" \
  "an untruncated trailing year is left alone"
assert_eq "$("$BIN/csw-ticket" slug 'Add nav vocabulary')" "add-nav-vocabulary" \
  "a slug shorter than the cut is otherwise unchanged"

# A reference the cut never touched is still a reference, and a tracker scanning
# the branch name cannot tell the two apart -- "Port the fix from TRA-120" is an
# ordinary title to write, and it reopens TRA-120 exactly as the bisected one
# did. So the tail is stripped whether or not the cut fired, but only when it
# names *this repo's* configured prefix: that is narrow enough to leave
# "roadmap-for-2026" alone, which the generic letters-dash-digits rule applied
# unconditionally would eat.
assert_eq "$("$BIN/csw-ticket" slug 'Port the fix from TRA-120')" "port-the-fix-from" \
  "an untruncated tail naming the configured prefix is stripped too"
assert_eq "$("$BIN/csw-ticket" branch feat TRA-1206 'Port the fix from TRA-120')" \
  "feat/tra-1206-port-the-fix-from" \
  "branch: the configured-prefix tail goes, the leading reference stays"

# Partial trailing words are already tolerated in generated names, which is
# what makes dropping a whole segment cheap. This is the sibling branch from
# the same week that was safe only by luck.
assert_eq "$("$BIN/csw-ticket" slug 'Local dev db drifts silently and just barely works')" \
  "local-dev-db-drifts-silently-and-just-ba" \
  "a partial trailing word is still tolerated"

# One strip is not enough: dropping the last ticket-shaped segment can expose
# another one underneath, and the tracker matches whatever is left.
assert_eq "$("$BIN/csw-ticket" slug 'Sync the issue references ENG-45 TRA-1206 now')" \
  "sync-the-issue-references" \
  "stripping repeats until no ticket-shaped tail remains"

assert_eq "$("$BIN/csw-ticket" branch feat TRA-1088 Add nav vocabulary)" \
  "feat/tra-1088-add-nav-vocabulary" "branch renders the pattern"
assert_eq "$("$BIN/csw-ticket" branch fix 1076 'Replace the DSN setting')" \
  "fix/tra-1076-replace-the-dsn-setting" "branch normalises a bare number"

# A different pattern must be honoured, not hardcoded around.
write_config "$repo" <<'JSON'
{ "ticketPrefix": "ENG", "branchPattern": "<ticket>/<type>-<slug>" }
JSON
assert_eq "$("$BIN/csw-ticket" branch chore 42 'Bump deps')" "eng-42/chore-bump-deps" "custom pattern"

# No prefix configured: a bare number is ambiguous and must fail loudly.
bare=$(make_repo)
assert_status 2 "bare number without ticketPrefix exits 2" -- in_dir "$bare" "$BIN/csw-ticket" normalize 1088
assert_eq "$(cd "$bare" && "$BIN/csw-ticket" normalize ENG-7)" "ENG-7" "explicit prefix works without config"

# Team keys that contain digits (Linear/Jira style) must round-trip: normalize's
# own output must be re-parseable by normalize, and number must strip only the
# prefix, not everything up to the first dash.
write_config "$repo" <<'JSON'
{ "ticketPrefix": "K8S", "branchPattern": "<type>/<ticket>-<slug>" }
JSON
assert_eq "$("$BIN/csw-ticket" normalize 42)" "K8S-42" "digit-bearing prefix from a bare number"
assert_eq "$("$BIN/csw-ticket" normalize K8S-42)" "K8S-42" "digit-bearing prefix round-trips"
assert_eq "$("$BIN/csw-ticket" number K8S-42)" "42" "number strips a digit-bearing prefix, not up to the first dash"

# An invalid configured ticketPrefix must fail loudly rather than mint a
# reference normalize can't parse back. Exit 4, not 2: this is a broken
# config, the same class of failure as csw-config's own malformed-config
# checks, not a bad invocation of csw-ticket.
write_config "$repo" <<'JSON'
{ "ticketPrefix": "1AB", "branchPattern": "<type>/<ticket>-<slug>" }
JSON
assert_status 4 "ticketPrefix starting with a digit exits 4" -- "$BIN/csw-ticket" normalize 42
write_config "$repo" <<'JSON'
{ "ticketPrefix": "TRA-X", "branchPattern": "<type>/<ticket>-<slug>" }
JSON
assert_status 4 "ticketPrefix containing a dash exits 4" -- "$BIN/csw-ticket" normalize 42

# A malformed config file must propagate csw-config's real exit code (4)
# through `branch` and `number`, not collapse into the misleading "needs
# ticketPrefix" usage error (2) that fires when normalize's internal
# `config get ticketPrefix` failure is silently swallowed by a nested command
# substitution lacking `inherit_errexit`.
badcfg=$(make_repo)
mkdir -p "$badcfg/.claude"
printf '{ not json\n' >"$badcfg/.claude/csw.json"
assert_status 4 "branch propagates a malformed-config exit 4 through a bare-number ticket ref" -- \
  in_dir "$badcfg" "$BIN/csw-ticket" branch feat 5 title
assert_status 4 "number propagates a malformed-config exit 4 through a bare-number ticket ref" -- \
  in_dir "$badcfg" "$BIN/csw-ticket" number 5

# branchPattern is free text, unlike the strictly validated ticketPrefix. Left
# unvalidated it can render every ticket to the same branch ("wip"), a
# literal "null", or an illegal ref — silent collisions in /csw:batch. It
# must contain a placeholder and render to a legal git branch name, or exit 4.
write_config "$repo" <<'JSON'
{ "ticketPrefix": "TRA", "branchPattern": "wip" }
JSON
assert_status 4 "branchPattern with no <ticket>/<slug> placeholder exits 4" -- \
  "$BIN/csw-ticket" branch feat 1088 'Add nav vocabulary'

write_config "$repo" <<'JSON'
{ "ticketPrefix": "TRA", "branchPattern": null }
JSON
assert_status 4 "branchPattern of null exits 4" -- \
  "$BIN/csw-ticket" branch feat 1088 'Add nav vocabulary'

write_config "$repo" <<'JSON'
{ "ticketPrefix": "TRA", "branchPattern": {"a": 1} }
JSON
assert_status 4 "branchPattern as an object exits 4" -- \
  "$BIN/csw-ticket" branch feat 1088 'Add nav vocabulary'

write_config "$repo" <<'JSON'
{ "ticketPrefix": "TRA", "branchPattern": "<ticket>:<slug>" }
JSON
assert_status 4 "branchPattern with a placeholder that still renders an illegal git ref (colon) exits 4" -- \
  "$BIN/csw-ticket" branch feat 1088 'Add nav vocabulary'

write_config "$repo" <<'JSON'
{ "ticketPrefix": "TRA", "branchPattern": "<ticket>" }
JSON
assert_eq "$("$BIN/csw-ticket" branch feat 1088 'Add nav vocabulary')" "tra-1088" \
  "branchPattern with only <ticket> is still a legal single-placeholder pattern"

# Reject every unparseable / ambiguous shape.
write_config "$repo" <<'JSON'
{ "ticketPrefix": "TRA", "branchPattern": "<type>/<ticket>-<slug>" }
JSON
assert_status 2 "prefix with no digits exits 2" -- "$BIN/csw-ticket" normalize "TRA-"
assert_status 2 "leading dash exits 2" -- "$BIN/csw-ticket" normalize "-1088"
assert_status 2 "double dash exits 2" -- "$BIN/csw-ticket" normalize "TRA--1088"
assert_status 2 "leading digits exits 2" -- "$BIN/csw-ticket" normalize "12AB34"
assert_status 2 "trailing extra segment exits 2" -- "$BIN/csw-ticket" normalize "TRA-1088-extra"
assert_status 2 "unparseable words exit 2" -- "$BIN/csw-ticket" normalize "not a ticket"

# --- GitHub-tracked repos: a bare issue number IS the canonical reference ---
# There is no prefix to configure, and issue numbers are unambiguous within a
# repo, so requiring ticketPrefix would make `tracker: github` undispatchable.
gh=$(make_repo)
write_config "$gh" <<'JSON'
{ "tracker": "github", "branchPattern": "<type>/<ticket>-<slug>" }
JSON
assert_eq "$(in_dir "$gh" "$BIN/csw-ticket" normalize 68)" "68" "github: bare number resolves to itself"
assert_eq "$(in_dir "$gh" "$BIN/csw-ticket" normalize '#68')" "68" "github: leading # is stripped"
assert_eq "$(in_dir "$gh" "$BIN/csw-ticket" number 68)" "68" "github: number of a bare reference"
assert_eq "$(in_dir "$gh" "$BIN/csw-ticket" branch feat 68 'Add the prep pass')" \
  "feat/68-add-the-prep-pass" "github: branch name from a bare issue number"

# With no ticketPrefix there is no repo-local reference shape to protect, and
# GitHub does not reopen an issue from a branch name anyway. A foreign tail the
# cut never touched is left exactly as written.
assert_eq "$(in_dir "$gh" "$BIN/csw-ticket" slug 'Port the fix from TRA-120')" \
  "port-the-fix-from-tra-120" \
  "github: no configured prefix, so an untruncated foreign tail is left alone"

# An explicit prefix still wins if someone configures one alongside github.
ghp=$(make_repo)
write_config "$ghp" <<'JSON'
{ "tracker": "github", "ticketPrefix": "GH" }
JSON
assert_eq "$(in_dir "$ghp" "$BIN/csw-ticket" normalize 68)" "GH-68" "github + prefix: prefix still applies"

# Other trackers keep rejecting a bare number - there it really is ambiguous.
for tr in linear none; do
  amb=$(make_repo)
  printf '{ "tracker": "%s" }\n' "$tr" | write_config "$amb"
  assert_status 2 "$tr: bare number still rejected" -- in_dir "$amb" "$BIN/csw-ticket" normalize 68
done

# The # form is only a prefix marker, not a licence for junk.
assert_status 2 "github: bare # is not a reference" -- in_dir "$gh" "$BIN/csw-ticket" normalize '#'
assert_status 2 "github: #abc is not a reference" -- in_dir "$gh" "$BIN/csw-ticket" normalize '#abc'
assert_eq "$(in_dir "$gh" "$BIN/csw-ticket" normalize '#ENG-7')" "ENG-7" "github: # before a prefixed ref"

report
