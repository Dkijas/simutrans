#!/bin/bash
# What this runner really is.  EXPECT_ARCH makes a wrong architecture fatal.
echo "macOS        : $(sw_vers 2>/dev/null | tr '\n' ' ')"
echo "image        : ${ImageOS:-unknown} ${ImageVersion:-unknown}"
echo "uname -m     : $(uname -m)"
echo "arch         : $(arch 2>/dev/null)"
echo "translated   : $(sysctl -n sysctl.proc_translated 2>/dev/null || echo n/a)"
echo "cpu          : $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo "/bin/bash    : $(/bin/bash --version | head -1)"
echo "bash in PATH : $(command -v bash) : $(bash --version | head -1)"
echo "all bash     : $(type -a bash | tr '\n' ';')"
echo "gpg          : $(command -v gpg) : $(gpg --version | head -1)"
echo "libgcrypt    : $(gpg --version | grep -i '^libgcrypt' || echo n/a)"
echo "git          : $(git --version)"
echo "grep         : $(grep --version 2>&1 | head -1)"
echo "sed          : $(sed --version 2>&1 | head -1 | cut -c1-60)"
echo "awk          : $(awk -version 2>&1 | head -1)"
echo "patch        : $(patch --version 2>&1 | head -1)"
echo "tar          : $(tar --version 2>&1 | head -1)"
echo "real xcrun   : $(command -v xcrun || echo none)"
echo "secrets seen : $(env | cut -d= -f1 | grep -E '^MACOS_|P12|NOTARY|DEVELOPER_ID' | tr '\n' ' ')(end)"
if [ -n "${EXPECT_ARCH:-}" ] && [ "$(uname -m)" != "$EXPECT_ARCH" ]; then
	echo "WRONG ARCHITECTURE: wanted $EXPECT_ARCH"
	exit 1
fi
