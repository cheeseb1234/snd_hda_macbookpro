# Linux hardware fixes for the 2017 MacBook Pro 13" (MacBookPro14,1 / A1708)

A documented collection of fixes for hardware that does not work correctly
out of the box on Linux on the **2017 13-inch Intel MacBook Pro
(MacBookPro14,1 / A1708, non-T2)** — including CS8409/Cirrus audio,
BCM4350C0 Bluetooth, and suspend/resume behavior, structured so Wi-Fi,
camera, touchpad and other fixes can be added later.

> This repository originated as a fork of
> **[davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)**,
> a kernel driver project for Cirrus CS8409 sound on Apple hardware.  The
> audio driver, its install scripts, DKMS metadata and source patches are
> the upstream project's work and are preserved unmodified in the repository
> root with full attribution.  The driver itself was authored by davidjo and
> contributors — not by this fork.  This project adds MacBookPro14,1
> hardware fixes and documentation around it.

## Supported hardware & environment

- **Machine:** 2017 MacBook Pro 13", model identifier `MacBookPro14,1`
  (board `A1708`), Intel, no T2 chip.
- **Distros:** Arch Linux / CachyOS are first-class.  Other distros may be
  documented where appropriate; no Ubuntu assumptions are made.
- **Dual-boot:** macOS via OpenCore Legacy Patcher — this project never
  touches Apple EFI, OpenCore, macOS partitions, EFI boot configuration,
  GRUB, or partition tables.

## Testing status

| Area | Status |
|---|---|
| Distro | CachyOS (userspace) |
| Kernel | Stock Arch `linux` **7.1.8-arch1-3** (not `linux-cachyos`); DKMS rebuilds per kernel |
| BlueZ | 5.87 |
| Audio driver | Build/install verified via DKMS; output-device testing not yet documented (see [docs/audio.md](docs/audio.md)) |
| Bluetooth | Working with ROM firmware + BlueZ policy (see [docs/bluetooth.md](docs/bluetooth.md)) |

## Hardware support matrix

| Component | Status |
|---|---|
| Audio (Cirrus CS8409) | ✅ Build/install verified (DKMS) — output-device testing ⏳ TBD |
| Bluetooth controller (BCM4350C0 UART) | ✅ Working (built-in ROM firmware) |
| Bluetooth HID reconnect | ✅ Working — BlueZ `[Policy]` fix |
| Bluetooth suspend/resume | ✅ Working |
| Bluetooth wake-from-suspend | ⛔ Intentionally disabled (causes drops) |
| Deep suspend | ✅ Working (`s2idle [deep]`) |
| Keyboard wake | ✅ Working (`SPIT`) |
| Trackpad wake | ✅ Working |
| Wi-Fi | ✅ Works — optimization TBD |
| FaceTime camera | ⏳ TBD |
| Touchpad tuning | ⏳ TBD |

## ⚠️ Bluetooth firmware warning — read before installing anything

**Do not install BCM4350C0 HCD firmware on this machine.**  Testing with a
valid firmware image (from vrilutza/MacBookPro14.1) caused the controller to
fail (`Patch command 4c01 failed (-110)`, no usable controller in
`bluetoothctl`).  Removing the external firmware restored functionality.
The controller works correctly from its built-in ROM firmware.

Never install (and remove if present):

- `/usr/lib/firmware/brcm/BCM.hcd`
- `/usr/lib/firmware/brcm/BCM4350C0.hcd`
- `/usr/lib/firmware/brcm/BCM2E7C.hcd`

See [docs/bluetooth.md](docs/bluetooth.md) for the full story and the
expected (non-fatal) boot log lines.

## Project layout

```
README.md
docs/
  audio.md            # CS8409 audio driver (DKMS) — install, verify, remove
  bluetooth.md        # BCM4350C0 UART — firmware warning, BlueZ reconnect fix
  suspend.md          # deep suspend, SPIT/BLTH wake configuration
  troubleshooting.md  # symptom → check/fix for audio, Bluetooth, suspend
scripts/
  setup-audio.sh      # wrapper → install.cirrus.driver.sh -i (DKMS)
  setup-bluetooth.sh  # idempotent BlueZ reconnect-policy configurator
  diagnose-bluetooth.sh  # read-only Bluetooth/ACPI diagnostic dump
# upstream audio driver files (preserved, do not move):
install.cirrus.driver.sh  dkms.conf  dkms.sh  patch_cirrus/  makefiles/  patches/  tests/
```

## Audio installation

