#!/bin/bash
#
# setup-camera.sh — MacBookPro14,1 (A1708) FaceTime HD camera (facetimehd)
#
# Validated on CachyOS userspace with the stock Arch linux kernel
# (7.1.8-arch1-3 during testing).  See docs/camera.md.
#
# Hardware: Broadcom 720p FaceTime HD Camera, PCI 14e4:1570
# Driver:   facetimehd (out-of-tree DKMS, upstream patjak/facetimehd)
# Firmware: facetimehd-firmware (AUR) -> /usr/lib/firmware/facetimehd/firmware.bin
#
# Safety rules implemented here:
#   * never runs makepkg as root;
#   * does not assume paru/yay exists;
#   * AUR packages are built in temporary clones as the NORMAL USER
#     (--build-aur) or by exact manual instructions (apply);
#   * does not add /etc/modules-load.d/facetimehd.conf (autoload works);
#   * does not disable kernel signature checking / Secure Boot;
#   * does not install facetimehd-data (optional calibration, not needed);
#   * uninstall removes only the camera packages/module.
#
# Usage:
#   sudo ./setup-camera.sh                  apply (deps + verify; prints AUR steps if needed)
#   sudo ./setup-camera.sh --build-aur      also build the two AUR packages
#                                           as the invoking non-root user
#   sudo ./setup-camera.sh --status         read-only diagnostics
#   sudo ./setup-camera.sh --uninstall      remove camera packages/module

set -euo pipefail

CAM_PCI_ID="14e4:1570"
REPO_DEPS="base-devel git dkms linux-headers v4l-utils ffmpeg"
AUR_PKGS="facetimehd-firmware facetimehd-dkms-git"
FIRMWARE="/usr/lib/firmware/facetimehd/firmware.bin"
AUR_BASE="https://aur.archlinux.org"

ACTION="apply"
BUILD_AUR=0

usage() {
	sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
	echo "error: $*" >&2
	exit 1
}

# capture the original arguments BEFORE the parsing loop consumes them,
# so the sudo re-exec below can pass them through unchanged
ORIG_ARGS=("$@")

require_root() {
	if [ "$(id -u)" -ne 0 ]; then
		if command -v sudo >/dev/null 2>&1; then
			exec sudo "$0" "${ORIG_ARGS[@]}"
		fi
		die "this script must run as root (no sudo found)"
	fi
}

dmi_product() {
	cat /sys/class/dmi/id/product_name 2>/dev/null || echo ""
}

check_model() {
	local model
	model="$(dmi_product)"
	if [ -z "${model}" ]; then
		echo "warning: cannot read DMI product name; continuing"
	elif [ "${model}" != "MacBookPro14,1" ]; then
		echo "warning: DMI model is '${model}', expected MacBookPro14,1 (continuing — PCI check below still applies)"
	fi
}

check_pci() {
	if ! lspci -nn 2>/dev/null | grep -qi "${CAM_PCI_ID}"; then
		die "FaceTime HD camera (${CAM_PCI_ID}) not found in lspci — nothing to configure"
	fi
	lspci -nnk -d "${CAM_PCI_ID}" 2>/dev/null | head -n 4 || true
}

check_pacman() {
	command -v pacman >/dev/null 2>&1 || die "pacman not found — this script targets Arch Linux / CachyOS"
}

install_repo_deps() {
	echo "== installing repository packages (idempotent) =="
	pacman -S --needed --noconfirm ${REPO_DEPS}
}

aur_pkg_missing() {
	# 0 = any of the AUR packages missing
	for p in ${AUR_PKGS}; do
		pacman -Q "${p}" >/dev/null 2>&1 || return 0
	done
	return 1
}

print_aur_instructions() {
	echo "== AUR packages required (user-controlled step) =="
	echo "Build these as your NORMAL user (never as root), e.g.:"
	echo
	for p in ${AUR_PKGS}; do
		echo "  git clone ${AUR_BASE}/${p}.git"
		echo "  cd ${p} && makepkg -si"
		echo
	done
	echo "Then re-run: sudo ${0}"
	echo "(or run: sudo ${0} --build-aur  to attempt this automatically"
	echo " as the invoking non-root user.)"
}

