#!/usr/bin/env bash
#
# check-seed-set.sh — assert that every language the scaffold offers can actually seed a repo
# that arrives with a working gate, and that the seeder refuses to guess a language.
#
# WHY THIS EXISTS ---------------------------------------------------------------------------
#
# ADR-0006 closes the seeding gap by teaching scaffold/ to ship a gate script. The sentence
# "the scaffold ships a gate script" is the kind of claim this estate has learned not to
# accept: a missing file in an overlay is invisible, because the seeded repo still *works* —
# it just has no format gate, or no fixtures, or a CI workflow that calls a script nobody
# shipped. Nothing goes red. The repo simply enforces less than anyone thinks, which is the
# same silent-green shape as a rule that matches nothing.
#
# A convention cannot enumerate; this script can. Adding scaffold/lang/<name>/ without the
# full artifact set fails HERE, in the PR that adds it, rather than in the first repo seeded
# from it six weeks later.
#
# THE RULES -----------------------------------------------------------------------------------
#   1. scaffold/lang/ exists and offers at least one language
#      (an empty lang/ would make rules 2-4 vacuous and green)
#   2. every language overlay ships every REQUIRED artifact (see REQUIRED below)
#   3. every language's ci.yml actually invokes its gate script, and its fixture harness
#      — a seeded CI that runs neither is the gap wearing a workflow file
#   4. the seeder refuses a MISSING --lang, and refuses an UNKNOWN one, both with exit 2
#
# RULE 4 IS THE HALF THAT IS NOT ABOUT FILES. A complete overlay behind a seeder that quietly
# defaults to the first language it finds would put a stack decision in a script — and the
# repo it produced would look entirely correct. So the refusal is tested, not documented.
#
# Usage:  scripts/check-seed-set.sh [--scaffold DIR]
# Exit:   0 clean · 1 violations found · 2 could not run
# Deps:   bash, grep, sed, find. No language runtime, no network, no credential.

set -uo pipefail

SCAFFOLD="scaffold"
while [ $# -gt 0 ]; do
  case "$1" in
    --scaffold) SCAFFOLD="${2:-}"; [ -n "$SCAFFOLD" ] || { printf -- '--scaffold needs a directory\n' >&2; exit 2; }; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'
else RED=""; GREEN=""; RST=""; fi

violations=0
v() { printf '%s  %s%s\n' "$RED" "$1" "$RST"; violations=$((violations + 1)); }

[ -d "$SCAFFOLD" ] || { printf 'scaffold not found: %s\n' "$SCAFFOLD" >&2; exit 2; }

SEEDER="$SCAFFOLD/seed-service.sh"
[ -f "$SEEDER" ] || { printf 'seeder not found: %s — nothing seeds a repo at all\n' "$SEEDER" >&2; exit 2; }
[ -d "$SCAFFOLD/common" ] || { printf 'scaffold/common/ not found under %s\n' "$SCAFFOLD" >&2; exit 2; }

# The artifact set a language overlay must ship for a seeded repo to arrive with a gate that
# runs, can fail, and says which gate fired. Each entry is here because its absence produces a
# repo that looks seeded and enforces less than it appears to.
REQUIRED="
scripts/check.sh
.xal/gate-inputs
.github/workflows/ci.yml
.github/workflows/deploy.yml
gates/check.test.sh
"

# --- rule 1: languages exist -------------------------------------------------------------
if [ ! -d "$SCAFFOLD/lang" ]; then
  v "RULE 1  $SCAFFOLD/lang/ does not exist — the scaffold offers no language, so it seeds no gate"
  printf '\n%s::error::check-seed-set found %s violation(s)%s\n' "$RED" "$violations" "$RST"
  exit 1
fi

langs="$(find "$SCAFFOLD/lang" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|.*/||' | sort)"
if [ -z "$langs" ]; then
  v "RULE 1  $SCAFFOLD/lang/ is empty — refusing to report green over an empty language set"
  printf '\n%s::error::check-seed-set found %s violation(s)%s\n' "$RED" "$violations" "$RST"
  exit 1
fi

nlang=0
# --- rules 2 + 3: per language -------------------------------------------------------------
while IFS= read -r l; do
  [ -n "$l" ] || continue
  nlang=$((nlang + 1))
  base="$SCAFFOLD/lang/$l"

  missing=0
  while IFS= read -r want; do
    [ -n "$want" ] || continue
    if [ ! -f "$base/$want" ]; then
      v "RULE 2  scaffold/lang/$l is missing $want — a repo seeded from it would not have it"
      missing=1
    fi
  done <<< "$REQUIRED"

  # Rule 3 needs the files rule 2 just checked for; one missing file trips one rule.
  [ "$missing" -eq 0 ] || continue

  ci="$base/.github/workflows/ci.yml"
  # The gate-input checker discovers callers by the `./scripts/check.sh` spelling, so a
  # workflow that invokes it some other way reads to that checker as NO CALLERS FOUND. Assert
  # the same spelling here, where the scaffold is authored, rather than leaving every seeded
  # repo to discover it.
  grep -qE '\./scripts/check\.sh' "$ci" \
    || v "RULE 3  scaffold/lang/$l ci.yml never invokes ./scripts/check.sh — the seeded repo would have a gate nothing runs"
  grep -qE '\./gates/check\.test\.sh' "$ci" \
    || v "RULE 3  scaffold/lang/$l ci.yml never invokes ./gates/check.test.sh — the seeded repo's gate would never be proven able to fail"
done <<< "$langs"

# --- rule 4: the seeder refuses to guess a language ------------------------------------------
# Run the real seeder, twice, with arguments that must be refused. Asserting the REFUSAL by
# execution rather than by reading the source is the whole point: a default added later would
# be invisible to any grep written today.
tmp="$(mktemp -d)" || exit 2
trap 'rm -rf "$tmp"' EXIT

out="$(bash "$SEEDER" --name probe --dest "$tmp/no-lang" 2>&1)"; rc=$?
if [ "$rc" -ne 2 ]; then
  v "RULE 4  the seeder exited $rc with no --lang, wanted 2 — a default language would be a stack decision taken by a script"
  printf '%s\n' "$out" | sed 's/^/      | /'
fi
[ -e "$tmp/no-lang" ] && v "RULE 4  the seeder created $tmp/no-lang despite refusing — a refusal must leave nothing behind"

out="$(bash "$SEEDER" --name probe --lang definitely-not-a-language --dest "$tmp/bad-lang" 2>&1)"; rc=$?
if [ "$rc" -ne 2 ]; then
  v "RULE 4  the seeder exited $rc for an unknown --lang, wanted 2"
  printf '%s\n' "$out" | sed 's/^/      | /'
fi
[ -e "$tmp/bad-lang" ] && v "RULE 4  the seeder created $tmp/bad-lang despite refusing — a refusal must leave nothing behind"

if [ "$violations" -ne 0 ]; then
  printf '\n%s::error::check-seed-set found %s violation(s)%s\n' "$RED" "$violations" "$RST"
  printf '  A seeded repo inherits exactly what the overlay ships. A missing piece is silent:\n'
  printf '  the repo still builds, and simply enforces less than everyone believes it does.\n'
  exit 1
fi

printf '  %sseed sets complete%s — %s language(s) ship the full artifact set; the seeder refuses to guess one\n' \
  "$GREEN" "$RST" "$nlang"
exit 0
