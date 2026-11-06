#!/bin/bash
# Static checks over the workflow files and the shell itself.
# Usage: test-workflow.sh <dir holding .github> [<dir holding the base .github>]
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
BASE=${2:-}
if [ -n "$BASE" ]; then
	# Absolute, because W-11 compares after a cd.  A base that cannot be entered
	# must fail W-10 to W-12, never skip them.
	BASE=$(cd "$BASE" 2>/dev/null && pwd) || BASE=$2
fi

G="$TREE/.github"
SIGN="$G/workflows/macos-sign-notarize.yml"
RESUME="$G/workflows/macos-notarize-resume.yml"
new_case

# Prints the block of one job, from its key to the next two-space key.
job_block() {
	awk -v j="  $2:" '$0==j{f=1;print;next} f&&/^  [a-zA-Z_-]+:$/{exit} f{print}' "$1"
}
PUBLISH=$(job_block "$SIGN" publish)

check W-01 "publish job exists and needs sign" 'grep -qE "needs: \[resolve, sign\]" <<<"$PUBLISH"'
check W-02 "publish job cannot run after a failed sign" \
	'grep -qE "^    if: needs.resolve.outputs.publish == .true.$" <<<"$PUBLISH" && ! grep -qE "^    if:.*(always|failure|cancelled)\(" <<<"$PUBLISH"'
check W-03 "no continue-on-error while signing" '! grep -q "continue-on-error" "$SIGN"'
# The recovery workflow has one on purpose: the binding artifact may be absent.
coe=$(grep -B2 "continue-on-error" "$RESUME" | grep -c "name: Fetch the submission binding")
check W-03b "recovery: continue-on-error only on the optional binding download" \
	'[ "$(grep -c "continue-on-error" "$RESUME")" -eq 1 ] && [ "$coe" -eq 1 ]'

step_line() { grep -nF -- "- name: $2" "$1" | head -1 | cut -d: -f1; }
n_notarize=$(step_line "$SIGN" "Notarize and staple")
n_archive=$(step_line "$SIGN" "Build the distribution archive")
n_verify=$(step_line "$SIGN" "Verify the archive that would be shipped")
n_upload=$(step_line "$SIGN" "Upload the signed archive")
check W-04 "order: notarize, archive, verify, upload" \
	'[ "$n_notarize" -lt "$n_archive" ] && [ "$n_archive" -lt "$n_verify" ] && [ "$n_verify" -lt "$n_upload" ]'
check W-05 "archive and verify do not run after a failure" \
	'! sed -n "${n_archive},$((n_verify + 3))p" "$SIGN" | grep -qE "if:.*always\("'
check W-06 "upload only on success" 'sed -n "${n_upload},$((n_upload + 3))p" "$SIGN" | grep -qE "if: success\(\) &&"'

direct=$(grep -rn --include='*' -E '^[^#]*xcrun stapler' "$G" | grep -v '/macos/notary-lib.sh:' || true)
check W-07 "every stapler call goes through stapler_run" '[ -z "$direct" ]'

# Bash 3.2 is what macOS runs for #!/bin/bash.  None could be run here, so this
# only rules out the constructs that do not exist there, plus empty-array use
# under set -u, which fails on anything older than 4.4.
functions_of() { awk '/^(stapler_failure_class|stapler_run|artifact_assert_aead)\(\)/{f=1} f{print} f&&/^}/{f=0}' "$G/macos/notary-lib.sh" "$G/macos/artifact-lib.sh"; }
FUNCS=$(functions_of)
check W-08 "new functions exist" '[ "$(grep -cE "^(stapler_failure_class|stapler_run|artifact_assert_aead)\(\)" <<<"$FUNCS")" -eq 3 ]'
check W-09 "no construct missing from bash 3.2" \
	'! grep -qE "declare -[Ang]|local -n|mapfile|readarray|coproc|\|&|&>>|\\$\{[a-zA-Z_]+(,,|\^\^)|\[\[ -v|\[@\]" <<<"$FUNCS"'

if [ -n "$BASE" ]; then
	unchanged=""
	for f in macos/sign.sh macos/keychain.sh macos/inspect-bundle.sh macos/check-payload.sh \
			macos/preserve-artifact.sh macos/restore-artifact.sh macos/bind-submission.sh \
			macos/verify-binding.sh macos/notary-status.sh macos/README.md \
			workflows/macos-sign-notarize.yml workflows/macos-notary-status.yml \
			workflows/nightly-android.yml workflows/update-nightly-release.yml; do
		cmp -s "$G/$f" "$BASE/.github/$f" || unchanged="$unchanged $f"
	done
	check W-10 "signing, identity, entitlements and publishing files are byte-identical to base" '[ -z "$unchanged" ]'

	compared=$(cd "$G" && find . -type f | wc -l | tr -d ' ')
	echo "INFO W-11 compared $compared files against $BASE/.github"
	changed=$(cd "$G" && find . -type f | while read -r f; do cmp -s "$f" "$BASE/.github/$f" || echo "$f"; done | LC_ALL=C sort | tr '\n' ' ')
	echo "INFO W-11 differs: $changed"
	check W-11 "only the five expected files differ from base" \
		'[ "$changed" = "./macos/artifact-lib.sh ./macos/notarize.sh ./macos/notary-lib.sh ./macos/verify.sh ./workflows/macos-notarize-resume.yml " ]'

	refs() { grep -rhoE '(secrets|vars)\.[A-Z0-9_]+' "$1" | sort | uniq -c; }
	check W-12 "no secret or variable reference added or removed" '[ "$(refs "$G")" = "$(refs "$BASE/.github")" ]'
fi

finish
