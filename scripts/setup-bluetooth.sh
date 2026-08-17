#!/bin/bash
#
# setup-bluetooth.sh — MacBookPro14,1 (A1708) BCM4350C0 Bluetooth reconnect policy
#
# Configures BlueZ (/etc/bluetooth/main.conf) so paired HID devices
# (e.g. Logitech M720 Triathlon) reconnect automatically after reboot and
# after suspend/resume.  Validated on BlueZ 5.87 with an M720 on the
# BCM4350C0 UART controller.
#
# The controller keeps using its built-in ROM firmware — this script never
# installs BCM4350C0 HCD firmware (loading an external .hcd currently breaks
# the controller; see docs/bluetooth.md).
#
# Behavior guarantees:
#   * Idempotent — running it repeatedly never duplicates active [Policy]
#     entries and never changes already-correct values.
#   * Conservative — unrelated configuration and user-set values for
#     ReconnectAttempts/ReconnectIntervals are preserved; only missing keys
#     are added and only the HID/UUID list is extended (never replaced).
#   * Reversible — a timestamped backup of main.conf is created before any
#     modification; --uninstall restores the newest script-created backup.
#   * Non-destructive — does NOT touch firmware, rfkill, ACPI wake settings,
#     the hci_uart driver, or the Bluetooth controller itself.
#
# Usage:
#   sudo ./setup-bluetooth.sh                apply the reconnect policy
#   sudo ./setup-bluetooth.sh --status       show current [Policy] state (read-only)
#   sudo ./setup-bluetooth.sh --uninstall    restore the newest script backup
#   sudo ./setup-bluetooth.sh --restart      also restart the bluetooth service
#                                            after applying (takes effect at once)
#   sudo ./setup-bluetooth.sh -c /path/main.conf   use a different config file
#                                                  (testing only)
#
# Manual rollback (if no backup exists): edit /etc/bluetooth/main.conf and
# remove the ReconnectUUIDs / ReconnectAttempts / ReconnectIntervals lines
# from the [Policy] section, then restart bluetooth.

set -euo pipefail

CONF="${CONF:-/etc/bluetooth/main.conf}"
ACTION="apply"
DO_RESTART=0

# Known-good reconnect policy (validated on BlueZ 5.87 + Logitech M720).
# 00001124 is Bluetooth HID; 00001112 PnP info; 0000111f AVRCP target;
# 0000110a A2DP audio source; 0000110b A2DP audio sink.  Keeping the full
# validated list avoids surprises with other HID/audio peripherals.
readonly KNOWN_UUIDS=(
	"00001124-0000-1000-8000-00805f9b34fb"
	"00001112-0000-1000-8000-00805f9b34fb"
	"0000111f-0000-1000-8000-00805f9b34fb"
	"0000110a-0000-1000-8000-00805f9b34fb"
	"0000110b-0000-1000-8000-00805f9b34fb"
)
readonly DEFAULT_ATTEMPTS="7"
readonly DEFAULT_INTERVALS="1,2,4,8,16,32,64"

usage() {
	sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# policy_value KEY — read stdin, print the current value of KEY in [Policy]
# (last match wins; trailing/leading whitespace trimmed).
policy_value() {
	local key="$1"
	awk -v key="${key}" '
		/^[[:space:]]*\[/ { in_policy = ($0 ~ /^[[:space:]]*\[Policy\]/) }
		in_policy && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
			sub(/^[^=]*=[[:space:]]*/, "")
			gsub(/[[:space:]]+$/, "")
			print
		}
	'
}

# set_policy_key KEY VALUE — read stdin, print the same content with
# KEY=VALUE active inside the [Policy] section.  Replaces the key in place if
# already present (never duplicates), appends it to the section end if the
# section exists, or appends a new [Policy] section if it does not.
set_policy_key() {
	local key="$1" val="$2"
	awk -v key="${key}" -v val="${val}" '
		BEGIN { in_policy = 0; pol_seen = 0; key_seen = 0 }
		/^[[:space:]]*\[[^]]+\]/ {
			if (in_policy && !key_seen) { print key "=" val; key_seen = 1 }
			in_policy = ($0 ~ /^[[:space:]]*\[Policy\]/)
			if (in_policy) pol_seen = 1
			print
			next
		}
		in_policy && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
			print key "=" val
			key_seen = 1
			next
		}
		{ print }
		END {
			if (in_policy && !key_seen) print key "=" val
			if (!pol_seen) {
				if (NR > 0) print ""
				print "[Policy]"
				print key "=" val
			}
		}
	'
}

# next_uuid_list EXISTING — print EXISTING (whitespace normalized, empty
# entries dropped) with any KNOWN_UUIDS not already present appended.
# User-provided UUIDs are always preserved.
next_uuid_list() {
	local existing="$1" out="" part u
	local -a parts=()
	IFS=',' read -r -a parts <<<"${existing}" || true
	for part in "${parts[@]:-}"; do
		part="${part//[[:space:]]/}"
		[ -n "${part}" ] || continue
		out="${out:+${out},}${part}"
	done
	for u in "${KNOWN_UUIDS[@]}"; do
		case ",${out}," in
			*",${u},"*) ;;
			*) out="${out:+${out},}${u}" ;;
		esac
	done
	printf '%s\n' "${out}"
}

backup_conf() {
	local backup
	backup="${CONF}.bak-$(date +%Y%m%d-%H%M%S)"
	cp -a "${CONF}" "${backup}"
	echo "backup created: ${backup}"
}

write_conf() {
	# Replace $CONF atomically, preserving inode, ownership and permissions
	# of the original file (or creating a new one for new installs).
	local tmp="${CONF}.tmp.$$"
	trap 'rm -f "${tmp}"' EXIT
	cat >"${tmp}"
	cat "${tmp}" >"${CONF}"
	rm -f "${tmp}"
	trap - EXIT
}

