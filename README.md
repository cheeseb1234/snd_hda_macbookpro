# Linux hardware fixes for the 2017 MacBook Pro 13" (MacBookPro14,1 / A1708)

A documented collection of fixes for hardware that does not work correctly
out of the box on Linux on the **2017 13-inch Intel MacBook Pro
(MacBookPro14,1 / A1708, non-T2)** — including CS8409/Cirrus audio,
BCM4350C0 Bluetooth, BCM4350 Wi-Fi, FaceTime HD camera, and suspend/resume
behavior, structured so touchpad and other fixes can be added later.

> **Validation scope:** every fix here was validated on a single
> MacBookPro14,1 / A1708 running CachyOS userspace with the stock Arch
> `linux` kernel (`7.1.8-arch1-3` during testing).  Do not assume results
> transfer to other machines/distros without re-validation.

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
| Wi-Fi | Working — board NVRAM + powersave disabled (see [docs/wifi.md](docs/wifi.md)) |
| Camera | Working — facetimehd DKMS + firmware, live capture verified (see [docs/camera.md](docs/camera.md)) |

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
| Wi-Fi BCM4350 (`14e4:43a3`) | ✅ Working — board NVRAM + powersave disabled |
| Wi-Fi cold boot | ✅ Working |
| Wi-Fi suspend/resume | ✅ Working |
| Wi-Fi roaming | ✅ Working — `roamoff` deliberately not used |
| FaceTime HD camera (`14e4:1570`) | ✅ Working — firmware + `facetimehd` DKMS |
| Camera live capture | ✅ Verified in VLC |
| Camera suspend/resume | ✅ Working on tested MacBookPro14,1 |
| Camera reboot/autoload | ✅ Working |
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

> ⚠️ **Do not confuse Bluetooth HCD with Wi-Fi NVRAM.**  The Wi-Fi fix
> installs board **NVRAM** `.txt` files for `brcmfmac` ([docs/wifi.md](docs/wifi.md)).
> Bluetooth **HCD** `.hcd` files are a different thing and are harmful on
> this machine's Bluetooth controller.  Never copy one into the other's
> firmware paths.

## Project layout

