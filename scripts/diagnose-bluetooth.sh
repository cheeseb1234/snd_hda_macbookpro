#!/bin/bash
#
# diagnose-bluetooth.sh — MacBookPro14,1 (A1708) BCM4350C0 Bluetooth diagnostics
#
# Read-only diagnostic dump for the Broadcom BCM4350C0 UART Bluetooth
# controller (ACPI BCM2E7C / BLTH, hci_uart transport).  Prints the state of
# the controller, BlueZ, ACPI wake settings and the relevant kernel log lines
# so issues can be reported or debugged without touching the hardware.
#
# NON-DESTRUCTIVE CONTRACT — this script MUST NOT:
#   * unload hci_uart (or any module)
#   * reset or reinitialize the controller
#   * toggle rfkill
#   * modify /proc/acpi/wakeup or any power/wakeup setting
#   * install firmware
#   * restart or stop Bluetooth services
#
# The BCM4350 controller is sensitive to reinitialization; diagnostics are
# deliberately passive.  Run as a normal user; some sections (kernel log)
# may need: sudo ./diagnose-bluetooth.sh

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

sep "BlueZ tools"
if command -v bluetoothctl >/dev/null 2>&1; then
	bluetoothctl --version
else
	not_found "bluetoothctl (bluez package)"
fi

sep "Controllers (bluetoothctl list)"
bluetoothctl list 2>/dev/null || not_found "no controller listed"

sep "Paired devices"
bluetoothctl devices Paired 2>/dev/null || not_found "none"

sep "Trusted devices"
bluetoothctl devices Trusted 2>/dev/null || not_found "none"

sep "Connected devices"
bluetoothctl devices Connected 2>/dev/null || not_found "none"

sep "rfkill — Bluetooth"
rfkill_out="$(rfkill list bluetooth 2>/dev/null)" || true
if [ -n "${rfkill_out}" ]; then
	printf '%s\n' "${rfkill_out}"
else
	not_found "no bluetooth rfkill entries (soft/hard block state unknown)"
fi

sep "Bluetooth kernel modules (hci_uart / btbcm / btusb / bluetooth)"
if lsmod 2>/dev/null | grep -E 'hci_uart|btbcm|btusb|bluetooth'; then
	:
else
	not_found "no bluetooth-related modules loaded"
fi

sep "Sleep mode (/sys/power/mem_sleep)"
cat /sys/power/mem_sleep 2>/dev/null || not_found "mem_sleep"

sep "ACPI wake sources (SPIT=keyboard/trackpad, BLTH=bluetooth)"
grep -E 'SPIT|BLTH' /proc/acpi/wakeup 2>/dev/null || not_found "no SPIT/BLTH entries"

sep "hci power/wakeup (controller wake permission)"
found=0
for dev in /sys/class/bluetooth/hci*/device; do
	[ -e "${dev}" ] || continue
	found=1
	printf '  %s -> ' "${dev}"
	cat "${dev}/power/wakeup" 2>/dev/null || echo "n/a"
done
[ "${found}" -eq 1 ] || not_found "no hci device dir"

sep "Kernel log — hci_uart / hci0 / BCM / bluetooth / baudrate / firmware Patch"
if command -v journalctl >/dev/null 2>&1 && journalctl -k -b --no-pager -n 1 >/dev/null 2>&1; then
	journalctl -k -b --no-pager 2>/dev/null \
		| grep -Ei 'hci_uart|hci0|BCM|bluetooth|baudrate|firmware Patch' \
		|| echo "  (no matching kernel log lines)"
elif command -v dmesg >/dev/null 2>&1 && dmesg 2>/dev/null | head -n 1 >/dev/null; then
	dmesg 2>/dev/null \
		| grep -Ei 'hci_uart|hci0|BCM|bluetooth|baudrate|firmware Patch' \
		|| echo "  (no matching kernel log lines)"
else
	echo "  kernel log not readable — rerun with: sudo ${0}"
fi

echo
echo "Note: this script is read-only. Nothing was loaded, unloaded, reset,"
echo "modified, or restarted. Expected non-fatal lines:"
echo "  - 'BCM: failed to write update baudrate (-16)'"
echo "  - 'BCM: firmware Patch file not found ... brcm/BCM.hcd'"
echo "  - 'BCM4350C0 UART 37.4 MHz Gamay USI UHE' / 'BCM (003.001.134) build 1532'"
