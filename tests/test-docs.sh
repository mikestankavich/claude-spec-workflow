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

# Exactly one Unreleased section, and it is the first version heading in the file.
# The original rule here was "none", written when two stray ones (one of them empty)
# rode along into the *middle* of the file and would have leaked into the 1.0.0 release
# notes. The hazard was always their position rather than their existence -- Keep a
# Changelog wants one at the top, and without it an entry has nowhere to go but the last
# released section, which is how a September change ended up dated 4 August in [1.1.0].
unreleased_count=$(grep -c '^## \[Unreleased\]' "$changelog")
assert_eq "$unreleased_count" "1" "CHANGELOG keeps exactly one Unreleased section"
first_version_heading=$(grep -m1 '^## \[' "$changelog")
assert_eq "$first_version_heading" "## [Unreleased]" \
  "the Unreleased section is the first version heading, not stranded mid-file"

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

# --- The ADR convention, enforced rather than described ---
# csw:work writes these unattended, so "the directory supplies the convention" is only true
# while the directory actually carries one. A record that drifts from the documented shape
# teaches the next dispatch the drift, because that is what it reads to derive the format.
assert_contains "$(cat "$config_doc")" "Status" \
  "configuration.md documents the ADR Status field"
for value in "Proposed" "Accepted"; do
  assert_contains "$(cat "$config_doc")" "$value" \
    "configuration.md names $value as an ADR status"
done
# A dispatch may propose a decision; it may not take one on the repo's behalf. That is the
# whole reason there are two values rather than none.
# The rule this repo ran on unwritten: merging an ADR is accepting it, and declining is a
# revert before the merge. A dispatch writing one unattended cannot infer that, which is
# why it is documented rather than left to be picked up.
assert_contains "$(cat "$config_doc")" "Merging an ADR is accepting it" \
  "configuration.md states that merging an ADR accepts it"

adr_dir="$REPO_ROOT/docs/adr"
if [ -d "$adr_dir" ]; then
  for adr in "$adr_dir"/[0-9]*.md; do
    [ -e "$adr" ] || continue
    name=$(basename "$adr")
    head_block=$(head -6 "$adr")
    for field in "Date:" "Status:" "Tracking:"; do
      assert_contains "$head_block" "$field" "$name carries $field"
    done
    # Anything after the value is supersession detail, which the Status line is where
    # it belongs -- so match the start of the value, not the whole line.
    status=$(printf '%s\n' "$head_block" | sed -n 's/^Status: //p')
    case "$status" in
      Proposed|Proposed\;*|Accepted|Accepted\;*)
        PASSES=$((PASSES + 1)) ;;
      *)
        FAILURES=$((FAILURES + 1))
        printf 'FAIL %s has an unknown Status: %s\n' "$name" "$status" >&2 ;;
    esac
  done
fi

# --- The changelog carries the release it declares ---
# Ported from trakrf/platform's scripts/assert-changelog-section.sh. One difference:
# platform's VERSION carries X.Y.Z-dev between releases, so its gate is inert on every
# ordinary PR and fires only on the release one. CSW's VERSION always holds the last
# released number, so this is always on and ordinarily satisfied by the section already
# there -- it bites when a release PR bumps VERSION and forgets the notes.
version=$(tr -d '[:space:]' <"$REPO_ROOT/VERSION")
# -F, and the heading keeps its closing bracket, so 1.2.0 is not satisfied by [1.2.01].
if grep -qF "## [${version}]" "$changelog"; then
  PASSES=$((PASSES + 1))
else
  FAILURES=$((FAILURES + 1))
  printf 'FAIL VERSION declares %s but CHANGELOG.md has no "## [%s]" section\n' \
    "$version" "$version" >&2
fi

# An entry has to have somewhere to go that is not the last released section. Without this
# heading, "append to the changelog" lands on the newest release by construction -- which is
# how a September change ended up dated 4 August inside [1.1.0].
assert_contains "$(cat "$changelog")" "keepachangelog.com/en/1.1.0/" \
  "CHANGELOG.md cites the Keep a Changelog version it follows"
assert_contains "$(cat "$REPO_ROOT/CONTRIBUTING.md")" "Unreleased" \
  "CONTRIBUTING says where a changelog entry goes"

report
