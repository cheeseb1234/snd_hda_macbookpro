# Audio — Cirrus CS8409 (snd_hda_macbookpro)

Internal speakers, headphones and the internal microphone on the
MacBookPro14,1 (A1708) are handled by a Cirrus CS8409 HDA codec.  The
`cs8409` codec support ships in the upstream kernel but is not configured
for Apple's speaker/amplifier wiring, so a patched module is built and
installed via DKMS.

This repository keeps the full upstream audio driver project
([davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro)),
unchanged, in the repository root.  The install scripts, DKMS metadata and
`patch_cirrus/` sources are the upstream project's files — this repository
only adds MacBookPro14,1 documentation and convenience wrappers around them.

## Known working configuration

Validated on **CachyOS / Arch Linux with the stock Arch kernel** using the
DKMS install path.

Example successful install (from the repository root):

```bash
sudo pacman -S --needed dkms gcc linux-headers make patch wget git
git clone https://github.com/cheeseb1234/snd_hda_macbookpro.git
cd snd_hda_macbookpro
sudo ./install.cirrus.driver.sh -i
```

or, via the project wrapper (same thing, from anywhere in the checkout):

```bash
sudo ./scripts/setup-audio.sh          # == install.cirrus.driver.sh -i
sudo ./scripts/setup-audio.sh -r      # remove the DKMS module
```

The DKMS module installs as `snd_hda_codec_cs8409` (module file
`snd-hda-codec-cs8409.ko.zst`), e.g.:

```
/usr/lib/modules/<kernel>/updates/dkms/snd-hda-codec-cs8409.ko.zst
```

DKMS rebuilds the module automatically for every kernel you install, so a
kernel update does not require re-running the installer.

## Verify it works

```bash
lsmod | grep cs8409                 # module should be loaded
aplay -l                            # CS8409/Apple device should be listed
```

The primary audio profile should be **Analogue Stereo Output** (or
**Analogue Stereo Duplex** if you want the internal microphone).  The
headphone jack is handled by the same codec; headset microphones are
supported but not fully integrated on the userland side (upstream status).

## Remove

```bash
sudo ./install.cirrus.driver.sh -r   # or: sudo ./scripts/setup-audio.sh -r
```

## Notes inherited from upstream

- The hardware device format is limited to 2/4 channel 44.1 kHz
  S24_LE/S32_LE; other formats/frequencies work through the default device.
- `hw:0,0` / `plughw:0,0` have **no volume control and are very loud** —
  use the default device.
- Internal speaker sound is duplicated across the 4 physical speakers
  (2× tweeter + 2× woofer) in Linux channel order.
- Recording level is low; amplify with PipeWire/PulseEffects if needed.
- The installer supports the kernel source layout change introduced in
  **6.17**; for older kernels it transparently calls
  `install.cirrus.driver.pre617.sh`.
- The upstream installer also supports Debian/Ubuntu, Fedora and Void for
  the audio driver.  The MacBookPro14,1 project targets Arch Linux/CachyOS
  first; other distros are not assumed for the surrounding docs.

See the upstream README (`README.md` in the repository root) and
`NOTES.md` for the driver's full behavior and limitations.
