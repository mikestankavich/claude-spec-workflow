#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"

readme="$REPO_ROOT/README.md"
config_doc="$REPO_ROOT/docs/configuration.md"
example="$REPO_ROOT/examples/csw.json"

assert_contains "$(cat "$readme")" "Claude Ship Workflow" "README uses the new name"
if grep -q "Claude Spec Workflow" "$readme"; then
  FAILURES=$((FAILURES + 1)); printf 'FAIL README still says Claude Spec Workflow\n' >&2
else
  PASSES=$((PASSES + 1))
fi
for phrase in "not yours" "unmaintained" "/csw:prep" "/csw:work" "/csw:merge" "/csw:cleanup" "/csw:batch"; do
  assert_contains "$(cat "$readme")" "$phrase" "README mentions $phrase"
done
# A batch's isolation is per ticket in both senses — its own worktree and its own context —
# and the second one is the part a reader cannot infer from "one PR each".
assert_contains "$(cat "$readme")" "its own context" \
  "README says a batch isolates each ticket's context, not only its worktree"

# #109: a rider is accepted silently only in the sense that nothing stops to ask about it —
# the README is where someone learns they can write one at all, and that writing one buys
# context rather than permission.
assert_contains "$(cat "$readme")" "rider" \
  "README documents the editorial rider both phases accept"
assert_contains "$(cat "$readme")" "context, never authority" \
  "README says a rider adds to the brief rather than granting permission"

for gone in "/csw:spec" "/csw:plan" "/csw:build" "/csw:ship"; do
  if grep -q -- "$gone" "$readme"; then
    FAILURES=$((FAILURES + 1)); printf 'FAIL README still advertises %s\n' "$gone" >&2
  else
    PASSES=$((PASSES + 1))
  fi
done

# Every default key must be documented, including the nested batch keys.
repo=$(make_repo)
top_keys=$(in_dir "$repo" "$BIN/csw-config" json | jq -r 'keys[]')
batch_keys=$(in_dir "$repo" "$BIN/csw-config" json | jq -r '.batch | keys[] | "batch." + .')
for key in $top_keys $batch_keys; do
  assert_contains "$(cat "$config_doc")" "$key" "configuration.md documents $key"
done

if jq -e . "$example" >/dev/null 2>&1; then
  PASSES=$((PASSES + 1))
else
  FAILURES=$((FAILURES + 1)); printf 'FAIL examples/csw.json is not valid JSON\n' >&2
fi

# This repo dogfoods its own config, and it must be committed.
own="$REPO_ROOT/.claude/csw.json"
if jq -e . "$own" >/dev/null 2>&1; then
  PASSES=$((PASSES + 1))
else
  FAILURES=$((FAILURES + 1)); printf 'FAIL .claude/csw.json is missing or invalid\n' >&2
fi
tracked=$(git -C "$REPO_ROOT" ls-files --error-unmatch .claude/csw.json 2>/dev/null || true)
assert_eq "$tracked" ".claude/csw.json" ".claude/csw.json is tracked, not gitignored"
ignored=$(git -C "$REPO_ROOT" check-ignore .claude/worktrees 2>/dev/null || true)
assert_eq "$ignored" ".claude/worktrees" ".claude/worktrees stays ignored"

changelog="$REPO_ROOT/CHANGELOG.md"

assert_contains "$(cat "$changelog")" "## [1.0.0]" "CHANGELOG has a 1.0.0 entry"

# At most one Unreleased section — two stray ones (one of them empty) previously
# rode along into the middle of the file and would have leaked into the 1.0.0
# release notes.
unreleased_count=$(grep -c '^## \[Unreleased\]' "$changelog")
assert_eq "$unreleased_count" "0" "CHANGELOG has no stray Unreleased sections"

# Version headers must read newest-first, consistently, with no version out of
# order (0.1.0 previously sorted above 0.4.0).
versions=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$changelog" | sed -E 's/^## \[//; s/\]$//')
sorted_versions=$(printf '%s\n' "$versions" | sort -rV)
assert_eq "$versions" "$sorted_versions" "CHANGELOG version headers are strictly descending"

# The check that actually protects the release: Task 14 extracts the 1.0.0 notes
# by slicing from the [1.0.0] header to the next version header. That slice must
# contain exactly those two "## " lines — the 1.0.0 heading itself and the next
# version's heading marking where the section ends — nothing stray in between.
extraction=$(sed -n '/^## \[1.0.0\]/,/^## \[0.4.0\]/p' "$changelog")
extraction_headers=$(printf '%s\n' "$extraction" | grep -c '^## ')
assert_eq "$extraction_headers" "2" "Task 14's 1.0.0 extraction contains only the 1.0.0 section"

# The reboot renamed the project; no repo-root markdown file may still call it by
# the old name except CHANGELOG.md, which legitimately narrates that history.
spec_leak=$(grep -l "Claude Spec Workflow" "$REPO_ROOT"/*.md 2>/dev/null | grep -vFx "$changelog" || true)
assert_eq "$spec_leak" "" "no repo-root markdown file except CHANGELOG.md says Claude Spec Workflow"

# --- the service teardown, and the gap the fixtures cannot close ---
assert_contains "$(cat "$readme")" "csw-services" "README documents the service teardown"
assert_contains "$(cat "$readme")" "still running" \
  "README says what removing a worktree used to leave behind"
assert_contains "$(cat "$config_doc")" "csw-services" \
  "configuration.md documents csw-services' errors"
# This repo runs no services, so csw-services cannot be dogfooded here and the
# fixtures are the whole of the automated coverage. Stated where the next
# contributor meets it, rather than discovered at validation time.
assert_contains "$(cat "$REPO_ROOT/CONTRIBUTING.md")" "csw-services" \
  "CONTRIBUTING records that csw-services cannot be dogfooded here"

# Every bin ships in the plugin, so a new one must be listed wherever the others are.
for doc in "$readme" "$config_doc"; do
  if grep -q "csw-sweep" "$doc" && ! grep -q "csw-services" "$doc"; then
    FAILURES=$((FAILURES + 1))
    printf 'FAIL %s lists csw-sweep but not csw-services\n' "$doc" >&2
  else
    PASSES=$((PASSES + 1))
  fi
done

report
