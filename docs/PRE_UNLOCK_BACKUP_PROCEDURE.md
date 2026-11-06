# Pre-Unlock Calibration Backup Procedure — Lenovo TB-8505X

> [!IMPORTANT]
> **Safety Rule:** Never execute `fastboot flashing unlock`, root, or flash any partition before completing and validating this backup. Unique radio calibration data (`nvram`, `nvdata`, `proinfo`) cannot be recovered from factory firmware images.

---

## 1. Verified Physical Connection Procedure

Empirically confirmed from practical hardware research on this exact tablet (`references/docs/01-firmware-and-backup.md:59`):

### Why Volume Up + Volume Down?
- **Power + Volume Down Only:** Enters Little Kernel Fastboot mode or Android Safe Mode.
- **Power + Volume Up Only:** Enters Little Kernel Android Recovery mode.
- **Volume Up + Volume Down (Power OFF):** Hardware strap pins the SoC GPIO boot mode selection lines, forcing the MediaTek MT6761 Boot ROM into USB download mode (`0E8D:0003`) before the eMMC preloader executes.

### Step-by-Step Connection Flow:
1. Ensure the tablet has at least 50% battery (currently verified at **3874 mV**).
2. If currently in Fastboot mode, issue:
   ```bash
   fastboot reboot-bootloader # or hold power for 10 seconds to power down
   ```
3. Disconnect the USB cable.
4. Ensure the tablet is completely powered **OFF** (screen completely black, no charging indicator).
5. Open a terminal and start MTKClient **before** connecting the USB cable:
   *(MTKClient will actively poll the USB subsystem waiting for device handshake).*
6. Press and hold **Volume Up AND Volume Down** simultaneously.
7. While keeping both buttons pressed, plug the USB cable into the Linux development machine.
8. Release the buttons as soon as MTKClient detects the device and prints `Device detected... Handshake success`.

---

## 2. Partition Dump Selection & Technical Justification

| Partition Name | Block Node | Expected Size | Content Description | Criticality |
|---|---|---|---|---|
| `nvram` | `mmcblk0p25` | **67,108,864 B** (64 MiB) | Factory IMEI, RF power tables, Wi-Fi MAC, Bluetooth MAC | 🔴 **Irrecoverable** |
| `nvdata` | `mmcblk0p7` | **67,108,864 B** (64 MiB) | Dynamic runtime radio parameters and calibration updates | 🔴 **Irrecoverable** |
| `nvcfg` | `mmcblk0p6` | **33,554,432 B** (32 MiB) | NVRAM structure configuration and partition pointers | 🔴 **Irrecoverable** |
| `proinfo` | `mmcblk0p12`| **3,145,728 B** (3 MiB) | Factory serial number, hardware model barcode, PCB ID | 🔴 **Irrecoverable** |
| `persist` | `mmcblk0p15`| **50,331,648 B** (48 MiB) | Touchscreen sensor calibration, ambient sensor offsets | 🔴 **Irrecoverable** |
| `protect1` | `mmcblk0p9` | **8,388,608 B** (8 MiB) | SIM-lock tokens, modem security parameters | 🔴 **Irrecoverable** |
| `protect2` | `mmcblk0p10`| **9,928,704 B** (9.47 MiB)| Radio security fallback and IMEI checksums | 🔴 **Irrecoverable** |
| `seccfg` | `mmcblk0p11`| **8,388,608 B** (8 MiB) | Bootloader lock status flags (allows re-locking to green) | 🟡 **High** |
| `boot` | `mmcblk0p28`| **33,554,432 B** (32 MiB) | Factory stock Linux 4.9.190+ kernel image | 🟢 **Recoverable** |
| `recovery` | `mmcblk0p2` | **33,554,432 B** (32 MiB) | Factory stock recovery image | 🟢 **Recoverable** |
| `vbmeta` | `mmcblk0p13`| **8,388,608 B** (8 MiB) | Factory AVB 2.0 verification root tree | 🟢 **Recoverable** |
| `dtbo` | `mmcblk0p29`| **8,388,608 B** (8 MiB) | Factory device tree overlay partition | 🟢 **Recoverable** |

*Note: Large generic operating system partitions (`system` 3.8 GiB, `vendor` 800 MiB, `userdata` 25 GiB) are excluded from the pre-unlock dump to optimize backup time and disk efficiency, as they are fully recoverable from the official Lenovo Software Fix package.*

---

## 3. Corrected MTKClient Backup Commands

Output destination: `~/Desktop/TB8505X/backups/brom_pre_unlock/` (directory initialized with `0700` permissions).

### All-in-One Command (Corrected 1-to-1 Syntax)
```bash
python3 tools/mtkclient/mtk.py r \
  nvram,nvdata,nvcfg,proinfo,persist,protect1,protect2,seccfg,boot,recovery,vbmeta,dtbo \
  /home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/nvram.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/nvdata.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/nvcfg.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/proinfo.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/persist.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/protect1.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/protect2.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/seccfg.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/boot.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/recovery.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/vbmeta.bin,\
/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/dtbo.bin
```

---

## 4. Post-Dump Validation Runbook

Immediately after acquisition, execute the automated validation script:

```bash
./scripts/backup/validate_backup.sh
```

The script verifies:
1. Every partition file exists and is non-empty.
2. File sizes match the exact byte count of the physical GPT partition map.
3. Content contains valid non-zero data (not empty sparse padding).
4. Generates a permanent `SHA256SUMS.txt` cryptographic manifest inside the backup folder.
