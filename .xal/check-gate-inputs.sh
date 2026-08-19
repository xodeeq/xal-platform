#!/usr/bin/env bash
#
# check-gate-inputs.sh — assert that every caller of a repo's gate script supplies
# every input that script's gates require.
#
# CANONICAL COPY: xcos-core (xal-company/plugins/xcos-core/scripts/). Each repo runs a
# vendored copy at .xal/check-gate-inputs.sh, because CI runs plain scripts and a plugin
# is not resolvable from a plain `run:` step. Change it HERE and re-vendor; never edit a
# vendored copy in place (xal-company ADR-0004 §4, one-way sync).
#
# WHY THIS EXISTS ------------------------------------------------------------------
#
# Twice, a gate was added to a repo's check.sh that needed something not in the repo,
# and a workflow invoking that script was not updated to supply it:
#
#   * 2026-08-12, xal-auth   — gate 7 (platform spec drift) needed a platform checkout
#     + $XAL_PLATFORM_DIR. ci.yml got it, deploy.yml did not. deploy.yml sets CI=true,
#     which makes the gate mandatory, so its gate job failed and `needs: gate` blocked
#     production deploys for ~3.5h. CI on the same commit was GREEN.
#   * 2026-08-15, xal-platform — gate 5 (plugin manifests) needed the `claude` CLI.
#     ci.yml did not install it; the gate failed on its first CI run.
#
# The shared root cause is NOT that the setup is duplicated. It is that a gate's input
# requirements are DISCOVERED BY EXECUTION rather than DECLARED AS DATA — and the
# author's machine satisfies them ambiently (the sibling repo happens to be at
# ../xal-platform, `claude` happens to be on $PATH) while CI must satisfy each one by an
# explicit step. So the authoring environment is structurally incapable of revealing the
# obligation CI will enforce, and there is no artifact for a caller to be checked
# against. A guardrail ("grep every caller before pushing") is a memory aid attached to
# nothing, which is why it failed the second time.
#
# This script inverts that. Inputs become declared data (.xal/gate-inputs); the gate
# script's implicit requirements are DERIVED and checked against that declaration; and
# every caller is checked against every input. Adding an input without wiring a caller
# now fails the gate LOCALLY, at authoring time, before push.
#
# IT REQUIRES NO INPUTS OF ITS OWN. It reads only files already in the repo — the gate
# script, the manifest, and .github/workflows/. That is deliberate and load-bearing: a
# gate that catches missing inputs must not itself be able to have one missing.
#
# MANIFEST FORMAT (.xal/gate-inputs) — one record per line, five pipe-delimited fields:
#
#   id | detect | required-in-ci | caller-pattern | description
#
#   id              short stable name, e.g. claude-cli
#   detect          how check.sh discovers it: command:<name> | env:<VAR> | none
#   required-in-ci  yes | no   (no = the gate skips rather than fails when absent)
#   caller-pattern  ERE that MUST match a caller workflow that supplies it, or the
#                   literal `-` meaning "provided by the runner image; no step needed"
#   description     prose, for the human reading a failure
#
# Usage:  .xal/check-gate-inputs.sh [--gate-script P] [--manifest P] [--workflows D]
# Deps:   bash, grep, sed, awk, find. No language runtime, no network, no credential.

set -uo pipefail

GATE_SCRIPT="scripts/check.sh"
MANIFEST=".xal/gate-inputs"
WORKFLOWS=".github/workflows"

while [ $# -gt 0 ]; do
  case "$1" in
    --gate-script) GATE_SCRIPT="$2"; shift 2 ;;
    --manifest)    MANIFEST="$2";    shift 2 ;;
    --workflows)   WORKFLOWS="$2";   shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then RED=$'\033[31m'; YEL=$'\033[33m'; RST=$'\033[0m'
else RED=""; YEL=""; RST=""; fi

fail=0
note() { printf '%s  %s%s\n' "$RED" "$1" "$RST"; fail=1; }
warn() { printf '%s  ⚠ %s%s\n' "$YEL" "$1" "$RST"; }

# Exit 2 (cannot run) is deliberately distinct from exit 1 (found a real problem) —
# the auth gate-7 precedent. A missing manifest is an infrastructure fault, not a pass.
[ -f "$GATE_SCRIPT" ] || { printf '%sgate script not found: %s%s\n' "$RED" "$GATE_SCRIPT" "$RST"; exit 2; }
[ -f "$MANIFEST" ]    || { printf '%smanifest not found: %s%s\n' "$RED" "$MANIFEST" "$RST"; exit 2; }

# --- read the manifest --------------------------------------------------------
# Records are held in parallel arrays rather than an associative array so this runs on
# bash 3.2 (the macOS system bash) as well as on the CI runner's bash 5.
IDS=(); DETECTS=(); REQS=(); PATTERNS=(); DESCS=()

lineno=0
while IFS= read -r raw || [ -n "$raw" ]; do
  lineno=$((lineno + 1))
  line="${raw%%#*}"
  case "$line" in *[![:space:]]*) ;; *) continue ;; esac

  n="$(printf '%s' "$line" | awk -F'|' '{print NF}')"
  if [ "$n" -ne 5 ]; then
    note "$MANIFEST:$lineno: expected 5 pipe-delimited fields, got $n"
    continue
  fi

  f_id="$(  printf '%s' "$line" | awk -F'|' '{print $1}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  f_det="$( printf '%s' "$line" | awk -F'|' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  f_req="$( printf '%s' "$line" | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  f_pat="$( printf '%s' "$line" | awk -F'|' '{print $4}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  f_dsc="$( printf '%s' "$line" | awk -F'|' '{print $5}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  case "$f_req" in yes|no) ;; *) note "$MANIFEST:$lineno: required-in-ci must be yes|no, got '$f_req'" ;; esac
  case "$f_det" in command:?*|env:?*|none) ;; *) note "$MANIFEST:$lineno: detect must be command:<n>|env:<V>|none, got '$f_det'" ;; esac
  [ -n "$f_dsc" ] || note "$MANIFEST:$lineno: description is required — a failure message with no prose is a puzzle"

  IDS+=("$f_id"); DETECTS+=("$f_det"); REQS+=("$f_req"); PATTERNS+=("$f_pat"); DESCS+=("$f_dsc")
