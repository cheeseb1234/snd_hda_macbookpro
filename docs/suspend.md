# Suspend / Resume — MacBookPro14,1 (A1708)

## Sleep mode: deep (s2idle [deep])

The preferred sleep state on this machine is **deep** (`s2idle [deep]` in
`/sys/power/mem_sleep`).  Deep sleep works correctly and is the default —
**do not** switch the machine to s2idle as a permanent setting.  s2idle was
tried during testing but is unnecessary: keyboard/trackpad wake already
works with deep, so deep stays preferred for lower suspend power
consumption.

Check the current state:

```bash
cat /sys/power/mem_sleep     # e.g.: s2idle [deep]
```

## Known-good ACPI wake configuration

| Wake source | State |
|---|---|
| `SPIT` (keyboard / trackpad) | `S3 *enabled` |
| `BLTH` (Bluetooth) | `S4 *disabled` |

```bash
grep -E 'SPIT|BLTH' /proc/acpi/wakeup
```

Bluetooth controller wake permission:

```
/sys/class/bluetooth/hci0/device/power/wakeup  ->  disabled
```

## Resulting behavior

With this combination:

- The MacBook enters deep suspend.
- The built-in keyboard wakes it.
- The built-in trackpad wakes it.
- The power button wakes it.
- The Bluetooth mouse does **not** need permission to wake the computer.
- The Bluetooth controller survives suspend/resume.
- The M720 reconnects automatically after resume (BlueZ policy fix — see
  [bluetooth.md](bluetooth.md)).

## Why Bluetooth wake stays disabled (tested, rejected)

An experiment enabled both `BLTH` and the hci0 wake permission:

```bash
echo BLTH > /proc/acpi/wakeup
echo enabled > /sys/class/bluetooth/hci0/device/power/wakeup
```

This was **not desirable**: the Bluetooth mouse then lost its connection
across suspend and required manual reconnection.  The final working setup
therefore leaves:

```
BLTH                 disabled
hci0 power/wakeup    disabled
SPIT                 enabled
deep suspend         selected
```

**Do not persistently enable Bluetooth as a system wake source.**

## No resume scripts needed

Because BlueZ reconnect now works via the `[Policy]` configuration, **no**
systemd resume/suspend scripts are installed for Bluetooth.  If you
encounter a peripheral that does not reconnect after resume, first check
that the BlueZ policy is applied (see [bluetooth.md](bluetooth.md)) and that
the controller survived (run `scripts/diagnose-bluetooth.sh`) before
reaching for resume hooks.
