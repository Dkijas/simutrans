#!/bin/bash
# A container made by one runner's gpg, opened with another's.  Synthetic key and payload.
# Usage: cross-gpg.sh make <dir holding .github> <out dir>
#        cross-gpg.sh read <dir holding .github> <in dir>
set -u
MODE=${1:?make or read}
TREE=$(cd "${2:?tree}" && pwd)
DIR=${3:?dir}
export MACOS_ARTIFACT_KEY=lab-only-cross-version-key
export GNUPGHOME
GNUPGHOME=$(mktemp -d "${TMPDIR:-/tmp}/simu-cross.XXXXXX")
chmod 700 "$GNUPGHOME"
trap 'rm -rf "$GNUPGHOME"' EXIT
. "$TREE/.github/macos/artifact-lib.sh"

case "$MODE" in
	make)
		mkdir -p "$DIR"
		printf 'synthetic cross-version payload %s\n' "$(uname -m)" > "$DIR/plain.txt"
		artifact_encrypt "$DIR/plain.txt" "$DIR/container.gpg" || exit 1
		gpg --version | head -1 > "$DIR/made-by.txt"
		uname -m >> "$DIR/made-by.txt"
		echo "made by: $(tr '\n' ' ' < "$DIR/made-by.txt")"
		gpg --list-packets --list-only "$DIR/container.gpg" 2>/dev/null
		;;
	read)
		echo "made by: $(tr '\n' ' ' < "$DIR/made-by.txt")"
		echo "read by: $(gpg --version | head -1) $(uname -m)"
		gpg --list-packets --list-only "$DIR/container.gpg" 2>/dev/null
		back=$(mktemp "${TMPDIR:-/tmp}/simu-cross-back.XXXXXX")
		rm -f "$back"
		artifact_decrypt "$DIR/container.gpg" "$back" || exit 1
		cmp "$DIR/plain.txt" "$back" || exit 1
		rm -f "$back"
		echo "CROSS-VERSION OK: decrypted and identical"
		cp "$DIR/container.gpg" "$DIR/bad.gpg"
		size=$(wc -c < "$DIR/bad.gpg" | tr -d ' ')
		printf '\125' | dd of="$DIR/bad.gpg" bs=1 seek=$((size - 4)) conv=notrunc 2>/dev/null
		cmp -s "$DIR/container.gpg" "$DIR/bad.gpg" && printf '\252' | dd of="$DIR/bad.gpg" bs=1 seek=$((size - 4)) conv=notrunc 2>/dev/null
		back2=$(mktemp "${TMPDIR:-/tmp}/simu-cross-bad.XXXXXX")
		rm -f "$back2"
		if artifact_decrypt "$DIR/bad.gpg" "$back2" > /dev/null 2>&1; then
			echo "CROSS-VERSION FAIL: an altered container was accepted"
			exit 1
		fi
		[ ! -e "$back2" ] || { echo "CROSS-VERSION FAIL: plaintext left behind"; exit 1; }
		echo "CROSS-VERSION OK: altered container refused, no plaintext left"
		;;
	*)
		echo "unknown mode $MODE"
		exit 2
		;;
esac