done < "$MANIFEST"

# --- A. every input the gate script actually needs must be DECLARED -----------
# This is the half that makes occurrence 2 impossible. Adding `command -v jq` to the
# gate script without declaring it fails here, in the author's own local run, before
# any workflow is even considered.
#
# Two idioms are derived, and they are exactly the two the real occurrences used:
#   * `command -v NAME`                    -> command:NAME
#   * `VAR="${VAR:-default}"` (top level)  -> env:VAR
# CI is excluded: it is a mode switch the runner sets, not an input to be supplied.
derived="$( { grep -oE 'command -v [A-Za-z0-9_.-]+' "$GATE_SCRIPT" \
                | sed 's/^command -v /command:/'
              grep -oE '^[A-Z_]+="\$\{[A-Z_]+:-' "$GATE_SCRIPT" \
                | sed 's/=.*//; s/^/env:/'
            } | sort -u | grep -v '^env:CI$' )"

declared="$(printf '%s\n' "${DETECTS[@]:-}" | grep -v '^none$' | sort -u)"

if [ -n "$derived" ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if ! printf '%s\n' "$declared" | grep -qxF -- "$d"; then
      note "UNDECLARED INPUT  $GATE_SCRIPT requires '$d' but $MANIFEST does not declare it"
      printf '    Add a record for it, then wire every caller. Both halves, or neither counts.\n'
    fi
  done <<< "$derived"
fi

# The inverse is a WARNING, not a failure: derivation is deliberately incomplete. An
# input invoked directly (auth calls `dotnet restore` without ever `command -v`-ing it)
# is real and undetectable, so a declaration with no derived match is normal.
if [ -n "$declared" ]; then
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -n "$derived" ] && ! printf '%s\n' "$derived" | grep -qxF -- "$d"; then
      warn "declared but not derived: '$d' — fine if invoked directly, stale otherwise"
    fi
  done <<< "$declared"
fi

# --- B. discover the callers ---------------------------------------------------
# Zero callers is a FAILURE, never a pass. A renamed gate script would otherwise
# silently empty this check while it kept reporting green — the exact "passes because it
# matches nothing" shape this estate has already hit twice (the awk \b bug, the
# --include='*.cs' glob in a Go repo).
callers=""
if [ -d "$WORKFLOWS" ]; then
  callers="$(grep -lE "(^|[^A-Za-z0-9_/.-])\./?$(printf '%s' "$GATE_SCRIPT" | sed 's/[.[\*^$]/\\&/g')" \
             "$WORKFLOWS"/*.y*ml 2>/dev/null | sort || true)"
fi

if [ -z "$callers" ]; then
  if [ ! -d "$WORKFLOWS" ]; then
    note "NO WORKFLOW DIRECTORY  $WORKFLOWS does not exist, so nothing runs these gates in CI"
  else
    note "NO CALLERS FOUND  no workflow under $WORKFLOWS invokes $GATE_SCRIPT"
  fi
  printf '    A gate script nothing calls is not passing — it is absent. If the script was\n'
  printf '    renamed, pass --gate-script; if CI genuinely does not run it, say so in an ADR.\n'
fi

# --- C. every caller must supply every CI-required input ----------------------
ncheck=0
if [ -n "$callers" ] && [ "${#IDS[@]:-0}" -gt 0 ]; then
  while IFS= read -r wf; do
    [ -n "$wf" ] || continue
    i=0
    while [ "$i" -lt "${#IDS[@]}" ]; do
      if [ "${REQS[$i]}" = "yes" ]; then
        pat="${PATTERNS[$i]}"
        if [ "$pat" = "-" ]; then
          : # runner-provided; no step required. Deliberate escape hatch — keep it rare.
        else
          ncheck=$((ncheck + 1))
          if ! grep -qE -- "$pat" "$wf"; then
            note "MISSING INPUT  $wf does not supply '${IDS[$i]}'"
            printf '    %s\n' "${DESCS[$i]}"
            printf '    Expected this workflow to match: /%s/\n' "$pat"
          fi
        fi
      fi
      i=$((i + 1))
    done
  done <<< "$callers"
fi

# --- report -------------------------------------------------------------------
if [ "$fail" -ne 0 ]; then
  printf '\n%s::error::a gate input is undeclared, or a caller of %s does not supply one%s\n' \
    "$RED" "$GATE_SCRIPT" "$RST"
  printf '  The gate script cannot see its callers, so this check sees them for it.\n'
  printf '  Fix BOTH halves: declare the input in %s and wire every workflow above.\n' "$MANIFEST"
  exit 1
fi

ncallers="$(printf '%s\n' "$callers" | grep -c . || true)"
printf '  %s input(s) declared; %s caller(s) of %s; %s caller×input assertion(s) — all satisfied\n' \
  "${#IDS[@]:-0}" "$ncallers" "$GATE_SCRIPT" "$ncheck"
exit 0
