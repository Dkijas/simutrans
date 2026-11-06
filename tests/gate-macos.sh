#!/bin/bash
# Final gate of a macOS job.  Reads the logs the job wrote.  Everything the mission
# requires is here, as a number: nothing is inferred from a green step.
# Usage: gate-macos.sh <out dir>
O=${1:?out dir}
T=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
rc=0
gate() {
	if [ "$2" = ok ]; then
		echo "GATE ok   $1"
	else
		echo "GATE FAIL $1"
		rc=1
	fi
}
yes_if() { if "$@" > /dev/null 2>&1; then echo ok; else echo bad; fi; }
one_line() { grep -qE "$2" "$1"; }

gate "real Bash 3.2 in the scripts: $(grep -h 'INFO shell' "$O/v2-run-all.txt" | head -1 | cut -c7-)" \
	"$(yes_if one_line "$O/v2-run-all.txt" '^INFO shell inside the scripts: bash 3\.2 \(/bin/bash\)$')"
for f in v2-run-all frozen-run-all; do
	gate "$f: every one of 144 checks ran and passed" "$(yes_if bash "$T/require-results.sh" "$O/$f.txt" "$T/ids/run-all-macos.txt")"
	gate "$f: 13 scripts through bash -n" "$(yes_if one_line "$O/$f.txt" '^syntax checked: 13 files$')"
done
gate "v2 strict: 11 of 11, S3-00 to S3-10" "$(yes_if bash "$T/require-results.sh" "$O/v2-strict.txt" "$T/ids/strict.txt")"
gate "manipulated messages are what they claim" "$(yes_if bash "$T/require-results.sh" "$O/v2-structure.txt" "$T/ids/structure.txt")"
gate "the harness can fail" "$(yes_if bash "$T/require-results.sh" "$O/harness.txt" "$T/ids/harness.txt")"
gate "original 32 mutants caught" "$(yes_if one_line "$O/frozen-controls.txt" '^MUTANTS total=32 caught=32 survived=0 broken=0$')"
gate "v2 34 mutants caught" "$(yes_if one_line "$O/v2-controls.txt" '^MUTANTS total=34 caught=34 survived=0 broken=0$')"
gate "base reproduces the defects" "$(yes_if one_line "$O/base-repro.txt" '^BASE-REPRO rc=0$')"

e2e=$(grep -cE '^PASS E-(0[1-9]|1[0-2]) ' "$O/v2-run-all.txt")
if [ "$e2e" -eq 12 ]; then gate "12 of 12 malicious messages refused end to end, v2" ok; else gate "end to end: $e2e of 12" bad; fi
iso=$(grep -cE '^PASS S3-(0[1-9]|10) ' "$O/v2-strict.txt")
if [ "$iso" -eq 10 ]; then gate "10 of 10 manipulated messages refused by the isolated validator, v2" ok; else gate "isolated validator: $iso of 10" bad; fi

# The frozen candidate must still show the gap, or this no longer tells them apart.
gapmissing=0
for id in S3-01 S3-02 S3-04 S3-05 S3-08 S3-09 S3-10; do
	grep -q "^FAIL $id " "$O/frozen-strict.txt" || gapmissing=1
done
if [ "$gapmissing" -eq 0 ]; then gate "the frozen validator still shows the 7 known gaps: the check discriminates" ok; else gate "frozen gap not reproduced" bad; fi

echo "versions: $(grep -hE '^gpg  *:' "$O/env.txt" | cut -c1-70)"
echo "label: $(grep -h 'INFO label' "$O/v2-run-all.txt" | head -1)"
echo "GATE-MACOS rc=$rc"
exit "$rc"
