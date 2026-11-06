#!/bin/bash
# bash -n, one file at a time: `bash -n a b` only reads a.  Fewer or more files than
# expected is a failure, so that an empty glob cannot pass.
# Usage: syntax-check.sh <dir holding .github> [expected count, default 13]
DIR=${1:?tree}
EXPECT=${2:-13}
rc=0
checked=0
for f in "$DIR"/.github/macos/*.sh; do
	if ! bash -n "$f"; then
		echo "SYNTAX ERROR in $f"
		rc=1
	fi
	checked=$((checked + 1))
done
echo "syntax checked: $checked files"
if [ "$checked" -ne "$EXPECT" ]; then
	echo "SYNTAX wrong number of files: wanted $EXPECT"
	rc=1
fi
exit "$rc"
