#!/bin/bash
# Can the harness itself say no?  Run from the top of the branch.
# Usage: test-harness.sh   (uses candidate-v2, candidate and base, by relative path)
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 9
. tests/lib.sh candidate-v2
new_case
T="$WORK/harness"
mkdir -p "$T/noPython" "$T/noGpg"
printf '#!/bin/bash\nexit 1\n' > "$T/noPython/python3"
printf '#!/bin/bash\nexit 127\n' > "$T/noGpg/gpg"
chmod +x "$T/noPython/python3" "$T/noGpg/gpg"
IDW="$WORK/ids-w"
printf 'W-11\n' > "$IDW"
wf() { bash tests/test-workflow.sh "$@" 2>&1; }

# ---- W-11 runs and can fail ----------------------------------------------------
out=$(wf candidate-v2 base)
check H-01 "W-11 passes with relative paths, the case that failed before" 'grep -q "^PASS W-11 " <<<"$out"'
check H-01b "W-11 really compared the files" 'grep -qE "^INFO W-11 compared [1-9][0-9]* files" <<<"$out"'

cp -R candidate-v2 "$T/sixth"
echo '# changed' >> "$T/sixth/.github/macos/sign.sh"
out=$(wf "$T/sixth" base)
check H-02 "W-11 fails when a sixth file differs" 'grep -q "^FAIL W-11 " <<<"$out"'
check H-02b "W-10 fails when a signing file differs" 'grep -q "^FAIL W-10 " <<<"$out"'

out=$(wf base base)
check H-03 "W-11 fails when nothing differs" 'grep -q "^FAIL W-11 " <<<"$out"'

out=$(wf candidate-v2 "$T/does-not-exist")
check H-04 "a missing base fails W-10 and W-11, it does not skip them" \
	'grep -q "^FAIL W-10 " <<<"$out" && grep -q "^FAIL W-11 " <<<"$out" && ! grep -q "^PASS W-11 " <<<"$out"'

# ---- omitted is not passed -----------------------------------------------------
wf candidate-v2 > "$T/nobase.log"
bash tests/require-results.sh "$T/nobase.log" "$IDW" > "$T/gate.out" 2>&1
RC=$?
check H-05 "the gate fails when W-11 did not run" '[ $RC -ne 0 ] && grep -q "NOT RUN OR REPEATED W-11" "$T/gate.out"'

printf 'PASS A one\nFAIL B two\n' > "$T/f.log"
printf 'A\nB\n' > "$T/f.ids"
bash tests/require-results.sh "$T/f.log" "$T/f.ids" > /dev/null 2>&1
RC=$?
check H-06 "the gate fails on a FAIL line" '[ $RC -ne 0 ]'

printf 'PASS A one\nPASS B two\n' > "$T/g.log"
bash tests/require-results.sh "$T/g.log" "$T/f.ids" > /dev/null 2>&1
RC=$?
check H-07 "the gate passes a complete log" '[ $RC -eq 0 ]'

printf 'PASS A one\nPASS B two\nPASS C three\n' > "$T/h.log"
bash tests/require-results.sh "$T/h.log" "$T/f.ids" > /dev/null 2>&1
RC=$?
check H-07b "the gate fails on an unexpected extra check" '[ $RC -ne 0 ]'

: > "$T/empty.log"
bash tests/require-results.sh "$T/empty.log" "$T/f.ids" > /dev/null 2>&1
RC=$?
check H-07c "the gate fails on an empty log" '[ $RC -ne 0 ]'

# ---- no empty passes from a missing tool ---------------------------------------
out=$(PATH="$T/noPython:$PATH" bash tests/test-strict.sh candidate-v2 2>&1)
RC=$?
check H-08 "without python3 the strict test stops and passes nothing" \
	'[ $RC -ne 0 ] && grep -q "^FATAL " <<<"$out" && ! grep -q "^PASS S3-" <<<"$out"'

out=$(PATH="$T/noGpg:$PATH" bash tests/test-strict.sh candidate-v2 2>&1)
RC=$?
check H-09 "without gpg the strict test does not pass" '[ $RC -ne 0 ]'

# ---- syntax --------------------------------------------------------------------
bash tests/syntax-check.sh candidate-v2 > "$T/s.out" 2>&1
RC=$?
check H-10 "syntax: the 13 scripts pass" '[ $RC -eq 0 ] && grep -q "syntax checked: 13 files" "$T/s.out"'

cp -R candidate-v2 "$T/broken"
printf 'if then fi (\n' >> "$T/broken/.github/macos/verify.sh"
bash tests/syntax-check.sh "$T/broken" > /dev/null 2>&1
RC=$?
check H-11 "syntax: an error in the LAST file is caught" '[ $RC -ne 0 ]'

cp -R candidate-v2 "$T/short"
rm "$T/short/.github/macos/verify.sh"
bash tests/syntax-check.sh "$T/short" > /dev/null 2>&1
RC=$?
check H-12 "syntax: a missing script is caught" '[ $RC -ne 0 ]'

# ---- the isolated validator: does it decide before any decryption? -------------
. tests/glued.sh
make_glued "$T/g" || { echo "FATAL could not build the test messages"; exit 3; }
REAL_GPG=$(command -v gpg)
export REAL_GPG
decrypt_calls() {
	local tree=$1 file=$2
	: > "$T/gpg.log"
	(cd "$tree" && env PATH="$TESTS/gpg-shim:$PATH" GPG_LOG="$T/gpg.log" RUNNER_TEMP="$T" MACOS_ARTIFACT_KEY=lab-only-key \
		bash -c ". .github/macos/artifact-lib.sh; artifact_decrypt '$T/g/$file.gpg' '$T/back'") > "$T/d.out" 2>&1
	RC=$?
	DEC=$(grep -c -- '--decrypt' "$T/gpg.log")
	LST=$(grep -c -- '--list-packets' "$T/gpg.log")
}

decrypt_calls candidate-v2 lit-aead
check H-13 "v2 refuses a glued message without ever calling gpg --decrypt" '[ $RC -ne 0 ] && [ "$LST" -ge 1 ] && [ "$DEC" -eq 0 ]'

decrypt_calls candidate-v2 nest-lit-aead
check H-14 "v2 refuses a nested message without ever calling gpg --decrypt" '[ $RC -ne 0 ] && [ "$LST" -ge 1 ] && [ "$DEC" -eq 0 ]'

decrypt_calls candidate lit-aead
check H-15 "the frozen candidate does reach gpg --decrypt, so this check can tell them apart" '[ $RC -ne 0 ] && [ "$DEC" -ge 1 ]'

decrypt_calls candidate-v2 ok
check H-16 "v2 does call gpg --decrypt for the intact container" '[ $RC -eq 0 ] && [ "$DEC" -eq 1 ]'

finish
