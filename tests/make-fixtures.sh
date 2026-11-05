#!/bin/bash
# Writes the --list-packets fixtures.  aead-2.4.9 is real gpg 2.4.9 output and
# ocb-production is verbatim from run 40985712752; the rest are those two, altered.
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
mkdir -p fixtures
cd fixtures || exit 1

SYM=$'# off=0 ctb=8c tag=3 hlen=2 plen=77\n:symkey enc packet: version 5, cipher 9, aead 2, s2k 3, hash 10, encrypted seskey 63 bytes\n\tsalt F00F9F3BF45A953F, count 65011712 (255)'
HDR='# off=79 ctb=d4 tag=20 hlen=2 plen=99 new-ctb'
LEN=$'\tlength: 99'
CLASSIC=$'# off=15 ctb=d2 tag=18 hlen=2 plen=56 new-ctb\n:encrypted data packet:\n\tlength: 56\n\tmdc_method: 2'

w() { printf '%s\n' "$2" > "$1"; }

w ocb-production.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"
w aead-2.4.9.txt "$SYM"$'\n# off=79 ctb=d4 tag=20 hlen=2 plen=66 new-ctb\n:aead encrypted packet: cipher=9 aead=2 cb=16\n\tlength: 66'
w ocb-cipher7.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=7 aead=2 cb=16\n'"$LEN"
w aead-cipher7.txt "$SYM"$'\n'"$HDR"$'\n:aead encrypted packet: cipher=7 aead=2 cb=16\n'"$LEN"
w ocb-mode1.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=9 aead=1 cb=16\n'"$LEN"
w aead-mode1.txt "$SYM"$'\n'"$HDR"$'\n:aead encrypted packet: cipher=9 aead=1 cb=16\n'"$LEN"
w ocb-noparams.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet:\n'"$LEN"
w ocb-partparams.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=9 aead=2\n'"$LEN"
w truncated.txt "$SYM"
: > empty.txt
w ocb-tooshort.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet: [too short]'
w classic.txt "$SYM"$'\n'"$CLASSIC"
w ocb-suffix.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=9 aead=2 cb=16 extra\n'"$LEN"
w ocb-indented.txt "$SYM"$'\n'"$HDR"$'\n\t:ocb encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"
w ocb-prefix.txt "$SYM"$'\n'"$HDR"$'\nnote :ocb encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"
w ocb-in-name.txt $'# off=0 ctb=ac tag=11 hlen=2 plen=56\n:literal data packet:\n\tmode b (62), created 0, name=":ocb encrypted packet: cipher=9 aead=2 cb=16 ",\n\traw data: 6 bytes'
w aead-in-name.txt $'# off=0 ctb=ac tag=11 hlen=2 plen=56\n:literal data packet:\n\tmode b (62), created 0, name=":aead encrypted packet: cipher=9 aead=2 cb=16",\n\traw data: 6 bytes'
w ocb-wrongtag.txt "$SYM"$'\n# off=79 ctb=d2 tag=18 hlen=2 plen=99 new-ctb\n:ocb encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"
w ocb-notag.txt "$SYM"$'\n:ocb encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"
w ocb-and-classic.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"$'\n'"$CLASSIC"
w classic-and-ocb.txt "$SYM"$'\n'"$CLASSIC"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"
w ocb-twice.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"
w aead-and-classic.txt "$SYM"$'\n'"$HDR"$'\n:aead encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"$'\n'"$CLASSIC"
w classic-and-aead.txt "$SYM"$'\n'"$CLASSIC"$'\n'"$HDR"$'\n:aead encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"
w aead-twice.txt "$SYM"$'\n'"$HDR"$'\n:aead encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"$'\n'"$HDR"$'\n:aead encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"
w other-label.txt "$SYM"$'\n'"$HDR"$'\n:gcm encrypted packet: cipher=9 aead=2 cb=16\n'"$LEN"
w ocb-cipher90.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=90 aead=2 cb=16\n'"$LEN"
w ocb-mode20.txt "$SYM"$'\n'"$HDR"$'\n:ocb encrypted packet: cipher=9 aead=20 cb=16\n'"$LEN"
w nomdc.txt "$SYM"$'\n# off=79 ctb=c9 tag=9 hlen=2 plen=99 new-ctb\n:encrypted data packet:\n'"$LEN"
w ocb-spoof-mixed.txt $'# off=0 ctb=ac tag=11 hlen=2 plen=27\n:literal data packet:\n\tmode b (62), created 0, name="",\n\traw data: 17 bytes\n'"$HDR"$'\n:ocb encrypted packet: cipher=9 aead=2 cb=16 fake\n'"$LEN"
ls | wc -l
