#!/usr/bin/env bash
#
# scripts/check.sh — the single source of truth for "the gates" (<SERVICE>, Go).
#
# CI (.github/workflows/ci.yml) invokes this exact script, so "green locally" equals "green
# in CI" byte for byte. To change a gate, change this script, not the workflow. The only
# thing a workflow may add is an INPUT a gate needs — and every such input is declared in
# .xal/gate-inputs, which gate 0 checks against every caller.
#
# GATE ORDER, and why it is this order. It mirrors the reference service's .NET gate order
# one-for-one, because the order is a platform decision and the language is an
# implementation detail behind it: cheapest and most localising first, so a failure names
# the smallest thing that could be wrong.
#
#   0. gate inputs        — .xal/check-gate-inputs.sh            (the meta-gate; no inputs)
#   1. modules            — go mod verify + a `go mod tidy` diff (auth: restore)
#   2. format             — gofmt -l                             (auth: dotnet format)
#   3. vet                — go vet ./...                         (auth: build, half 1)
#   4. lint               — golangci-lint run                    (auth: build, half 2)
#   5. test               — go test -race -covermode=atomic      (auth: test)
#   6. coverage           — per-package floors                   (auth: coverage ratchet)
#   7. vulnerability audit — govulncheck ./...                   (auth: dotnet list --vulnerable)
#   8. docker build       — docker build                         (skippable locally)
#   9. platform spec drift — platform-sync.sh --check            (skippable locally)
#
# GOTCHA (gate 1, why `tidy` is diffed and not run): `go mod verify` only checks that the
# module cache matches the checksums — it says nothing about go.mod being complete or
# minimal. A go.mod with a stale require line builds fine here and fails the first time
# anyone builds from a clean cache. So the gate copies go.mod/go.sum aside, runs tidy, and
# diffs. It never leaves a tidied file behind: a gate that edits the tree it is judging
# cannot be run twice and mean the same thing.
#
# GOTCHA (gate 2, why not `gofmt -l .`): the fixture tree under gates/_fixtures/ contains
# DELIBERATELY broken Go files (see gates/check.test.sh). The `_` prefix keeps them away
# from `./...`, because the go tool ignores directories beginning with `_` or `.` — but
# gofmt walks the filesystem and has no such rule. So gate 2 drives gofmt from an explicit
# find that prunes gates/. Without that prune the repo's own format gate would report its
# own fixtures as failures, which is the fastest possible way to teach everyone to ignore it.
#
# GOTCHA (gate 6, why the coverprofile is parsed and not `go tool cover -func`): -func
# reports per-FUNCTION percentages plus one total. Per-PACKAGE floors cannot be recovered
# from it without re-weighting by statement counts, which -func does not print. The
# coverprofile has exactly that data — `file:l.c,l.c numStatements count` per block — so the
# gate aggregates it directly. Same numbers, one parse, no dependency on a human-formatted
# table's column layout.
#
# GOTCHA (gates 8 and 9): both are MANDATORY under CI=true and skippable locally, matching
# the reference service. A developer without Docker, or without the sibling platform
# checkout, still gets a useful local run; CI gets no such courtesy. "Skipped" is printed
# loudly, never silently.
#
# Usage:  scripts/check.sh        (from anywhere; it cd's to the repo root)
# Env:    XAL_PLATFORM_DIR        path to the xal-platform repo (default ../xal-platform)
#         CI=true                 makes the Docker and drift gates mandatory
# Deps:   bash, go, gofmt, golangci-lint, govulncheck, docker — all declared in
#         .xal/gate-inputs, which is what gate 0 exists to keep honest.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- platform spec location (gate 9) -----------------------------------------
# Where the xal-platform repo is checked out. Overridable so the sibling-clone layout used
# locally and the in-workspace path used by CI can differ; never hardcoded. A relative value
# resolves against $ROOT, which we have already cd'd to.
XAL_PLATFORM_DIR="${XAL_PLATFORM_DIR:-../xal-platform}"

COV_DIR="$ROOT/.coverage"
COV_PROFILE="$COV_DIR/cover.out"
FLOORS="$ROOT/coverage-floors"
DOCKER_TAG="xal/<SERVICE>:check"

# --- pretty output -----------------------------------------------------------
if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; YEL=""; RST=""; fi

PASSED=()
FAILED=""

banner() { printf '\n%s━━ %s%s\n' "$BOLD" "$1" "$RST"; }

gate() {
  local name="$1"; shift
  banner "$name"
  if "$@"; then
    PASSED+=("$name")
    printf '%s✔ %s%s\n' "$GREEN" "$name" "$RST"
  else
    FAILED="$name"
    printf '%s✗ %s — FAILED%s\n' "$RED" "$name" "$RST"
    summary
    exit 1
  fi
}

