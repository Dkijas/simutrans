#!/bin/bash
# S1: stapler retries.  Runs the real notarize.sh and verify.sh against mocks.
# Usage: test-stapler.sh <dir holding .github>
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# ---- notarize.sh, staple ----------------------------------------------------
new_case; run_notarize
check S1-01 "first attempt works: one call each, no wait" \
	'[ $RC -eq 0 ] && [ "$(calls staple)" -eq 1 ] && [ "$(calls validate)" -eq 1 ] && [ -z "$(sleeps)" ]'

new_case; script staple "68|$MSG_1005" "0|worked"; run_notarize
check S1-02 "-1005 then success: immediate retry with -v" \
	'[ $RC -eq 0 ] && [ "$(calls staple)" -eq 2 ] && [ -z "$(sleeps)" ] && grep -q "^xcrun stapler staple -v " "$MOCK_DIR/calls.log"'
check S1-02b "first attempt has no -v" \
	'grep -q "^xcrun stapler staple $C/app.app" "$MOCK_DIR/calls.log"'

new_case; script staple "68|$MSG_1001" "68|$MSG_1001" "0|worked"; run_notarize
check S1-03 "transient 68 twice then success: third try after one wait" \
	'[ $RC -eq 0 ] && [ "$(calls staple)" -eq 3 ] && [ "$(sleeps)" = "30" ]'

new_case; script staple "68|$MSG_1005" "68|$MSG_1005" "68|$MSG_1005" "0|worked"; run_notarize
check S1-04 "success on the last allowed attempt" \
	'[ $RC -eq 0 ] && [ "$(calls staple)" -eq 4 ] && [ "$(sleeps)" = "30 120" ]'

new_case; script staple "68|$MSG_1001"; run_notarize
check S1-05 "persistent timeout: exactly 4 attempts, then fail" \
	'[ $RC -eq 1 ] && [ "$(calls staple)" -eq 4 ] && [ "$(sleeps)" = "30 120" ] && ! has "notarized and stapled"'
check S1-05b "never reaches validate after staple failed" '[ "$(calls validate)" -eq 0 ]'

new_case; script staple "65|$MSG_BADSIG"; run_notarize
check S1-06 "invalid signature: one attempt, fail" \
	'[ $RC -eq 1 ] && [ "$(calls staple)" -eq 1 ] && [ -z "$(sleeps)" ] && ! has "notarized and stapled"'

new_case; script staple "66|$MSG_CORRUPT"; run_notarize
check S1-07 "corrupt artifact: one attempt, fail" \
	'[ $RC -eq 1 ] && [ "$(calls staple)" -eq 1 ] && ! has "notarized and stapled"'

new_case; script staple "65|$MSG_NORECORD"; run_notarize
check S1-08 "ticket not found: one attempt, fail" '[ $RC -eq 1 ] && [ "$(calls staple)" -eq 1 ]'

new_case; script staple "68|Processing: APP\nThe staple and validate action failed! Error 68."; run_notarize
check S1-09 "68 with no network evidence is not retried" '[ $RC -eq 1 ] && [ "$(calls staple)" -eq 1 ]'

new_case; script staple "65|$MSG_1005"; run_notarize
check S1-10 "network text with a different exit status is not retried" '[ $RC -eq 1 ] && [ "$(calls staple)" -eq 1 ]'

new_case; script staple '68|error is Error Domain=NSURLErrorDomain Code=-10050 "lookalike"'; run_notarize
check S1-11 "lookalike code -10050 is not retried" '[ $RC -eq 1 ] && [ "$(calls staple)" -eq 1 ]'

new_case; script staple '68|error is Error Domain=NSURLErrorDomain Code=-1200 "TLS failed"'; run_notarize
check S1-12 "TLS failure -1200 is not retried" '[ $RC -eq 1 ] && [ "$(calls staple)" -eq 1 ]'

new_case; script staple '68|error is Error Domain=SomeOtherDomain Code=-1005 "not NSURL"'; run_notarize
check S1-13 "same number in another error domain is not retried" '[ $RC -eq 1 ] && [ "$(calls staple)" -eq 1 ]'

new_case; script staple "127|command not found"; run_notarize
check S1-14 "tool missing is not retried" '[ $RC -eq 1 ] && [ "$(calls staple)" -eq 1 ]'

new_case; script staple "68|$MSG_1005" "65|$MSG_NORECORD" "0|would work"; run_notarize
check S1-15 "permanent error after a network error stops at once" '[ $RC -eq 1 ] && [ "$(calls staple)" -eq 2 ]'

# ---- notarize.sh, validate --------------------------------------------------
new_case; script validate "68|$MSG_1005" "0|worked"; run_notarize
check S1-16 "network error during validate: retried, then success" \
	'[ $RC -eq 0 ] && [ "$(calls staple)" -eq 1 ] && [ "$(calls validate)" -eq 2 ] && has "notarized and stapled"'

new_case; script validate "68|$MSG_1005"; run_notarize
check S1-17 "validate never succeeds: notarize.sh must fail" \
	'[ $RC -ne 0 ] && [ "$(calls validate)" -eq 4 ] && ! has "notarized and stapled"'

new_case; script validate "65|$MSG_NOTICKET"; run_notarize
check S1-18 "no ticket at validate: one attempt, notarize.sh must fail" \
	'[ $RC -ne 0 ] && [ "$(calls validate)" -eq 1 ] && ! has "notarized and stapled"'

# ---- nothing else is repeated, nothing leaks --------------------------------
new_case; script staple "68|$MSG_1005"; run_notarize
check S1-19 "retries never resubmit or re-sign" \
	'[ "$(submits)" -eq 1 ] && ! grep -q "^codesign" "$MOCK_DIR/calls.log"'
