# Lenovo TB-8505X Ubuntu Touch Port: Comprehensive Build Audit Report

**Date:** 2026-11-05  
**Target:** Lenovo Tab M8 HD LTE (`TB-8505X` / `akita_row_call`)  
**SoC:** MediaTek MT8766B / MT6761 (Helio A22)  
**Host:** Ubuntu 26.04 x86_64 (`Phantom`)  
**Repository:** [`TB8505X-ubuntutouch/`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/)

---

## 1. Executive Summary & Critical Corrections

An independent, rigorous audit of all project source code, build scripts, kernel binaries, and device-tree objects was conducted. This audit identified and corrected multiple erroneous claims and dangerous partition misidentifications made in previous development reports.

### Major Audit Findings and Corrections:
1. **Boot Image Ramdisk Reality:**  
   *Previous Claim:* The boot image contained a 0-byte SAR (System-As-Root) ramdisk.  
   *Verified Reality:* [`out/boot.img`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/boot.img) contains a **4,106,247 byte** ramdisk (`initrd.img-touch-arm64`) with the official `initramfs-tools-halium` boot scripts (`scripts/halium`). Halium on discrete partitions requires this ramdisk to initialize early block devices, mount the root filesystem, and pivot root to Ubuntu Touch.
2. **Missing Recovery Partition Table (`recovery.fstab`):**  
   *Defect Discovered:* The recovery image was missing a device-specific `recovery.fstab`, rendering `system-image-upgrader` unable to mount partitions.  
   *Resolution:* Implemented [`ramdisk-recovery-overlay/system/etc/recovery.fstab`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/ramdisk-recovery-overlay/system/etc/recovery.fstab) and rebuilt [`out/recovery.img`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/recovery.img).
3. **Partition Minor Number Misidentifications:**  
   *Previous Claims:* System was reported as `mmcblk0p35`, boot as `mmcblk0p31`, recovery as `mmcblk0p32`, and userdata as `mmcblk0p44`.  
   *Verified Reality (from physical hardware `/dev/block/by-name`):*  
   - `boot` = `/dev/block/mmcblk0p28` (32 MiB)
   - `recovery` = `/dev/block/mmcblk0p2` (32 MiB)
   - `vendor` = `/dev/block/mmcblk0p36` (800 MiB)
   - `system` = `/dev/block/mmcblk0p37` (3896 MiB)
   - `userdata` = `/dev/block/mmcblk0p38` (23.46 GiB)  
   Writing to `mmcblk0p31` would have destroyed `tee2` (TrustZone), and writing `system` to `mmcblk0p35` would have overwritten `product` (32 MiB).
4. **Binder IPC Architecture:**  
   *Previous Claim:* `CONFIG_ANDROID_BINDERFS=y` was reported as active.  
   *Verified Reality:* Android kernel 4.9.190 does not support BinderFS. IPC uses static device nodes created by the driver: `CONFIG_ANDROID_BINDER_IPC=y` and `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder,anbox-binder,anbox-hwbinder,anbox-vndbinder"`.
5. **Extraneous Qualcomm udev Rules:**  
   *Defect Discovered:* `70-akita.rules` contained legacy Qualcomm nodes (`msm_*`, `kgsl`, `ttyMSM0`).  
   *Resolution:* Completely rewritten to enforce least-privilege permissions on MediaTek MT6761 hardware nodes (`pvr_sync`, `mtk_disp_mgr`, `M4U_device`, `ccci*`, `stpwmt`).

---

## 2. Independent Artifact Audit Matrix

All build artifacts were verified using independent Python tools (`unpack_bootimg.py`, `avbtool`) and archive inspectors:

| Artifact | Size (Bytes) | SHA-256 Checksum | Internal Structure | Verified Offsets & Constraints |
| :--- | :--- | :--- | :--- | :--- |
| [`boot.img`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/boot.img) | `33,554,432` | `35f85659dde6498864d865d2e11eba8159974324b0a107a30772757809efc6e6` | Android Boot v2 + AVB 1.0 Footer | Kernel: `9,866,648` bytes (`Image.gz`)<br>Ramdisk: `4,106,247` bytes (`initrd`)<br>DTB: `102,208` bytes<br>Base: `0x40000000` |
| [`recovery.img`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/recovery.img) | `33,554,432` | `232903d53332c87031608770b17079bcb8bca009cdfc06dbabfc30992e14e069` | Android Boot v2 + AVB 1.0 Footer | Kernel: `9,866,648` bytes (`Image.gz`)<br>Ramdisk: `15,274,510` bytes<br>Contains: `recovery.fstab`, BusyBox, `adbd`, `system-image-upgrader` |
| [`device_akita_row_call.tar.xz`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/device_akita_row_call.tar.xz) | `38,846,332` | `22d49f1cc24907f97d2ceb054a590119cb155d6c017aed34371305ac37f5426d` | Tar.xz Device Adaptation Layer | `partitions/boot.img`, `partitions/recovery.img`, `/system/opt/halium-overlay/` (udev, pulse, gbinder, init overrides) |
| [`Module.symvers`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/Module.symvers) | `523,586` | `54bc45aabdd7a88e6109cf608c1a2d781a62f4e2003252ecefa7c950a767c779` | Kernel Symbol Table | Symbol CRC export for out-of-tree debugging |

---

## 3. Kernel Verification Summary

- **Source Branch:** `https://github.com/who53/kernel-lenovo-akita.git` (`main`)
- **Base Commit:** `07692302d5db321648a8036ed751f9224e45b9ff`
- **Compiler:** Android NDK Google Clang 9.0.3 (based on SVN r353983c) with `aarch64-linux-android-4.9` binutils
- **Defconfig:** `akita_row_call_defconfig`
- **Monolithic State:** 100% built-in (`grep "=m" .config` returns 0). Zero modules required.
- **Mandatory Subsystems Verified:**
  - AppArmor LSM: `CONFIG_SECURITY_APPARMOR=y`, `CONFIG_DEFAULT_SECURITY_APPARMOR=y`
  - Container Namespaces: `CONFIG_NAMESPACES=y`, `CONFIG_USER_NS=y`, `CONFIG_PID_NS=y`, `CONFIG_NET_NS=y`
  - Cgroups: `CONFIG_CGROUPS=y`, `CONFIG_CGROUP_FREEZER=y`, `CONFIG_CPUSETS=y`
  - VFS: `CONFIG_DEVTMPFS=y`, `CONFIG_DEVTMPFS_MOUNT=y`, `CONFIG_OVERLAY_FS=y`
  - Binder IPC: `CONFIG_ANDROID_BINDER_IPC=y`, `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder,anbox-binder,anbox-hwbinder,anbox-vndbinder"`
  - GPU: PowerVR Rogue GE8300 (`CONFIG_MTK_GPU_SUPPORT=y`, `CONFIG_MTK_GPU_VERSION="rgx clark m1.9ED4971894"`)
  - Touchscreen: Focaltech FT8201 (`CONFIG_TOUCHSCREEN_MTK_FOCALTECH_TS=y`)
  - Audio/PMIC: MediaTek MT6357 (`CONFIG_MTK_PMIC_CHIP_MT6357=y`, `CONFIG_MTK_SND_SOC_CODEC="mt6357"`)

---

## 4. Automated Verification Results

All automated verification scripts passed cleanly:
1. [`scripts/validate_kernel.sh`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/scripts/validate_kernel.sh): **PASSED** (all 7 kconfig and binary checks green).
2. [`scripts/validate_installation_package.sh`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/scripts/validate_installation_package.sh): **PASSED** (all 7 package and ramdisk checks green).