The audio fix is the upstream
[snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) driver,
installed as a DKMS module.  **Verified:** DKMS build/install succeeds on
CachyOS with the stock Arch `linux` kernel `7.1.8-arch1-3`; the module
loads into the running kernel.  (Speaker/mic/headphone output testing is
not yet documented — see [docs/audio.md](docs/audio.md).)

```bash
sudo pacman -S --needed dkms gcc linux-headers make patch wget git
git clone https://github.com/cheeseb1234/snd_hda_macbookpro.git
cd snd_hda_macbookpro
sudo ./install.cirrus.driver.sh -i
```

or with the project wrapper (run from anywhere in the checkout):

```bash
sudo ./scripts/setup-audio.sh
```

The module installs as `snd_hda_codec_cs8409`
(`/usr/lib/modules/<kernel>/updates/dkms/snd-hda-codec-cs8409.ko.zst`) and
rebuilds automatically on kernel updates.  Remove with:

```bash
sudo ./scripts/setup-audio.sh -r
```

Details, verification commands and upstream notes: [docs/audio.md](docs/audio.md).

## Bluetooth installation / configuration

The BCM4350C0 UART controller works out of the box using its built-in ROM
firmware (the `-16` baudrate and missing-`BCM.hcd` messages in the boot log
are expected and non-fatal).  What needs configuration is **automatic HID
reconnection** (e.g. Logitech M720) after boot and suspend/resume:

```bash
sudo ./scripts/setup-bluetooth.sh        # idempotent; backs up main.conf
sudo systemctl restart bluetooth         # apply the userspace policy
```

`setup-bluetooth.sh` merges the validated HID reconnect UUIDs into
`/etc/bluetooth/main.conf` without duplicating entries or discarding your
existing configuration, and supports `--status`, `--uninstall` (restore
backup) and `--restart`.

Diagnose with the read-only tool:

```bash
sudo ./scripts/diagnose-bluetooth.sh
```

Full details: [docs/bluetooth.md](docs/bluetooth.md).

## Suspend / resume

Known-good state: **deep** suspend (`s2idle [deep]`), `SPIT` (keyboard /
trackpad) wake **enabled**, `BLTH` (Bluetooth) wake **disabled**, hci0
wake **disabled**.  The keyboard, trackpad and power button wake the
machine; the Bluetooth mouse does not wake it; the controller survives
suspend/resume and HID devices reconnect via the BlueZ policy — **no
systemd resume scripts are needed**.

Details: [docs/suspend.md](docs/suspend.md).

## Known limitations

- Audio hardware-output testing (speaker / microphone / headphone jack /
  audio quality) is **not yet documented** — only DKMS build/install is
  verified so far.
- Bluetooth wake-from-suspend is intentionally disabled (enabling it made
  the mouse drop its connection across suspend).
- External BCM4350C0 HCD firmware currently breaks the controller — ROM
  firmware only, until a compatible image is proven.
- A rare Bluetooth cold-init edge case (`command 0xfc18 tx timeout` /
  `BCM: Reset failed (-110)` — `bluetoothctl list` can be empty) has been
  seen occasionally.  No kernel patch is applied by default; a possible
  future research direction is an `hci_bcm` MacBookPro14,1-specific quirk
  (see [docs/bluetooth.md](docs/bluetooth.md)).
- Audio recording level is low (same as macOS); amplification recommended.
- Direct hardware ALSA devices (`hw:0,0`) have no volume control.
- Wi-Fi optimization, FaceTime camera support and touchpad tuning are not
  yet documented (planned).

## Troubleshooting

```bash
sudo ./scripts/diagnose-bluetooth.sh       # Bluetooth + ACPI + kernel log
lsmod | grep -E 'cs8409|hci_uart|btbcm'    # audio + Bluetooth modules
cat /sys/power/mem_sleep                   # deep suspend state
grep -E 'SPIT|BLTH' /proc/acpi/wakeup      # wake sources
```

Symptom → fix tables for audio, Bluetooth and suspend:
[docs/troubleshooting.md](docs/troubleshooting.md).

## Credits / upstream projects

- **[davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)**
  — the audio driver this repository forked from; all driver code, install
  scripts, DKMS metadata and patches are theirs (with contributions from
  leifliddy, BrewCoffeeeAdict, osalbahr and others in the git history).
- **[vrilutza/MacBookPro14.1](https://github.com/vrilutza/MacBookPro14.1)**
  — firmware image used in Bluetooth HCD testing; result (controller
  failure) is documented in [docs/bluetooth.md](docs/bluetooth.md).
- Hardware validation of the MacBookPro14,1 fixes documented here performed
  on the author's machine.

## License

[GPL-2.0](LICENSE) — inherited from the upstream driver project.
