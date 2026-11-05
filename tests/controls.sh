#!/bin/bash
# Negative controls.  Applies each frozen mutant to a disposable copy of the candidate;
# the named check must then FAIL.  A mutant that fails to apply or changes nothing is an
# error, because a control that was never applied proves nothing.
# Usage: controls.sh <dir holding the candidate .github> <mutants dir name> <expected total>
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CAND=$(cd "${1:?candidate}" && pwd)
SET="$TESTS/${2:?mutants dir name}"
EXPECT=${3:?expected total}
JOBS=${JOBS:-3}
M=$(mktemp -d "${TMPDIR:-/tmp}/simu-sign-mutants.XXXXXX")
trap 'rm -rf "$M"' EXIT
RESULTS="$M/results"
mkdir -p "$RESULTS"

one() {
	local id=$1 test=$2 want=$3 desc=$4 dir out
	dir="$M/$id"
	mkdir -p "$dir"
	cp -R "$CAND/.github" "$dir/.github"
	if ! (cd "$dir" && patch -s -p1 < "$SET/$id.diff"); then
		echo "BROKEN   $id the mutation did not apply: $desc"
		return
	fi
	if diff -rq "$dir/.github" "$CAND/.github" > /dev/null; then
		echo "BROKEN   $id the mutation changed nothing: $desc"
		return
	fi
	out=$(bash "$TESTS/$test" "$dir" 2>&1)
	if grep -qE "^FAIL $want " <<<"$out"; then
		echo "CAUGHT   $id $want: $desc"
	else
		echo "SURVIVED $id wanted $want to fail: $desc"
		grep -E '^FAIL|^SUMMARY' <<<"$out" | sed 's/^/         /' | cut -c1-150
	fi
	rm -rf "$dir"
}

while IFS=$'\t' read -r id test want desc; do
	while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$JOBS" ]; do
		sleep 1
	done
	one "$id" "$test" "$want" "$desc" > "$RESULTS/$id" 2>&1 &
done < "$SET/manifest.tsv"
wait
cat "$RESULTS"/M*

total=$(wc -l < "$SET/manifest.tsv" | tr -d ' ')
caught=$(cat "$RESULTS"/M* | grep -c '^CAUGHT')
survived=$(cat "$RESULTS"/M* | grep -c '^SURVIVED')
broken=$(cat "$RESULTS"/M* | grep -c '^BROKEN')
echo "MUTANTS total=$total caught=$caught survived=$survived broken=$broken"
[ "$caught" -eq "$total" ] && [ "$total" -eq "$EXPECT" ]