check S1-20 "log names action, attempt, exit, class, wait and result" \
	'has "stapler staple: attempt 1/4, exit 68, network error, retrying in 0s" && has "stapler staple: attempt 2/4, exit 68, network error, retrying in 30s" && has "stapler staple: attempt 3/4, exit 68, network error, retrying in 120s" && has "stapler staple: attempt 4/4, exit 68, network error, result failure"'
check S1-21 "credentials do not reach the log" \
	'! has "SENTINEL-KEYID" && ! has "SENTINEL-ISSUER" && ! has "U0VOVElORUwtS0VZ" && ! has "SENTINEL-KEY"'

new_case; script staple "65|$MSG_BADSIG"; run_notarize
check S1-22 "permanent failure is logged as such" \
	'has "stapler staple: attempt 1/4, exit 65, permanent error, result failure"'

# ---- exit status -------------------------------------------------------------
new_case; script staple "68|$MSG_1005"
(cd "$C/repo" && mock_env bash -c '. .github/macos/notary-lib.sh; stapler_run staple X; echo "rc=$?"') > "$C/out" 2>&1
check S1-23 "stapler_run returns stapler's own last status" 'has "rc=68"'

new_case; script staple "65|$MSG_BADSIG"
(cd "$C/repo" && mock_env bash -c 'set -euo pipefail; . .github/macos/notary-lib.sh; stapler_run staple X; echo REACHED') > "$C/out" 2>&1
RC=$?
check S1-24 "under set -e a failure stops the caller" '[ $RC -eq 65 ] && ! has REACHED'

# ---- verify.sh ---------------------------------------------------------------
new_case; run_verify
check S1-25 "verify.sh: clean run" '[ $RC -eq 0 ] && [ "$(calls validate)" -eq 1 ] && has "VERIFIED:"'

new_case; script validate "68|$MSG_1005" "0|worked"; run_verify
check S1-26 "verify.sh: network error then success" '[ $RC -eq 0 ] && [ "$(calls validate)" -eq 2 ] && has "VERIFIED:"'

new_case; script validate "68|$MSG_1005"; run_verify
check S1-27 "verify.sh: validate never succeeds, fail" \
	'[ $RC -ne 0 ] && [ "$(calls validate)" -eq 4 ] && [ "$(sleeps)" = "30 120" ] && ! has "VERIFIED:" && has "no valid notarization ticket"'

new_case; script validate "65|$MSG_NOTICKET"; run_verify
check S1-28 "verify.sh: no ticket, one attempt, fail" \
	'[ $RC -ne 0 ] && [ "$(calls validate)" -eq 1 ] && ! has "VERIFIED:"'

new_case; touch "$MOCK_DIR/codesign.fail"; run_verify
check S1-29 "verify.sh: a bad signature still fails" '[ $RC -ne 0 ] && ! has "VERIFIED:"'

new_case; touch "$MOCK_DIR/spctl.reject"; run_verify
check S1-30 "verify.sh: a Gatekeeper rejection still fails" '[ $RC -ne 0 ] && ! has "VERIFIED:"'

# ---- the job, step by step: nothing after a failure, as GitHub runs it --------
# Same order as macos-sign-notarize.yml.  test-workflow.sh checks the file itself
# has no way past a failed step.
job() {
	(cd "$C/repo" && mock_env bash .github/macos/notarize.sh "$C/n.zip" "$C/app.app") > "$C/out" 2>&1 || return 1
	(cd "$C/repo" && mock_env bash .github/macos/verify.sh "$C/n.zip" arm64 0) >> "$C/out" 2>&1 || return 1
	touch "$C/published"
}

new_case; job
check S1-31 "job: everything works, publish reached" '[ -f "$C/published" ]'

new_case; script staple "68|$MSG_1005" "0|worked"; script validate "0|worked" "68|$MSG_1005" "0|worked"; job
check S1-32 "job: transient errors recovered, publish reached" '[ -f "$C/published" ]'

new_case; script staple "68|$MSG_1005"; job
check S1-33 "job: staple never works, publish blocked" '[ ! -f "$C/published" ]'

new_case; script validate "68|$MSG_1005"; job
check S1-34 "job: validate never works, publish blocked" '[ ! -f "$C/published" ]'

new_case; script validate "0|worked" "68|$MSG_1005"; job
check S1-35 "job: only the final check fails, publish blocked" '[ ! -f "$C/published" ]'

# ---- the recovery workflow ---------------------------------------------------
# Runs the shell of its "Staple the ticket" step as written in the file.
resume_step() {
	awk '/- name: Staple the ticket/{f=1;next} f&&/- name:/{exit} f&&!/run: \|/{sub(/^ +/,""); print}' \
		"$C/repo/.github/workflows/macos-notarize-resume.yml" \
		| sed "s#\${{ steps.bundle.outputs.app }}#$C/app.app#g" > "$C/step.sh"
	(cd "$C/repo" && mock_env bash "$C/step.sh") > "$C/out" 2>&1
	RC=$?
}

new_case; script staple "68|$MSG_1005" "0|worked"; resume_step
check S1-36 "resume workflow: a transient failure is retried" \
	'[ $RC -eq 0 ] && [ "$(calls staple)" -eq 2 ] && [ "$(calls validate)" -eq 1 ]'

new_case; script validate "68|$MSG_1005"; resume_step
check S1-37 "resume workflow: validate never works, the step fails" \
	'[ $RC -ne 0 ] && [ "$(calls validate)" -eq 4 ]'

finish
