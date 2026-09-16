#!/usr/bin/env bash
#
# seed-service.sh — create a new xal service repo that arrives with its gate already working.
#
# WHY THIS EXISTS -------------------------------------------------------------------------
#
# Until this script, nothing put a gate into a new repo. Two mechanisms looked like they
# should: the platform `scaffold/` + `sync/`, which had the right scope but shipped no gate
# script; and the `xcos-core` plugin, which reaches every repo "code or not" but cannot ship
# an executable CI can run — CI runs plain scripts, and bootstrapping a plugin would itself
# be a new gate input in every workflow in every repo. The mechanism with the right scope had
# the wrong reach and vice versa, and adoption was left to whoever remembered.
#
# That matters more than it sounds. The whole estate's gate discipline rests on a script
# whose exit code decides pass. A repo created without one does not fail loudly — it emits
# green from a gate that is not there, which is indistinguishable from a passing build.
# See adr/0006-repo-seeding.md.
#
# WHAT IT DOES ----------------------------------------------------------------------------
#
#   1. copies scaffold/common/ (everything language-agnostic)
#   2. overlays scaffold/lang/<lang>/ (the gate script, CI, Dockerfile, fixtures)
#   3. copies this repo's .xal/check-gate-inputs.sh (gate 0's checker)
#   4. renames *.template and the SERVICE path placeholder; substitutes <SERVICE>
#   5. vendors the platform spec via sync/platform-sync.sh and pins the VERSION
#   6. writes .xal/seed.config recording the language, its deciding ADR, and the pin
#   7. git init + one commit, so the tree is pushable
#   8. prints the human-only actions that remain — and stops
#
# IT TAKES NO INPUTS OF ITS OWN beyond this platform checkout: bash, tar, sed, find, git.
# Same discipline as platform-sync.sh, and for the same reason — a seeding step that can need
# a toolchain is a seeding step that can be missing one.
#
# Usage:
#   scaffold/seed-service.sh --name <service> --lang <language> --dest <dir> [--adr <path>]
#
#   --name   the service name; becomes the repo name, the Go module's last segment, the
#            binary, and every <SERVICE> in the seeded files
#   --lang   the language overlay to apply, from scaffold/lang/. NO DEFAULT — see below
#   --dest   where to create the repo. Must not already exist
#   --adr    the path, inside the new repo, of the ADR that decided --lang. Recorded in
#            .xal/seed.config. Defaults to docs/adr/0001-stack-selection.md
#
# THERE IS NO DEFAULT LANGUAGE, DELIBERATELY. A default language is a stack decision taken by
# a script. Stack selection is a human-gated, per-service decision recorded as that service's
# first ADR, chosen on that service's workload — so this script refuses to guess and exits 2.
#
# Exit: 0 seeded · 1 a step failed · 2 called wrongly (bad or missing arguments)

set -uo pipefail

PLATFORM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLD="$PLATFORM/scaffold"

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; YEL=""; RST=""; fi

die()  { printf '%s%s%s\n' "$RED" "$1" "$RST" >&2; exit "${2:-1}"; }
step() { printf '\n%s━━ %s%s\n' "$BOLD" "$1" "$RST"; }
note() { printf '   %s\n' "$1"; }

languages() { find "$SCAFFOLD/lang" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort; }

usage() {
  cat >&2 <<EOF
usage: scaffold/seed-service.sh --name <service> --lang <language> --dest <dir> [--adr <path>]

  --lang has no default. Stack selection is a per-service, human-gated decision recorded as
  that service's first ADR; a script must not make it.

  languages available in scaffold/lang/:
$(languages | sed 's/^/    /')
EOF
}

NAME=""; LANG_ID=""; DEST=""; ADR="docs/adr/0001-stack-selection.md"
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --lang) LANG_ID="${2:-}"; shift 2 ;;
    --dest) DEST="${2:-}"; shift 2 ;;
    --adr)  ADR="${2:-}";  shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%sunknown argument: %s%s\n' "$RED" "$1" "$RST" >&2; usage; exit 2 ;;
  esac
done

# --- argument validation; every failure here is exit 2, "called wrongly" ---------------
[ -n "$NAME" ] || { printf '%s--name is required%s\n' "$RED" "$RST" >&2; usage; exit 2; }
[ -n "$DEST" ] || { printf '%s--dest is required%s\n' "$RED" "$RST" >&2; usage; exit 2; }

