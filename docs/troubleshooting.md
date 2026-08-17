# Troubleshooting — MacBookPro14,1 (A1708)

General rule: **run the diagnostics first, change one thing at a time, and
keep everything reversible.**  This machine dual-boots macOS via OpenCore
Legacy Patcher — none of the fixes here touch Apple EFI, OpenCore, macOS
partitions, the EFI boot configuration, GRUB, or partition tables.

## Audio

| Symptom | Check / fix |
|---|---|
| No sound after install | `lsmod \| grep cs8409`; re-run `sudo ./scripts/setup-audio.sh`; confirm the module path `/usr/lib/modules/$(uname -r)/updates/dkms/snd-hda-codec-cs8409.ko.zst` |
| `snd_hda_intel: Primary patch_cs8409 NOT FOUND trying APPLE` in dmesg | **Expected** — benign; the DKMS module still builds and loads |
| Kernel headers missing | `sudo pacman -S linux-headers` (match `uname -r`) |
| Build failed | Kernel version vs installer: 6.17+ uses the current script, older uses `install.cirrus.driver.pre617.sh` automatically |
| Very loud, no volume | You are using `hw:0,0`/`plughw:0,0` — use the default device instead |
| Low recording level | Expected (same level as macOS); amplify in PipeWire/PulseEffects |
| After a kernel update | DKMS should rebuild automatically; if not: `sudo ./scripts/setup-audio.sh` |

More detail: [audio.md](audio.md) and the upstream README in the repository
root.

## Bluetooth

The BCM4350C0 UART controller is sensitive to reinitialization — always use
the read-only diagnostic first:

```bash
sudo ./scripts/diagnose-bluetooth.sh
```

| Symptom | Check / fix |
|---|---|
| `failed to write update baudrate (-16)` / `Failed to set baudrate` | **Expected** — non-fatal *when chip identification continues and `hci0` appears* afterwards |
| `firmware Patch file not found ... brcm/BCM.hcd` | **Expected** — ROM firmware is the intended state |
| `hci_uart_bcm serial0-0: Unexpected ACPI gpio_int_idx: -1` / `Unexpected number of ACPI GPIOs: 0` / `No reset resource, using default baud rate` | **Expected** — benign ACPI resource warnings; controller still comes up |
| `command 0xfc18 tx timeout` / `failed to write update baudrate (-110)` / `Reset failed (-110)` | **Genuinely bad** — `bluetoothctl list` can be empty.  Reboot (Linux→Linux); NOT caused by and NOT fixed by the HCD.  See the cold-init caveat in [bluetooth.md](bluetooth.md) |
| Controller gone after installing an `.hcd` file | Remove `brcm/BCM.hcd` / `BCM4350C0.hcd` / `BCM2E7C.hcd` from `/usr/lib/firmware/brcm/` and reboot (see [bluetooth.md](bluetooth.md)) |
| No controller at all | `rfkill list bluetooth` (not blocked), `lsmod \| grep hci_uart`, `systemctl status bluetooth` |
| Device won't reconnect after boot/resume | Apply the BlueZ policy: `sudo ./scripts/setup-bluetooth.sh` then `sudo systemctl restart bluetooth` |
| Bluetooth mouse drops after suspend | Do **not** enable `BLTH`/hci0 wake — that causes this.  Keep them disabled (see [suspend.md](suspend.md)) |

The kernel log lines that matter (from `journalctl -k -b` or
`dmesg | grep -Ei 'hci0|BCM|bluetooth|baudrate'`):

- Healthy: `BCM4350C0 UART 37.4 MHz Gamay USI UHE`, `BCM (003.001.134) build 1532`
- Healthy (non-fatal): the -16 baudrate and missing-`BCM.hcd` lines
- Bad: `Patch command 4c01 failed (-110)`, `Reading local version info failed (-110)` — an external HCD was loaded; remove it

## Suspend / resume

| Symptom | Check / fix |
|---|---|
| Not suspending deeply | `cat /sys/power/mem_sleep` — `[deep]` should be selected; do not force `s2idle` |
| Keyboard/trackpad won't wake | `grep SPIT /proc/acpi/wakeup` — must be `S3 *enabled` |
| Bluetooth mouse wakes the machine (undesired) or drops across suspend | `grep BLTH /proc/acpi/wakeup` must be `S4 *disabled` and `/sys/class/bluetooth/hci0/device/power/wakeup` must be `disabled` |

## Where to collect evidence

When reporting an issue, attach the output of:

```bash
sudo ./scripts/diagnose-bluetooth.sh      # Bluetooth + ACPI + kernel log
lsmod | grep -E 'cs8409|hci_uart|btbcm'   # audio + BT modules
journalctl -b -p 3                        # errors from this boot
```
