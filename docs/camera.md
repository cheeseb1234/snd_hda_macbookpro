# FaceTime HD Camera — Broadcom 720p (facetimehd)

The MacBookPro14,1 (A1708) has a **Broadcom 720p FaceTime HD Camera**
(PCI ID `14e4:1570`, PCI address `0000:03:00.0` during testing), driven by
the out-of-tree **facetimehd** DKMS driver (upstream project:
[patjak/facetimehd](https://github.com/patjak/facetimehd)) plus the
`facetimehd-firmware` package.

| Property | Value |
|---|---|
| Camera | Broadcom 720p FaceTime HD |
| PCI ID | `14e4:1570` |
| PCI address (tested) | `0000:03:00.0` |
| Driver | `facetimehd` (out-of-tree, DKMS) |
| Upstream | [patjak/facetimehd](https://github.com/patjak/facetimehd) |
| Firmware | `/usr/lib/firmware/facetimehd/firmware.bin` (~1.4 MiB) |
| V4L2 | `Apple Facetime HD` → `/dev/video0` |
| Validated on | CachyOS userspace, stock Arch `linux` kernel `7.1.8-arch1-3` |

Before the fix: no `/dev/video*` devices, no `facetimehd` module, no
FaceTime HD firmware installed.

## Prerequisites (Arch / CachyOS)

Repository packages:

```bash
sudo pacman -S --needed \
  base-devel git dkms linux-headers v4l-utils ffmpeg
```

AUR packages (built as the normal user — never `makepkg` as root):

- `facetimehd-firmware`
- `facetimehd-dkms-git`

Versions validated during testing (do **not** treat as permanent
requirements — they are what was tested):

- `facetimehd-firmware 1:1.43_5-2`
- `facetimehd-dkms-git 0.7.0.1.r7.g364b1c6-1`

The DKMS module installed for all locally installed kernels, including the
working stock Arch kernel:

```
facetimehd/... 7.1.8-arch1-3: installed
```

## Install

`scripts/setup-camera.sh` handles the repository packages and verification.
The AUR build step is **user-controlled** (the script never runs
`makepkg` as root and does not assume `paru`/`yay`):

```bash
sudo ./scripts/setup-camera.sh            # deps + firmware/DKMS/video0 checks
```

If the AUR packages are missing, the script prints exact commands to build
them in a temporary directory as your normal user, e.g.:

```bash
git clone https://aur.archlinux.org/facetimehd-firmware.git
cd facetimehd-firmware && makepkg -si        # as your normal user, not root
git clone https://aur.archlinux.org/facetimehd-dkms-git.git
cd facetimehd-dkms-git && makepkg -si
```

then re-run `sudo ./scripts/setup-camera.sh` to finish verification.

DKMS module path on the validated kernel:

```
/lib/modules/7.1.8-arch1-3/updates/dkms/facetimehd.ko.zst
```

## Functional validation

After loading the module:

```bash
sudo modprobe facetimehd
```

the system produced `/dev/video0` and:

```
Apple Facetime HD (PCI:0000:03:00.0):
    /dev/video0
```

V4L2 reported:

```
Driver name: facetimehd
Card type: Apple Facetime HD
Video input: Camera: ok
1296x736
YUYV
30 fps
```

**Actual live video was successfully viewed in VLC** — this is not merely a
successful module build; the camera was functionally tested.

## Suspend / resume

With `facetimehd` loaded:

- `/dev/video0` existed before suspend;
- the system entered deep suspend successfully;
- keyboard/trackpad wake still worked;
- `facetimehd` remained available after resume;
- `/dev/video0` returned/remained present;
- opening the camera again in VLC produced live video.

The log performs a hardware deinit/reinitialization during resume.  A
message may appear:

```
Failed to lock S2 PLL: 0xc902c902
```

On this specific tested MacBook this was **non-fatal**: immediately
afterward the driver completed

```
DDR40 PHY PLL locked on safe settings
Full memory verification succeeded!
Loaded firmware, size: 1392kb
ISP woke up
Enabling interrupts
```

and live video still worked.  Document this as an observed non-fatal
warning on the validated machine — **not** a universal guarantee for every
MacBookPro14,1.

## Reboot / autoload

After a full reboot, without manually running `modprobe`, `facetimehd` was
**automatically loaded** (normal PCI modalias/udev autoloading), `/dev/video0`
existed, V4L2 identified `Apple Facetime HD`, and live video worked.

Therefore: do **not** add `/etc/modules-load.d/facetimehd.conf`.

## Expected DKMS warnings

Boot may report:

```
facetimehd: loading out-of-tree module taints kernel
facetimehd: module verification failed: signature and/or required key missing - tainting kernel
```

This is **expected** for the tested unsigned out-of-tree DKMS module on
this configuration — do not mistake it for camera failure.  This project
does **not** disable kernel signature checking or Secure Boot as part of
the default fix.

## Optional: `facetimehd-data`

`facetimehd-data` (AUR) is optional sensor calibration data.  It was **not
needed** on this tested MacBook to obtain a normal, usable live image.
It is documented here only as optional/troubleshooting for image-quality
problems; it is **not** installed by default and **not** made mandatory.

## Uninstall / rollback

```bash
sudo ./scripts/setup-camera.sh --uninstall   # prints/executes removal steps
```

Manual:

```bash
sudo dkms remove facetimehd/<version> --all  # version from: dkms status
sudo modprobe -r facetimehd
sudo pacman -Rns facetimehd-dkms-git facetimehd-firmware
```

This only removes the camera packages/module — it does not touch the
audio driver, Bluetooth, Wi-Fi, or boot configuration.

## Troubleshooting

```bash
lspci -nnk | grep -A6 -iE '1570|camera|multimedia'   # device present?
lsmod | grep facetimehd                              # module loaded?
ls -l /dev/video*                                    # device node
v4l2-ctl --list-devices                               # V4L2 view
dkms status                                           # DKMS state

sudo journalctl -b -k --no-pager |
  grep -iE 'facetimehd|03:00.0|video0|firmware'
```

- **No `/dev/video0` after install** — confirm the firmware file exists
  (`ls -l /usr/lib/firmware/facetimehd/firmware.bin`), `dkms status` shows
  `facetimehd` installed for the running kernel, and
  `sudo modprobe facetimehd` reports errors in `journalctl -k`.
- **`facetimehd` not built for the current kernel** — kernel was updated
  after install; re-run the AUR package install (`facetimehd-dkms-git`
  rebuilds via DKMS) or `sudo ./scripts/setup-camera.sh`.
- **Poor image quality** — `facetimehd-data` (optional calibration) is the
  documented next step; it was not required on the validated machine.
- **Camera was working, then stopped after resume** — check the S2 PLL
  warning context; on the validated machine reinit succeeded and video
  worked.  If yours does not recover, capture the full
  `journalctl -k` resume section.
