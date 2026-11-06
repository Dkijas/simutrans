#!/bin/bash
# Are the manipulated messages really what the tests call them?  Otherwise a refusal
# could be a refusal of something else.  Lists each one with the real gpg.
# Usage: test-glued-structure.sh <dir holding .github>
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
. "$TESTS/glued.sh"
new_case
make_glued "$WORK/g" || { echo "FATAL could not build the test messages"; exit 3; }
G=$(command -v gpg)
DATA='^:(aead|ocb) encrypted packet: cipher=9 aead=2 cb=16$'

# structure <id> <file> <description> <extended pattern> ...: all must be present.
structure() {
	local id=$1 file=$2 desc=$3 listing p ok=true
	shift 3
	listing=$("$G" --list-packets --list-only "$WORK/g/$file.gpg" 2>/dev/null)
	for p in "$@"; do
		grep -qE "$p" <<<"$listing" || ok=false
	done
	cmp -s "$WORK/g/$file.gpg" "$WORK/g/ok.gpg" && ok=false
	printf '%s\n' "$listing" | grep -E '^(:|# off)' | sed "s/^/INFO $file: /" | cut -c1-80
	check "$id" "$desc" "$ok"
}

structure T-01 lit-aead "literal packet and a genuine data packet" '^:literal data packet:' "$DATA"
structure T-02 aead-lit "genuine data packet and a literal packet" '^:literal data packet:' "$DATA"
structure T-03 zipd-aead "a compressed packet comes first" '^:compressed packet:'
structure T-04 aead-zipd "genuine data packet and a compressed packet" '^:compressed packet:' "$DATA"
structure T-05 lit-bare "literal packet and a data packet" '^:literal data packet:' "$DATA"
structure T-06 aead-aead "a genuine data packet, twice" "$DATA"
twice=$("$G" --list-packets --list-only "$WORK/g/aead-aead.gpg" 2>/dev/null | grep -cE "$DATA")
check T-06b "two data packets really are there" '[ "$twice" -eq 2 ]'
nokey=$("$G" --list-packets --list-only "$WORK/g/lit-bare.gpg" 2>/dev/null | grep -c '^:symkey enc packet:')
check T-05b "no session key in that message" '[ "$nokey" -eq 0 ]'
structure T-07 zipi-aead "a compressed packet of open length comes first" '^:compressed packet:'
structure T-08 nest-lit-aead "compressed: literal then genuine data packet" '^:compressed packet:' '^:literal data packet:' "$DATA"
structure T-09 nest-aead-lit "compressed: genuine data packet then literal" '^:compressed packet:' '^:literal data packet:' "$DATA"
structure T-10 nest-aead "compressed: genuine data packet alone" '^:compressed packet:' "$DATA"
intact=$("$G" --list-packets --list-only "$WORK/g/ok.gpg" 2>/dev/null | grep -c '^:')
check T-00 "the intact message has exactly two packets" '[ "$intact" -eq 2 ]'

finish
