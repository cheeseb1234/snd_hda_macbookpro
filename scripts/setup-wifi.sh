#!/bin/bash
#
# setup-wifi.sh — MacBookPro14,1 (A1708) BCM4350/5 Wi-Fi configuration
#
# Validated on CachyOS userspace with the stock Arch linux kernel
# (7.1.8-arch1-3 during testing).  See docs/wifi.md.
#
# What this script does:
#   1. verifies the machine is a MacBookPro14,1 with BCM4350 (14e4:43a3);
#   2. installs the MacBookPro14,1 board NVRAM files (downloaded from the
#      credited upstream source vrilutza/MacBookPro14.1 — NOT vendored —
#      or prints exact manual instructions if the download fails);
#   3. creates the two brcmfmac4350c2-pcie compatibility symlinks;
#   4. writes /etc/NetworkManager/conf.d/99-wifi-powersave-off.conf,
#      merging (never clobbering) unrelated user configuration;
#   5. applies the runtime power-save-off setting if wlan0 exists.
#
# What this script deliberately does NOT do:
#   - does not install or replace any Broadcom driver (brcmfmac stays);
#   - does NOT set "options brcmfmac roamoff=1" (roaming is validated);
#   - does not touch Bluetooth HCD firmware (that is harmful; separate);
#   - does not modify EFI/OpenCore/macOS/GRUB or partitioning.
#
# Usage:
#   sudo ./setup-wifi.sh                apply (idempotent)
#   sudo ./setup-wifi.sh --status       read-only verification
#   sudo ./setup-wifi.sh --uninstall    remove only files this script added
#
# Uninstall removes exactly: the two NVRAM .txt files, the two c2 symlinks,
# and the NM powersave conf (only if it matches what this script writes).

set -euo pipefail

NVRAM_RAW="https://raw.githubusercontent.com/vrilutza/MacBookPro14.1/master/firmware/wifi"
NVRAM_DIR="/usr/lib/firmware/brcm"
NM_CONF="/etc/NetworkManager/conf.d/99-wifi-powersave-off.conf"
NM_CONF_CONTENT="# MacBookPro14,1 BCM4350
[connection]
wifi.powersave=2
"

# file names (with the literal space used by the upstream project)
F_APPLE="brcmfmac4350-pcie.Apple Inc.-MacBookPro14,1.txt"
F_PLAIN="brcmfmac4350-pcie.txt"
# url-encoded equivalents for the space
F_APPLE_URL="brcmfmac4350-pcie.Apple%20Inc.-MacBookPro14,1.txt"

ACTION="apply"

usage() {
	sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
		die "this fix is for MacBookPro14,1 (found '${model}')"
	fi
}

check_pci() {
	if ! lspci -nn 2>/dev/null | grep -qi '14e4:43a3'; then
		die "BCM4350 (14e4:43a3) not found in lspci — refusing to install Wi-Fi config"
	fi
	lspci -nnk -d 14e4:43a3 2>/dev/null | head -n 4 || true
}

# ensure_key SECTION KEY VALUE — read stdin, print same content with
# KEY=VALUE active inside SECTION (replaces in place, never duplicates,
# appends section if missing; preserves all other lines).
ensure_key() {
	local section="$1" key="$2" val="$3"
	awk -v sec="${section}" -v key="${key}" -v val="${val}" '
		BEGIN { in_sec=0; sec_seen=0; key_seen=0 }
		/^[[:space:]]*\[[^]]+\]/ {
			if (in_sec && !key_seen) { print key "=" val; key_seen = 1 }
			in_sec = ($0 ~ ("^[[:space:]]*\\[" sec "\\]"))
			if (in_sec) sec_seen = 1
			print
			next
		}
		in_sec && $0 ~ ("^[[:space:]]*" key "[[:space:]]*=") {
			print key "=" val
			key_seen = 1
			next
		}
		{ print }
		END {
			if (in_sec && !key_seen) print key "=" val
			if (!sec_seen) {
				if (NR > 0) print ""
				print "[" sec "]"
				print key "=" val
			}
		}
	'
}

write_atomic() {
	# stdin -> $1, preserving inode/perms of existing file
	local target="$1" tmp
	tmp="${target}.tmp.$$"
	trap 'rm -f "${tmp}"' EXIT
	cat >"${tmp}"
	cat "${tmp}" >"${target}"
	rm -f "${tmp}"
	trap - EXIT
}

