#!/usr/bin/env bash
#
# scripts/check.sh — the single source of truth for "the gates" (platform repo).
#
# Mirrors the auth service's scripts/check.sh in structure and contract: CI
# (.github/workflows/ci.yml) invokes this exact script, so "green locally" equals
# "green in CI" byte for byte. To change a gate, change this script, not the workflow.
#
# This repo is docs/tooling/process — there is no application, no compiler and no TDD
# gate. Its quality bar is the four clauses CLAUDE.md already names ("How we work
# here"), turned into checks:
#
#   1. language-agnostic spec   — no service-language specifics as normative statements
#   2. links resolve            — relative links resolve; manifest files may not link
#                                 outside the vendored set          (see GOTCHA below)
#   3. scaffold self-consistency — scaffold links resolve; manifest ⊆ spec/
#   4. sync round-trip          — sync into a temp dir, assert --check passes
#   5. plugin manifests         — `claude plugin validate --strict` on the marketplace
#                                 and every plugin under plugins/  (see GOTCHA below)
#
# GOTCHA (gate 2, the rule that pays for this script): a file in sync/manifest is
# copied VERBATIM into a consumer's docs/platform/. Its links travel with it but its
# neighbours do not — inside a consumer, `../` resolves to that service's docs/, not
# to this repo's root. So a link can be correct here and broken in every consumer at
# once, and it looks fine to anyone reviewing it here. That is not hypothetical: three
# such links shipped in spec/README.md and reached auth's docs/platform/ before a link
# check caught them (fixed in 0.1.1). Gate 2 checks the VENDORED context, not just
# local resolution.
#
# GOTCHA (gate 1, deciding what counts as a citation): CLAUDE.md's prime directive
# allows a service-language specific ONLY inside a labelled "auth reference
# realization" citation. "Inside a citation" has to be mechanically decidable or the
# gate is a fuzzy heuristic, so two markers are canonical:
#   - "**Auth ref:**" / "**Auth reference.**"  start a citation region, which runs to
#     the end of that bullet (indented continuations) or, for the paragraph form, to
#     the next blank line;
#   - "<!-- auth-ref -->" anywhere in a blank-line-delimited paragraph exempts that
#     whole paragraph — the escape hatch for an illustration that legitimately sits
#     inside normative prose (e.g. a multi-language example list).
# A hit outside both is a leak and fails the gate.
#
# GOTCHA (gate 3, the scaffold's forward references): the scaffold links into
# docs/platform/<file> for files that do NOT exist in the scaffold — its
# docs/platform/ is an empty landing dir until a seeded service runs its first sync.
# Those links are correct by design, so they are validated against sync/manifest
# rather than against the filesystem. That is STRICTER than a file check: it also
# catches a scaffold link to a spec file nobody vendors, which would dangle forever
# in every real service.
#
# Usage:  scripts/check.sh        (from anywhere; it cd's to the repo root)
# Deps:   bash, awk, grep, diff, mktemp — deliberately no language runtime, in a repo
#         whose entire purpose is to stay language-agnostic.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MANIFEST="sync/manifest"
SYNC="sync/platform-sync.sh"

# The CLAUDE.md leak grep. Keep this in step with the one documented there.
LEAK_RE='\bdotnet\b|\.csproj|\.slnx|xUnit|Npgsql|Argon2|\bAuth\.[A-Z]'

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

# --- shared helpers ----------------------------------------------------------

# The vendored set: the files sync/manifest names (comments/blanks stripped).
manifest_files() {
  sed 's/#.*//' "$MANIFEST" | tr -d '[:blank:]' | grep -v '^$'
}

# Every markdown-ish file in the repo, excluding .git. CLAUDE.md.template is included
# because it is real content that ships in the scaffold.
md_files() {
  find . -path ./.git -prune -o \( -name '*.md' -o -name '*.md.template' \) -print \
    | sed 's|^\./||' | sort
}

# Split by scaffold membership. These exist as functions rather than inline `case`
# filters because a `)` in a case pattern closes an enclosing <( … ) substitution.
scaffold_md_files()     { md_files | grep '^scaffold/'    || true; }
non_scaffold_md_files() { md_files | grep -v '^scaffold/' || true; }

