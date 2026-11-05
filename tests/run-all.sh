#!/bin/bash
# Usage: run-all.sh <dir holding the candidate .github> <dir holding the base .github>
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CAND=${1:?candidate}
BASE=${2:?base}
echo "bash : $BASH_VERSION ($BASH)"
echo "gpg  : $(gpg --version | head -1)"
echo "os   : $(uname -srm)"
rc=0
# One file at a time: bash -n a b only reads a.
checked=0
for f in "$CAND"/.github/macos/*.sh; do
	bash -n "$f" || rc=1
	checked=$((checked + 1))
done
echo "syntax checked: $checked files"
bash "$TESTS/test-stapler.sh" "$CAND" || rc=1
bash "$TESTS/test-gpg.sh" "$CAND" || rc=1
bash "$TESTS/test-workflow.sh" "$CAND" "$BASE" || rc=1
bash "$TESTS/test-rehearsal.sh" "$CAND" || rc=1
echo "RESULT rc=$rc"
exit "$rc"
