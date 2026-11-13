#!/usr/bin/bash
# bash roles/syncthing/tests/check-verbose-log.sh (from the collection root)
# Runs the molecule scenario at -vvvv (where module arguments, headers included, are printed) and fails if the hub's API key appears in the role's
# own runs (check, converge, idempotence). prepare and verify use it on purpose.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
log=$(mktemp)
trap 'rm -f "$log"' EXIT
ANSIBLE_VERBOSITY=4 molecule test -s default >"$log" 2>&1; rc=$?
fail=0
if [ "$rc" -ne 0 ]; then echo "FAIL  molecule itself failed (rc $rc)"; fail=1; else echo "ok    molecule passed"; fi
n=$(sed 's/\x1b\[[0-9;]*m//g' "$log" | sed -n '/check: Executing/,/verify: Executing/p' | grep -c -- hub-test-key)
if [ "$n" -gt 0 ]; then echo "FAIL  the hub's API key appears $n time(s) in the role's -v output"; fail=1; else echo "ok    the hub's API key is not in the role's -v output"; fi
exit "$fail"