build_aur_as_user() {
	local user="${SUDO_USER:-}"
	[ -n "${user}" ] && [ "${user}" != "root" ] || {
		echo "cannot determine a non-root user to build AUR packages as"
		echo "(run with: sudo ${0} --build-aur)"
		print_aur_instructions
		return 1
	}

	local work
	work="$(mktemp -d /tmp/facetimehd-aur.XXXXXX)"
	chown "${user}:${user}" "${work}" 2>/dev/null || true
	trap 'rm -rf "${work}"' EXIT

	echo "== building AUR packages as user '${user}' in ${work} =="
	for p in ${AUR_PKGS}; do
		if pacman -Q "${p}" >/dev/null 2>&1; then
			echo "already installed: ${p}"
			continue
		fi
		echo "-- building ${p} --"
		install -d -o "${user}" -g "${user}" "${work}/${p}"
		if ! sudo -u "${user}" bash -c "cd '${work}/${p}' && git clone -q ${AUR_BASE}/${p}.git . && makepkg -si --noconfirm"; then
			echo
			echo "WARNING: automatic AUR build failed for ${p}."
			print_aur_instructions
			return 1
		fi
	done

	rm -rf "${work}"
	trap - EXIT
	echo "== AUR packages installed =="
}

verify_firmware() {
	echo "== firmware =="
	if [ -f "${FIRMWARE}" ]; then
		printf '  %s: %s bytes\n' "${FIRMWARE}" "$(wc -c <"${FIRMWARE}")"
		[ "$(wc -c <"${FIRMWARE}")" -ge 1048576 ] || {
			echo "  warning: firmware smaller than expected (~1.4 MiB during testing)"
			return 1
		}
	else
		echo "  MISSING: ${FIRMWARE} (facetimehd-firmware not installed?)"
		return 1
	fi
}

verify_dkms() {
	echo "== DKMS =="
	local ver
	ver="$(dkms status 2>/dev/null | sed -n 's|^facetimehd/\([^,]*\),.*|\1|p' | head -n 1 || true)"
	if [ -z "${ver}" ]; then
		echo "  facetimehd not registered with DKMS (facetimehd-dkms-git not installed?)"
		return 1
	fi
	echo "  facetimehd/${ver} present"
	if dkms status 2>/dev/null | grep -q "facetimehd/${ver}, $(uname -r).*installed"; then
		echo "  installed for running kernel $(uname -r): yes"
	else
		echo "  installed for running kernel $(uname -r): NO — module must be rebuilt"
		echo "  (reinstall facetimehd-dkms-git, e.g. via AUR rebuild, or dkms autoinstall)"
		return 1
	fi
}

load_and_test() {
	echo "== module load / device test =="
	if ! lsmod | grep -q '^facetimehd'; then
		echo "  loading: modprobe facetimehd"
		if ! modprobe facetimehd 2>/dev/null; then
			echo "  modprobe facetimehd failed — check:"
			echo "    sudo journalctl -k -b | grep -iE 'facetimehd|firmware'"
			return 1
		fi
	else
		echo "  already loaded"
	fi

	sleep 1
	if [ -e /dev/video0 ]; then
		echo "  /dev/video0 present"
	else
		echo "  /dev/video0 NOT present after load — check journalctl -k for facetimehd errors"
		return 1
	fi

	if command -v v4l2-ctl >/dev/null 2>&1; then
		v4l2-ctl --list-devices 2>/dev/null | grep -A2 -i 'facetime' | sed 's/^/  /' || true
	fi

	echo
	echo "  Live capture check (manual):"
	echo "    v4l2-ctl --device /dev/video0 --list-formats-ext"
	echo "    ffplay /dev/video0        # or open /dev/video0 in VLC"
	echo "  (actual live video in VLC was verified during testing)"
}

