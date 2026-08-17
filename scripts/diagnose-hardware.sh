#!/bin/bash
#
# diagnose-hardware.sh — MacBookPro14,1 (A1708) Wi-Fi + camera diagnostics
#
# Read-only diagnostic dump for the BCM4350 Wi-Fi and FaceTime HD camera
# subsystems.  For Bluetooth/audio use scripts/diagnose-bluetooth.sh.
#
# NON-DESTRUCTIVE CONTRACT — this script MUST NOT:
#   * load/unload any module (facetimehd, brcmfmac, ...)
#   * change Wi-Fi power settings, roaming, or regulatory settings
#   * toggle rfkill
#   * modify firmware files or create symlinks
#   * modify /proc/acpi/wakeup or any power setting
#   * restart services
#
# Diagnostics are strictly passive.  Run as a normal user; some sections
# (kernel log) may need: sudo ./diagnose-hardware.sh

set -u   # note: no -e — every section should be attempted even if one fails

sep() {
	printf '\n==== %s ====\n' "$1"
}

not_found() {
	printf '  (not available: %s)\n' "$1"
}

sep "Kernel"
uname -r

sep "Mac model (DMI)"
for f in sys_vendor product_name product_version; do
	printf '  %-16s: ' "${f}"
	cat "/sys/class/dmi/id/${f}" 2>/dev/null || echo "n/a"
done

# ---------------------------------------------------------------- Wi-Fi ----
sep "Wi-Fi — PCI (BCM4350 14e4:43a3)"
lspci -nnk -d 14e4:43a3 2>/dev/null | head -n 4 || not_found "14e4:43a3"

sep "Wi-Fi — firmware files (brcm/)"
for f in \
	"brcmfmac4350-pcie.Apple Inc.-MacBookPro14,1.txt" \
	"brcmfmac4350-pcie.txt" \
	"brcmfmac4350c2-pcie.Apple Inc.-MacBookPro14,1.txt" \
	"brcmfmac4350c2-pcie.txt"; do
	p="/usr/lib/firmware/brcm/${f}"
	if [ -L "${p}" ]; then
		printf '  symlink  %-52s -> %s\n' "${f}" "$(readlink "${p}")"
	elif [ -f "${p}" ]; then
		printf '  file     %-52s %s bytes\n' "${f}" "$(wc -c <"${p}")"
	else
		printf '  MISSING  %s\n' "${f}"
	fi
done

sep "Wi-Fi — runtime state"
if [ -d /sys/class/net/wlan0 ]; then
	iw dev wlan0 get power_save 2>/dev/null | sed 's/^/  /' || not_found "iw power_save"
	iw dev wlan0 link 2>/dev/null | sed 's/^/  /' || not_found "iw link"
	iw reg get 2>/dev/null | sed 's/^/  /' || not_found "iw reg get"
else
	not_found "no wlan0 interface"
fi

sep "Wi-Fi — rfkill"
rfkill_out="$(rfkill list wifi 2>/dev/null)" || true
if [ -n "${rfkill_out}" ]; then
	printf '%s\n' "${rfkill_out}" | sed 's/^/  /'
else
	not_found "no wifi rfkill entries"
fi

sep "Wi-Fi — kernel log (brcmfmac / MMIO / 4350 / flowring / txstatus)"
if command -v journalctl >/dev/null 2>&1 && journalctl -k -b --no-pager -n 1 >/dev/null 2>&1; then
	lines="$(journalctl -k -b --no-pager 2>/dev/null \
		| grep -Ei 'brcmfmac|MMIO|4350|flowring|txstatus' || true)"
	if [ -n "${lines}" ]; then
		printf '%s\n' "${lines}" | tail -n 15 | sed 's/^/  /'
	else
		echo "  (no matching lines)"
	fi
else
	echo "  kernel log not readable — rerun with: sudo ${0}"
fi

# --------------------------------------------------------------- camera ----
sep "Camera — PCI (FaceTime HD 14e4:1570)"
lspci -nnk 2>/dev/null | grep -A6 -iE '1570|camera|multimedia' | sed 's/^/  /' || not_found "14e4:1570"

sep "Camera — firmware"
if [ -f /usr/lib/firmware/facetimehd/firmware.bin ]; then
	printf '  /usr/lib/firmware/facetimehd/firmware.bin: %s bytes\n' "$(wc -c </usr/lib/firmware/facetimehd/firmware.bin)"
else
	not_found "facetimehd firmware"
fi

sep "Camera — DKMS"
dkms status 2>/dev/null | grep -i 'facetimehd' | sed 's/^/  /' || not_found "facetimehd in dkms status"

sep "Camera — module & devices"
lsmod | grep '^facetimehd' | sed 's/^/  /' || echo "  module not loaded"
ls -l /dev/video* 2>/dev/null | sed 's/^/  /' || not_found "/dev/video*"
if command -v v4l2-ctl >/dev/null 2>&1; then
	v4l2-ctl --list-devices 2>/dev/null | sed 's/^/  /' || not_found "v4l2-ctl --list-devices"
else
	not_found "v4l2-ctl (install v4l-utils)"
fi

sep "Camera — kernel log (facetimehd / 03:00.0 / video0 / firmware)"
if command -v journalctl >/dev/null 2>&1 && journalctl -k -b --no-pager -n 1 >/dev/null 2>&1; then
	lines="$(journalctl -k -b --no-pager 2>/dev/null \
		| grep -Ei 'facetimehd|03:00.0|video0|firmware' || true)"
	if [ -n "${lines}" ]; then
		printf '%s\n' "${lines}" | tail -n 15 | sed 's/^/  /'
	else
		echo "  (no matching lines)"
	fi
else
	echo "  kernel log not readable — rerun with: sudo ${0}"
fi

echo
echo "Note: this script is read-only. Nothing was loaded, unloaded, changed,"
echo "or restarted.  For Bluetooth/audio diagnostics run:"
echo "  sudo ./scripts/diagnose-bluetooth.sh"
