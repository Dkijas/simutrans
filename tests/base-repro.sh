#!/bin/bash
# The unpatched base must fail the checks that define the defects.  If it passes any of
# them, the tests cannot see the defect on this machine and nothing else here counts.
# Usage: base-repro.sh <dir holding the base .github>
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BASE=$(cd "${1:?base}" && pwd)
out=$( { bash "$TESTS/test-stapler.sh" "$BASE"; bash "$TESTS/test-gpg.sh" "$BASE"; bash "$TESTS/test-workflow.sh" "$BASE"; } 2>&1 )
printf '%s\n' "$out" | grep -E '^FAIL|^SUMMARY' | cut -c1-120
rc=0
for id in S1-02 S1-16 S1-17 S1-26 S1-36 S2-02 S2-34 S2-44 W-07; do
	if grep -qE "^FAIL $id " <<<"$out"; then
		echo "REPRODUCED $id"
	else
		echo "NOT REPRODUCED $id"
		rc=1
	fi
done
# With a gpg that really prints the new name, the production failure itself appears.
label=$(gpg --version | head -1)
if grep -qE "^FAIL S2-30 " <<<"$out"; then
	echo "REPRODUCED S2-30 with the real gpg: $label (the production failure, not a fixture)"
else
	echo "S2-30 passes on the base with $label: this gpg still prints the old name"
fi
echo "BASE-REPRO rc=$rc"
exit "$rc"