summary() {
  printf '\n%s──────── gate summary ────────%s\n' "$BOLD" "$RST"
  for p in "${PASSED[@]:-}"; do
    [ -n "$p" ] && printf '  %s✔%s %s\n' "$GREEN" "$RST" "$p"
  done
  if [ -n "$FAILED" ]; then
    printf '  %s✗%s %s\n' "$RED" "$RST" "$FAILED"
    printf '\n%sCHECK FAILED%s at: %s\n' "$RED$BOLD" "$RST" "$FAILED"
  else
    printf '\n%sALL GATES PASSED%s\n' "$GREEN$BOLD" "$RST"
  fi
}

# Every .go file that is part of this repo's own source — never the fixture tree.
source_go_files() {
  find . -path ./gates -prune -o -path ./.xal-platform -prune -o -name '*.go' -print
}

# --- gate 0: gate inputs are declared and every caller supplies them ----------
# The meta-gate. It runs FIRST and needs NO inputs of its own, which is deliberate and
# load-bearing: a check that catches missing inputs must not be able to have one missing.
#
# It exists because twice in four days a gate was added to a repo's check.sh that needed
# something not in the repo, and a workflow invoking that script was not updated to supply
# it. The second time, production deploys were blocked for ~3.5h while CI on the same commit
# stayed green. See xal-company ADR-0005.
#
# Canonical copy lives in xcos-core; this is a vendored copy, seeded from xal-platform's own.
# Do not edit .xal/check-gate-inputs.sh in place.
gate_inputs_step() {
  [ -f .xal/check-gate-inputs.sh ] || {
    printf '%s  .xal/check-gate-inputs.sh is missing%s\n' "$RED" "$RST"; return 1; }
  bash .xal/check-gate-inputs.sh
}

# --- gate 1: modules verified and go.mod is what tidy would write -------------
modules_step() {
  go mod verify || return 1

  local tmp rc
  tmp="$(mktemp -d)" || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  cp go.mod "$tmp/go.mod"
  [ -f go.sum ] && cp go.sum "$tmp/go.sum"

  go mod tidy || { printf '%s  go mod tidy failed%s\n' "$RED" "$RST"; return 1; }

  rc=0
  if ! diff -u "$tmp/go.mod" go.mod >/dev/null 2>&1; then
    printf '%s  go.mod is not tidy:%s\n' "$RED" "$RST"
    diff -u "$tmp/go.mod" go.mod | sed 's/^/    /'
    rc=1
  fi
  if [ -f go.sum ] && [ -f "$tmp/go.sum" ] && ! diff -u "$tmp/go.sum" go.sum >/dev/null 2>&1; then
    printf '%s  go.sum is not tidy:%s\n' "$RED" "$RST"
    diff -u "$tmp/go.sum" go.sum | sed 's/^/    /'
    rc=1
  fi

  # Restore whatever was committed. The gate reports; it does not edit the tree it judges.
  cp "$tmp/go.mod" go.mod
  [ -f "$tmp/go.sum" ] && cp "$tmp/go.sum" go.sum

  if [ "$rc" -ne 0 ]; then
    printf '\n%s::error::run `go mod tidy` and commit the result%s\n' "$RED" "$RST"
    return 1
  fi
  printf '  modules verified; go.mod and go.sum are tidy\n'
  return 0
}

# --- gate 2: gofmt ------------------------------------------------------------
format_step() {
  local unformatted
  # Refusing to run over an empty file list is not defensiveness. BSD xargs has no `-r`, so
  # an empty list runs `gofmt -l` with no arguments, which reads stdin and HANGS — and a
  # repo whose Go files all moved would otherwise report a green format gate over nothing.
  if [ -z "$(source_go_files)" ]; then
    printf '%s  no Go source files found — refusing to report a format gate green over nothing%s\n' "$RED" "$RST"
    return 1
  fi
  unformatted="$(source_go_files | xargs gofmt -l)"
  if [ -n "$unformatted" ]; then
    printf '%s  these files are not gofmt-clean:%s\n' "$RED" "$RST"
    printf '%s\n' "$unformatted" | sed 's/^/    /'
    printf '\n%s::error::run `gofmt -w` on the files above%s\n' "$RED" "$RST"
    return 1
  fi
  printf '  %s file(s) gofmt-clean\n' "$(source_go_files | wc -l | tr -d ' ')"
  return 0
}

# --- gate 3: vet --------------------------------------------------------------
vet_step() { go vet ./...; }

