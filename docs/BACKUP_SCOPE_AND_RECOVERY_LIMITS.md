# Backup Scope & Recovery Limits: Lenovo TB-8505X

**Target Device:** Lenovo Tab M8 HD LTE (`TB-8505X` / `akita_row_call`)  
**Operation:** Pre-Unlock MediaTek Boot ROM (BROM) Partition Acquisition  
**Tool:** MTKClient v2.1.4 (Kamakiri volatile SRAM DAA bypass)

---

## 1. Scope of the Pre-Unlock Backup

The pre-unlock BROM backup targets **12 specific partitions** (~316.37 MiB total) residing in the eMMC User Data Area (`mmcblk0`):

| Partition Dump | Block Device | Byte Size | Critical Content / Purpose | Uniqueness |
| :--- | :--- | :--- | :--- | :---: |
| `nvram.bin` | `mmcblk0p25` | 67,108,864 | Baseband RF parameters, cellular calibration master | **UNIQUE TO DEVICE** |
| `nvdata.bin` | `mmcblk0p7` | 67,108,864 | Device IMEI, baseband runtime NVRAM state | **UNIQUE TO DEVICE** |
| `nvcfg.bin` | `mmcblk0p6` | 33,554,432 | MediaTek NVRAM filesystem configuration | **DEVICE SPECIFIC** |
| `proinfo.bin` | `mmcblk0p12` | 3,145,728 | Factory barcode, PCBA serial number, serial `HGR2YTWY` | **UNIQUE TO DEVICE** |
| `persist.bin` | `mmcblk0p15` | 50,331,648 | Wi-Fi MAC address, Bluetooth MAC address, sensor calibration | **UNIQUE TO DEVICE** |
| `protect1.bin` | `mmcblk0p9` | 8,388,608 | SIM / Radio lock protection region 1 | **DEVICE SPECIFIC** |
| `protect2.bin` | `mmcblk0p10` | 9,928,704 | SIM / Radio lock protection region 2 | **DEVICE SPECIFIC** |
| `seccfg.bin` | `mmcblk0p11` | 8,388,608 | Little Kernel unlock state, anti-rollback flags | Security State |
| `boot.bin` | `mmcblk0p28` | 33,554,432 | Factory stock kernel 4.9.190+ and ramdisk | Generic to Build |
| `recovery.bin` | `mmcblk0p2` | 33,554,432 | Factory stock Android 10 recovery image | Generic to Build |
| `vbmeta.bin` | `mmcblk0p13` | 8,388,608 | Factory AVB 1.1 root cryptographic verification table | Generic to Build |
| `dtbo.bin` | `mmcblk0p29` | 8,388,608 | Factory Device Tree Overlays | Generic to Build |

---

## 2. Explicit Recovery Limits (What is NOT Covered)

> [!CAUTION]
> ### Important Boundary of Protection:
> This backup is designed to preserve **device-unique hardware calibration and identity**. It does **NOT** constitute a full bare-metal disk image of the eMMC storage. Do **not** assume this backup can recover the tablet under every circumstance without external files.

### Specific Exclusions & Recovery Boundaries:
1. **Operating System (`system` - `mmcblk0p37`, 3896 MiB):**
   - The 3.8 GiB Android 10 system partition is **NOT** included in this backup.
   - *Consequence:* If `system` is formatted or overwritten by Ubuntu Touch, restoring back to stock Android requires the official Lenovo SVC factory image (`TB-8505X_S301129_230914_BMP_SVC.zip`).
2. **Factory Vendor Blobs (`vendor` - `mmcblk0p36`, 800 MiB):**
   - The 800 MiB vendor partition is **NOT** included in this backup.
   - *Mitigation:* The Ubuntu Touch porting process preserves `/vendor` 100% untouched on eMMC. However, if `/vendor` is accidentally erased or damaged, it must be restored from the factory SVC package.
3. **Personal User Data (`userdata` - `mmcblk0p38`, 23.46 GiB):**
   - User photos, downloads, Android apps, and personal settings are **NOT** backed up.
   - *Consequence:* Executing `fastboot flashing unlock` permanently erases `userdata`.
4. **OEM Customization (`lenovocust`, `product`, `lenovoraw`):**
   - Partitions containing Lenovo OEM wallpapers, preloaded apps, and telemetry are omitted.
5. **Replay Protected Memory Block (`RPMB` - `mmcblk0rpmb`):**
   - The hardware RPMB partition is cryptographically authenticated using an internal key burned into the SoC OTP eFuses during manufacturing. It cannot be backed up or restored via standard partition imaging.
6. **Hardware eFuses (`otp`):**
   - Physical silicon fuses blown during factory provisioning cannot be undone by software dumps.

---

## 3. Realistic Recovery Scenarios & Runbooks

### Scenario A: Unbootable Custom Kernel / Bootloop
- **State:** Device is in bootloop or stops at Lenovo logo after flashing `boot.img`.
- **Recovery Path:** 
  - Enter Fastboot: `fastboot flash boot ~/Desktop/TB8505X/backups/brom_pre_unlock/boot.bin`
  - Result: 100% immediate recovery to stock bootloader execution.

### Scenario B: Little Kernel Verification Rejection (AVB Panic)
- **State:** Device halts with `dm-verity corruption` or `red state`.
- **Recovery Path:**
  - Enter Fastboot or BROM.
  - Flash stock vbmeta: `fastboot flash vbmeta ~/Desktop/TB8505X/backups/brom_pre_unlock/vbmeta.bin`
  - Result: Restores original verified boot state.

### Scenario C: Lost Baseband / Null IMEI / Radio Inoperable
- **State:** Tablet boots, but cellular network reports `No SIM`, `IMEI unknown`, or Wi-Fi MAC is `02:00:00:00:00:00`.
- **Recovery Path:**
  - Boot into MediaTek BROM mode.
  - Execute:
    ```bash
    python3 tools/mtkclient/mtk.py w nvram,nvdata,persist \
      ~/Desktop/TB8505X/backups/brom_pre_unlock/nvram.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/nvdata.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/persist.bin
    ```
  - Result: Restores hardware RF calibration and original factory MAC addresses.

### Scenario D: Total Flash Corruption / Return to Factory Stock
- **State:** User wants to completely revert tablet to stock Android 10 factory condition.
- **Recovery Path:**
  - Download official Lenovo rescue package `TB-8505X_S301129_230914_BMP_SVC`.
  - Flash `system.img`, `vendor.img`, `boot.img`, `recovery.img` via SP Flash Tool v5.1920 or MTKClient.
  - If IMEI/calibration was affected, re-flash `nvdata.bin` and `nvram.bin` from the pre-unlock backup.
  - Relock bootloader: `fastboot flashing lock` (or `mtk w seccfg seccfg.bin`).
