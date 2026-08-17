# Bluetooth — Broadcom BCM4350C0 (UART)

The MacBookPro14,1 (A1708) has a **Broadcom BCM4350C0 UART Bluetooth
controller** — it is *not* a USB adapter, so `btusb` never binds to it.

| Property | Value |
|---|---|
| Controller | Broadcom BCM4350C0 |
| Transport | UART (`hci_uart` / `hci_uart_bcm` / `btbcm`) |
| ACPI device | `BCM2E7C` / `BLTH` |
| Firmware | **built-in ROM** (do **not** install external HCD) |
| Identifies as | `BCM4350C0 UART 37.4 MHz Gamay USI UHE` |
| Version string | `BCM (003.001.134) build 1532` |
| Validated with | BlueZ 5.87, Arch Linux / CachyOS |

## Normal working boot log

A healthy boot produces these kernel messages (the two "error-looking" lines
are **expected**):

```
Bluetooth: hci0: BCM: failed to write update baudrate (-16)
Bluetooth: hci0: Failed to set baudrate
Bluetooth: hci0: BCM: chip id 92
Bluetooth: hci0: BCM: features 0x2f
Bluetooth: hci0: BCM4350C0 UART 37.4 MHz Gamay USI UHE
Bluetooth: hci0: BCM (003.001.134) build 1532
Bluetooth: hci0: BCM: firmware Patch file not found, tried:
Bluetooth: hci0: BCM: 'brcm/BCM.hcd'
```

### Non-fatal warnings — do not chase these

- **`failed to write update baudrate (-16)`** — the -16 baudrate warning is
  **non-fatal on this machine**.  The controller works fine with the
  default UART baudrate.
- **`firmware Patch file not found ... brcm/BCM.hcd`** — **non-fatal**.
  The controller runs from its built-in ROM firmware.  This message simply
  means no external patch file is loaded, which is the *desired* state.

## ⚠️ Do NOT install BCM4350C0 HCD firmware

Loading an external `.hcd` patch file **breaks the controller** on this
machine.  This was tested with the BCM4350C0 firmware from
[vrilutza/MacBookPro14.1](https://github.com/vrilutza/MacBookPro14.1): the
firmware file itself was valid and Linux found it, but loading it caused the
controller to fail:

```
Bluetooth: hci0: BCM 'brcm/BCM.hcd' Patch
Bluetooth: hci0: command 0x4c01 tx timeout
Bluetooth: hci0: BCM: Patch command 4c01 failed (-110)
Bluetooth: hci0: BCM: Patch failed (-110)
Bluetooth: hci0: BCM: failed to write update baudrate (-110)
Bluetooth: hci0: command 0x1001 tx timeout
Bluetooth: hci0: BCM: Reading local version info failed (-110)
```

`bluetoothctl` then showed no usable controller.  Removing the external HCD
firmware restored working Bluetooth.

**Therefore: never install any of these files as part of an automated fix:**

- `/usr/lib/firmware/brcm/BCM.hcd`
- `/usr/lib/firmware/brcm/BCM4350C0.hcd`
- `/usr/lib/firmware/brcm/BCM2E7C.hcd`

Use the controller's built-in ROM firmware.  If one of these files already
exists (e.g. from another guide), remove it and reboot:

```bash
sudo rm -f /usr/lib/firmware/brcm/BCM.hcd \
           /usr/lib/firmware/brcm/BCM4350C0.hcd \
           /usr/lib/firmware/brcm/BCM2E7C.hcd
sudo reboot
```

This project will not automate HCD installation unless future testing proves
a compatible image exists.

## HID reconnect fix (BlueZ policy)

Bluetooth itself works reliably on BlueZ 5.87, but a **Logitech M720
Triathlon** (already paired, bonded and trusted) initially required a manual
`Connect` after boot.  Adding the HID service UUID to BlueZ's reconnect
policy fixed automatic reconnection.

The validated `/etc/bluetooth/main.conf` `[Policy]` configuration:

```ini
[Policy]
ReconnectUUIDs=00001124-0000-1000-8000-00805f9b34fb,00001112-0000-1000-8000-00805f9b34fb,0000111f-0000-1000-8000-00805f9b34fb,0000110a-0000-1000-8000-00805f9b34fb,0000110b-0000-1000-8000-00805f9b34fb
ReconnectAttempts=7
ReconnectIntervals=1,2,4,8,16,32,64
```

(`00001124` is Bluetooth HID.  The other UUIDs cover common input/audio
profiles used with this machine.)

After this change the M720 automatically reconnects after **reboot** and
after **suspend/resume**.

### Apply it

```bash
sudo ./scripts/setup-bluetooth.sh            # apply (idempotent)
sudo systemctl restart bluetooth             # activate userspace policy
```

The script:

- backs up `/etc/bluetooth/main.conf` to
  `main.conf.bak-<timestamp>` before any modification;
- merges the validated HID UUIDs into an existing `ReconnectUUIDs` list
  **without removing user-supplied UUIDs** and without duplicating entries;
- leaves an existing `ReconnectAttempts` / `ReconnectIntervals` untouched if
  the user already set values (and reports the validated defaults);
- never overwrites the whole file and is safe to re-run.

Other options:

```bash
sudo ./scripts/setup-bluetooth.sh --status        # read-only preview
sudo ./scripts/setup-bluetooth.sh --uninstall     # restore newest backup
sudo ./scripts/setup-bluetooth.sh --restart       # apply + restart service
```

Manual rollback: remove the three `Reconnect*` lines from the `[Policy]`
section of `/etc/bluetooth/main.conf` (or restore your own backup) and
restart bluetooth.

## Diagnostics

```bash
sudo ./scripts/diagnose-bluetooth.sh
```

Prints the kernel version, DMI model, BlueZ version, controller list,
paired/trusted/connected devices, rfkill state, bluetooth kernel modules,
sleep mode, ACPI wake entries, hci0 wake permission, and the relevant
kernel log lines.  The script is strictly **read-only** — it never unloads
`hci_uart`, resets the controller, toggles rfkill, modifies ACPI wake
settings, installs firmware, or restarts Bluetooth (the BCM4350 is
sensitive to reinitialization).

## What this project deliberately does NOT do

- No `broadcom-wl` driver.
- No blacklisting of `hci_uart`.
- No `btusb` configuration for this UART controller.
- No external HCD firmware.
- No Bluetooth wake-from-suspend (see [suspend.md](suspend.md)).
