#!/bin/bash
#
# This file is part of the Simutrans project under the Artistic License.
# (see LICENSE.txt)
#
# Tie a submission id to the archive it was made from.
#
# Usage: bind-submission.sh <preserved-dir> <uuid> <output-dir>
#
# Ordering, and why it is this way
# --------------------------------
# The archive is preserved and uploaded BEFORE it is submitted, with the
# submission id left empty.  A runner that dies immediately after `submit`
# then still leaves the signed bytes behind, which is the case that cost a
# whole signing run on 2026-09-08.
#
# The id only exists afterwards, so it is bound in a second, tiny record that
# points back at the same archive by hash.  Nothing is re-encrypted and the
# archive is not uploaded twice.
#
# If a submission was made but no id came back, nothing is bound.  The archive
# is then preserved but UNRECONCILED: it cannot be resumed, and it must not be
# resubmitted on the assumption that the first attempt failed - Apple may well
# have it.  Reconciling means finding the id with `notarytool history` and
# binding it deliberately.

set -euo pipefail

DIR=${1:?usage: bind-submission.sh <preserved-dir> <uuid> <output-dir>}
UUID=${2:?usage: bind-submission.sh <preserved-dir> <uuid> <output-dir>}
OUT=${3:?usage: bind-submission.sh <preserved-dir> <uuid> <output-dir>}

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=/dev/null
. "$HERE/notary-lib.sh"

if ! is_uuid "$UUID"; then
	echo "::error::'$UUID' is not a submission UUID; refusing to bind it."
	echo "::error::An archive bound to something that is not a submission id could"
	echo "::error::never be resumed, and would hide the fact that the id was lost."
	exit 1
fi

manifest="$DIR/manifest.json"
[ -f "$manifest" ] || { echo "::error::no manifest in $DIR."; exit 1; }

zip_sha=$(json_field "$manifest" zip_sha256 || true)
printf '%s' "$zip_sha" | grep -qE '^[0-9a-f]{64}$' || {
	echo "::error::the preserved manifest has no usable zip_sha256; nothing to bind to."
	exit 1
}

mkdir -p "$OUT"
umask 077

# Carried forward field by field rather than patched in place, so the bound
# record cannot silently inherit something unexpected.
cat > "$OUT/manifest.json" <<MANIFEST
{
  "schema": "simutrans-macos-signed-artifact/1",
  "created_utc": "$(json_field "$manifest" created_utc || echo '')",
  "bound_utc": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "zip_sha256": "$zip_sha",
  "zip_bytes": "$(json_field "$manifest" zip_bytes || echo '')",
  "encrypted_sha256": "$(json_field "$manifest" encrypted_sha256 || echo '')",
  "product_sha": "$(json_field "$manifest" product_sha || echo '')",
  "workflow_sha": "$(json_field "$manifest" workflow_sha || echo '')",
  "revision_id": "$(json_field "$manifest" revision_id || echo '')",
  "arch": "$(json_field "$manifest" arch || echo '')",
  "signing_identity": "$(json_field "$manifest" signing_identity || echo '')",
  "team_id": "$(json_field "$manifest" team_id || echo '')",
  "repository": "$(json_field "$manifest" repository || echo '')",
  "run_id": "$(json_field "$manifest" run_id || echo '')",
  "run_attempt": "$(json_field "$manifest" run_attempt || echo '')",
  "not_for_distribution": "$(json_field "$manifest" not_for_distribution || echo '')",
  "submission_id": "$UUID",
  "submitted_utc": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "notarization_status": "submitted, awaiting verdict"
}
MANIFEST

echo "== submission bound to the preserved archive ==============="
cat "$OUT/manifest.json"
echo
echo "submission $UUID is now tied to the archive with sha256 $zip_sha"