if [ -z "$LANG_ID" ]; then
  printf '%s--lang is required and has NO DEFAULT.%s\n' "$RED" "$RST" >&2
  printf 'A default language would be a stack decision taken by a script. Stack selection is\n' >&2
  printf 'the per-service, human-gated decision recorded as that service ADR-0001 — pass the\n' >&2
  printf 'language that ADR chose.\n\n' >&2
  usage
  exit 2
fi

if [ ! -d "$SCAFFOLD/lang/$LANG_ID" ]; then
  printf '%sno language overlay at scaffold/lang/%s%s\n' "$RED" "$LANG_ID" "$RST" >&2
  printf 'available:\n' >&2
  languages | sed 's/^/  /' >&2
  printf '\nAdding a language is a PR that adds scaffold/lang/<name>/ with the full artifact\n' >&2
  printf 'set; scripts/check-seed-set.sh refuses a partial one.\n' >&2
  exit 2
fi

[ -e "$DEST" ] && die "destination already exists: $DEST (refusing to seed over it)" 2
[ -d "$SCAFFOLD/common" ] || die "scaffold/common/ is missing — this is not a platform checkout" 2
[ -f "$PLATFORM/.xal/check-gate-inputs.sh" ] || die ".xal/check-gate-inputs.sh is missing from this platform checkout" 2
[ -x "$PLATFORM/sync/platform-sync.sh" ] || die "sync/platform-sync.sh is missing or not executable" 2

printf '\n%sSeeding %s (%s) into %s%s\n' "$BOLD" "$NAME" "$LANG_ID" "$DEST" "$RST"

mkdir -p "$DEST" || die "could not create $DEST"
DEST="$(cd "$DEST" && pwd)"

# --- 1 + 2: the common tree, then the language overlay -----------------------------------
# tar rather than cp -r because it copies dotfiles predictably on both GNU and BSD, which
# matters: .claude/, .github/ and .xal/ are most of what a seeded repo is.
step "copying scaffold/common/, then scaffold/lang/$LANG_ID/"
( cd "$SCAFFOLD/common" && tar -cf - . ) | ( cd "$DEST" && tar -xf - ) || die "copying common/ failed"
( cd "$SCAFFOLD/lang/$LANG_ID" && tar -cf - . ) | ( cd "$DEST" && tar -xf - ) || die "copying lang/$LANG_ID/ failed"
note "$(find "$DEST" -type f | wc -l | tr -d ' ') files"

# --- 3: gate 0's checker -----------------------------------------------------------------
# Seeded from THIS repo's vendored copy rather than from a second copy kept in the scaffold.
# The canonical copy lives in xcos-core; keeping one copy per repo and no extra copy here
# means this step adds no new replica pair to keep identical. The residual — cross-repo drift
# between those copies — is real, named in ADR-0006, and detected only agent-side today.
step "seeding .xal/check-gate-inputs.sh (gate 0's checker)"
mkdir -p "$DEST/.xal"
cp "$PLATFORM/.xal/check-gate-inputs.sh" "$DEST/.xal/check-gate-inputs.sh" || die "copying the gate-input checker failed"
chmod +x "$DEST/.xal/check-gate-inputs.sh"
note "from $PLATFORM/.xal/ (canonical: xcos-core)"

# --- 4: placeholders ----------------------------------------------------------------------
step "filling placeholders"

# Path placeholder first: a literal `SERVICE` path component becomes the service name, so
# cmd/SERVICE/ becomes cmd/<name>/. Deepest paths first, or renaming a parent invalidates the
# child paths still queued behind it.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  mv "$p" "$(dirname "$p")/$NAME" || die "renaming $p failed"
done <<< "$(find "$DEST" -depth -name 'SERVICE' | sed '/^$/d')"

# *.template -> the real filename. `.gitignore.template` -> `.gitignore` falls out of the
# same rule, which is why it is named that way in the scaffold rather than `gitignore.template`.
while IFS= read -r t; do
  [ -n "$t" ] || continue
  mv "$t" "${t%.template}" || die "renaming $t failed"
done <<< "$(find "$DEST" -type f -name '*.template' | sed '/^$/d')"

