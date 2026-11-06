#!/bin/bash
# Containers with attacker data glued on, built with the real gpg.  The attacker model
# holds a genuine container, which is public as an artifact, and not the key.
# Sourced by the tests; expects REAL_GPG or gpg in PATH, and MACOS_ARTIFACT_KEY.
make_glued() {
	local d=$1 g off
	g=${REAL_GPG:-$(command -v gpg)}
	mkdir -p "$d" "$d/home"
	chmod 700 "$d/home"
	export GNUPGHOME="$d/home"
	export MACOS_ARTIFACT_KEY=${MACOS_ARTIFACT_KEY:-lab-only-key}
	printf 'GENUINE payload\n' > "$d/genuine"
	printf 'ATTACKER payload\n' > "$d/evil"
	printf '%s' "$MACOS_ARTIFACT_KEY" | "$g" --batch --yes --quiet --no-tty --pinentry-mode loopback --passphrase-fd 0 \
		--symmetric --cipher-algo AES256 --force-aead --aead-algo OCB --s2k-mode 3 --s2k-digest-algo SHA512 \
		--s2k-count 65011712 --compress-algo none --output "$d/ok.gpg" "$d/genuine"
	"$g" --batch --yes --quiet --no-tty --store --compress-algo none --output "$d/lit.gpg" "$d/evil"
	"$g" --batch --yes --quiet --no-tty --store --compress-algo zip --output "$d/zipi.gpg" "$d/evil"
	# A compressed packet of definite length, so that what follows it is still read.
	# Synthetic fixture: raw deflate of a literal packet holding "ATTACKER payload".
	cp "$TESTS/fixtures/zip-definite-literal.pgp" "$d/zipd.gpg"
	off=$("$g" --list-packets --list-only "$d/ok.gpg" 2>/dev/null | sed -n -E 's/^# off=([0-9]+) .* tag=20 .*/\1/p' | head -1)
	tail -c +"$((off + 1))" "$d/ok.gpg" > "$d/bare.gpg"
	cat "$d/lit.gpg" "$d/ok.gpg" > "$d/lit-aead.gpg"
	cat "$d/ok.gpg" "$d/lit.gpg" > "$d/aead-lit.gpg"
	cat "$d/zipi.gpg" "$d/ok.gpg" > "$d/zipi-aead.gpg"
	cat "$d/zipd.gpg" "$d/ok.gpg" > "$d/zipd-aead.gpg"
	cat "$d/ok.gpg" "$d/zipd.gpg" > "$d/aead-zipd.gpg"
	cat "$d/lit.gpg" "$d/bare.gpg" > "$d/lit-bare.gpg"
	cat "$d/ok.gpg" "$d/ok.gpg" > "$d/aead-aead.gpg"
	# The same parts nested inside one compressed packet.
	python3 "$TESTS/nest.py" "$d/nest-lit-aead.gpg" "$d/lit.gpg" "$d/ok.gpg" || return 1
	python3 "$TESTS/nest.py" "$d/nest-aead-lit.gpg" "$d/ok.gpg" "$d/lit.gpg" || return 1
	python3 "$TESTS/nest.py" "$d/nest-aead.gpg" "$d/ok.gpg" || return 1
	local f
	for f in ok lit zipi zipd bare lit-aead aead-lit zipi-aead zipd-aead aead-zipd lit-bare aead-aead nest-lit-aead nest-aead-lit nest-aead; do
		[ -s "$d/$f.gpg" ] || { echo "make_glued: $f.gpg was not built"; return 1; }
	done
}
