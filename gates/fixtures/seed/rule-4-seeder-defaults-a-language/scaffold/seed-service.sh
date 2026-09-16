#!/usr/bin/env bash
#
# FIXTURE seeder stub — NOT the real seeder.
#
# It implements only the contract rule 4 of scripts/check-seed-set.sh asserts: refuse a
# missing --lang and an unknown one, with exit 2, creating nothing. The real seeder is
# exercised by the real run of the rule against scaffold/, not here — a fixture tests the
# RULE, and a copy of the real seeder in five fixture trees would be five replicas nothing
# holds identical.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANG_ID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --lang) LANG_ID="${2:-}"; shift 2 ;;
    --name|--dest|--adr) shift 2 ;;
    *) shift ;;
  esac
done

# THE DEFECT THIS FIXTURE CARRIES: no --lang silently becomes the first language found,
# so a stack decision is taken by a script and the repo it produces looks entirely correct.
if [ -z "$LANG_ID" ]; then
  LANG_ID="$(find "$ROOT/lang" -mindepth 1 -maxdepth 1 -type d | sed 's|.*/||' | sort | head -1)"
fi
[ -d "$ROOT/lang/$LANG_ID" ] || exit 2
exit 0
