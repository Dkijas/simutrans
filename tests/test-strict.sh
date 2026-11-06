#!/bin/bash
# Does artifact_assert_aead ITSELF refuse a message with anything but one session key
# and one data packet, with no help from gpg at decryption?  The frozen candidate is
# expected to fail this; candidate-v2 must pass.
# Usage: test-strict.sh <dir holding .github>
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$TESTS/glued.sh"
REAL_GPG=$(command -v gpg)
export REAL_GPG

new_case
make_glued "$WORK/g" || { echo "FATAL could not build the test messages"; exit 3; }

strict() {
	new_case
	(cd "$C/repo" && env PATH="$TESTS/gpg-shim:$TESTS/mocks:$PATH" MOCK_DIR="$MOCK_DIR" RUNNER_TEMP="$C/tmp" \
		bash -c ". .github/macos/artifact-lib.sh; artifact_assert_aead '$WORK/g/$2.gpg'") > "$C/out" 2>&1
	RC=$?
	check "$1" "validator alone refuses: $3" '[ $RC -ne 0 ] && has "::error::"'
}
new_case
(cd "$C/repo" && env PATH="$TESTS/gpg-shim:$TESTS/mocks:$PATH" MOCK_DIR="$MOCK_DIR" RUNNER_TEMP="$C/tmp" \
	bash -c ". .github/macos/artifact-lib.sh; artifact_assert_aead '$WORK/g/ok.gpg'") > "$C/out" 2>&1
RC=$?
check S3-00 "validator accepts the intact container" '[ $RC -eq 0 ]'
strict S3-01 lit-aead "literal packet before a genuine container"
strict S3-02 aead-lit "literal packet after a genuine container"
strict S3-03 zipd-aead "compressed literal, definite length, before a genuine container"
strict S3-04 aead-zipd "compressed literal, definite length, after a genuine container"
strict S3-05 lit-bare "literal packet before a data packet with no session key"
strict S3-06 aead-aead "two genuine containers"
strict S3-07 zipi-aead "compressed literal, open length, before a genuine container"
strict S3-08 nest-lit-aead "literal and genuine container inside one compressed packet"
strict S3-09 nest-aead-lit "genuine container and literal inside one compressed packet"
strict S3-10 nest-aead "genuine container alone inside a compressed packet"

finish
