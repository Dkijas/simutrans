#!/bin/bash
# Run once, on Linux, to freeze the 32 mutants of the previous mission as patches, so
# that macOS applies exactly the same changes without depending on GNU sed.
# Usage: make-mutants.sh <dir holding the candidate .github> <out dir name> <1 or 2>
# The last argument is the packet count that tree requires: 1 frozen, 2 for v2.
TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CAND=$(cd "${1:?candidate}" && pwd)
OUT="$TESTS/${2:?out dir name}"
COUNT=${3:?count}
rm -rf "$OUT"
mkdir -p "$OUT"
: > "$OUT/manifest.tsv"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

mutant() {
	local id=$1 file=$2 prog=$3 test=$4 want=$5 desc=$6
	mkdir -p "$T/$id/a/.github/$(dirname "$file")" "$T/$id/b/.github/$(dirname "$file")"
	cp "$CAND/.github/$file" "$T/$id/a/.github/$file"
	cp "$CAND/.github/$file" "$T/$id/b/.github/$file"
	sed -i -E "$prog" "$T/$id/b/.github/$file"
	if cmp -s "$T/$id/a/.github/$file" "$T/$id/b/.github/$file"; then
		echo "BROKEN $id changed nothing"
		exit 1
	fi
	(cd "$T/$id" && diff -u "a/.github/$file" "b/.github/$file") > "$OUT/$id.diff"
	printf '%s\t%s\t%s\t%s\n' "$id" "$test" "$want" "$desc" >> "$OUT/manifest.tsv"
}

L=macos/notary-lib.sh
N=macos/notarize.sh
V=macos/verify.sh
A=macos/artifact-lib.sh
R=workflows/macos-notarize-resume.yml
W=workflows/macos-sign-notarize.yml

mutant M01 $L 's/^STAPLER_MAX_ATTEMPTS=4/STAPLER_MAX_ATTEMPTS=1/' test-stapler.sh S1-02 "no retry at all"
mutant M02 $L 's/^STAPLER_MAX_ATTEMPTS=4/STAPLER_MAX_ATTEMPTS=5/' test-stapler.sh S1-05 "one attempt too many"
mutant M03 $L "s/^(\s*)grep -qE 'NSURLErrorDomain.*; then/\1true; then/" test-stapler.sh S1-09 "any exit 68 counts as network"
mutant M04 $L 's/\[ "\$rc" -eq 68 \] \&\& \\/true \&\& \\/' test-stapler.sh S1-10 "network text counts whatever the exit status"
mutant M05 $L 's/"\$action" -v "\$target"/"$action" "$target"/' test-stapler.sh S1-02 "retry without -v"
mutant M06 $L 's/^(\s*)sleep "\$delay"/\1:/' test-stapler.sh S1-03 "retries without waiting"
mutant M07 $L 's/\(\[\^0-9\]\|\$\)//' test-stapler.sh S1-11 "-10050 passes as -1005"
mutant M08 $L 's/1001\|1003/1200|1001|1003/' test-stapler.sh S1-12 "TLS failure counted as network"
mutant M09 $L 's/^(\s*)return "\$rc"/\1return 0/' test-stapler.sh S1-05 "giving up reports success"
mutant M10 $L 's/NSURLErrorDomain Code/[A-Za-z]+ Code/' test-stapler.sh S1-13 "any error domain accepted"
mutant M11 $L '/retrying in/d' test-stapler.sh S1-20 "retries not logged"
mutant M12 $N 's/if ! stapler_run validate "\$APP"; then/if ! { stapler_run validate "$APP"; true; }; then/' test-stapler.sh S1-17 "notarize.sh ignores a failed validate"
mutant M13 $N 's/if ! stapler_run staple "\$APP"; then/if ! xcrun stapler staple "$APP"; then/' test-stapler.sh S1-02 "notarize.sh staple without retry"
mutant M14 $V 's/if ! stapler_run validate "\$app"; then/if ! { stapler_run validate "$app"; true; }; then/' test-stapler.sh S1-27 "verify.sh ignores a failed validate"
mutant M15 $V 's/if ! stapler_run validate "\$app"; then/if ! xcrun stapler validate "$app"; then/' test-stapler.sh S1-26 "verify.sh validate without retry"
mutant M16 $V '/^\. "\$HERE\/notary-lib.sh"/d' test-stapler.sh S1-25 "verify.sh does not load the helper"
mutant M17 $R 's/stapler_run staple "/xcrun stapler staple "/' test-stapler.sh S1-36 "recovery staple without retry"
mutant M18 $R 's/^(\s*)stapler_run validate (.*)$/\1stapler_run validate \2 || true/' test-stapler.sh S1-37 "recovery ignores a failed validate"
mutant M19 $R 's/stapler_run staple "/xcrun stapler staple "/' test-workflow.sh W-07 "static gate sees a direct call"

