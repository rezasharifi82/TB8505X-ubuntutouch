# Lenovo TB-8505X Reconstructed Physical Partition Map

**Target Device:** Lenovo Tab M8 HD LTE (`TB-8505X` / `akita_row_call`)  
**Storage:** 32GB eMMC (Sector size: 512 bytes / `0x200`)  
**Evidence Sources:**
1. Android OS sysfs `/dev/block/platform/bootdevice/by-name/` (recorded in [`device-info/partitions.txt`](file:///home/mreza/Desktop/TB8505X/device-info/partitions.txt))
2. Little Kernel (LK v0.5) `fastboot getvar all` (recorded in [`device-info/fastboot.txt`](file:///home/mreza/Desktop/TB8505X/device-info/fastboot.txt))
3. Mount table and storage stats (recorded in [`device-info/storage.txt`](file:///home/mreza/Desktop/TB8505X/device-info/storage.txt))

---

## 1. Physical eMMC Partition Layout Table

| Partition Name | Number | Block Device Path | Hex Size | Byte Size | Human Size | Filesystem | Purpose | Backup Req. | Flash Target |
| :--- | :---: | :--- | :--- | :--- | :--- | :--- | :--- | :---: | :---: |
| `preloader` | - | `mmcblk0boot0/1` | `0x40000` | 262,144 | 256 KiB | Raw | MTK Preloader | **YES** | No |
| `boot_para` | `p1` | `/dev/block/mmcblk0p1` | `0x100000` | 1,048,576 | 1.00 MiB | Raw | Boot parameters | No | No |
| `recovery` | `p2` | `/dev/block/mmcblk0p2` | `0x2000000` | 33,554,432 | 32.00 MiB | Raw (Boot v2) | UBports Recovery | **YES** | **YES** |
| `para` | `p3` | `/dev/block/mmcblk0p3` | `0x80000` | 524,288 | 512 KiB | Raw | BCB / Misc | No | No |
| `expdb` | `p4` | `/dev/block/mmcblk0p4` | `0x1400000` | 20,971,520 | 20.00 MiB | Raw | Exception debug logs | No | No |
| `frp` | `p5` | `/dev/block/mmcblk0p5` | `0x100000` | 1,048,576 | 1.00 MiB | Raw | Factory Reset Protection | No | No |
| `nvcfg` | `p6` | `/dev/block/mmcblk0p6` | `0x2000000` | 33,554,432 | 32.00 MiB | ext4 | NVRAM Config | **CRITICAL** | No |
| `nvdata` | `p7` | `/dev/block/mmcblk0p7` | `0x4000000` | 67,108,864 | 64.00 MiB | ext4 | Cellular Calibration/IMEI | **CRITICAL** | No |
| `metadata` | `p8` | `/dev/block/mmcblk0p8` | `0x2000000` | 33,554,432 | 32.00 MiB | Raw | FBE Crypto Metadata | No | No |
| `protect1` | `p9` | `/dev/block/mmcblk0p9` | `0x800000` | 8,388,608 | 8.00 MiB | ext4 | Radio Protection 1 | **CRITICAL** | No |
| `protect2` | `p10` | `/dev/block/mmcblk0p10` | `0x978000` | 9,928,704 | 9.47 MiB | ext4 | Radio Protection 2 | **CRITICAL** | No |
| `seccfg` | `p11` | `/dev/block/mmcblk0p11` | `0x800000` | 8,388,608 | 8.00 MiB | Raw | Bootloader Security/Unlock | **CRITICAL** | No |
| `proinfo` | `p12` | `/dev/block/mmcblk0p12` | `0x300000` | 3,145,728 | 3.00 MiB | Raw | Serial No / Product Info | **CRITICAL** | No |
| `vbmeta` | `p13` | `/dev/block/mmcblk0p13` | `0x800000` | 8,388,608 | 8.00 MiB | Raw (AVB 1.1) | AVB Root Verification | **YES** | **YES** |
| `logo` | `p14` | `/dev/block/mmcblk0p14` | `0xd00000` | 13,631,488 | 13.00 MiB | Raw | Boot Splash Image | No | No |
| `persist` | `p15` | `/dev/block/mmcblk0p15` | `0x3000000` | 50,331,648 | 48.00 MiB | ext4 | Factory Calibration & Wi-Fi MAC | **CRITICAL** | No |
| `sec1` | `p16` | `/dev/block/mmcblk0p16` | `0x200000` | 2,097,152 | 2.00 MiB | Raw | Security Region 1 | No | No |
| `md1img` | `p17` | `/dev/block/mmcblk0p17` | `0x6400000` | 104,857,600 | 100.00 MiB | Raw | LTE Modem Firmware | **YES** | No |
| `spmfw` | `p18` | `/dev/block/mmcblk0p18` | `0x100000` | 1,048,576 | 1.00 MiB | Raw | Power Management Firmware | No | No |
| `scp1` | `p19` | `/dev/block/mmcblk0p19` | `0x100000` | 1,048,576 | 1.00 MiB | Raw | System Coprocessor 1 | No | No |
| `scp2` | `p20` | `/dev/block/mmcblk0p20` | `0x100000` | 1,048,576 | 1.00 MiB | Raw | System Coprocessor 2 | No | No |
| `sspm_1` | `p21` | `/dev/block/mmcblk0p21` | `0x100000` | 1,048,576 | 1.00 MiB | Raw | Secure Coprocessor 1 | No | No |
| `sspm_2` | `p22` | `/dev/block/mmcblk0p22` | `0x100000` | 1,048,576 | 1.00 MiB | Raw | Secure Coprocessor 2 | No | No |
| `gz1` | `p23` | `/dev/block/mmcblk0p23` | `0x1000000` | 16,777,216 | 16.00 MiB | Raw | Microtrust GZ Runtime 1 | No | No |
| `gz2` | `p24` | `/dev/block/mmcblk0p24` | `0x1000000` | 16,777,216 | 16.00 MiB | Raw | Microtrust GZ Runtime 2 | No | No |
| `nvram` | `p25` | `/dev/block/mmcblk0p25` | `0x4000000` | 67,108,864 | 64.00 MiB | Raw | Baseband NVRAM Master | **CRITICAL** | No |
| `lk` | `p26` | `/dev/block/mmcblk0p26` | `0x100000` | 1,048,576 | 1.00 MiB | Raw | Little Kernel Bootloader 1 | **YES** | No |
| `lk2` | `p27` | `/dev/block/mmcblk0p27` | `0x100000` | 1,048,576 | 1.00 MiB | Raw | Little Kernel Bootloader 2 | **YES** | No |
| `boot` | `p28` | `/dev/block/mmcblk0p28` | `0x2000000` | 33,554,432 | 32.00 MiB | Raw (Boot v2) | Linux 4.9.190+ Standalone Kernel | **YES** | **YES** |
| `dtbo` | `p29` | `/dev/block/mmcblk0p29` | `0x800000` | 8,388,608 | 8.00 MiB | Raw | Device Tree Overlays | **YES** | No |
| `tee1` | `p30` | `/dev/block/mmcblk0p30` | `0x500000` | 5,242,880 | 5.00 MiB | Raw | TrustZone TEE 1 | No | No |
| `tee2` | `p31` | `/dev/block/mmcblk0p31` | `0x600000` | 6,291,456 | 6.00 MiB | Raw | TrustZone TEE 2 | No | No |
| `cache` | `p32` | `/dev/block/mmcblk0p32` | `0x10000000` | 268,435,456 | 256.00 MiB | ext4 | System Recovery Cache | No | No |
| `lenovocust` | `p33` | `/dev/block/mmcblk0p33` | `0xc800000` | 209,715,200 | 200.00 MiB | ext4 | Lenovo Custom Blobs | No | No |
| `lenovoraw` | `p34` | `/dev/block/mmcblk0p34` | `0x1000000` | 16,777,216 | 16.00 MiB | ext4 | Lenovo Raw Data | No | No |
| `product` | `p35` | `/dev/block/mmcblk0p35` | `0x2000000` | 33,554,432 | 32.00 MiB | ext4 | OEM Product Partition | No | No |
| `vendor` | `p36` | `/dev/block/mmcblk0p36` | `0x32000000` | 838,860,800 | 800.00 MiB | ext4 | Factory MT6761 HAL Vendor | **YES** | **PRESERVE** |
| `system` | `p37` | `/dev/block/mmcblk0p37` | `0xf3800000` | 4,085,252,096 | 3896.00 MiB | ext4 | Ubuntu Touch Rootfs / GSI | **YES** | **YES** |
| `userdata` | `p38` | `/dev/block/mmcblk0p38` | `0x5dd7fbe00` | 25,190,448,640 | 23.46 GiB | ext4 | Userdata & Container Storage | **BACKUP** | Format on Unlock |
| `otp` | `p39` | `/dev/block/mmcblk0p39` | `0x2b00000` | 45,088,768 | 43.00 MiB | Raw | One-Time Programmable | No | No |
| `flashinfo` | `p40` | `/dev/block/mmcblk0p40` | `0x1000000` | 16,777,216 | 16.00 MiB | Raw | Flash Info Configuration | No | No |

---

## 2. Discrepancy Resolution Summary

1. **System Partition:** Formerly reported as `p35`. Correct path is `/dev/block/mmcblk0p37`. `p35` is `product` (32 MiB).
2. **Boot Partition:** Formerly reported as `p31`. Correct path is `/dev/block/mmcblk0p28`. `p31` is `tee2` (TrustZone).
3. **Recovery Partition:** Formerly reported as `p32`. Correct path is `/dev/block/mmcblk0p2`. `p32` is `cache`.
4. **Userdata Partition:** Formerly reported as `p44`. Correct path is `/dev/block/mmcblk0p38`. The device has exactly 40 partitions.
