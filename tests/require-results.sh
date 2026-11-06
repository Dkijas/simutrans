#!/bin/bash
# A log only counts if every expected check ran exactly once and passed.  A missing
# check is a failure: omitted tests must never read as success.
# Usage: require-results.sh <log> <file of expected check ids>
LOG=${1:?log}
IDS=${2:?ids file}
rc=0
if [ ! -s "$LOG" ]; then
	echo "RESULTS empty or missing log: $LOG"
	exit 1
fi
if [ ! -s "$IDS" ]; then
	echo "RESULTS empty or missing list of ids: $IDS"
	exit 1
fi
while read -r id; do
	[ -n "$id" ] || continue
	n=$(grep -c "^PASS $id " "$LOG")
	if [ "$n" -ne 1 ]; then
		echo "NOT RUN OR REPEATED $id: $n PASS lines"
		rc=1
	fi
done < "$IDS"
want=$(grep -c . "$IDS")
got=$(grep -c '^PASS ' "$LOG")
failed=$(grep -c '^FAIL ' "$LOG")
[ "$got" -eq "$want" ] || { echo "WRONG COUNT: wanted $want PASS lines, got $got"; rc=1; }
[ "$failed" -eq 0 ] || { grep '^FAIL ' "$LOG" | cut -c1-110; rc=1; }
echo "RESULTS $(basename "$LOG"): expected=$want pass=$got fail=$failed rc=$rc"
exit "$rc"
