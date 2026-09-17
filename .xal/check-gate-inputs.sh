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
#   id | detect | required-in-ci | caller-pattern | expires | description
#
#   id              short stable name, e.g. claude-cli
#   detect          how check.sh discovers it: command:<name> | env:<VAR> | none
#   required-in-ci  yes | no   (no = the gate skips rather than fails when absent)
#   caller-pattern  one of three forms:
#                     `-`                  provided by the runner image; no step needed
#                     `<ERE>`              EVERY caller of the gate script must match it
#                     `<workflow>:<ERE>`   only that one workflow must match it
#   expires         ISO date YYYY-MM-DD, or `-` for an input that cannot expire
#                   (a toolchain, a runner-provided binary). REQUIRED to be a real date
#                   when the caller-pattern references `secrets.` — see below.
#   description     prose, for the human reading a failure
#
# THE WORKFLOW-SCOPED CALLER PATTERN, and why it exists (platform ADR-0008, revised during
# implementation). This manifest was built to answer one question — "does every caller of
# THE GATE SCRIPT supply what that script needs?" — and a repo's other workflows had no
# input contract at all. That gap surfaced the moment a credential needed declaring: the
# xcos-core read token and the board-add project token are both supplied to workflows that
# never invoke scripts/check.sh, so declaring them the old way would have forced ci.yml and
# deploy.yml to reference secrets they have no use for. A manifest that can only describe
# one script's inputs cannot hold a repo's credentials, which is what ADR-0008 asked it to
# do. So a pattern may name its workflow: `board-add.yml:secrets.XAL_PROJECT_TOKEN` asserts
# that THAT file exists and matches, and says nothing about the gate script's callers.
#
# THE EXPIRY FIELD (platform ADR-0008). A credential is an input like any other, with one
# property no other input has: it stops working on a date known in advance. Before this
# field, that date lived in prose or in someone's memory — on 2026-09-17 a 90-day PAT was
# issued and had to be parked in xal-company's status/current.md for want of anywhere
# better, which is the failure the restructuring note had predicted a day earlier.
#
# So the date is DATA, checked by the same mechanism that checks every other input:
#   * every record carries an `expires` (a date or an explicit `-`) — there is no silent
#     default, because "nobody filled it in" and "it cannot expire" must not look alike;
#   * a caller-pattern that references `secrets.` is a credential by construction, so `-`
#     is refused there — a secret that can never expire is a claim, not a configuration;
#   * a past date FAILS, and a date inside 30 days WARNS, so the build goes yellow before
#     it goes red rather than discovering the lapse as a mystery checkout failure.
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
IDS=(); DETECTS=(); REQS=(); PATTERNS=(); EXPIRES=(); DESCS=()

lineno=0
while IFS= read -r raw || [ -n "$raw" ]; do
  lineno=$((lineno + 1))
  line="${raw%%#*}"
  case "$line" in *[![:space:]]*) ;; *) continue ;; esac

  n="$(printf '%s' "$line" | awk -F'|' '{print NF}')"
  if [ "$n" -ne 6 ]; then
    note "$MANIFEST:$lineno: expected 6 pipe-delimited fields, got $n"
    [ "$n" -eq 5 ] && printf '    Five fields is the pre-ADR-0008 format. Add an `expires` column before the
    description: an ISO date for a credential, `-` for anything that cannot expire.
'
    continue
  fi

  f_id="$(  printf '%s' "$line" | awk -F'|' '{print $1}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  f_det="$( printf '%s' "$line" | awk -F'|' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  f_req="$( printf '%s' "$line" | awk -F'|' '{print $3}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  f_pat="$( printf '%s' "$line" | awk -F'|' '{print $4}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  f_exp="$( printf '%s' "$line" | awk -F'|' '{print $5}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  f_dsc="$( printf '%s' "$line" | awk -F'|' '{print $6}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  case "$f_req" in yes|no) ;; *) note "$MANIFEST:$lineno: required-in-ci must be yes|no, got '$f_req'" ;; esac
  case "$f_det" in command:?*|env:?*|none) ;; *) note "$MANIFEST:$lineno: detect must be command:<n>|env:<V>|none, got '$f_det'" ;; esac
  [ -n "$f_dsc" ] || note "$MANIFEST:$lineno: description is required — a failure message with no prose is a puzzle"

  case "$f_exp" in
    -) ;;
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
    *) note "$MANIFEST:$lineno: expires must be an ISO date YYYY-MM-DD or '-', got '$f_exp'" ;;
  esac

  IDS+=("$f_id"); DETECTS+=("$f_det"); REQS+=("$f_req"); PATTERNS+=("$f_pat"); EXPIRES+=("$f_exp"); DESCS+=("$f_dsc")
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

