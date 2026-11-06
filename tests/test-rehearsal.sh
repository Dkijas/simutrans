#!/bin/bash
# Checks added for the macOS rehearsal.  Everything is synthetic.
# Usage: test-rehearsal.sh <dir holding .github>
# EXPECT_BASH_MAJOR=3 makes it prove, by behaviour, that this really is Bash 3.2.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REAL_GPG=$(command -v gpg)
export REAL_GPG
export GNUPGHOME="$WORK/gnupghome"
mkdir -p "$GNUPGHOME"
chmod 700 "$GNUPGHOME"
export MACOS_ARTIFACT_KEY=lab-only-key
FX="$TESTS/fixtures"
SHIM="$TESTS/gpg-shim"

lib_env() {
	env PATH="$SHIM:$TESTS/mocks:$PATH" MOCK_DIR="$MOCK_DIR" RUNNER_TEMP="$C/tmp" "$@"
}

# ---- which shell is really running the scripts --------------------------------
new_case
in_scripts=$(mock_env bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')
echo "INFO shell inside the scripts: bash $in_scripts ($(mock_env bash -c 'echo "$BASH"'))"
if [ -n "${EXPECT_BASH_MAJOR:-}" ]; then
	check B3-01 "the scripts run under the expected Bash major version" '[ "${in_scripts%%.*}" = "$EXPECT_BASH_MAJOR" ]'
	# A version string can be faked by nothing here, but behaviour is the better
	# proof: an empty array under set -u is fatal before Bash 4.4.
	mock_env bash -c 'set -u; a=(); echo "${a[@]}"' > "$C/out" 2>&1
	RC=$?
	if [ "$EXPECT_BASH_MAJOR" = 3 ]; then
		check B3-02 "behaves like Bash 3.2: empty array under set -u is fatal" '[ $RC -ne 0 ]'
		check B3-03 "the shebang shell is /bin/bash" '[ "$(mock_env bash -c "echo \$BASH")" = "/bin/bash" ]'
	fi
fi

check G0-01 "no MACOS_ variable reaches this job from outside" '[ -z "$(env | grep "^MACOS_" | grep -v "^MACOS_ARTIFACT_KEY=lab-only-key$" || true)" ]'
new_case
check G0-02 "xcrun inside the tests is the simulator" '[ "$(mock_env bash -c "command -v xcrun")" = "$TESTS/mocks/xcrun" ]'
check G0-03 "codesign inside the tests is the simulator" '[ "$(mock_env bash -c "command -v codesign")" = "$TESTS/mocks/codesign" ]'

# ---- intervals ----------------------------------------------------------------
new_case
script staple "68|$MSG_1005"
(cd "$C/repo" && mock_env SIMU_STAPLER_DELAY_1=7 SIMU_STAPLER_DELAY_2=11 bash -c '. .github/macos/notary-lib.sh; stapler_run staple X') > "$C/out" 2>&1
check I-01 "configured intervals are honoured" '[ "$(sleeps)" = "7 11" ] && [ "$(calls staple)" -eq 4 ]'

new_case
script staple "68|$MSG_1005"
(cd "$C/repo" && mock_env bash -c '. .github/macos/notary-lib.sh; stapler_run staple X') > "$C/out" 2>&1
check I-02 "default intervals are 30 and 120 seconds" '[ "$(sleeps)" = "30 120" ]'

new_case
script staple "68|$MSG_1005"
started=$(date +%s)
(cd "$C/repo" && mock_env MOCK_REAL_SLEEP=1 SIMU_STAPLER_DELAY_1=1 SIMU_STAPLER_DELAY_2=2 bash -c '. .github/macos/notary-lib.sh; stapler_run staple X') > "$C/out" 2>&1
RC=$?
elapsed=$(( $(date +%s) - started ))
check I-03 "the wait really happens, in real time" '[ "$elapsed" -ge 3 ] && [ $RC -eq 68 ]'

new_case
script staple "68|$MSG_1005" "0|worked"
(cd "$C/repo" && mock_env bash -c '. .github/macos/notary-lib.sh; stapler_run staple X') > "$C/out" 2>&1
check I-04 "the second attempt uses -v" 'sed -n 2p "$MOCK_DIR/calls.log" | grep -q "^xcrun stapler staple -v X$" && sed -n 1p "$MOCK_DIR/calls.log" | grep -q "^xcrun stapler staple X$"'

# ---- ambiguous messages -------------------------------------------------------
ambiguous() {
	new_case
	script staple "$2|$3"
	(cd "$C/repo" && mock_env bash -c '. .github/macos/notary-lib.sh; stapler_run staple X') > "$C/out" 2>&1
	RC=$?
	check "$1" "ambiguous, not retried: $4" '[ $RC -ne 0 ] && [ "$(calls staple)" -eq 1 ]'
}
ambiguous A-01 68 'network connection lost, maybe' "words without the error domain"
ambiguous A-02 68 'Code=-1005 "The network connection was lost."' "code without the domain"
ambiguous A-03 68 'NSURLErrorDomain' "domain without a code"
ambiguous A-04 68 'NSURLErrorDomain Code=-1' "code cut short"
ambiguous A-05 1 'error is Error Domain=NSURLErrorDomain Code=-1005' "right text, exit 1"
ambiguous A-06 68 'error is Error Domain=NSURLErrorDomain Code=1005' "positive number"

# ---- N1: a failed validate is never ignored -----------------------------------
new_case
script validate "65|$MSG_NOTICKET"
run_notarize
check N1-01 "PRIORITY: permanent validate failure makes notarize.sh fail" '[ $RC -ne 0 ] && ! has "notarized and stapled"'
new_case
script validate "68|$MSG_1005"
run_notarize
check N1-02 "PRIORITY: exhausted validate makes notarize.sh fail" '[ $RC -ne 0 ] && [ "$(calls validate)" -eq 4 ] && ! has "notarized and stapled"'

# ---- N2: an unencrypted file with a misleading name ---------------------------
printf 'plain text pretending to be a container\n' > "$WORK/plain"
n2() {
	"$REAL_GPG" --batch --yes --quiet --no-tty --store --compress-algo none \
		--set-filename "$2" --output "$WORK/n2-$1.gpg" "$WORK/plain"
	new_case
	rm -f "$WORK/back"
	(cd "$C/repo" && lib_env bash -c ". .github/macos/artifact-lib.sh; artifact_decrypt '$WORK/n2-$1.gpg' '$WORK/back'") > "$C/out" 2>&1
	RC=$?
	check "N2-$1" "PRIORITY: unencrypted file refused: $3" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'
}
n2 01 ':aead encrypted packet: cipher=9 aead=2 cb=16' "name imitating the old line"
n2 02 ':ocb encrypted packet: cipher=9 aead=2 cb=16' "name imitating the new line"
n2 03 '# off=79 ctb=d4 tag=20 hlen=2 plen=99 new-ctb' "name imitating the tag line"
n2 04 "x
# off=79 ctb=d4 tag=20 hlen=2 plen=99 new-ctb
:ocb encrypted packet: cipher=9 aead=2 cb=16" "name with line breaks imitating both lines"

# ---- other rejections ---------------------------------------------------------
assert_fixture() {
	new_case
	(cd "$C/repo" && lib_env GPG_FIXTURE="$FX/$2" bash -c '. .github/macos/artifact-lib.sh; artifact_assert_aead dummy') > "$C/out" 2>&1
	RC=$?
	check "$1" "rejected: $3" '[ $RC -ne 0 ]'
}
assert_fixture G-01 nomdc.txt "a packet with no authentication at all"
assert_fixture G-02 ocb-spoof-mixed.txt "a real data packet plus a fake line"

# ---- substitution and tampering, with the real scripts and real gpg ------------
PROV=(GITHUB_REPOSITORY=lab/lab GITHUB_RUN_ATTEMPT=1 SIMU_PRODUCT_SHA=abc123 SIMU_WORKFLOW_SHA=def456
	SIMU_REVISION_ID=r1 SIMU_ARCH=arm64 SIMU_NOT_FOR_DISTRIBUTION=false
	MACOS_SIGNING_IDENTITY=lab MACOS_TEAM_ID=LAB EXPECT_PRODUCT_SHA=abc123 EXPECT_RUN_ID=77 EXPECT_ARCH=arm64)
new_case
(cd "$C/repo" && lib_env "${PROV[@]}" GITHUB_RUN_ID=77 bash .github/macos/preserve-artifact.sh "$C/n.zip" "$C/good") > "$C/out" 2>&1
RC=$?
check G-10 "a good container is produced" '[ $RC -eq 0 ] && [ -s "$C/good/bundle.gpg" ]'
good="$C/good"
(cd "$C/repo" && lib_env "${PROV[@]}" GITHUB_RUN_ID=77 bash .github/macos/restore-artifact.sh "$good" "$C/ok.zip") > "$C/out" 2>&1
RC=$?
check G-11 "the good container restores" '[ $RC -eq 0 ] && cmp -s "$C/n.zip" "$C/ok.zip"'

(cd "$C/repo" && lib_env "${PROV[@]}" GITHUB_RUN_ID=78 bash .github/macos/preserve-artifact.sh "$C/n.zip" "$C/other") > "$C/out2" 2>&1
(cd "$C/repo" && lib_env "${PROV[@]}" GITHUB_RUN_ID=78 bash .github/macos/restore-artifact.sh "$C/other" "$C/sub.zip") > "$C/out" 2>&1
RC=$?
check G-12 "substitution: a valid container from another run is refused" '[ $RC -ne 0 ] && [ ! -e "$C/sub.zip" ]'

(cd "$C/repo" && lib_env "${PROV[@]}" GITHUB_RUN_ID=77 MACOS_ARTIFACT_KEY=another-key bash .github/macos/preserve-artifact.sh "$C/n.zip" "$C/rogue") > "$C/out2" 2>&1
(cd "$C/repo" && lib_env "${PROV[@]}" GITHUB_RUN_ID=77 bash .github/macos/restore-artifact.sh "$C/rogue" "$C/rogue.zip") > "$C/out" 2>&1
RC=$?
check G-13 "substitution: a container made with another key is refused" '[ $RC -ne 0 ] && [ ! -e "$C/rogue.zip" ]'

mkdir -p "$C/tampered"
cp -R "$good/." "$C/tampered/"
size=$(wc -c < "$C/tampered/bundle.gpg" | tr -d ' ')
printf '\125' | dd of="$C/tampered/bundle.gpg" bs=1 seek=$((size - 5)) conv=notrunc 2>/dev/null
cmp -s "$good/bundle.gpg" "$C/tampered/bundle.gpg" && printf '\252' | dd of="$C/tampered/bundle.gpg" bs=1 seek=$((size - 5)) conv=notrunc 2>/dev/null
(cd "$C/repo" && lib_env "${PROV[@]}" GITHUB_RUN_ID=77 bash .github/macos/restore-artifact.sh "$C/tampered" "$C/t.zip") > "$C/out" 2>&1
RC=$?
check G-14 "a container altered after creation is refused" '[ $RC -ne 0 ] && [ ! -e "$C/t.zip" ]'

mkdir -p "$C/cut"
cp -R "$good/." "$C/cut/"
head -c $((size - 20)) "$good/bundle.gpg" > "$C/cut/bundle.gpg"
(cd "$C/repo" && lib_env "${PROV[@]}" GITHUB_RUN_ID=77 bash .github/macos/restore-artifact.sh "$C/cut" "$C/c.zip") > "$C/out" 2>&1
RC=$?
check G-15 "a truncated container is refused" '[ $RC -ne 0 ] && [ ! -e "$C/c.zip" ]'

# ---- attacker data glued to a genuine container, whole decryption path ----------
. "$TESTS/glued.sh"
make_glued "$WORK/g" || { echo "FATAL could not build the test messages"; exit 3; }
glued() {
	new_case
	rm -f "$WORK/back"
	(cd "$C/repo" && lib_env bash -c ". .github/macos/artifact-lib.sh; artifact_decrypt '$WORK/g/$2.gpg' '$WORK/back'") > "$C/out" 2>&1
	RC=$?
	check "$1" "PRIORITY: refused end to end, no output: $3" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ] && has "::error::"'
}
new_case
rm -f "$WORK/back"
(cd "$C/repo" && lib_env bash -c ". .github/macos/artifact-lib.sh; artifact_decrypt '$WORK/g/ok.gpg' '$WORK/back'") > "$C/out" 2>&1
RC=$?
check E-00 "the intact container decrypts" '[ $RC -eq 0 ] && cmp -s "$WORK/g/genuine" "$WORK/back"'
glued E-01 lit-aead "literal packet before a genuine container"
glued E-02 aead-lit "literal packet after a genuine container"
glued E-03 zipi-aead "compressed literal, open length, before a genuine container"
glued E-04 zipd-aead "compressed literal, definite length, before a genuine container"
glued E-05 aead-zipd "compressed literal, definite length, after a genuine container"
glued E-06 lit-bare "literal packet before a data packet with no session key"
glued E-07 aead-aead "two genuine containers"
glued E-08 lit "literal packet alone"
glued E-09 zipd "compressed literal alone"
glued E-10 bare "data packet with no session key"
glued E-11 nest-lit-aead "literal and genuine container inside one compressed packet"
glued E-12 nest-aead-lit "genuine container and literal inside one compressed packet"