# --- gate 4: lint -------------------------------------------------------------
lint_step() {
  if ! command -v golangci-lint >/dev/null 2>&1; then
    if [ "${CI:-}" = "true" ]; then
      printf '%sgolangci-lint is required in CI but is unavailable.%s\n' "$RED" "$RST"
      return 1
    fi
    printf '%s⚠ golangci-lint unavailable — SKIPPING the lint gate (mandatory in CI).%s\n' "$YEL" "$RST"
    return 0
  fi
  golangci-lint run ./...
}

# --- gate 5: test -------------------------------------------------------------
# -race because every background loop this service will grow (the sequencer, the feed
# poller) is a goroutine, and a data race that only shows under load is the one class of bug
# a coverage number says nothing about.
test_step() {
  rm -rf "$COV_DIR"
  mkdir -p "$COV_DIR"
  go test -race -covermode=atomic -coverprofile="$COV_PROFILE" ./...
}

# --- gate 6: per-package coverage floors --------------------------------------
# Floors live in ./coverage-floors as `package | floor` records. A floor is a RATCHET: set
# from the first measured green build, and it only ever goes up. A package listed at floor 0
# is collect-only — printed, not gated — which is how a package with no tests yet stays
# visible instead of silently absent.
#
# A package in the floors file with NO measured statements is a failure, not a pass, unless
# its floor is 0. "The package vanished" and "the package is fully covered" must never emit
# the same green.
coverage_step() {
  [ -f "$FLOORS" ] || {
    printf '%s  %s is missing — per-package floors are enforced by nothing%s\n' "$RED" "$FLOORS" "$RST"
    return 1; }
  [ -s "$COV_PROFILE" ] || {
    printf '%s  no coverage profile at %s — did the test gate run?%s\n' "$RED" "$COV_PROFILE" "$RST"
    return 1; }

  local module
  module="$(go list -m)"

  # Aggregate the profile by package directory: sum statements, and sum those with count>0.
  # Profile lines are `name.go:startLine.col,endLine.col numStatements count`.
  local measured
  measured="$(awk -v mod="$module" '
    NR == 1 && $0 ~ /^mode:/ { next }
    {
      split($0, parts, ":")
      file = parts[1]
      n = split(file, seg, "/")
      pkg = ""
      for (i = 1; i < n; i++) pkg = pkg (i > 1 ? "/" : "") seg[i]
      total[pkg] += $2
      if ($3 + 0 > 0) covered[pkg] += $2
    }
    END {
      for (p in total) {
        rel = p
        sub("^" mod "/", "", rel)
        if (rel == mod) rel = "."
        printf "%s %d %d\n", rel, covered[p] + 0, total[p]
      }
    }' "$COV_PROFILE")"

  local fail=0 line pkg floor cov tot pct
  printf '  %-34s %9s  %6s   %s\n' "package" "covered" "floor" "status"
  printf '  %-34s %9s  %6s   %s\n' "----------------------------------" "---------" "------" "------"

  while IFS= read -r line; do
    line="${line%%#*}"
    case "$line" in *[![:space:]]*) ;; *) continue ;; esac
    pkg="$( printf '%s' "$line" | awk -F'|' '{print $1}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    floor="$(printf '%s' "$line" | awk -F'|' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    cov="$(printf '%s\n' "$measured" | awk -v p="$pkg" '$1 == p {print $2; found=1} END{if(!found) print ""}')"
    tot="$(printf '%s\n' "$measured" | awk -v p="$pkg" '$1 == p {print $3; found=1} END{if(!found) print ""}')"

    if [ -z "$tot" ] || [ "$tot" = "0" ]; then
      if [ "$floor" -eq 0 ]; then
        printf '  %-34s %8s   %6s   %scollect-only (no statements measured)%s\n' "$pkg" "—" "—" "$YEL" "$RST"
      else
        printf '  %-34s %8s   %5s%%   %sNO STATEMENTS MEASURED%s\n' "$pkg" "—" "$floor" "$RED" "$RST"
        fail=1
      fi
      continue
    fi

    pct="$(awk -v c="$cov" -v t="$tot" 'BEGIN{printf "%.2f", (c*100.0)/t}')"
    if [ "$floor" -eq 0 ]; then
      printf '  %-34s %7s%%   %6s   %scollect-only%s\n' "$pkg" "$pct" "—" "$YEL" "$RST"
    elif awk -v a="$pct" -v b="$floor" 'BEGIN{exit !(a+0 < b+0)}'; then
      printf '  %-34s %7s%%   %5s%%   %sBELOW FLOOR%s\n' "$pkg" "$pct" "$floor" "$RED" "$RST"
      fail=1
    else
      printf '  %-34s %7s%%   %5s%%   %s>= floor%s\n' "$pkg" "$pct" "$floor" "$GREEN" "$RST"
    fi
  done < "$FLOORS"

  # A package that has statements but no floor record is a hole in the ratchet. Report it
  # loudly rather than letting new code arrive ungated — the closed-world move every other
  # manifest in this estate makes.
  local undeclared=""
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    pkg="${m%% *}"
    grep -qE "^[[:space:]]*${pkg//\//\\/}[[:space:]]*\|" "$FLOORS" || undeclared="${undeclared}${pkg}"$'\n'
  done <<< "$measured"
  if [ -n "$undeclared" ]; then
    printf '\n%s  these packages have measured statements but no floor record in %s:%s\n' "$RED" "$FLOORS" "$RST"
    printf '%s' "$undeclared" | sed 's/^/    /'
    printf '    Add each at its measured percentage (a floor is a ratchet: set it from reality).\n'
    fail=1
  fi

  if [ "$fail" -ne 0 ]; then
    printf '\n%s::error::coverage is below an enforced per-package floor, or a package is ungated%s\n' "$RED" "$RST"
    return 1
  fi
  return 0
}

