#!/bin/bash
# S2: artifact_assert_aead and everything that relies on it.
# Encryption and decryption always use the real gpg on this machine.  What gpg
# >= 2.5.23 prints is replayed from the production log or relabelled by
# gpg-shim/gpg; no such gpg ran here.
# Usage: test-gpg.sh <dir holding .github>
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

# assert_fixture <id> <accept|reject> <fixture> <description> [gpg exit status]
assert_fixture() {
	new_case
	(cd "$C/repo" && lib_env GPG_FIXTURE="$FX/$3" GPG_FIXTURE_RC="${5:-0}" \
		bash -c '. .github/macos/artifact-lib.sh; artifact_assert_aead dummy') > "$C/out" 2>&1
	RC=$?
	if [ "$2" = accept ]; then
		check "$1" "accepted: $4" '[ $RC -eq 0 ]'
	else
		check "$1" "rejected: $4" '[ $RC -ne 0 ]'
	fi
}

assert_fixture S2-01 accept aead-2.4.9.txt "old label, correct parameters (real gpg 2.4.9 output)"
assert_fixture S2-02 accept ocb-production.txt "new label, correct parameters (verbatim from run 40985712752)"
assert_fixture S2-03 reject ocb-cipher7.txt "new label, AES-128"
assert_fixture S2-04 reject aead-cipher7.txt "old label, AES-128"
assert_fixture S2-05 reject ocb-mode1.txt "new label, EAX instead of OCB"
assert_fixture S2-06 reject aead-mode1.txt "old label, EAX instead of OCB"
assert_fixture S2-07 reject ocb-noparams.txt "new label with parameters missing"
assert_fixture S2-08 reject ocb-partparams.txt "new label with cb missing"
assert_fixture S2-09 reject truncated.txt "output ends before any data packet"
assert_fixture S2-10 reject empty.txt "no output at all"
assert_fixture S2-11 reject ocb-tooshort.txt "gpg's own [too short] line"
assert_fixture S2-12 reject classic.txt "classic MDC packet"
assert_fixture S2-13 reject ocb-production.txt "valid text but gpg exited 2" 2
assert_fixture S2-14 reject ocb-suffix.txt "trailing text after the parameters"
assert_fixture S2-15 reject ocb-indented.txt "the line indented, as inside another packet"
assert_fixture S2-16 reject ocb-prefix.txt "the line with text before it"
assert_fixture S2-17 reject ocb-in-name.txt "the line inside a literal packet's file name"
assert_fixture S2-18 reject aead-in-name.txt "old label inside a literal packet's file name"
assert_fixture S2-19 reject ocb-wrongtag.txt "right text on a tag 18 packet"
assert_fixture S2-20 reject ocb-notag.txt "right text with no packet header before it"
assert_fixture S2-21 reject ocb-and-classic.txt "AEAD packet followed by a classic one"
assert_fixture S2-22 reject classic-and-ocb.txt "classic packet followed by an AEAD one"
assert_fixture S2-23 reject ocb-twice.txt "two AEAD packets"
assert_fixture S2-27 reject aead-and-classic.txt "old label followed by a classic packet"
assert_fixture S2-28 reject classic-and-aead.txt "classic packet followed by the old label"
assert_fixture S2-29 reject aead-twice.txt "two packets with the old label"
assert_fixture S2-24 reject other-label.txt "unknown label, same parameters and tag"
assert_fixture S2-25 reject ocb-cipher90.txt "cipher=90 must not pass as cipher=9"
assert_fixture S2-26 reject ocb-mode20.txt "aead=20 must not pass as aead=2"

# ---- the real gpg ------------------------------------------------------------
run_lib() {
	(cd "$C/repo" && lib_env ${GPG_RELABEL_ENV:+GPG_RELABEL=1} bash -c ". .github/macos/artifact-lib.sh; $1") > "$C/out" 2>&1
	RC=$?
}

new_case; run_lib artifact_selftest
check S2-30 "real gpg, old label: self-test passes" '[ $RC -eq 0 ] && has "retention self-test passed"'

GPG_RELABEL_ENV=1
new_case; run_lib artifact_selftest
check S2-31 "real crypto, new label: self-test passes (the production failure)" '[ $RC -eq 0 ] && has "retention self-test passed"'
GPG_RELABEL_ENV=

# Real containers, built once and then damaged.
new_case
printf 'payload that must stay secret\n' > "$WORK/plain"
(cd "$C/repo" && lib_env bash -c ". .github/macos/artifact-lib.sh; artifact_encrypt '$WORK/plain' '$WORK/ok.gpg'") > "$C/out" 2>&1
RC=$?
check S2-32 "real gpg: artifact_encrypt works" '[ $RC -eq 0 ] && [ -s "$WORK/ok.gpg" ]'

decrypt() {
	new_case
	rm -f "$WORK/back"
	(cd "$C/repo" && lib_env ${GPG_RELABEL_ENV:+GPG_RELABEL=1} MACOS_ARTIFACT_KEY="${2:-lab-only-key}" \
		bash -c ". .github/macos/artifact-lib.sh; artifact_decrypt '$1' '$WORK/back'") > "$C/out" 2>&1
	RC=$?
}