# Emit "file<TAB>line<TAB>target" for every markdown inline link in $1.
# Anchors and absolute URLs are dropped here; callers only see path-ish targets.
extract_links() {
  awk -v F="$1" '
    {
      line = $0
      while (match(line, /\]\([^)]+\)/)) {
        tgt = substr(line, RSTART + 2, RLENGTH - 3)
        line = substr(line, RSTART + RLENGTH)
        sub(/#.*$/, "", tgt)                  # strip anchor
        sub(/[[:space:]].*$/, "", tgt)        # strip a title after the path
        if (tgt == "") continue
        if (tgt ~ /^(https?|mailto):/) continue
        printf "%s\t%d\t%s\n", F, NR, tgt
      }
    }' "$1"
}

# --- gate 1: language-agnostic spec ------------------------------------------
# Every LEAK_RE hit in spec/ must sit inside a citation region or an escaped
# paragraph (see GOTCHA above). Anything else is a .NET-ism stated as a platform rule.
spec_language_agnostic_step() {
  local fail=0 f out hits allowed
  for f in $(manifest_files); do
    # GOTCHA: the LEAK_RE from CLAUDE.md uses \b, which grep -E supports and awk does
    # NOT (POSIX awk reads \b as backspace, so `\bdotnet\b` silently matches nothing).
    # So grep finds the hits and awk only computes which lines are excused; keeping one
    # pattern, evaluated by the one engine that understands it.
    hits="$(grep -nE "$LEAK_RE" "spec/$f" | cut -d: -f1)"
    [ -z "$hits" ] && continue
    allowed="$(awk '
      { L[NR] = $0 }
      END {
        # Pass 1 — mark citation regions.
        inregion = 0; shapeB = 0
        for (i = 1; i <= NR; i++) {
          l = L[i]
          if (l ~ /^[[:space:]]*([-*][[:space:]]+)?\*\*Auth ref(erence)?[:.]\*\*/) {
            inregion = 1; shapeB = (l ~ /^\*\*/); cite[i] = 1; continue
          }
          if (!inregion) continue
          if (l ~ /^[[:space:]]*$/) {
            # A blank ends a paragraph-form region; for the bullet form, keep going
            # only if the next non-blank line is still an indented continuation.
            if (shapeB) { inregion = 0; continue }
            j = i + 1
            while (j <= NR && L[j] ~ /^[[:space:]]*$/) j++
            if (j <= NR && L[j] ~ /^[[:space:]][[:space:]]+[^[:space:]]/) { cite[i] = 1; continue }
            inregion = 0; continue
          }
          if (l ~ /^[[:space:]][[:space:]]+[^[:space:]]/) { cite[i] = 1; continue }  # continuation
          # A paragraph-form marker ("**Auth reference.**" on its own line) is routinely
          # followed by a top-level bullet list that is still part of the citation.
          if (shapeB && l ~ /^[-*][[:space:]]/) { cite[i] = 1; continue }
          inregion = 0
        }
        # Pass 2 — mark paragraphs carrying the explicit escape comment.
        start = 1
        for (i = 1; i <= NR + 1; i++) {
          if (i > NR || L[i] ~ /^[[:space:]]*$/) {
            esc = 0
            for (j = start; j < i; j++) if (L[j] ~ /<!--[[:space:]]*auth-ref[[:space:]]*-->/) esc = 1
            if (esc) for (j = start; j < i; j++) exempt[j] = 1
            start = i + 1
          }
        }
        # Pass 3 — emit the line numbers that are excused.
        for (i = 1; i <= NR; i++) if (cite[i] || exempt[i]) print i
      }' "spec/$f")"

    # A hit that is not in the excused set is a leak. Set difference via grep -vxF, not
    # comm: comm assumes LEXICALLY sorted input, and line numbers sort differently
    # numerically ("127" < "30" lexically) — feeding it `sort -n` silently mis-pairs.
    # Guard the empty case: an empty pattern list would make grep -vxF drop everything.
    if [ -z "$allowed" ]; then
      out="$(printf '%s\n' $hits)"
    else
      out="$(printf '%s\n' $hits | grep -vxF -f <(printf '%s\n' $allowed) || true)"
    fi
    out="$(printf '%s\n' $out | sort -n -u | while read -r n; do
               [ -n "$n" ] && printf '    spec/%s:%s: %s\n' "$f" "$n" \
                 "$(sed -n "${n}p" "spec/$f" | cut -c1-100)"
             done)"
    if [ -n "$out" ]; then
      printf '%s  LEAK — service-language specifics outside an auth citation:%s\n' "$RED" "$RST"
      printf '%s\n' "$out"
      fail=1
    fi
  done
  if [ "$fail" -ne 0 ]; then
    printf '\n%s::error::spec/ states a service-language specific as a platform rule%s\n' "$RED" "$RST"
    printf '  Fix: move it into an "**Auth ref:**" / "**Auth reference.**" citation, or\n'
    printf '  mark the paragraph with <!-- auth-ref --> if it is an illustration in prose.\n'
    return 1
  fi
  printf '  no .NET-isms outside a labelled auth citation (%s spec files scanned)\n' "$(manifest_files | wc -l | tr -d ' ')"
  return 0
}

