#!/bin/bash
# Usage: run-all.sh <dir holding the candidate .github> <dir holding the base .github>
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CAND=${1:?candidate}
BASE=${2:?base}
echo "bash : $BASH_VERSION ($BASH)"
echo "gpg  : $(gpg --version | head -1)"
echo "os   : $(uname -srm)"
rc=0
bash "$TESTS/syntax-check.sh" "$CAND" || rc=1
bash "$TESTS/test-stapler.sh" "$CAND" || rc=1
bash "$TESTS/test-gpg.sh" "$CAND" || rc=1
bash "$TESTS/test-workflow.sh" "$CAND" "$BASE" || rc=1
bash "$TESTS/test-rehearsal.sh" "$CAND" || rc=1
echo "RESULT rc=$rc"
exit "$rc"