# A workflow-scoped record describes an input to a DIFFERENT workflow, so the gate script
# can never derive it. Excluding those from the "declared but not derived" warning below is
# not leniency — a warning that fires on every correctly-declared credential is noise, and
# noise is how a real stale declaration gets scrolled past.
scoped_detects=""
if [ "${#IDS[@]:-0}" -gt 0 ]; then
  i=0
  while [ "$i" -lt "${#IDS[@]}" ]; do
    case "${PATTERNS[$i]}" in
      */*) ;;
      *.yml:*|*.yaml:*) scoped_detects="${scoped_detects}${DETECTS[$i]}"$'\n' ;;
    esac
    i=$((i + 1))
  done
fi

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
    if printf '%s' "$scoped_detects" | grep -qxF -- "$d"; then
      continue   # workflow-scoped; the gate script is not where it is used
    fi
    if [ -n "$derived" ] && ! printf '%s\n' "$derived" | grep -qxF -- "$d"; then
      warn "declared but not derived: '$d' — fine if invoked directly, stale otherwise"
    fi
  done <<< "$declared"
fi

# --- A2. credentials declare a real expiry, and it has not passed --------------
# Deps stay bash/awk: the day-number conversion below is the civil-from-days algorithm,
# so no `date -d` (GNU) vs `date -v` (BSD) split and no language runtime. A checker that
# acquires an input of its own would be the joke this script exists to prevent.
today="$(date -u +%Y-%m-%d)"

day_number() {
  printf '%s' "$1" | awk -F- '{
    y = $1 + 0; m = $2 + 0; d = $3 + 0
    if (m <= 2) y -= 1
    era = int((y >= 0 ? y : y - 399) / 400)
    yoe = y - era * 400
    doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
    doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
    print era * 146097 + doe - 719468
  }'
}

if [ "${#IDS[@]:-0}" -gt 0 ]; then
  today_n="$(day_number "$today")"
  i=0
  while [ "$i" -lt "${#IDS[@]}" ]; do
    exp="${EXPIRES[$i]}"
    pat="${PATTERNS[$i]}"

    # A caller-pattern naming `secrets.` is a credential by construction: CI supplies it
    # from the secret store. `-` there asserts a secret that never expires, which is a
    # claim about the provider that this repo cannot make.
    case "$pat" in
      *secrets.*)
        if [ "$exp" = "-" ]; then
          note "CREDENTIAL WITHOUT AN EXPIRY  '${IDS[$i]}' is supplied from the secret store but declares expires '-'"
          printf '    %s\n' "${DESCS[$i]}"
          printf "    A secret has an expiry date whether or not it is written down. Put it in the\n"
          printf "    manifest — that is the difference between a rotation you schedule and one you\n"
          printf "    discover from a red checkout.\n"
        fi
        ;;
    esac

    if [ "$exp" != "-" ]; then
      exp_n="$(day_number "$exp")"
      if [ "$exp_n" -lt "$today_n" ]; then
        note "EXPIRED INPUT  '${IDS[$i]}' expired on $exp (today is $today)"
        printf '    %s\n' "${DESCS[$i]}"
        printf "    Rotate it, update this field, and re-vendor if the manifest is shared.\n"
      elif [ "$((exp_n - today_n))" -le 30 ]; then
        warn "'${IDS[$i]}' expires on $exp — $((exp_n - today_n)) day(s) left; rotate before it lapses"
      fi
    fi
    i=$((i + 1))
  done
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
        elif case "$pat" in */*) false ;; *.yml:*|*.yaml:*) true ;; *) false ;; esac; then
          : # workflow-scoped; asserted against its named workflow in C2, not against every
            # caller of the gate script.
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

# --- C2. workflow-scoped inputs: the named workflow must exist and supply it ---
# A missing workflow is a FAILURE, not a skip — the same reasoning as "zero callers is
# never a pass". A record pointing at a file that does not exist asserts nothing, and would
# report green forever while the credential it describes reached no workflow at all.
if [ "${#IDS[@]:-0}" -gt 0 ]; then
  i=0
  while [ "$i" -lt "${#IDS[@]}" ]; do
    pat="${PATTERNS[$i]}"
    case "$pat" in
      -|*/*) ;;
      *.yml:*|*.yaml:*)
        wf_name="${pat%%:*}"
        wf_pat="${pat#*:}"
        wf_path="$WORKFLOWS/$wf_name"
        ncheck=$((ncheck + 1))
        if [ ! -f "$wf_path" ]; then
          note "MISSING WORKFLOW  '${IDS[$i]}' names $wf_name, which does not exist"
          printf '    %s\n' "${DESCS[$i]}"
          printf "    Declaring an input against a workflow that is not there asserts nothing.\n"
        elif ! grep -qE -- "$wf_pat" "$wf_path"; then
          note "MISSING INPUT  $wf_path does not supply '${IDS[$i]}'"
          printf '    %s\n' "${DESCS[$i]}"
          printf '    Expected this workflow to match: /%s/\n' "$wf_pat"
        fi
        ;;
    esac
    i=$((i + 1))
  done
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
