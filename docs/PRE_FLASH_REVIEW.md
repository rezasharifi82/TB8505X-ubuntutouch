# Pre-Flash Installation Review & Safety Plan: Lenovo TB-8505X

**Date:** 2026-11-05  
**Target:** Lenovo Tab M8 HD LTE (`TB-8505X` / `akita_row_call`)  
**Current State:** Connected in Fastboot mode (`HGR2YTWY`), Locked (`unlocked: no`, `verifiedbootstate: green`).  
**Approval Gate:** GATE 1 — Pre-Unlock BROM Acquisition & Bootloader Unlock

---

## 1. Device & Hardware Identity Verification

- **Manufacturer & Model:** Lenovo Tab M8 HD LTE (`TB-8505X`)
- **Board Codename:** `akita_row_call` (Product: `8505X`)
- **Platform BSP / SoC:** MediaTek MT6761 (Hardware code: `MT8766B`)
- **Factory Stock Firmware:** `TB-8505X_S301129_230914_BMP` (Android 10, SDK 29)
- **Stock Kernel:** Linux 4.9.190+ (SMP PREEMPT aarch64)
- **Display:** 800 × 1280 Novatek NT35521 LCD
- **Digitizer:** Focaltech FT8201 In-cell Touchscreen
- **GPU:** Imagination PowerVR Rogue GE8300 (`rgx clark m1.9ED4971894`)
- **Audio / PMIC:** MediaTek MT6357
- **Connectivity:** MediaTek MT6631 (Wi-Fi, Bluetooth, FM, GPS) + MT6761 LTE Modem

---

## 2. Reconstructed Physical Partition Map & Flash Targets

| Target Partition | Minor Device Path | Hex Size | Byte Size | Image to Flash | Flash Method | Action |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `boot` | `/dev/block/mmcblk0p28` | `0x2000000` | 33,554,432 | [`out/boot.img`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/boot.img) | `fastboot flash boot` | Flash Custom Kernel + Halium Initramfs |
| `recovery` | `/dev/block/mmcblk0p2` | `0x2000000` | 33,554,432 | [`out/recovery.img`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/recovery.img) | `fastboot flash recovery` | Flash UBports Recovery with `recovery.fstab` |
| `vbmeta` | `/dev/block/mmcblk0p13` | `0x800000` | 8,388,608 | `vbmeta_disabled.img` | `fastboot --disable-verity --disable-verification flash vbmeta` | Disable AVB Enforcement |
| `system` | `/dev/block/mmcblk0p37` | `0xf3800000` | 4,085,252,096 | `system.img` (3800MB) | `fastboot flash system` | Flash Ubuntu Touch Rootfs / GSI |
| `vendor` | `/dev/block/mmcblk0p36` | `0x32000000` | 838,860,800 | None | N/A | **PRESERVE 100% UNTOUCHED** |
| `userdata` | `/dev/block/mmcblk0p38` | `0x5dd7fbe00` | 25,190,448,640 | Empty ext4 | `fastboot format userdata` | Erased on Unlock / Container Storage |

---

## 3. Pre-Unlock Backup Strategy & Checksums

Before executing any modification to Little Kernel or partitions:
- **Acquisition Tool:** `MTK Flash/Exploit Client V2.1.4 (c) B.Kerler 2018-2026` at [`tools/mtkclient/mtk.py`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/tools/mtkclient/mtk.py).
- **Target Partitions (12 total):** `nvram`, `nvdata`, `nvcfg`, `proinfo`, `persist`, `protect1`, `protect2`, `seccfg`, `boot`, `recovery`, `vbmeta`, `dtbo`.
- **Destination:** `~/Desktop/TB8505X/backups/brom_pre_unlock/` (permissions `0700`, outside Git).
- **Automated Validation:** [`scripts/backup/validate_backup.sh`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/scripts/backup/validate_backup.sh) checks byte counts and generates `SHA256SUMS.txt`.

---

## 4. Expected Device State Changes & Data Impact

1. **Userdata Wipe:** Unlocking the bootloader (`fastboot flashing unlock`) triggers an intentional factory cryptographic wipe of `userdata` (`mmcblk0p38`). All existing Android user files and apps will be erased.
2. **Bootloader Warning:** Upon power-on, Little Kernel will transition from `verifiedbootstate: green` to `verifiedbootstate: orange`, displaying the standard 5-second Android unlocked boot warning.
3. **AVB Status:** AVB 1.1 verification flags are disabled on `vbmeta` to allow execution of unsigned or test-key signed boot images.

---

## 5. Disaster Recovery & Rollback Procedure

- **Silicon Boot ROM Safeguard:** The MediaTek MT6761 Boot ROM resides in read-only mask ROM. Even if all eMMC partitions are erased or corrupted, the device can always enter BROM mode by holding **Volume Up + Volume Down** while plugging in USB.
- **Rollback to Stock:**
  - Fastboot mode: Re-flash original `boot.bin`, `recovery.bin`, and `vbmeta.bin` from the BROM backup directory.
  - BROM mode: Restore any partition directly via `python3 tools/mtkclient/mtk.py w <partition> <backup_file>`.
  - Factory Rescue: Full restore package `TB-8505X_S301129_230914_BMP_SVC` flashable via Lenovo Software Fix or SP Flash Tool.

---

## 6. Known Risks & Mitigation

| Identified Risk | Severity | Mitigation Strategy |
| :--- | :---: | :--- |
| **ModemManager Serial Probe Collision** | HIGH | Stop host ModemManager service (`sudo systemctl stop ModemManager`) or apply udev rule `ENV{ID_MM_DEVICE_IGNORE}="1"` before BROM connection. |
| **Volume Key Handshake Timing** | MEDIUM | Keep Volume Up + Volume Down pressed firmly until terminal displays `Port - Device detected`. |
| **Accidental Overwrite of NVRAM/IMEI** | CRITICAL | All backup operations use `mtk r` (read-only). Flash commands explicitly target `boot`, `recovery`, and `system` only. |
| **USB Hub Latency** | LOW | Connect USB cable directly to a rear motherboard USB port; avoid unpowered external hubs. |

---

## 7. Approval Gates & Next Steps

> [!IMPORTANT]
> ### Execution Sequence & Gates:
> 1. **User Approval Step 1 (BROM Read):**
>    - Host action: `sudo systemctl stop ModemManager`
>    - Device action: User powers tablet OFF, holds Volume Up + Volume Down, and connects USB cable.
>    - Autonomous action: Run verified MTKClient read command and execute [`scripts/backup/validate_backup.sh`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/scripts/backup/validate_backup.sh).
> 2. **User Approval Step 2 (Bootloader Unlock):**
>    - Autonomous action: Run `fastboot flashing unlock`.
>    - Device action: User presses Volume Up on physical tablet screen to confirm wipe and unlock.
> 3. **User Approval Step 3 (Flashing Images):**
>    - Autonomous action: Flash verified `vbmeta`, `boot.img`, `recovery.img`, and deploy Ubuntu Touch rootfs.