# What gpg alone does with each, for the record: this decides how much the validator
# has to carry.  Informational, not a check.
for f in ok lit-aead aead-lit zipi-aead zipd-aead aead-zipd lit-bare aead-aead lit zipi zipd bare nest-lit-aead nest-aead-lit nest-aead; do
	rm -f "$WORK/raw"
	printf '%s' "$MACOS_ARTIFACT_KEY" | "$REAL_GPG" --batch --yes --quiet --no-tty --pinentry-mode loopback \
		--passphrase-fd 0 --decrypt --output "$WORK/raw" "$WORK/g/$f.gpg" > /dev/null 2>&1
	rc=$?
	echo "INFO raw gpg --decrypt $f: exit $rc, output [$( [ -e "$WORK/raw" ] && tr '\n' ' ' < "$WORK/raw")]"
done

# ---- what the real gpg on this machine prints ----------------------------------
new_case
real=$("$REAL_GPG" --list-packets --list-only "$good/bundle.gpg" 2>/dev/null)
RC=$?
echo "INFO gpg: $("$REAL_GPG" --version | head -1)"
printf '%s\n' "$real" | sed 's/^/INFO packet: /'
label=$(printf '%s\n' "$real" | sed -n -E 's/^:(aead|ocb) encrypted packet:.*/\1/p')
echo "INFO label: $label"
check R-01 "real gpg: --list-packets --list-only exits 0 on a valid container" '[ $RC -eq 0 ]'
check R-02 "real gpg: the data packet is tag 20" 'grep -qE "^# off=[0-9]+ ctb=[0-9a-f]+ tag=20 " <<<"$real"'
check R-03 "real gpg: cipher 9, aead 2" 'grep -qE "^:(aead|ocb) encrypted packet: cipher=9 aead=2 cb=16$" <<<"$real"'
if [ -n "${EXPECT_GPG_LABEL:-}" ]; then
	check R-04 "real gpg prints the expected label" '[ "$label" = "$EXPECT_GPG_LABEL" ]'
fi

finish
