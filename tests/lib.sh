#!/bin/bash
# Shared by the test files.  Each case gets a disposable copy of the tree under
# test, so nothing here can touch the tree itself.

TESTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TREE=$(cd "${1:?usage: <test> <dir holding .github>}" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/simu-sign-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
chmod +x "$TESTS"/mocks/* "$TESTS"/gpg-shim/* 2>/dev/null
export MOCK_DIR=
PASSES=0
FAILS=0
N=0

MSG_1005='Processing: APP\nerror is Error Domain=NSURLErrorDomain Code=-1005 "The network connection was lost." UserInfo={_kCFStreamErrorCodeKey=-4, NSErrorFailingURLStringKey=https://api.apple-cloudkit.com/database/1/com.apple.gk.ticket-delivery/production/public/records/lookup, _kCFStreamErrorDomainKey=4}\nCloudKit'"'"'s response is inconsistent with expections: (null)\nThe staple and validate action failed! Error 68.'
MSG_1001='Processing: APP\nerror is Error Domain=NSURLErrorDomain Code=-1001 "The request timed out."\nThe staple and validate action failed! Error 68.'
MSG_NOTICKET='Processing: APP\nAPP does not have a ticket stapled to it.\nThe validate action failed! Error 65.'
MSG_NORECORD='Processing: APP\nCloudKit query for APP failed due to "Record Not Found".\nCould not find base64 encoded ticket in response\nThe staple and validate action failed! Error 65.'
MSG_BADSIG='Processing: APP\nThe signature of the binary is invalid.\nThe staple and validate action failed! Error 65.'
MSG_CORRUPT='Processing: APP\nCould not read the bundle: file is corrupt.\nThe staple and validate action failed! Error 66.'

new_case() {
	N=$((N + 1))
	C="$WORK/$N"
	MOCK_DIR="$C/m"
	mkdir -p "$MOCK_DIR" "$C/repo" "$C/tmp"
	cp -R "$TREE/.github" "$C/repo/.github"
	printf '#!/bin/bash\nexit 0\n' > "$C/repo/.github/macos/inspect-bundle.sh"
	chmod +x "$C"/repo/.github/macos/*.sh
	mkdir -p "$C/app.app/Contents"
	echo zip > "$C/n.zip"
	: > "$MOCK_DIR/calls.log"
	: > "$MOCK_DIR/sleeps.log"
}

# script <action> <rc|message> ...
script() {
	local action=$1 line
	shift
	: > "$MOCK_DIR/$action.script"
	for line in "$@"; do
		printf '%s\n' "$line" >> "$MOCK_DIR/$action.script"
	done
}

mock_env() {
	env PATH="$TESTS/mocks:$PATH" MOCK_DIR="$MOCK_DIR" RUNNER_TEMP="$C/tmp" \
		GITHUB_OUTPUT="$C/gh_output" PLISTBUDDY="$TESTS/mocks/plistbuddy" \
		MACOS_NOTARY_API_KEY_P8="U0VOVElORUwtS0VZ" \
		MACOS_NOTARY_API_KEY_ID="SENTINEL-KEYID" \
		MACOS_NOTARY_API_ISSUER_ID="SENTINEL-ISSUER" \
		"$@"
}

run_notarize() {
	(cd "$C/repo" && mock_env bash .github/macos/notarize.sh "$C/n.zip" "$C/app.app") > "$C/out" 2>&1
	RC=$?
}

run_verify() {
	(cd "$C/repo" && mock_env bash .github/macos/verify.sh "$C/n.zip" arm64 0) > "$C/out" 2>&1
	RC=$?
}

calls() { grep -c "^xcrun stapler $1" "$MOCK_DIR/calls.log"; }
submits() { grep -c '^xcrun notarytool submit' "$MOCK_DIR/calls.log"; }
sleeps() { tr '\n' ' ' < "$MOCK_DIR/sleeps.log" | sed 's/ $//'; }

# check <id> <description> <condition text>; the condition is eval'd.
check() {
	if eval "$3"; then
		PASSES=$((PASSES + 1))
		echo "PASS $1 $2"
	else
		FAILS=$((FAILS + 1))
		echo "FAIL $1 $2 [$3] rc=${RC:-} staple=$(calls staple 2>/dev/null) validate=$(calls validate 2>/dev/null) sleeps='$(sleeps 2>/dev/null)'"
	fi
}

has() { grep -qF -- "$1" "$C/out"; }

finish() {
	echo "SUMMARY $(basename "$0") pass=$PASSES fail=$FAILS"
	[ "$FAILS" -eq 0 ]
}
