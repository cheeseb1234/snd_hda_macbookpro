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

## Wi-Fi

| Symptom | Check / fix |
|---|---|
| No `wlan0` after boot | `lspci -nnk -s 02:00.0` must show `Kernel driver in use: brcmfmac`; `rfkill list wifi`; verify the NVRAM files and `4350c2` symlinks via `sudo ./scripts/setup-wifi.sh --status` |
| `no clm_blob available (err=-2)` / `no txcap_blob available (err=-2)` | **Expected** — harmless; not claimed as fixed (see [wifi.md](wifi.md)) |
| Power saving still on | `iw dev wlan0 get power_save`; re-apply `sudo ./scripts/setup-wifi.sh` (writes the NetworkManager conf) |
| Roaming not working / a guide says `roamoff=1` | Roaming is validated on this machine — do **not** set `roamoff=1`; remove it if present (`grep -r roamoff /etc/modprobe.d/`) |
| NVRAM download failed during setup | Follow the manual instructions printed by `setup-wifi.sh`; source is vrilutza/MacBookPro14.1 (credited) |
| `MMIO read failed: 0xffffffff` / recurring probe failures / `flowring ... timed out waiting for txstatus` | **Not** seen during validation — if they appear, capture `journalctl -k -b \| grep -iE 'brcmfmac|MMIO|4350|flowring|txstatus'` and report |

## Camera (facetimehd)

| Symptom | Check / fix |
|---|---|
| No `/dev/video0` | `lsmod \| grep facetimehd`; `dkms status` (installed for the running kernel); firmware exists (`ls -l /usr/lib/firmware/facetimehd/firmware.bin`); then `sudo modprobe facetimehd` |
| `facetimehd: loading out-of-tree module taints kernel` / `module verification failed: signature and/or required key missing` | **Expected** for the unsigned DKMS module — not a camera failure |
| `Failed to lock S2 PLL: 0xc902c902` during resume | **Observed non-fatal** on the validated machine — reinit completes (`DDR40 PHY PLL locked`, `Loaded firmware`), video works.  Not guaranteed universal; capture the full resume log if yours does not recover |
| AUR packages missing | Build `facetimehd-firmware` + `facetimehd-dkms-git` as your normal user (see [camera.md](camera.md)) — never `makepkg` as root |
| Poor image quality | Optional: install `facetimehd-data` (calibration) — was **not** needed on the validated machine |
| Camera worked, stopped after resume | Check the S2 PLL context in `journalctl -k`; on the validated machine live video continued to work |

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
sudo ./scripts/diagnose-hardware.sh       # Wi-Fi + camera + kernel log
lsmod | grep -E 'cs8409|hci_uart|btbcm|brcmfmac|facetimehd'   # relevant modules
journalctl -b -p 3                        # errors from this boot
```
