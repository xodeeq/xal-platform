#!/usr/bin/env bash
#
# gates/check.test.sh — proof that scripts/check.sh has teeth, and that it says which tooth.
#
# THE STANDING RULE THIS SATISFIES: "Every new gate ships with committed failing fixtures. A
# gate that has never been seen to fail has not been tested — a rule matching nothing and a
# rule finding nothing emit byte-identical green, and `return 0` passes just as convincingly
# as real logic." One committed fixture proving a gate fails, asserting WHICH gate fired
# (a gate can fail for the wrong reason and look right from its exit code alone), plus a
# clean fixture proving the chain can still say yes.
#
# WHY THIS IS NOT A GATE INSIDE check.sh -------------------------------------------------
#
# It runs check.sh. A gate inside check.sh that ran this would recurse forever. So ci.yml
# invokes it as a SEPARATE STEP, after the real gate run — which also means a genuine failure
# is reported before a fixture failure and the two are never confused.
#
# HOW A FIXTURE IS APPLIED ---------------------------------------------------------------
#
# Each fixture is an overlay: a partial file tree that is copied OVER a throwaway copy of the
# repo, replacing the real files at the same paths. The repo itself is never modified, so
# this suite is re-runnable and cannot leave the working tree broken.
#
# GOTCHA — the `_` in gates/_fixtures/ is load-bearing. The go tool ignores directories whose
# name begins with `_` or `.`, so a deliberately-broken package sitting there is invisible to
# `./...` during the repo's own real gate run. Rename it to `fixtures/` and the repo's own
# vet and test gates start failing on the fixtures, which is the fastest possible way to
# teach everyone to ignore a red gate. (gofmt has no such rule, which is why check.sh's
# format gate prunes gates/ explicitly rather than walking the tree.)
#
# GOTCHA — XAL_PLATFORM_DIR is made ABSOLUTE before each run. CI sets it to `.xal-platform`,
# a path relative to the repo root; inside a throwaway copy that path does not exist, so the
# drift gate would fail for the wrong reason and every fixture would "pass" its exit-code
# assertion while proving nothing.
#
# GOTCHA — never pipe a deliberately-failing command into a test's condition. `set -o
# pipefail` is on, so `bash check.sh | grep -q` returns CHECK's status, not grep's, and the
# `if` reads false on a harness that is working perfectly. Capture first, match second.
#
# Usage:  gates/check.test.sh
# Exit:   0 every fixture behaved as specified · 1 at least one did not
# Env:    XAL_PLATFORM_DIR (same meaning as in check.sh; resolved to an absolute path here)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIX="$ROOT/gates/_fixtures"

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; YEL=""; RST=""; fi

[ -f "$ROOT/scripts/check.sh" ] || {
  printf '%sscripts/check.sh not found — there is no gate to prove%s\n' "$RED" "$RST"; exit 2; }
[ -d "$FIX" ] || {
  printf '%sno fixtures at %s — refusing to report green over an empty suite%s\n' "$RED" "$FIX" "$RST"; exit 2; }

# Resolve the platform checkout to an absolute path, once. Missing is fatal under CI=true for
# the same reason it is fatal in check.sh: a gate that cannot run has not passed.
PLATFORM_ABS=""
_pd="${XAL_PLATFORM_DIR:-../xal-platform}"
if [ -d "$_pd" ]; then
  PLATFORM_ABS="$(cd "$_pd" && pwd)"
elif [ "${CI:-}" = "true" ]; then
  printf '%sXAL_PLATFORM_DIR=%s does not resolve, and CI=true makes the drift gate mandatory%s\n' \
    "$RED" "$_pd" "$RST"
  exit 2
else
  printf '%s⚠ no platform repo at %s — the drift gate will skip inside each fixture run%s\n' \
    "$YEL" "$_pd" "$RST"
fi

pass=0
fail=0

# run <fixture> <want_exit> <want_gate_pattern> <description>
#
# want_gate_pattern is matched against check.sh's own output, so it asserts WHICH gate fired,
# not merely that something did.
run() {
  local fixture="$1" want_exit="$2" want_pat="$3" desc="$4"
  local tmp out rc problem=""

  [ -d "$FIX/$fixture" ] || {
    printf '%s  ✗%s %-20s fixture directory does not exist\n' "$RED" "$RST" "$fixture"
    fail=$((fail + 1)); return; }

  tmp="$(mktemp -d)" || { printf '%smktemp failed%s\n' "$RED" "$RST"; fail=$((fail + 1)); return; }

  # Copy the repo, minus the things that must not travel: git history, the coverage output of
  # a previous run, and the platform checkout (which is passed by absolute path instead, and
  # would otherwise be copied once per fixture).
  ( cd "$ROOT" && tar --exclude='./.git' --exclude='./.coverage' --exclude='./.xal-platform' \
        -cf - . ) | ( cd "$tmp" && tar -xf - )

  # Overlay the fixture over the copy.
  ( cd "$FIX/$fixture" && tar -cf - . ) | ( cd "$tmp" && tar -xf - )

  out="$( cd "$tmp" && XAL_PLATFORM_DIR="$PLATFORM_ABS" bash scripts/check.sh 2>&1 )"
  rc=$?
  rm -rf "$tmp"

  [ "$rc" = "$want_exit" ] || problem="exit $rc, wanted $want_exit"
  if [ -n "$want_pat" ] && ! printf '%s' "$out" | grep -qE -- "$want_pat"; then
    problem="${problem:+$problem; }output did not name /$want_pat/"
  fi

  if [ -z "$problem" ]; then
    printf '%s  ✔%s %-20s exit %s  %s\n' "$GREEN" "$RST" "$fixture" "$rc" "$desc"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-20s %s  (%s)\n' "$RED" "$RST" "$fixture" "$problem" "$desc"
    printf '%s\n' "$out" | tail -40 | sed 's/^/      | /'
    fail=$((fail + 1))
  fi
}

printf '\n%s━━ the gate chain fails, and names the gate that fired%s\n\n' "$BOLD" "$RST"

# The cheap one first: it stops at gate 2, so a broken harness is visible in seconds rather
# than after a full Docker build.
run failing-gofmt    1 'CHECK FAILED at: format \(gofmt -l\)' \
    'code that compiles but is not gofmt-clean'

# The expensive one, and the one that matters most. Every other gate in the chain delegates
# its verdict to a tool that is itself tested; the coverage floor is the only gate whose
# arithmetic is written in this repo, so it is the only one that can be quietly wrong.
run failing-coverage 1 'CHECK FAILED at: coverage \(per-package floors\)' \
    'an exported function no test covers, below the package floor'

printf '\n%s━━ and it can still say yes%s\n\n' "$BOLD" "$RST"

run clean            0 'ALL GATES PASSED' \
    'a real, tested change must PASS (guards against a chain that always fails)'

printf '\n%s──────── %s passed · %s failed ────────%s\n' "$BOLD" "$pass" "$fail" "$RST"
if [ "$fail" -ne 0 ]; then
  printf '%s::error::the gate chain did not behave as its fixtures specify%s\n' "$RED" "$RST"
  exit 1
fi
printf '%sscripts/check.sh is proven able to fail, to name which gate fired, and to pass.%s\n' \
  "$GREEN" "$RST"
exit 0