# --- gate 7: vulnerability audit ----------------------------------------------
audit_step() {
  if ! command -v govulncheck >/dev/null 2>&1; then
    if [ "${CI:-}" = "true" ]; then
      printf '%sgovulncheck is required in CI but is unavailable.%s\n' "$RED" "$RST"
      return 1
    fi
    printf '%s⚠ govulncheck unavailable — SKIPPING the audit gate (mandatory in CI).%s\n' "$YEL" "$RST"
    return 0
  fi
  govulncheck ./...
}

# --- gate 8: docker image build -----------------------------------------------
docker_step() {
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    if [ "${CI:-}" = "true" ]; then
      printf '%sDocker is required in CI but is unavailable.%s\n' "$RED" "$RST"
      return 1
    fi
    printf '%s⚠ Docker unavailable — SKIPPING image build (mandatory in CI).%s\n' "$YEL" "$RST"
    return 0
  fi
  docker build -t "$DOCKER_TAG" .
}

# --- gate 9: platform spec drift ----------------------------------------------
# Delegates to the platform repo's own platform-sync.sh --check; the sync contract lives
# there, not here. The fix for a red drift gate is ALWAYS to re-run the sync and review the
# diff — NEVER to hand-edit docs/platform/, which would only make the gate permanently red.
#
# Exit codes are distinguished: 1 is real drift, anything else is misconfiguration. Both fail
# — a gate that cannot run has not passed — but a broken XAL_PLATFORM_DIR must not read as
# genuine spec drift.
platform_drift_step() {
  local sync_script="${XAL_PLATFORM_DIR}/sync/platform-sync.sh"

  if [ ! -x "$sync_script" ]; then
    if [ "${CI:-}" = "true" ]; then
      printf '%sThe platform repo is required in CI but %s is missing or not executable.%s\n' \
        "$RED" "$sync_script" "$RST"
      printf '%sCheck out xodeeq/xal-platform and point XAL_PLATFORM_DIR at it.%s\n' "$RED" "$RST"
      return 1
    fi
    printf '%s⚠ No platform repo at %s — SKIPPING the spec-drift check (mandatory in CI).%s\n' \
      "$YEL" "$XAL_PLATFORM_DIR" "$RST"
    return 0
  fi

  "$sync_script" "$XAL_PLATFORM_DIR" --check
  local rc=$?
  case "$rc" in
    0) return 0 ;;
    1) printf '%s::error::this service is BEHIND the platform spec — run `%s %s` from the repo root and review the unstaged diff in your PR.%s\n' \
         "$RED" "$sync_script" "$XAL_PLATFORM_DIR" "$RST"
       return 1 ;;
    *) printf '%s::error::platform-sync.sh could not run (exit %s) — XAL_PLATFORM_DIR=%s is not a valid platform repo.%s\n' \
         "$RED" "$rc" "$XAL_PLATFORM_DIR" "$RST"
       return 1 ;;
  esac
}

# --- run the gates in CI order -------------------------------------------------
gate "gate inputs declared + every caller wired"   gate_inputs_step
gate "modules (go mod verify + tidy diff)"         modules_step
gate "format (gofmt -l)"                           format_step
gate "vet (go vet ./...)"                          vet_step
gate "lint (golangci-lint run)"                    lint_step
gate "test (go test -race, with coverage)"         test_step
gate "coverage (per-package floors)"               coverage_step
gate "vulnerability audit (govulncheck)"           audit_step
gate "docker image build"                          docker_step
gate "platform spec drift (vendored docs/platform/)" platform_drift_step

summary