mutant M20 $A 's/\(aead\|ocb\)/aead/g' test-gpg.sh S2-02 "new label refused (S2 itself)"
mutant M21 $A 's/\(aead\|ocb\)/[a-z]+/g' test-gpg.sh S2-24 "any label accepted"
mutant M22 $A 's/^(\s*)if \[ "\$rc" -ne 0 \]; then/\1if false; then/' test-gpg.sh S2-13 "gpg exit status ignored"
mutant M23 $A 's/if \[ "\$count" -ne '"$COUNT"' \] \|\| /if /' test-gpg.sh S2-21 "several data packets accepted"
mutant M24 $A 's/cb=\[0-9\]\+\\\$"/cb=[0-9]+"/' test-gpg.sh S2-14 "trailing text accepted"
mutant M25 $A '/grep -qE "\^:\(aead/s/cipher=\$_ARTIFACT_CIPHER_AES256/cipher=[0-9]+/' test-gpg.sh S2-03 "cipher not checked"
mutant M26 $A '/grep -qE "\^:\(aead/s/aead=\$_ARTIFACT_AEAD_OCB/aead=[0-9]+/' test-gpg.sh S2-05 "mode not checked"
mutant M27 $A 's/ tag=20 / tag=[0-9]+ /' test-gpg.sh S2-19 "any packet tag accepted"
if [ "$COUNT" = 1 ]; then
	mutant M28 $A '/^artifact_assert_aead\(\)/,/^}/{s/\^:/:/g}' test-gpg.sh S2-16 "no line anchors at all"
else
	# The count is what stops an unanchored line here, so it has to go as well.
	mutant M28 $A '/^artifact_assert_aead\(\)/,/^}/{s/\^:/:/g; s/^(\s*)count=.*/\1count=2/}' test-gpg.sh S2-16 "no line anchors, no count"
	mutant M33 $A "s/ \|\| ! grep -q '\^:symkey enc packet:' <<<\"\\\$packets\" \|\| \\\\$/ || \\\\/" test-strict.sh S3-05 "session key not required"
	mutant M34 $A 's/count=\$\(grep -c .\^:. <<<"\$packets" \|\| true\)/count=2/' test-strict.sh S3-01 "other packets not counted"
fi
mutant M29 $A '/decryption failed/{n;s/return 1/return 0/}' test-gpg.sh S2-36 "failed decryption reported as success"
mutant M30 $A '/^artifact_decrypt\(\)/,/^}/{/artifact_assert_aead "\$in"/d}' test-gpg.sh S2-41 "decrypt no longer checks the container"

mutant M31 $W "s/^    if: needs.resolve.outputs.publish == 'true'/    if: always() \&\& needs.resolve.outputs.publish == 'true'/" test-workflow.sh W-02 "publish runs after a failed sign"
mutant M32 $W 's/^(\s*)- name: Verify the archive that would be shipped/\1- name: Verify the archive that would be shipped\n\1  continue-on-error: true/' test-workflow.sh W-03 "verification allowed to fail"

wc -l < "$OUT/manifest.tsv"