download_nvram() {
	# $1 = destination dir (must exist). Downloads both NVRAM files from
	# the credited upstream source. Prints paths on success, instructions
	# on failure.
	local dest="$1" url1 url2 ok=0
	url1="${NVRAM_RAW}/${F_APPLE_URL}"
	url2="${NVRAM_RAW}/${F_PLAIN}"

	if command -v curl >/dev/null 2>&1; then
		if curl -fsSL --max-time 60 -o "${dest}/${F_APPLE}" "${url1}" \
			&& curl -fsSL --max-time 60 -o "${dest}/${F_PLAIN}" "${url2}"; then
			ok=1
		fi
	else
		echo "note: curl not found; skipping automatic download"
	fi

	if [ "${ok}" -ne 1 ]; then
		echo
		echo "WARNING: could not download the NVRAM files from the upstream source."
		echo "They are NOT vendored here (Apple-derived content). Install them manually:"
		echo
		echo "  sudo mkdir -p ${NVRAM_DIR}"
		echo "  sudo curl -fLo '${NVRAM_DIR}/${F_APPLE}' \\"
		echo "       '${url1}'"
		echo "  sudo curl -fLo '${NVRAM_DIR}/${F_PLAIN}' \\"
		echo "       '${url2}'"
		echo
		return 1
	fi

	# sanity checks: not an HTML error page, non-trivial size
	for f in "${dest}/${F_APPLE}" "${dest}/${F_PLAIN}"; do
		if grep -qi '<html' "${f}" 2>/dev/null \
			|| [ "$(wc -c <"${f}")" -lt 500 ]; then
			rm -f "${f}"
			echo "error: downloaded NVRAM file '${f}' looks invalid; aborting" >&2
			return 1
		fi
	done
	return 0
}

install_nvram() {
	local tmp
	tmp="$(mktemp -d)"
	trap 'rm -rf "${tmp}"' EXIT

	if ! download_nvram "${tmp}"; then
		rm -rf "${tmp}"
		trap - EXIT
		return 1
	fi

	mkdir -p "${NVRAM_DIR}"
	local changed=0
	for f in "${F_APPLE}" "${F_PLAIN}"; do
		if [ -f "${NVRAM_DIR}/${f}" ] && cmp -s "${tmp}/${f}" "${NVRAM_DIR}/${f}"; then
			echo "ok: ${NVRAM_DIR}/${f} already correct"
		else
			cp -f "${tmp}/${f}" "${NVRAM_DIR}/${f}"
			echo "installed: ${NVRAM_DIR}/${f}"
			changed=1
		fi
	done

	# compatibility symlinks for the kernel's 4350c2 firmware naming
	local link target
	for link in "brcmfmac4350c2-pcie.Apple Inc.-MacBookPro14,1.txt:${F_APPLE}" \
		"brcmfmac4350c2-pcie.txt:${F_PLAIN}"; do
		target="${link#*:}"
		link="${link%%:*}"
		ln -sfn "${target}" "${NVRAM_DIR}/${link}"
		echo "symlink: ${NVRAM_DIR}/${link} -> ${target}"
		changed=1
	done

	rm -rf "${tmp}"
	trap - EXIT
	[ "${changed}" -eq 1 ] || echo "NVRAM already in place (symlinks refreshed)."
}

install_nm_conf() {
	local original current
	if [ -f "${NM_CONF}" ]; then
		original="$(cat "${NM_CONF}")"
	else
		original=""
	fi

	current="$(printf '%s' "${original}" | ensure_key connection wifi.powersave 2)"

	if [ "${current}" = "${original}" ]; then
		echo "ok: ${NM_CONF} already has wifi.powersave=2"
		return
	fi

	if [ -n "${original}" ]; then
		cp -a "${NM_CONF}" "${NM_CONF}.bak-$(date +%Y%m%d-%H%M%S)"
		echo "backup: ${NM_CONF}.bak-* created"
	fi

	if [ -z "${original}" ]; then
		printf '%b' "${NM_CONF_CONTENT}" | write_atomic "${NM_CONF}"
	else
		printf '%s' "${current}" | write_atomic "${NM_CONF}"
	fi
	echo "updated: ${NM_CONF} (wifi.powersave=2 under [connection])"
}

apply_runtime() {
	if [ -d /sys/class/net/wlan0 ]; then
		iw dev wlan0 set power_save off 2>/dev/null \
			&& echo "runtime: iw dev wlan0 set power_save off" \
			|| echo "note: could not set runtime power_save (iw may be missing)"
	else
		echo "note: no wlan0 interface present right now (will apply at NetworkManager reconnect)"
	fi
}