```
README.md
docs/
  audio.md            # CS8409 audio driver (DKMS) — install, verify, remove
  bluetooth.md        # BCM4350C0 UART — firmware warning, BlueZ reconnect fix
  wifi.md             # BCM4350 — board NVRAM, powersave off, no roamoff
  camera.md           # FaceTime HD — facetimehd DKMS, firmware, VLC verify
  suspend.md          # deep suspend, SPIT/BLTH wake configuration
  troubleshooting.md  # symptom → check/fix for audio, BT, Wi-Fi, camera, suspend
scripts/
  setup-audio.sh      # wrapper → install.cirrus.driver.sh -i (DKMS)
  setup-bluetooth.sh  # idempotent BlueZ reconnect-policy configurator
  setup-wifi.sh       # idempotent BCM4350 NVRAM + powersave configurator
  setup-camera.sh     # facetimehd deps/DKMS/video0 setup (AUR step is user-run)
  diagnose-bluetooth.sh  # read-only Bluetooth/ACPI diagnostic dump
  diagnose-hardware.sh   # read-only Wi-Fi + camera diagnostic dump
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

## Wi-Fi installation

The BCM4350 (`14e4:43a3`) works with the mainline `brcmfmac` driver once it
has the MacBookPro14,1 board NVRAM and power saving is off.  The script
downloads the NVRAM from the credited upstream source
(vrilutza/MacBookPro14.1 — not vendored here), installs it with the
required `4350c2` symlinks, and writes the NetworkManager powersave config
(merge-only, never clobbers unrelated user config):

```bash
sudo ./scripts/setup-wifi.sh            # idempotent install/configure
sudo ./scripts/setup-wifi.sh --status   # read-only verification
sudo ./scripts/setup-wifi.sh --uninstall  # remove only what the script added
```

**Roaming is validated and kept enabled** — `roamoff=1` is deliberately not
used.  The `no clm_blob` / `no txcap_blob` kernel messages are harmless and
not claimed as fixed.  Full details: [docs/wifi.md](docs/wifi.md).

## Camera installation

The Broadcom FaceTime HD camera (`14e4:1570`) uses the `facetimehd` DKMS
driver ([patjak/facetimehd](https://github.com/patjak/facetimehd)) plus the
`facetimehd-firmware` package.  The AUR build step is **user-controlled** —
the script never runs `makepkg` as root and does not assume `paru`/`yay`:

```bash
sudo ./scripts/setup-camera.sh          # repo deps + firmware/DKMS/video0 checks
sudo ./scripts/setup-camera.sh --status # read-only diagnostics
sudo ./scripts/setup-camera.sh --build-aur  # attempt AUR build as the normal user
sudo ./scripts/setup-camera.sh --uninstall  # remove camera packages/module
```

If the AUR packages are missing, the script prints exact commands to build
them in temporary clones as your normal user, then re-run it.  Validated:
`/dev/video0` created, `Apple Facetime HD` in V4L2, **live video verified
in VLC**, suspend/resume and reboot/autoload all working.  No
`/etc/modules-load.d` entry is needed.  Full details: [docs/camera.md](docs/camera.md).

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
- Wi-Fi: the `no clm_blob` / `no txcap_blob` kernel messages remain
  (harmless on the tested machine; not claimed as fixed).  Wi-Fi is not
  forced to 5 GHz — the tested machine correctly prefers stronger 2.4 GHz
  APs.
- Camera: the `Failed to lock S2 PLL: 0xc902c902` message during resume is
  **observed non-fatal** on the tested machine (reinit completes, video
  works) but is not a universal guarantee.  Expected benign boot messages:
  unsigned-DKMS taint/signature warnings.  `facetimehd-data` (optional
  calibration) is not installed by default.
- Touchpad tuning is not yet documented (planned).

## Troubleshooting

```bash
sudo ./scripts/diagnose-bluetooth.sh       # Bluetooth + ACPI + kernel log
sudo ./scripts/diagnose-hardware.sh        # Wi-Fi + camera + kernel log
lsmod | grep -E 'cs8409|hci_uart|btbcm|brcmfmac|facetimehd'   # relevant modules
cat /sys/power/mem_sleep                   # deep suspend state
grep -E 'SPIT|BLTH' /proc/acpi/wakeup      # wake sources
```

Symptom → fix tables for audio, Bluetooth, Wi-Fi, camera and suspend:
[docs/troubleshooting.md](docs/troubleshooting.md).

## Credits / upstream projects

- **[davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)**
  — the audio driver this repository forked from; all driver code, install
  scripts, DKMS metadata and patches are theirs (with contributions from
  leifliddy, BrewCoffeeeAdict, osalbahr and others in the git history).
- **[patjak/facetimehd](https://github.com/patjak/facetimehd)** — the
  FaceTime HD camera driver used here (via DKMS).  Firmware packaging and
  driver packaging for Arch are provided by the AUR maintainers of
  `facetimehd-firmware` and `facetimehd-dkms-git` — this project does not
  vendor the proprietary Apple camera firmware and claims no authorship of
  the driver, firmware extraction, or calibration work.
- **[vrilutza/MacBookPro14.1](https://github.com/vrilutza/MacBookPro14.1)**
  — source of the BCM4350 MacBookPro14,1 board NVRAM files (Wi-Fi fix) and
  of the firmware image used in Bluetooth HCD testing (result: controller
  failure — documented in [docs/bluetooth.md](docs/bluetooth.md)).  The
  NVRAM files are not vendored; they are fetched from this credited source
  during setup.
- Hardware validation of the MacBookPro14,1 fixes documented here performed
  on the author's machine.

## License

[GPL-2.0](LICENSE) — inherited from the upstream driver project.