apply_policy() {
	local original current uuid_current uuid_next
	local attempts_current intervals_current

	if [ ! -f "${CONF}" ]; then
		echo "note: ${CONF} does not exist yet — creating it with the reconnect policy."
		original=""
	else
		original="$(cat "${CONF}")"
	fi
	current="${original}"

	uuid_current="$(printf '%s' "${current}" | policy_value ReconnectUUIDs | tail -n 1)"
	uuid_next="$(next_uuid_list "${uuid_current}")"
	current="$(printf '%s' "${current}" | set_policy_key ReconnectUUIDs "${uuid_next}")"

	attempts_current="$(printf '%s' "${current}" | policy_value ReconnectAttempts | tail -n 1)"
	if [ -z "${attempts_current}" ]; then
		current="$(printf '%s' "${current}" | set_policy_key ReconnectAttempts "${DEFAULT_ATTEMPTS}")"
	else
		echo "note: ReconnectAttempts already set (${attempts_current}); leaving it untouched (validated value: ${DEFAULT_ATTEMPTS})"
	fi

	intervals_current="$(printf '%s' "${current}" | policy_value ReconnectIntervals | tail -n 1)"
	if [ -z "${intervals_current}" ]; then
		current="$(printf '%s' "${current}" | set_policy_key ReconnectIntervals "${DEFAULT_INTERVALS}")"
	else
		echo "note: ReconnectIntervals already set (${intervals_current}); leaving it untouched (validated value: ${DEFAULT_INTERVALS})"
	fi

	if [ "${current}" = "${original}" ]; then
		echo "no changes needed — reconnect policy already in place."
		echo "  ${CONF}"
	else
		[ -n "${original}" ] && backup_conf
		printf '%s\n' "${current}" | write_conf
		echo "updated: ${CONF}"
	fi

	echo
	echo "policy summary (${CONF}):"
	printf '%s\n' "${current}" | policy_value ReconnectUUIDs | tail -n 1 | sed 's/^/  ReconnectUUIDs=/'
	printf '%s\n' "${current}" | policy_value ReconnectAttempts | tail -n 1 | sed 's/^/  ReconnectAttempts=/'
	printf '%s\n' "${current}" | policy_value ReconnectIntervals | tail -n 1 | sed 's/^/  ReconnectIntervals=/'

	if [ "${DO_RESTART}" -eq 1 ]; then
		if command -v systemctl >/dev/null 2>&1; then
			systemctl restart bluetooth
			echo "bluetooth service restarted — the policy is active now."
		else
			echo "no systemd found — restart the bluetooth service manually to apply."
		fi
	else
		echo
		echo "apply it now (userspace only — does not touch the controller):"
		echo "  sudo systemctl restart bluetooth"
		echo "or simply reboot.  Paired/trusted HID devices will then auto-reconnect."
	fi
}

show_status() {
	if [ ! -f "${CONF}" ]; then
		echo "${CONF} does not exist — no BlueZ policy configured."
		exit 0
	fi
	local content
	content="$(cat "${CONF}")"
	echo "${CONF}:"
	echo
	echo "current [Policy] section:"
	printf '%s\n' "${content}" | awk '/^[[:space:]]*\[Policy\]/{p=1;next} /^[[:space:]]*\[/{p=0} p && NF && $0 !~ /^[[:space:]]*#/{print "  " $0}'
	echo
	echo "reconnect keys currently active:"
	printf '%s\n' "${content}" | policy_value ReconnectUUIDs | tail -n 1 | sed 's/^/  ReconnectUUIDs=/'
	printf '%s\n' "${content}" | policy_value ReconnectAttempts | tail -n 1 | sed 's/^/  ReconnectAttempts=/'
	printf '%s\n' "${content}" | policy_value ReconnectIntervals | tail -n 1 | sed 's/^/  ReconnectIntervals=/'
	echo
	echo "validated values for MacBookPro14,1 (BlueZ 5.87):"
	echo "  ReconnectUUIDs=00001124-0000-1000-8000-00805f9b34fb,... (HID first)"
	echo "  ReconnectAttempts=${DEFAULT_ATTEMPTS}"
	echo "  ReconnectIntervals=${DEFAULT_INTERVALS}"
}

uninstall_policy() {
	local latest
	latest="$(ls -1t "${CONF}".bak-* 2>/dev/null | head -n 1 || true)"
	if [ -z "${latest}" ]; then
		echo "no script-created backup found for ${CONF}."
		echo "manual rollback: remove the ReconnectUUIDs / ReconnectAttempts /"
		echo "ReconnectIntervals lines from the [Policy] section of ${CONF},"
		echo "then restart bluetooth."
		exit 1
	fi
	cp -a "${latest}" "${CONF}"
	echo "restored ${CONF} from ${latest}"
	echo "restart bluetooth to apply: sudo systemctl restart bluetooth"
}

# --- argument parsing --------------------------------------------------------
while [ $# -gt 0 ]; do
	case "${1}" in
		--status) ACTION="status" ;;
		--uninstall|--restore) ACTION="uninstall" ;;
		--restart) DO_RESTART=1 ;;
		-c|--config) CONF="${2:?--config needs a path}"; shift ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown option: ${1} (see --help)" ;;
	esac
	shift
done

require_root "$@"

if ! command -v bluetoothctl >/dev/null 2>&1; then
	echo "warning: bluetoothctl not found — is the bluez package installed?"
	echo "         sudo pacman -S bluez bluez-utils"
fi

case "${ACTION}" in
	apply) apply_policy ;;
	status) show_status ;;
	uninstall) uninstall_policy ;;
esac
