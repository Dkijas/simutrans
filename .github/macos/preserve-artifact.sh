#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Preserve the exact archive that is about to be sent to the notary service,
# so that a verdict arriving after the runner is gone can still be used.
#
# Usage: preserve-artifact.sh <submission.zip> <output-dir>
#
# Environment:
#   MACOS_ARTIFACT_KEY   passphrase used to encrypt the archive (required)
#   plus the descriptive values listed in the manifest section below
#
# Why this exists
# ---------------
# On 2026-09-08 a bundle was signed, submitted, and the run ended before Apple
# returned a verdict.  The signed bundle only ever existed on that runner, so
# even if the submission is accepted later there is nothing left to staple:
# the work has to be redone from the build.
#
# Why it is encrypted
# -------------------
# The obvious place to put it is a workflow artifact, and a workflow artifact
# in a PUBLIC repository is not private: GitHub's documentation requires "read
# access to the repository" to download one, and on a public repository every
# signed-in user has that.  A signed rehearsal build should not be handed out
# that way, so what is stored is ciphertext.
#
# Encryption is not a substitute for deciding who may read it, how long it
# stays, or how its integrity is checked.  Those are settled separately:
# access is whoever holds MACOS_ARTIFACT_KEY (an environment secret behind the
# same reviewer gate as the signing identity), retention is set by the
# workflow's retention-days, and integrity is the sha256 of the plaintext
# recorded in the manifest and re-checked after every restore.

set -euo pipefail

ZIP=${1:?usage: preserve-artifact.sh <submission.zip> <output-dir>}
OUT=${2:?usage: preserve-artifact.sh <submission.zip> <output-dir>}

if [ ! -f "$ZIP" ]; then
	echo "::error::archive to preserve not found: $ZIP"
	exit 1
fi
if [ -z "${MACOS_ARTIFACT_KEY:-}" ]; then
	echo "::error::MACOS_ARTIFACT_KEY is not set."
	echo "::error::The signed archive would then only exist on this runner, and a"
	echo "::error::verdict arriving later could not be used.  See .github/macos/README.md."
	exit 1
fi

mkdir -p "$OUT"
umask 077

zip_sha=$(shasum -a 256 "$ZIP" | awk '{ print $1 }')
zip_size=$(wc -c < "$ZIP" | tr -d ' ')

echo "== preserving the submitted archive ========================"
echo "source   : $ZIP"
echo "size     : $zip_size bytes"
echo "sha256   : $zip_sha"

# -pbkdf2 with a high iteration count, because the passphrase is the only
# thing between the ciphertext and anyone who can read a public repository.
enc="$OUT/signed-bundle.zip.enc"
openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
	-in "$ZIP" -out "$enc" -pass env:MACOS_ARTIFACT_KEY

enc_sha=$(shasum -a 256 "$enc" | awk '{ print $1 }')
echo "encrypted: $(wc -c < "$enc" | tr -d ' ') bytes, sha256 $enc_sha"

# ---------------------------------------------------------------------------
# Prove the round trip here, while the plaintext is still available to compare
# against.  Storing something that cannot be decrypted is worse than storing
# nothing, because it is only discovered when it is needed.
# ---------------------------------------------------------------------------
check="$OUT/.roundtrip.zip"
if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
		-in "$enc" -out "$check" -pass env:MACOS_ARTIFACT_KEY; then
	rm -f "$check"
	echo "::error::the archive could not be decrypted immediately after encrypting it."
	exit 1
fi
back_sha=$(shasum -a 256 "$check" | awk '{ print $1 }')
rm -f "$check"
if [ "$back_sha" != "$zip_sha" ]; then
	echo "::error::round trip produced different bytes ($back_sha != $zip_sha)."
	exit 1
fi
echo "round trip verified: decrypts back to the same bytes"

# ---------------------------------------------------------------------------
# The manifest.  Descriptive only: it names what was preserved and where it
# came from.  No key, no password, no keychain, no credential of any kind
# goes in here or into the artifact.
#
# submission_id is deliberately empty at this point.  This runs BEFORE the
# archive is sent, so that a runner dying immediately after submit still
# leaves the artifact behind; the id is bound to it afterwards by
# bind-submission.sh.
# ---------------------------------------------------------------------------
cat > "$OUT/manifest.json" <<MANIFEST
{
  "schema": "simutrans-macos-signed-artifact/1",
  "created_utc": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "zip_sha256": "$zip_sha",
  "zip_bytes": "$zip_size",
  "encrypted_sha256": "$enc_sha",
  "product_sha": "${SIMU_PRODUCT_SHA:-}",
  "workflow_sha": "${SIMU_WORKFLOW_SHA:-}",
  "revision_id": "${SIMU_REVISION_ID:-}",
  "arch": "${SIMU_ARCH:-}",
  "signing_identity": "${MACOS_SIGNING_IDENTITY:-}",
  "team_id": "${MACOS_TEAM_ID:-}",
  "repository": "${GITHUB_REPOSITORY:-}",
  "run_id": "${GITHUB_RUN_ID:-}",
  "run_attempt": "${GITHUB_RUN_ATTEMPT:-}",
  "not_for_distribution": "${SIMU_NOT_FOR_DISTRIBUTION:-}",
  "submission_id": "",
  "submitted_utc": "",
  "notarization_status": "not submitted"
}
MANIFEST

echo
echo "manifest:"
cat "$OUT/manifest.json"

# A credential in here would be published as ciphertext-adjacent plaintext.
if grep -qiE 'BEGIN [A-Z ]*PRIVATE KEY|password|p12|\.p8|keychain' "$OUT/manifest.json"; then
	echo "::error::the manifest appears to contain credential material; refusing."
	rm -rf "$OUT"
	exit 1
fi

echo
echo "preserved in $OUT"
