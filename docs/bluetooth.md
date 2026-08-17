# Bluetooth — Broadcom BCM4350C0 (UART)

The MacBookPro14,1 (A1708) has a **Broadcom BCM4350C0 UART Bluetooth
controller** — it is *not* a USB adapter, so `btusb` never binds to it.

| Property | Value |
|---|---|
| Controller | Broadcom BCM4350C0 |
| Transport | UART (`hci_uart` / `hci_uart_bcm` / `btbcm`) |
| ACPI device | `serial0-0` (UART node in kernel messages) |
| ACPI IDs / wake entries | `BCM2E7C` / `BLTH` (see [suspend.md](suspend.md)) |
| Observed address | `8C:85:90:99:F4:5B` (controller during testing) |
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

- **`failed to write update baudrate (-16)` / `Failed to set baudrate`** —
  **non-fatal on this machine** *when chip identification continues and
  `hci0` appears* afterwards.  The controller works fine with the default
  UART baudrate.
- **`firmware Patch file not found ... brcm/BCM.hcd`** — **non-fatal**.
  The controller runs from its built-in ROM firmware.  This message simply
  means no external patch file is loaded, which is the *desired* state.
- **ACPI resource warnings** — benign on their own and **not** a sign of a
  nonfunctional controller:
  ```
  hci_uart_bcm serial0-0: Unexpected ACPI gpio_int_idx: -1
  hci_uart_bcm serial0-0: Unexpected number of ACPI GPIOs: 0
  hci_uart_bcm serial0-0: No reset resource, using default baud rate
  ```
  These appear during normal init; the controller still comes up.

Do **not** try to "fix" the -16 warning by installing the external HCD
firmware — that makes things *worse* (next section).

### This failure state IS genuinely bad

The following sequence indicates real trouble, not a benign warning —
`bluetoothctl list` can be empty in this state:

```
command 0xfc18 tx timeout
Bluetooth: hci0: BCM: failed to write update baudrate (-110)
Bluetooth: hci0: BCM: Reset failed (-110)
```

A Linux → Linux reboot generally brings the controller back healthy.
See the cold-init caveat below.

## ⚠️ Do NOT install BCM4350C0 HCD firmware

> Some MacBookPro14,1 hardware-support guides (including the
> vrilutza/MacBookPro14.1 project this repository's testing borrowed
> firmware from) **recommend installing this HCD**.  That recommendation is
> **contradicted by our testing on this machine** — see below.  The
> BCM4350C0 works from its built-in ROM firmware; the external patch is
> neither needed nor safe on our tested configuration.

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
Triathlon** (observed address `C9:B5:B0:4B:C7:19`, already paired, bonded
and trusted) initially required a manual `Connect` after boot.  Adding the
HID service UUID to BlueZ's reconnect policy fixed automatic reconnection.

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

## Reboot / suspend behavior observed

Bluetooth was exercised across:

- **Linux → Linux reboot** — produced a valid controller despite the benign
  `-16` baud-rate warning; no macOS boot in between.
- **suspend → resume** — controller survives; M720 reconnects automatically
  via the BlueZ policy (see [suspend.md](suspend.md)).

## Cold-init caveat (research / future work)

Earlier in troubleshooting, occasional bad initialization was observed with:

```
command 0xfc18 tx timeout
failed to write update baudrate (-110)
Reset failed (-110)
```

This is a real edge case, but:

- it is **not** fixed by the external HCD (which makes things worse);
- current repeated operation is stable enough that **no kernel patch is
  applied by default**;
- we do **not** claim this hardware/driver cold-init edge case has been
  proven impossible forever.

Future investigation direction (clearly **research, not a tested patch**): a
`hci_bcm` MacBookPro14,1-specific quirk, such as avoiding an early baud-rate
transition on this controller.  If that direction is ever pursued, it must
remain opt-in until proven across many boots.

## What this project deliberately does NOT do

- No `broadcom-wl` driver.
- No blacklisting of `hci_uart`.
- No `btusb` configuration for this UART controller.
- No external HCD firmware.
- No Bluetooth wake-from-suspend (see [suspend.md](suspend.md)).
