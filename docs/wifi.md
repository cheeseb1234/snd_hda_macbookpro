# Wi-Fi — Broadcom BCM4350/5 (brcmfmac)

The MacBookPro14,1 (A1708) has a Broadcom BCM4350/5 PCIe Wi-Fi adapter
(PCI ID `14e4:43a3`, Apple subsystem) driven by the mainline `brcmfmac`
driver.  Do **not** replace `brcmfmac` with `b43` or `broadcom-wl`.

| Property | Value |
|---|---|
| Controller | Broadcom BCM4350/5 |
| PCI ID | `14e4:43a3` (Apple subsystem) |
| Driver | mainline `brcmfmac` (do not swap for `b43`/`broadcom-wl`) |
| Firmware naming | `brcmfmac4350c2-pcie` (reported by the running driver) |
| NVRAM source | [vrilutza/MacBookPro14.1](https://github.com/vrilutza/MacBookPro14.1) board-specific NVRAM |
| Validated on | CachyOS userspace, stock Arch `linux` kernel `7.1.8-arch1-3` |

The running driver reports:

```
brcmf_fw_alloc_request: using brcm/brcmfmac4350c2-pcie for chip BCM4350/5
```

## Validated configuration (two changes)

### 1. Disable NetworkManager Wi-Fi power saving

Wi-Fi power saving is disabled so the adapter does not drop into low-power
states that hurt throughput/latency.  Persistent config:

```ini
# /etc/NetworkManager/conf.d/99-wifi-powersave-off.conf
# MacBookPro14,1 BCM4350
[connection]
wifi.powersave=2
```

Runtime equivalent used during testing:

```bash
sudo iw dev wlan0 set power_save off
```

Verified after reboot:

```
Power save: off
```

### 2. Install MacBookPro14,1 board-specific NVRAM

The BCM4350 needs the Apple board NVRAM to configure antenna/band
settings correctly.  The files are taken from
[vrilutza/MacBookPro14.1](https://github.com/vrilutza/MacBookPro14.1)
(`firmware/wifi/`); this project does **not** vendor the Apple-derived
files directly, so the setup script downloads them from that credited
upstream source (or prints exact manual instructions if unavailable).

Installed as:

```
/usr/lib/firmware/brcm/brcmfmac4350-pcie.Apple Inc.-MacBookPro14,1.txt
/usr/lib/firmware/brcm/brcmfmac4350-pcie.txt
```

plus two compatibility symlinks required by the current kernel's `4350c2`
firmware naming:

```
/usr/lib/firmware/brcm/brcmfmac4350c2-pcie.Apple Inc.-MacBookPro14,1.txt -> brcmfmac4350-pcie.Apple Inc.-MacBookPro14,1.txt
/usr/lib/firmware/brcm/brcmfmac4350c2-pcie.txt                      -> brcmfmac4350-pcie.txt
```

### Do NOT set `roamoff=1`

Roaming was explicitly tested on a multi-AP enterprise network: the
MacBook successfully moved between BSSIDs across normal use and
suspend/resume.  This project deliberately:

- preserves normal roaming;
- does **not** add `options brcmfmac roamoff=1` to `/etc/modprobe.d/`;
- documents that older MacBook guides may recommend `roamoff=1`, but it is
  **not** part of this validated setup.

## Known harmless Wi-Fi messages

These lines may appear in the kernel log and are **not** blocking:

```
brcmf_c_process_clm_blob: no clm_blob available (err=-2)
brcmf_c_process_txcap_blob: no txcap_blob available (err=-2)
```

This project does **not** claim these are fixed.  Despite them, testing
confirmed:

- 2.4 GHz works;
- 5 GHz networks are visible;
- DFS/channel scanning works sufficiently for the tested environment;
- cold boot works;
- suspend/resume works;
- roaming works;
- power saving remains off;
- no recurring `MMIO read failed: 0xffffffff`;
- no recurring probe failures;
- no recurring `flowring ... timed out waiting for txstatus` during
  validation.

Note: the machine is **not forced to 5 GHz** — during testing it correctly
preferred a much stronger 2.4 GHz AP when nearby 5 GHz radios were
substantially weaker.

## Apply

```bash
sudo ./scripts/setup-wifi.sh              # idempotent install/configure
sudo ./scripts/setup-wifi.sh --status     # read-only verification
sudo ./scripts/setup-wifi.sh --uninstall  # remove only what the script added
```

The script verifies the model (DMI `MacBookPro14,1`) and the BCM4350 PCI
ID (`14e4:43a3`), installs the NVRAM files and symlinks, writes the
NetworkManager powersave config (merging, never clobbering unrelated user
config), and never installs a replacement Broadcom driver or `roamoff`.

## Verification commands

```bash
lspci -nnk -s 02:00.0                     # BCM4350 + brcmfmac driver
iw dev wlan0 get power_save               # expect: Power save: off
iw dev wlan0 link                         # current BSSID/SSID
iw reg get                                # regulatory domain

sudo journalctl -b -k --no-pager |
  grep -iE 'brcmfmac|MMIO|4350|flowring|txstatus'
```

## Troubleshooting

- **Wi-Fi not working after a kernel update** — the NVRAM files and
  symlinks persist; re-check with `scripts/setup-wifi.sh --status`.  If
  files were removed, re-run `sudo ./scripts/setup-wifi.sh`.
- **No `wlan0`** — `lspci -nnk -s 02:00.0` must show `Kernel driver in use:
  brcmfmac`; check `rfkill list wifi`; verify the `4350c2` symlinks exist.
- **NVRAM download failed during setup** — the script prints exact manual
  steps; the source is the credited `vrilutza/MacBookPro14.1` repository.
- **A guide tells you to install `broadcom-wl` or set `roamoff=1`** — both
  are contradicted by this validated setup; do not apply them.

## ⚠️ Do not confuse Wi-Fi NVRAM with Bluetooth HCD firmware

This Wi-Fi fix installs **board NVRAM** (`.txt` files + symlinks) for the
`brcmfmac` Wi-Fi driver.  It is completely separate from the **Bluetooth
BCM4350C0 HCD firmware** (`.hcd` files) which is documented as harmful on
this machine's Bluetooth controller (see [bluetooth.md](bluetooth.md)).
Never copy `.hcd` files into the Wi-Fi firmware paths or vice versa.
