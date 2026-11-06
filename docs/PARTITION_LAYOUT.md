# Partition Layout & Memory Map — Lenovo TB-8505X

## 1. Partition Scheme Architecture

The Lenovo TB-8505X uses a classic **Treble non-A/B partition layout**:

- **No `super` partition:** Unlike Android 10 devices launched with dynamic partitions, this tablet uses direct, discrete partitions for `system`, `vendor`, `product`, and `userdata`.
- **No A/B Slots:** Single slot scheme (`slot-count: 0`). Partitions are updated directly rather than via seamless slot switching.
- **Dedicated Recovery:** Features a standalone 32 MiB `recovery` partition (`mmcblk0p2`).

---

## 2. Partition Mapping Table

Calculated from Fastboot `getvar all` hexadecimal bytes and live block nodes (`/dev/block/platform/bootdevice/by-name`):

| Partition Name | Block Device | Hex Size | Size (MiB / GiB) | Filesystem / Type | Purpose & Safety Category |
|---|---|---|---|---|---|
| `userdata` | `mmcblk0p38` | `0x5dd7fbe00` | ~25.19 GiB | ext4 / f2fs | User data & app storage. Wiped on unlock. |
| `system` | `mmcblk0p37` | `0x0f3800000` | 3.80 GiB | ext4 (raw) | Ubuntu Touch rootfs target. **Safe to flash.** |
| `vendor` | `mmcblk0p36` | `0x032000000` | 800 MiB | ext4 | MediaTek HALs & proprietary blobs. **Preserve untouched.** |
| `product` | `mmcblk0p35` | `0x002000000` | 32 MiB | ext4 | OEM customization files. |
| `lenovocust`| `mmcblk0p33` | `0x00c800000` | 200 MiB | ext4 | Lenovo regional customizations. |
| `cache` | `mmcblk0p32` | `0x010000000` | 256 MiB | ext4 | Cache partition. Used by Magisk for pre-init. |
| `boot` | `mmcblk0p28` | `0x002000000` | 32 MiB | raw data | Kernel + Ramdisk. **Target for Halium boot.** |
| `recovery` | `mmcblk0p2` | `0x002000000` | 32 MiB | raw data | Stock recovery / Fastboot recovery. |
| `dtbo` | `mmcblk0p29` | `0x000800000` | 8 MiB | raw data | Device Tree Blob Overlay. |
| `vbmeta` | `mmcblk0p13` | `0x000800000` | 8 MiB | raw data | AVB 2.0 verification tree. |
| `nvram` | `mmcblk0p25` | `0x004000000` | 64 MiB | raw data | ⚠️ **DO NOT TOUCH:** IMEI, calibration, BT/Wi-Fi MAC. |
| `nvdata` | `mmcblk0p7` | `0x004000000` | 64 MiB | ext4 | ⚠️ **DO NOT TOUCH:** Runtime radio calibration & identity. |
| `nvcfg` | `mmcblk0p6` | `0x002000000` | 32 MiB | ext4 | ⚠️ **DO NOT TOUCH:** NVRAM configuration parameters. |
| `proinfo` | `mmcblk0p12` | `0x000300000` | 3 MiB | raw data | ⚠️ **DO NOT TOUCH:** Board serial & factory provisions. |
| `persist` | `mmcblk0p15` | `0x003000000` | 48 MiB | ext4 | ⚠️ **DO NOT TOUCH:** Sensor calibration & persistent settings. |
| `protect1` | `mmcblk0p9` | `0x000800000` | 8 MiB | ext4 | ⚠️ **DO NOT TOUCH:** SIM / modem protected calibration. |
| `protect2` | `mmcblk0p10` | `0x000978000` | 9.47 MiB | ext4 | ⚠️ **DO NOT TOUCH:** Radio security & identity backup. |
| `seccfg` | `mmcblk0p11` | `0x000800000` | 8 MiB | raw data | ⚠️ **DO NOT TOUCH:** Bootloader lock & security flags. |
| `preloader` | `mmcblk0boot0`| `0x000040000` | 256 KiB | raw data | ⚠️ **DO NOT TOUCH:** MediaTek BROM first-stage bootloader. |
| `md1img` | `mmcblk0p17` | `0x006400000` | 100 MiB | raw data | MediaTek Modem MD1 firmware image. |
| `lk` / `lk2` | `mmcblk0p26/27`| `0x000100000` | 1 MiB | raw data | Little Kernel (Bootloader 2nd stage). |
| `tee1` / `tee2`| `mmcblk0p30/31`| `0x000500000` | 5/6 MiB | raw data | Trusted Execution Environment (Beanpod). |

---

## 3. Flash Safety Assessment

### Partitions Safe for Ubuntu Touch Deployment
- `boot` (32 MiB): Flashed with `halium-boot.img` (kernel + initramfs).
- `system` (3.80 GiB): Flashed with Ubuntu Touch rootfs image or Halium system layer. Because `system` is 3.8 GiB, it easily accommodates the standard ~1.5 - 2.0 GiB rootfs image without repatitioning.
- `vbmeta` (8 MiB): Flashed with verification-disabled header.

### Partitions Strictly Protected
- **Radio & Calibration:** `nvram`, `nvdata`, `nvcfg`, `proinfo`, `persist`, `protect1`, `protect2`, `seccfg`.
- Any corruption to these partitions results in permanent loss of IMEI, cellular baseband capability, and hardware radio calibration that **CANNOT** be recovered from stock firmware downloads.
- Must be backed up before any partition manipulation.