# --- gate 2: links resolve + the vendored-set rule ----------------------------
# (a) every relative link outside the scaffold resolves to a real path;
# (b) a manifest file may only link relatively to another file in the vendored set.
links_resolve_step() {
  local fail=0 f line tgt dir vendored vset
  vendored="$(manifest_files)"
  # Space-delimited one-liner so membership is a bash `case` glob, not a grep fork.
  # These loops run once per link, so anything forking inside them costs real time.
  vset=" $(printf '%s ' $vendored)"

  # (a) resolution — scaffold is gate 3's job (its forward references are legitimate).
  while IFS=$'\t' read -r f line tgt; do
    [ -z "${f:-}" ] && continue
    dir="${f%/*}"; [ "$dir" = "$f" ] && dir="."
    if [ ! -e "$dir/$tgt" ]; then
      printf '%s  UNRESOLVED  %s:%s -> %s%s\n' "$RED" "$f" "$line" "$tgt" "$RST"
      fail=1
    fi
  done < <(for f in $(non_scaffold_md_files); do extract_links "$f"; done)

  # (b) the vendored-set rule — the check that would have caught 0.1.1's bug.
  for f in $vendored; do
    while IFS=$'\t' read -r sf line tgt; do
      [ -z "${sf:-}" ] && continue
      # Legal iff it is a bare sibling naming another vendored file: the whole set
      # lands flat in the consumer's docs/platform/.
      case "$tgt" in
        */*)        : ;;                                  # any path segment escapes
        *) case "$vset" in *" $tgt "*) continue ;; esac ;; # a vendored sibling: fine
      esac
      printf '%s  ESCAPES VENDORED SET  spec/%s:%s -> %s%s\n' "$RED" "$f" "$line" "$tgt" "$RST"
      fail=1
    done < <(extract_links "spec/$f")
  done

  if [ "$fail" -ne 0 ]; then
    printf '\n%s::error::a link is broken, or a vendored file links outside the vendored set%s\n' "$RED" "$RST"
    printf '  A manifest file is copied verbatim into a consumer, where ../ means that\n'
    printf '  service'"'"'s docs/. Use an absolute https://github.com/xodeeq/xal-platform/...\n'
    printf '  URL instead. See sync/SYNC.md "What'"'"'s in scope to sync".\n'
    return 1
  fi
  printf '  all relative links resolve; no vendored file links outside the vendored set\n'
  return 0
}

# --- gate 3: scaffold self-consistency ----------------------------------------
# The scaffold is the seed for service #2 onward, so a broken link there is inherited
# by every future service. Its docs/platform/ links are forward references validated
# against the manifest (see GOTCHA above).
scaffold_consistency_step() {
  local fail=0 f line tgt dir base vendored
  vendored="$(manifest_files)"

  # (a) every file the manifest names actually exists in spec/.
  for f in $vendored; do
    if [ ! -f "spec/$f" ]; then
      printf '%s  MANIFEST NAMES A MISSING FILE  spec/%s%s\n' "$RED" "$f" "$RST"
      fail=1
    fi
  done

  # (b) scaffold links: real files, or forward references into docs/platform/.
  while IFS=$'\t' read -r f line tgt; do
    [ -z "${f:-}" ] && continue
    dir="$(dirname "$f")"
    [ -e "$dir/$tgt" ] && continue
    # Forward reference? Resolve it and see if it lands on docs/platform/<vendored>.
    case "$tgt" in
      */docs/platform/*|docs/platform/*|*/platform/*)
        base="$(basename "$tgt")"
        if printf '%s\n' $vendored | grep -qx -- "$base"; then continue; fi
        printf '%s  SCAFFOLD LINKS A FILE THAT IS NEVER VENDORED  %s:%s -> %s%s\n' \
          "$RED" "$f" "$line" "$tgt" "$RST"
        printf '    (%s is not in sync/manifest, so it will dangle in every seeded service)\n' "$base"
        fail=1
        continue ;;
    esac
    printf '%s  UNRESOLVED  %s:%s -> %s%s\n' "$RED" "$f" "$line" "$tgt" "$RST"
    fail=1
  done < <(for f in $(scaffold_md_files); do extract_links "$f"; done)

  if [ "$fail" -ne 0 ]; then
    printf '\n%s::error::the scaffold is not self-consistent — every new service inherits this%s\n' "$RED" "$RST"
    return 1
  fi
  printf '  manifest ⊆ spec/; scaffold links resolve (docs/platform/ ones checked against the manifest)\n'
  return 0
}

# --- gate 4: sync round-trip ---------------------------------------------------
# Prove the mechanism itself still works: vendor into a throwaway consumer, then assert
# --check reports no drift against it. Catches a broken platform-sync.sh, a manifest
# naming a missing file, and a --check that has stopped actually comparing anything.
sync_roundtrip_step() {
  local tmp rc
  [ -x "$SYNC" ] || { printf '%s  %s is missing or not executable%s\n' "$RED" "$SYNC" "$RST"; return 1; }
  tmp="$(mktemp -d)" || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  ( cd "$tmp" && "$ROOT/$SYNC" "$ROOT" ) || {
    printf '%s  sync into a throwaway consumer FAILED%s\n' "$RED" "$RST"; return 1; }

  ( cd "$tmp" && "$ROOT/$SYNC" "$ROOT" --check ); rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s  --check reports drift immediately after a clean sync (exit %s)%s\n' "$RED" "$rc" "$RST"
    return 1
  fi

  # A sync that copies nothing would pass --check vacuously; assert it produced files.
  local want got
  want="$(manifest_files | wc -l | tr -d ' ')"
  got="$(find "$tmp/docs/platform" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$want" != "$got" ]; then
    printf '%s  round-trip vendored %s file(s), manifest names %s%s\n' "$RED" "$got" "$want" "$RST"
    return 1
  fi
  printf '  sync → --check round-trip clean (%s files vendored, pinned %s)\n' "$got" "$(cat VERSION)"
  return 0
}

# --- gate 5: plugin manifests -----------------------------------------------------
# This repo is a plugin MARKETPLACE as well as a spec source: `.claude-plugin/
# marketplace.json` plus one plugin per directory under `plugins/`. A malformed manifest
# does not fail loudly — Claude Code skips what it cannot parse — so a service repo would
# simply not get the conventions skill, silently, and nothing would say why.
#
# GOTCHA: the published schema reference and the validator DISAGREE, and the validator is
# what actually loads the plugin. Two real cases found writing this: `owner` is REQUIRED on
# a marketplace manifest though the reference's example omits it, and a top-level
# `displayName` is an unrecognized field the runtime ignores. So validate with the tool,
# never against the documentation. `--strict` turns those warnings into failures, which is
# what we want in a gate — an ignored field is a silently missing feature.
#
# Skipped (with a warning) when the `claude` CLI is unavailable, matching the Docker-gate
# precedent in the auth repo: mandatory under CI=true, courteous locally.
plugin_manifests_step() {
  if ! command -v claude >/dev/null 2>&1; then
    if [ "${CI:-}" = "true" ]; then
      printf '%sThe claude CLI is required in CI to validate plugin manifests.%s\n' "$RED" "$RST"
      return 1
    fi
    printf '%s⚠ claude CLI unavailable — SKIPPING plugin manifest validation.%s\n' "$YEL" "$RST"
    printf '%s  (This gate is mandatory in CI.)%s\n' "$YEL" "$RST"
    return 0
  fi

  local rc=0 target
  # The marketplace manifest itself.
  if claude plugin validate . --strict >/dev/null 2>&1; then
    printf '  %s✔%s marketplace manifest\n' "$GREEN" "$RST"
  else
    printf '  %s✗%s marketplace manifest\n' "$RED" "$RST"
    claude plugin validate . --strict 2>&1 | sed 's/^/      /'
    rc=1
  fi
  # Every plugin in the catalogue.
  for target in plugins/*/; do
    [ -d "$target" ] || continue
    if claude plugin validate "$target" --strict >/dev/null 2>&1; then
      printf '  %s✔%s %s\n' "$GREEN" "$RST" "${target%/}"
    else
      printf '  %s✗%s %s\n' "$RED" "$RST" "${target%/}"
      claude plugin validate "$target" --strict 2>&1 | sed 's/^/      /'
      rc=1
    fi
  done
  return "$rc"
}

# --- run the gates -------------------------------------------------------------
gate "plugin manifests (claude plugin validate --strict)" plugin_manifests_step
gate "language-agnostic spec (no .NET-isms as rules)"  spec_language_agnostic_step
gate "links resolve (+ vendored-set rule)"             links_resolve_step
gate "scaffold self-consistency"                       scaffold_consistency_step
gate "sync round-trip"                                 sync_roundtrip_step

summary