show_status() {
	echo "== MacBookPro14,1 Wi-Fi status (read-only) =="
	printf 'DMI product       : %s\n' "$(dmi_product)"
	echo "-- PCI --"
	lspci -nnk -d 14e4:43a3 2>/dev/null | head -n 4 || echo "  BCM4350 (14e4:43a3) NOT found"
	echo "-- firmware files --"
	for f in "${F_APPLE}" "${F_PLAIN}"; do
		if [ -f "${NVRAM_DIR}/${f}" ]; then
			printf '  %-58s %s bytes\n' "${f}" "$(wc -c <"${NVRAM_DIR}/${f}")"
		else
			printf '  %-58s MISSING\n' "${f}"
		fi
	done
	for l in "brcmfmac4350c2-pcie.Apple Inc.-MacBookPro14,1.txt" "brcmfmac4350c2-pcie.txt"; do
		if [ -L "${NVRAM_DIR}/${l}" ]; then
			printf '  symlink %-46s -> %s\n' "${l}" "$(readlink "${NVRAM_DIR}/${l}")"
		else
			printf '  symlink %-46s MISSING\n' "${l}"
		fi
	done
	echo "-- NetworkManager powersave --"
	if [ -f "${NM_CONF}" ]; then
		sed 's/^/  /' "${NM_CONF}"
	else
		echo "  ${NM_CONF} not present"
	fi
	echo "-- runtime --"
	if [ -d /sys/class/net/wlan0 ]; then
		iw dev wlan0 get power_save 2>/dev/null | sed 's/^/  /' || echo "  iw unavailable"
		iw dev wlan0 link 2>/dev/null | sed 's/^/  /' || true
	else
		echo "  no wlan0 interface"
	fi
	echo "-- roamoff check (should be absent) --"
	if grep -rqs 'roamoff' /etc/modprobe.d/ 2>/dev/null; then
		echo "  WARNING: roamoff option found in /etc/modprobe.d/ — not part of the validated setup"
	else
		echo "  no roamoff option configured (validated default)"
	fi
	echo "-- recent brcmfmac kernel log --"
	if command -v journalctl >/dev/null 2>&1 && journalctl -k -b --no-pager -n 1 >/dev/null 2>&1; then
		journalctl -k -b --no-pager 2>/dev/null \
			| grep -Ei 'brcmfmac|MMIO|4350|flowring|txstatus' | tail -n 12 \
			| sed 's/^/  /' || echo "  (no matching lines)"
	else
		echo "  kernel log not readable — rerun with: sudo ${0} --status"
	fi
}

uninstall() {
	echo "== removing files created by setup-wifi.sh =="
	local removed=0
	for f in "${F_APPLE}" "${F_PLAIN}" \
		"brcmfmac4350c2-pcie.Apple Inc.-MacBookPro14,1.txt" \
		"brcmfmac4350c2-pcie.txt"; do
		if [ -e "${NVRAM_DIR}/${f}" ] || [ -L "${NVRAM_DIR}/${f}" ]; then
			rm -f "${NVRAM_DIR}/${f}"
			echo "removed: ${NVRAM_DIR}/${f}"
			removed=1
		fi
	done

	if [ -f "${NM_CONF}" ]; then
		if cmp -s <(printf '%b' "${NM_CONF_CONTENT}") "${NM_CONF}"; then
			rm -f "${NM_CONF}"
			echo "removed: ${NM_CONF}"
			removed=1
		else
			echo "left in place: ${NM_CONF} differs from what this script writes (user config preserved)"
		fi
	fi

	[ "${removed}" -eq 1 ] || echo "nothing to remove."
	echo
	echo "Note: NetworkManager will reload the conf change on restart; a reboot"
	echo "or 'sudo systemctl restart NetworkManager' applies it.  The kernel"
	echo "module and driver are untouched."
}

# --- argument parsing --------------------------------------------------------
while [ $# -gt 0 ]; do
	case "${1}" in
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
		check_model
		check_pci
		install_nvram || die "NVRAM install failed (see manual instructions above)"
		install_nm_conf
		apply_runtime
		echo
		echo "Wi-Fi configuration applied. Verify with: sudo ${0} --status"
		;;
	status)
		show_status
		;;
	uninstall)
		uninstall
		;;
esac