decrypt "$WORK/ok.gpg"
check S2-33 "intact container decrypts to the same bytes" '[ $RC -eq 0 ] && cmp -s "$WORK/plain" "$WORK/back"'

GPG_RELABEL_ENV=1
decrypt "$WORK/ok.gpg"
check S2-34 "same container read with the new label" '[ $RC -eq 0 ] && cmp -s "$WORK/plain" "$WORK/back"'
GPG_RELABEL_ENV=

decrypt "$WORK/ok.gpg" wrong-key
check S2-35 "wrong key: failure, no plaintext" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'

size=$(wc -c < "$WORK/ok.gpg" | tr -d ' ')
cp "$WORK/ok.gpg" "$WORK/flip.gpg"
printf '\125' | dd of="$WORK/flip.gpg" bs=1 seek=$((size - 3)) conv=notrunc 2>/dev/null
cmp -s "$WORK/ok.gpg" "$WORK/flip.gpg" && printf '\252' | dd of="$WORK/flip.gpg" bs=1 seek=$((size - 3)) conv=notrunc 2>/dev/null
decrypt "$WORK/flip.gpg"
check S2-36 "altered ciphertext: failure, no plaintext" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'

GPG_RELABEL_ENV=1
decrypt "$WORK/flip.gpg"
check S2-37 "altered ciphertext with the new label: failure, no plaintext" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'
GPG_RELABEL_ENV=

head -c $((size - 10)) "$WORK/ok.gpg" > "$WORK/cut.gpg"
decrypt "$WORK/cut.gpg"
check S2-38 "truncated body: failure, no plaintext" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'

head -c 40 "$WORK/ok.gpg" > "$WORK/head.gpg"
decrypt "$WORK/head.gpg"
check S2-39 "cut inside the first packet: failure, no plaintext" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'

printf 'not an OpenPGP message\n' > "$WORK/garbage.gpg"
decrypt "$WORK/garbage.gpg"
check S2-40 "not OpenPGP at all: failure" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'

printf '%s' "$MACOS_ARTIFACT_KEY" | "$REAL_GPG" --batch --yes --quiet --no-tty --pinentry-mode loopback \
	--passphrase-fd 0 --symmetric --cipher-algo AES256 --compress-algo none --output "$WORK/classic.gpg" "$WORK/plain"
decrypt "$WORK/classic.gpg"
check S2-41 "real classic MDC message: refused" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'

cat "$WORK/classic.gpg" "$WORK/ok.gpg" > "$WORK/mixed1.gpg"
decrypt "$WORK/mixed1.gpg"
check S2-42 "real classic + AEAD message: refused" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'

cat "$WORK/ok.gpg" "$WORK/classic.gpg" > "$WORK/mixed2.gpg"
decrypt "$WORK/mixed2.gpg"
check S2-43 "real AEAD + classic message: refused" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'

"$REAL_GPG" --batch --yes --quiet --no-tty --store --compress-algo none \
	--set-filename ':aead encrypted packet: cipher=9 aead=2 cb=16' --output "$WORK/fakename.gpg" "$WORK/plain"
decrypt "$WORK/fakename.gpg"
check S2-44 "real plaintext message whose file name imitates the line: refused" '[ $RC -ne 0 ] && [ ! -e "$WORK/back" ]'

# ---- the scripts that consume it ----------------------------------------------
PROVENANCE=(GITHUB_REPOSITORY=lab/lab GITHUB_RUN_ID=77 GITHUB_RUN_ATTEMPT=1 SIMU_PRODUCT_SHA=abc123
	SIMU_WORKFLOW_SHA=def456 SIMU_REVISION_ID=r1 SIMU_ARCH=arm64 SIMU_NOT_FOR_DISTRIBUTION=false
	MACOS_SIGNING_IDENTITY=lab MACOS_TEAM_ID=LAB EXPECT_PRODUCT_SHA=abc123 EXPECT_RUN_ID=77 EXPECT_ARCH=arm64)

round_trip() {
	new_case
	(
		cd "$C/repo" || exit 9
		lib_env ${GPG_RELABEL_ENV:+GPG_RELABEL=1} "${PROVENANCE[@]}" \
			bash .github/macos/preserve-artifact.sh "$C/n.zip" "$C/preserved" || exit 1
		lib_env ${GPG_RELABEL_ENV:+GPG_RELABEL=1} "${PROVENANCE[@]}" \
			bash .github/macos/bind-submission.sh "$C/preserved" 11111111-2222-3333-4444-555555555555 "$C/binding" || exit 2
		lib_env ${GPG_RELABEL_ENV:+GPG_RELABEL=1} "${PROVENANCE[@]}" \
			bash .github/macos/restore-artifact.sh "$C/preserved" "$C/restored.zip" || exit 3
	) > "$C/out" 2>&1
	RC=$?
}

round_trip
check S2-50 "preserve, bind and restore, old label" '[ $RC -eq 0 ] && cmp -s "$C/n.zip" "$C/restored.zip"'

GPG_RELABEL_ENV=1
round_trip
check S2-51 "preserve, bind and restore, new label" '[ $RC -eq 0 ] && cmp -s "$C/n.zip" "$C/restored.zip"'
GPG_RELABEL_ENV=

finish
