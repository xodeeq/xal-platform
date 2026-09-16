#!/usr/bin/env bash
#
# gates/seed.test.sh — proof that scripts/check-seed-set.sh has teeth, per rule.
#
# CLAUDE.md's standing rules: "Every new gate ships with committed failing fixtures. A gate
# that has never been seen to fail has not been tested — a rule matching nothing and a rule
# finding nothing emit byte-identical green, and `return 0` passes just as convincingly as
# real logic." One fixture per rule, each proving THAT rule fails and no other, plus a clean
# one proving the gate can say yes.
#
# The warning is not decorative here. This gate's job is to notice that something is ABSENT,
# and the cheapest wrong implementation — iterating an empty language list, or checking a
# path that is always present — passes every happy-path check and never fails. So each
# fixture is the clean tree broken in exactly one way, and three things are asserted: the
# gate fails, WHICH rule fired, and that no OTHER rule fired.
#
# THE FIXTURE SEEDERS ARE STUBS, DELIBERATELY. Each fixture tree carries a ~20-line
# seed-service.sh implementing only the refusal contract rule 4 asserts. Copying the real
# seeder into five fixture trees would create five replicas that nothing holds identical —
# the drift this estate has a separate gate for. The real seeder is exercised by the real run
# of check-seed-set.sh against scaffold/, which is gate "seed sets complete" in check.sh.
#
# Usage:  gates/seed.test.sh
# Exit:   0 every scenario behaved as specified · 1 at least one did not
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GATE="scripts/check-seed-set.sh"
FIX="gates/fixtures/seed"

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; RST=""; fi

[ -f "$GATE" ] || { printf '%s%s not found%s\n' "$RED" "$GATE" "$RST"; exit 2; }
[ -d "$FIX" ]  || { printf '%sno fixtures at %s%s\n' "$RED" "$FIX" "$RST"; exit 2; }

pass=0; fail=0
ok()  { printf '%s  ✔%s %s\n' "$GREEN" "$RST" "$1"; pass=$((pass + 1)); }
bad() { printf '%s  ✗%s %s\n' "$RED" "$RST" "$1"; fail=$((fail + 1)); }

run() {
  local fixture="$1" want_exit="$2" want_pat="$3" desc="$4" out rc problem=""
  out="$(bash "$ROOT/$GATE" --scaffold "$ROOT/$FIX/$fixture/scaffold" 2>&1)"; rc=$?
  [ "$rc" = "$want_exit" ] || problem="exit $rc, wanted $want_exit"
  if [ -n "$want_pat" ] && ! printf '%s' "$out" | grep -qE -- "$want_pat"; then
    problem="${problem:+$problem; }output did not match /$want_pat/"
  fi
  if [ -z "$problem" ]; then
    printf '%s  ✔%s %-40s exit %s  %s\n' "$GREEN" "$RST" "$fixture" "$rc" "$desc"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-40s %s  (%s)\n' "$RED" "$RST" "$fixture" "$problem" "$desc"
    printf '%s\n' "$out" | sed 's/^/      | /'
    fail=$((fail + 1))
  fi
}

printf '\n%s━━ check-seed-set: a proven failure case per rule%s\n\n' "$BOLD" "$RST"

run clean                              0 'seed sets complete' 'a complete scaffold must PASS (guards against always-fails)'
run rule-1-no-languages                1 'RULE 1' 'lang/ offers no language at all'
run rule-2-missing-gate                1 'RULE 2' 'a language overlay ships no scripts/check.sh'
run rule-3-ci-never-calls-the-gate     1 'RULE 3' 'the seeded ci.yml never invokes the gate script'
run rule-4-seeder-defaults-a-language  1 'RULE 4' 'the seeder silently defaults --lang instead of refusing'

printf '\n%s━━ discrimination: each fixture trips exactly one rule%s\n\n' "$BOLD" "$RST"
for d in "$FIX"/rule-*; do
  name="$(basename "$d")"
  want="RULE $(printf '%s' "$name" | sed -E 's/^rule-([0-9]+)-.*/\1/')"
  out="$(bash "$ROOT/$GATE" --scaffold "$ROOT/$d/scaffold" 2>&1)"
  fired="$(printf '%s' "$out" | grep -oE 'RULE [0-9]+' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ "$fired" = "$want" ]; then ok "$(printf '%-40s fired: %s' "$name" "$fired")"
  else bad "$(printf '%-40s fired: [%s], wanted exactly [%s]' "$name" "$fired" "$want")"; fi
done

# ── cannot-run stays distinguishable from clean ────────────────────────────────────────
# Exit 2 is "the gate could not run", exit 1 is "the gate found a problem". Collapsing them
# is how a broken invocation comes to read as a passing repo.
printf '\n%s━━ cannot-run is distinguishable from clean%s\n\n' "$BOLD" "$RST"
out="$(bash "$ROOT/$GATE" --scaffold "$ROOT/$FIX/definitely-not-here" 2>&1)"; rc=$?
if [ "$rc" = "2" ]; then ok "a missing scaffold exits 2, not 0 or 1"
else bad "a missing scaffold exited $rc, wanted 2"; printf '%s\n' "$out" | sed 's/^/      | /'; fi

# ── rule 4 is asserted by EXECUTION, not by reading the source ───────────────────────────
# The rule-4 fixture's seeder is syntactically fine and would pass any grep for "exit 2" —
# it contains one. What makes it wrong is what it DOES with a missing --lang. If this suite
# ever stops running the seeder, rule 4 becomes unfalsifiable while still looking tested.
printf '\n%s━━ rule 4 is decided by running the seeder, not by reading it%s\n\n' "$BOLD" "$RST"
if grep -q 'exit 2' "$FIX/rule-4-seeder-defaults-a-language/scaffold/seed-service.sh"; then
  ok "the rule-4 fixture's seeder contains 'exit 2' and is still caught — the rule is behavioural"
else
  bad "the rule-4 fixture no longer contains 'exit 2'; it no longer proves the rule is behavioural"
fi

printf '\n%s──────── %s passed · %s failed ────────%s\n' "$BOLD" "$pass" "$fail" "$RST"
[ "$fail" -eq 0 ] || exit 1
printf '%scheck-seed-set is proven able to fail, per rule, and to discriminate between rules.%s\n' "$GREEN" "$RST"
exit 0