show_status() {
	echo "== FaceTime HD camera status (read-only) =="
	printf 'DMI product       : %s\n' "$(dmi_product)"
	echo "-- PCI --"
	lspci -nnk -d "${CAM_PCI_ID}" 2>/dev/null | head -n 4 || echo "  camera ${CAM_PCI_ID} NOT found"
	echo "-- packages --"
	for p in ${REPO_DEPS}; do
		pacman -Q "${p}" >/dev/null 2>&1 && printf '  %-20s ok\n' "${p}" || printf '  %-20s MISSING\n' "${p}"
	done
	for p in ${AUR_PKGS}; do
		if pacman -Q "${p}" >/dev/null 2>&1; then
			printf '  %-22s %s\n' "${p}" "$(pacman -Q "${p}")"
		else
			printf '  %-22s MISSING (AUR)\n' "${p}"
		fi
	done
	echo "-- firmware --"
	[ -f "${FIRMWARE}" ] \
		&& printf '  %s: %s bytes\n' "${FIRMWARE}" "$(wc -c <"${FIRMWARE}")" \
		|| echo "  MISSING: ${FIRMWARE}"
	echo "-- DKMS --"
	dkms status 2>/dev/null | grep -i facetimehd | sed 's/^/  /' || echo "  facetimehd not registered"
	echo "-- module / device --"
	lsmod | grep '^facetimehd' | sed 's/^/  /' || echo "  module not loaded"
	ls -l /dev/video* 2>/dev/null | sed 's/^/  /' || echo "  no /dev/video* devices"
	if command -v v4l2-ctl >/dev/null 2>&1; then
		v4l2-ctl --list-devices 2>/dev/null | grep -A2 -i 'facetime' | sed 's/^/  /' || true
	fi
	echo "-- kernel log (facetimehd / camera) --"
	if command -v journalctl >/dev/null 2>&1 && journalctl -k -b --no-pager -n 1 >/dev/null 2>&1; then
		journalctl -k -b --no-pager 2>/dev/null \
			| grep -Ei 'facetimehd|03:00.0|video0|firmware' | tail -n 12 | sed 's/^/  /' \
			|| echo "  (no matching lines)"
	else
		echo "  kernel log not readable — rerun with: sudo ${0} --status"
	fi
}

uninstall() {
	echo "== removing facetimehd camera packages/module =="
	local ver
	ver="$(dkms status 2>/dev/null | sed -n 's|^facetimehd/\([^,]*\),.*|\1|p' | head -n 1 || true)"
	if [ -n "${ver}" ]; then
		echo "  dkms remove facetimehd/${ver} --all"
		dkms remove "facetimehd/${ver}" --all || echo "  (dkms remove failed — try manually)"
	fi
	if lsmod | grep -q '^facetimehd'; then
		echo "  modprobe -r facetimehd"
		modprobe -r facetimehd || true
	fi
	echo "  pacman -Rns --noconfirm ${AUR_PKGS}"
	pacman -Rns --noconfirm ${AUR_PKGS} || true
	echo
	echo "Done. Only camera packages/module were removed — audio, Bluetooth,"
	echo "Wi-Fi and boot configuration are untouched."
	echo "If pacman removal failed, run manually: sudo pacman -Rns ${AUR_PKGS}"
}

# --- argument parsing --------------------------------------------------------
while [ $# -gt 0 ]; do
	case "${1}" in
		--build-aur) BUILD_AUR=1 ;;
		--status) ACTION="status" ;;
		--uninstall) ACTION="uninstall" ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown option: ${1} (see --help)" ;;
	esac
	shift
done

require_root "$@"

case "${ACTION}" in
	apply)
		check_pacman
		check_model
		check_pci
		install_repo_deps
		if aur_pkg_missing; then
			print_aur_instructions
			if [ "${BUILD_AUR}" -eq 1 ]; then
				echo
				build_aur_as_user
			else
				echo
				echo "AUR packages are required before the camera can work."
				echo "After installing them, re-run: sudo ${0}"
				exit 0
			fi
		fi
		verify_firmware
		verify_dkms
		load_and_test
		echo
		echo "Camera setup complete. Autoload happens via PCI modalias/udev on reboot."
		echo "Expected benign boot messages: 'out-of-tree module taints kernel' and"
		echo "'module verification failed' (unsigned DKMS module)."
		;;
	status)
		show_status
		;;
	uninstall)
		uninstall
		;;
esac