# <SERVICE> -> the service name, in every text file.
#
# GOTCHA: `sed -i` differs between GNU and BSD (BSD requires an argument to -i, GNU must not
# have one). Writing to a temp file and moving it back works identically on both, and this
# script runs on a developer's macOS as often as on a runner.
subst=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -q '<SERVICE>' "$f" 2>/dev/null || continue
  sed "s|<SERVICE>|$NAME|g" "$f" > "$f.seedtmp" && mv "$f.seedtmp" "$f" || die "substituting in $f failed"
  subst=$((subst + 1))
done <<< "$(find "$DEST" -type f ! -path '*/.git/*')"
note "<SERVICE> -> $NAME in $subst file(s)"

chmod +x "$DEST/scripts/"*.sh 2>/dev/null
chmod +x "$DEST/gates/"*.sh 2>/dev/null

# --- 5: vendor the platform spec -----------------------------------------------------------
step "vendoring the platform spec into docs/platform/"
( cd "$DEST" && "$PLATFORM/sync/platform-sync.sh" "$PLATFORM" ) || die "platform-sync.sh failed"
note "pinned $(cat "$PLATFORM/VERSION")"

# --- 6: the seed record ---------------------------------------------------------------------
step "writing .xal/seed.config"
cat > "$DEST/.xal/seed.config" <<EOF
# .xal/seed.config — how this repo was created. Written once, by
# xal-platform/scaffold/seed-service.sh; see that repo's adr/0006-repo-seeding.md.
#
# SEED_LANG is not a preference and not a default. It is the language this service's first
# ADR chose, on this service's workload, through the human-gated tool-selection layer.
# SEED_ADR is where that decision is recorded, so "why is this repo $LANG_ID?" resolves to a
# decision record in this repo rather than to whoever remembers.
#
# This file records the seed. It does not track drift: the gate script is a starting point
# this service now OWNS, unlike docs/platform/, which is a vendored contract the drift gate
# keeps current. Improvements to the scaffold do not flow back here.
SEED_SERVICE=$NAME
SEED_LANG=$LANG_ID
SEED_ADR=$ADR
SEED_PLATFORM_VERSION=$(cat "$PLATFORM/VERSION")
SEED_DATE=$(date -u +%Y-%m-%d)
EOF
note "language $LANG_ID, decided in $ADR"

# --- 7: git ---------------------------------------------------------------------------------
step "git init + first commit"
(
  cd "$DEST" || exit 1
  git init -q -b main || exit 1
  git add -A || exit 1
  git -c commit.gpgsign=false commit -q -m "chore: seed $NAME from xal-platform scaffold ($LANG_ID)

Seeded by xal-platform/scaffold/seed-service.sh per platform ADR-0006.
Language $LANG_ID, chosen in $ADR. Platform spec pinned at $(cat "$PLATFORM/VERSION").

The repo arrives with its gate: scripts/check.sh in the platform's gate order,
.xal/gate-inputs declaring every input, ci.yml supplying them, and committed
fixtures in gates/ proving the chain can fail and can pass." || exit 1
) || die "git init/commit failed"
note "$(cd "$DEST" && git rev-parse --short HEAD) on main"

# --- 8: stop, and say what only a person can do ----------------------------------------------
cat <<EOF

${GREEN}${BOLD}Seeded.${RST} ${DEST}

${BOLD}Agent-owned from here${RST} — reversible, so nothing waits on anyone:
  gh repo create xodeeq/$NAME --private --source "$DEST" --remote origin --push
  then open the first PR and let CI run.

${YEL}${BOLD}Human-only, and CI is not fully live until both are done${RST}:
  1. Install the Claude GitHub App on xodeeq/$NAME.
     Granting a third party access to a repo. Not scriptable — it is a GitHub UI grant.
  2. Set CLAUDE_CODE_OAUTH_TOKEN as a repository secret.
     A credential. \`gh secret set\` exists; minting the token does not.

  .github/workflows/claude.yml and claude-code-review.yml are committed already, so the
  install has something to activate. Until it happens they are inert — which is the point:
  an inert workflow waiting on one grant, not a missing file waiting on someone remembering.

  Deploying additionally needs provisioning and a cleared billing block; deploy.yml is
  dispatch-only until then, and says so at the top.
EOF
