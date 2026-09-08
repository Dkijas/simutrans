#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Recover a preserved signed archive and prove it is the one that was meant.
#
# Usage: restore-artifact.sh <preserved-dir> <output.zip>
#
# Environment:
#   MACOS_ARTIFACT_KEY        passphrase the archive was encrypted with
#   EXPECT_PRODUCT_SHA        commit the product must have been built from
#   EXPECT_SUBMISSION_ID      submission the archive must be bound to
#   EXPECT_SIGNING_IDENTITY   identity it must have been signed with (optional)
#
# Everything here is checked against values the caller already knows from
# somewhere else.  An artifact that says nice things about itself proves
# nothing: the manifest travels with the ciphertext and could have been
# rewritten, so it is the agreement between the manifest, the decrypted bytes
# and what the caller independently expects that makes the restore trustworthy.
#
# Apple accepting a submission does not make a recovered file the right file.
# Those are two separate questions and both have to be answered.

set -euo pipefail

DIR=${1:?usage: restore-artifact.sh <preserved-dir> <output.zip>}
OUTZIP=${2:?usage: restore-artifact.sh <preserved-dir> <output.zip>}

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$HERE/notary-lib.sh"

manifest="$DIR/manifest.json"
enc="$DIR/signed-bundle.zip.enc"

fail() {
	echo "::error::$1"
	exit 1
}

[ -f "$manifest" ] || fail "no manifest in $DIR; refusing to use this artifact."
[ -f "$enc" ]      || fail "no encrypted archive in $DIR; refusing to continue."
[ -n "${MACOS_ARTIFACT_KEY:-}" ] || fail "MACOS_ARTIFACT_KEY is not set; the archive cannot be opened."

echo "== restoring the preserved archive ========================="
echo "from     : $DIR"

schema=$(json_field "$manifest" schema || true)
[ "$schema" = "simutrans-macos-signed-artifact/1" ] || \
	fail "unrecognised manifest schema '${schema:-<none>}'; refusing to guess its meaning."

zip_sha=$(json_field "$manifest" zip_sha256 || true)
enc_sha_recorded=$(json_field "$manifest" encrypted_sha256 || true)
product_sha=$(json_field "$manifest" product_sha || true)
submission_id=$(json_field "$manifest" submission_id || true)
identity=$(json_field "$manifest" signing_identity || true)
arch=$(json_field "$manifest" arch || true)
revision_id=$(json_field "$manifest" revision_id || true)

printf '  %-18s %s\n' "product" "${product_sha:-<none>}"
printf '  %-18s %s\n' "revision" "${revision_id:-<none>}"
printf '  %-18s %s\n' "arch" "${arch:-<none>}"
printf '  %-18s %s\n' "identity" "${identity:-<none>}"
printf '  %-18s %s\n' "submission" "${submission_id:-<none>}"
echo

# Every field the rest of this depends on has to be present and well formed.
printf '%s' "$zip_sha" | grep -qE '^[0-9a-f]{64}$' || fail "the manifest has no usable zip_sha256."

# ---------------------------------------------------------------------------
# 1. The ciphertext is the one the manifest describes.
# ---------------------------------------------------------------------------
enc_sha_actual=$(shasum -a 256 "$enc" | awk '{ print $1 }')
if [ -n "$enc_sha_recorded" ] && [ "$enc_sha_actual" != "$enc_sha_recorded" ]; then
	fail "the stored archive does not match its manifest (encrypted sha256 differs). It may be truncated or replaced."
fi

# ---------------------------------------------------------------------------
# 2. It decrypts, and to exactly the bytes that were preserved.
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$OUTZIP")"
umask 077
if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
		-in "$enc" -out "$OUTZIP" -pass env:MACOS_ARTIFACT_KEY 2>/dev/null; then
	rm -f "$OUTZIP"
	fail "the archive could not be decrypted. Either MACOS_ARTIFACT_KEY is not the key it was encrypted with, or the file is corrupt."
fi

actual_sha=$(shasum -a 256 "$OUTZIP" | awk '{ print $1 }')
if [ "$actual_sha" != "$zip_sha" ]; then
	rm -f "$OUTZIP"
	fail "restored bytes do not match the manifest: got $actual_sha, expected $zip_sha."
fi
echo "decrypted and verified: sha256 $actual_sha"

# ---------------------------------------------------------------------------
# 3. It is the artifact the caller was expecting, not merely a valid one.
# ---------------------------------------------------------------------------
if [ -n "${EXPECT_PRODUCT_SHA:-}" ] && [ "$product_sha" != "$EXPECT_PRODUCT_SHA" ]; then
	rm -f "$OUTZIP"
	fail "this archive was built from $product_sha, but $EXPECT_PRODUCT_SHA was expected."
fi

if [ -n "${EXPECT_SUBMISSION_ID:-}" ]; then
	if ! is_uuid "$submission_id"; then
		rm -f "$OUTZIP"
		fail "the manifest records no valid submission id, so this archive cannot be tied to a notarization result."
	fi
	if [ "$submission_id" != "$EXPECT_SUBMISSION_ID" ]; then
		rm -f "$OUTZIP"
		fail "this archive is bound to submission $submission_id, not to $EXPECT_SUBMISSION_ID. Stapling a ticket from a different submission would produce a package nobody can account for."
	fi
fi

if [ -n "${EXPECT_SIGNING_IDENTITY:-}" ] && [ "$identity" != "$EXPECT_SIGNING_IDENTITY" ]; then
	rm -f "$OUTZIP"
	fail "this archive was signed as '$identity', not as '$EXPECT_SIGNING_IDENTITY'."
fi

echo "provenance accepted"
echo "restored to $OUTZIP"
