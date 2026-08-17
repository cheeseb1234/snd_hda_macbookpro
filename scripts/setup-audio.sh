#!/bin/bash
#
# setup-audio.sh — MacBookPro14,1 (A1708) CS8409/Cirrus audio driver (DKMS)
#
# Convenience wrapper around the upstream snd_hda_macbookpro installer.
# The authoritative installer lives in the repository root
# (install.cirrus.driver.sh) because dkms.conf's PRE_BUILD hook references it
# relative to the source tree; this wrapper just runs it from the right place.
#
# Default action is DKMS install (-i).  Any arguments are passed through,
# so the full option set of install.cirrus.driver.sh is available:
#
#   ./setup-audio.sh            # DKMS install for the running kernel
#   ./setup-audio.sh -r         # remove the DKMS module
#   ./setup-audio.sh -k 6.17.x  # target a specific kernel version
#
# Validated on: Arch Linux / CachyOS with the stock kernel.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# --- root check (re-exec via sudo if available) -----------------------------
if [ "$(id -u)" -ne 0 ]; then
	if command -v sudo >/dev/null 2>&1; then
		exec sudo "$0" "$@"
	fi
	echo "error: this script must run as root (no sudo found)" >&2
	exit 1
fi

# --- dependency check --------------------------------------------------------
missing=0
for dep in dkms gcc make patch wget git; do
	if ! command -v "${dep}" >/dev/null 2>&1; then
		echo "missing dependency: ${dep}"
		missing=1
	fi
done
if [ "${missing}" -eq 1 ]; then
	echo
	echo "Install the build dependencies first, e.g. on Arch/CachyOS:"
	echo "  sudo pacman -S --needed dkms gcc linux-headers make patch wget git"
	exit 1
fi

if [ ! -d "/usr/lib/modules/$(uname -r)/build" ]; then
	echo "warning: kernel headers for $(uname -r) not found in /usr/lib/modules"
	echo "         install them with: sudo pacman -S linux-headers"
	echo "         (the installer will fail without them; continuing anyway)"
fi

# --- run the upstream installer from the repository root --------------------
cd "${REPO_ROOT}"
echo "==> running ./install.cirrus.driver.sh ${*:--i} from ${REPO_ROOT}"
exec ./install.cirrus.driver.sh "${@:--i}"
