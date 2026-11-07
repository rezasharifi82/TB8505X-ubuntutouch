# Gate 3 Pre-Flash Audit: Comprehensive Evidence & Device Verification

**Target Device:** Lenovo Tab M8 HD LTE (`TB-8505X` / `akita_row_call`)  
**SoC Platform:** MediaTek MT6761 (Helio A22 / MT8766B, Hardware Code: `0x0717`)  
**Host System:** Linux x86_64 (`Phantom`)  
**Physical State:** Fastboot mode (`HGR2YTWY fastboot`), connected via USB.  
**Bootloader State:** `unlocked: yes`, `secure: no`, `kernel: lk`, `product: akita_row_call`.  
**Host Safe Backup Location:** `/home/mreza/TB8505X_backup_safe/brom_pre_unlock/` & [`backups/brom_pre_unlock/`](file:///home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/)  
**Safety Protocol:** Strict Read-Only Audit. Zero flashing, zero erasing, zero formatting, zero reboots, zero remote pushes.

---

## 1. Complete AVB 2.0 Analysis & Raw Header Verification

The device uses Android Verified Boot (AVB) 2.0. Little Kernel (LK) inspects the primary `vbmeta` partition (`mmcblk0p13`, physical size 8,388,608 bytes / 8 MiB) at boot.

### 1.1 Raw Header Binary Structure Comparison
Audited directly by parsing bytes 0 to 256 of the factory backup and the patched image:

| AVB Header Field | Byte Offset | Size / Type | Stock Factory `vbmeta.bin` | Patched `vbmeta_disabled.img` | Interpretation |
|---|---|---|---|---|---|
| **Magic** | 0..3 | 4 B (ASCII) | `AVB0` | `AVB0` | Valid AVB 2.0 Magic |
| **libavb Version** | 4..11 | 2x uint32 (BE) | `1.0` | `1.0` | libavb v1.0 standard |
| **Auth Block Size** | 12..19 | uint64 (BE) | 320 bytes | 320 bytes | SHA-256 (32B) + RSA-2048 Sig (256B) |
| **Aux Block Size** | 20..27 | uint64 (BE) | 3,264 bytes | 3,264 bytes | Descriptors + Public Keys |
| **Algorithm Type** | 28..31 | uint32 (BE) | `1` | `1` | `SHA256_RSA2048` |
| **Hash Offset / Size** | 32..47 | 2x uint64 (BE) | `0` / `32` | `0` / `32` | Header + Auth Hash |
| **Signature Offset / Size** | 48..63 | 2x uint64 (BE) | `32` / `256` | `32` / `256` | OEM RSA Signature |
| **Public Key Offset / Size**| 64..79 | 2x uint64 (BE) | `2688` / `520` | `2688` / `520` | OEM RSA-2048 Public Key |
| **Descriptors Offset / Size**| 96..111 | 2x uint64 (BE) | `0` / `2688` | `0` / `2688` | 4 Chains + 1 Hash Descriptor |
| **Rollback Index** | 112..119 | uint64 (BE) | `0` | `0` | Anti-rollback counter |
| **Flags** | 120..123 | uint32 (BE) | `0x00000000` (0) | `0x00000003` (3) | **Hashtree & Verification Disabled** |
| **Rollback Location** | 124..127 | uint32 (BE) | `0` | `0` | Primary vbmeta index location |
| **Release String** | 128..175 | 48 B (ASCII) | `avbtool 1.1.0` | `avbtool 1.1.0` | Google standard toolchain |

### 1.2 Raw Hex Dump of Critical Header Range (Bytes 112 to 127)
- **Stock `vbmeta.bin`:**
  ```text
  00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  ```
- **Patched `out/vbmeta_disabled.img`:**
  ```text
  00 00 00 00 00 00 00 00 00 00 00 03 00 00 00 00
  ```
  *(Byte 123 changed from `0x00` to `0x03`)*

### 1.3 Decoded AVB Flags
- **Bit 0 (`0x01`) — `AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED`:**  
  Signals the Linux kernel dm-verity driver to skip verification of the hashtrees on `/system` and `/vendor`.
- **Bit 1 (`0x02`) — `AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED`:**  
  Signals Little Kernel (LK) to skip cryptographic signature checks on all chained partitions before loading them into RAM.

### 1.4 Chained Descriptors & Partition Topology
Parsed from `avbtool info_image`:
1. **Chain Descriptor `vendor`:**
   - Rollback Index Location: 4
   - Public Key SHA-1: `9577bc6c0772975ecce93c4d8a178662c728dadf`
2. **Chain Descriptor `boot`:**
   - Rollback Index Location: 3
   - Public Key SHA-1: `9d808b0995768d0677fccb1efcddb7cf9e153d99`
3. **Chain Descriptor `recovery`:**
   - Rollback Index Location: 1
   - Public Key SHA-1: `0aa0987116fc792f36bc909b0a4d530413f02a54`
4. **Chain Descriptor `system`:**
   - Rollback Index Location: 2
   - Public Key SHA-1: `fa41159a5d696abdef93176a07d0b0d001263f01`
5. **Hash Descriptor `dtbo`:**
   - Partition Name: `dtbo`
   - Image Size: 130,160 bytes
   - Salt: `ce02b0e7ad8eec4619887c10689153f9b83a286b49c87408ac94217f8a841c6a`
   - Digest (SHA-256): `2b558c6fd622fdb5cffc402d5874c9bdd6b5f3587ad543ef47d83cb284c2be71`

**Architectural Conclusion:**  
Because `boot`, `recovery`, `system`, and `vendor` are all chained directly from this primary `vbmeta` partition, modifying byte 123 of this single partition is 100% sufficient to disable AVB across the entire device boot chain.

---

## 2. Kernel & Vendor Compatibility Evidence

Both the stock factory kernel and custom kernel configurations were extracted using `extract-ikconfig` and audited.

### 2.1 Compiler & Toolchain Alignment
- **Stock Kernel Version String:**  
  `Linux version 4.9.190+ (nobody@android-build) (Android (5484270 based on r353983c) clang version 9.0.3) #1 SMP PREEMPT Thu Sep 14 13:49:10 CST 2023`
- **Custom Kernel Version String:**  
  `Linux version 4.9.190+ (mreza@Phantom) (Android (5484270 based on r353983c) clang version 9.0.3) #5 SMP PREEMPT Thu Nov 5 16:22:11 +0330 2026`
- **Compiler Compatibility:** EXACT MATCH. Both kernels were compiled with Google Clang `r353983c` (Clang 9.0.3 / LLVM 9.0.3svn) targeting AArch64.

### 2.2 Kernel Configuration Diff & Halium Support
Audit of 1,441 stock configuration symbols vs 1,471 custom configuration symbols:

| Config Symbol | Stock Value | Custom Value | Functional Impact |
|---|---|---|---|
| `CONFIG_NAMESPACES` | *Not set* | `y` | Enables kernel namespace isolation for LXC |
| `CONFIG_UTS_NS` | *Not set* | `y` | Hostname / domain isolation |
| `CONFIG_IPC_NS` | *Not set* | `y` | System V IPC namespace isolation |
| `CONFIG_USER_NS` | *Not set* | `y` | Unprivileged user container mapping |
| `CONFIG_PID_NS` | *Not set* | `y` | Process ID namespace for Halium container |
| `CONFIG_NET_NS` | *Not set* | `y` | Virtualized network routing for container |
| `CONFIG_CGROUP_PIDS` | *Not set* | `y` | Process limit enforcement in systemd |
| `CONFIG_CGROUP_DEVICE` | *Not set* | `y` | Device node access control in Halium |
| `CONFIG_BLK_CGROUP` | *Not set* | `y` | Block I/O accounting |
| `CONFIG_FHANDLE` | *Not set* | `y` | Required by systemd 240+ |
| `CONFIG_SYSVIPC` | *Not set* | `y` | Required for standard Linux IPC |
| `CONFIG_ANDROID_BINDER_DEVICES` | `"binder,hwbinder,vndbinder"` | `"binder,hwbinder,vndbinder,anbox-binder,anbox-hwbinder,anbox-vndbinder"` | Halium container binder multiplexing |
| `CONFIG_DEFAULT_SECURITY` | `"selinux"` | `"apparmor"` | Ubuntu AppArmor LSM integration |

### 2.3 Kernel Modules & Proprietary Driver Linkage
- **Monolithic Architecture:** Audit of the stock boot ramdisk (`stock_boot/ramdisk`) confirms **0 loadable `.ko` kernel modules**. All essential hardware drivers (MediaTek MT6761 CCF clocks, MT6357 PMIC, PowerVR GE8300 GPU, display LCM, Goodix/Focaltech touchscreens, eMMC MSDC, WiFi/BT connectivity) are compiled statically into the monolithic `vmlinux` image.
- **Exported Kernel Symbols:** The custom kernel exports **9,593 symbols** (`EXPORT_SYMBOL` / `EXPORT_SYMBOL_GPL`) recorded in [`out/Module.symvers`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/Module.symvers).
- **Vendor Partition Integrity:** The stock `/vendor` partition (`mmcblk0p36`, 800 MiB) remains 100% untouched. All proprietary MediaTek HAL shared objects (`/vendor/lib/hw/*`, `/vendor/lib64/hw/*`) interact with the custom kernel via standard Android 10 ioctls and binder IPC channels (`/dev/binder`, `/dev/hwbinder`, `/dev/vndbinder`).

---

## 3. Recovery Boot Analysis & Initialization Flow

### 3.1 Boot Image Format Verification
- **Header:** Android Boot Image v2
- **Page Size:** 2048 bytes
- **Kernel Load Address:** `0x40080000`
- **Ramdisk Load Address:** `0x51b00000`
- **Tags / DTB Load Address:** `0x47880000`
- **DTB Size:** 102,208 bytes (decompiled compatible string: `mediatek,MT6761`)
- **Kernel Size:** 9,866,648 bytes
- **Ramdisk Size:** 15,274,510 bytes
- **Physical Padding:** Padded to exactly 33,554,432 bytes (matches physical 32 MiB partition).

### 3.2 Ramdisk Init & Service Declaration
The recovery ramdisk initialization flow was verified by inspecting [`system/etc/init/hw/init.rc`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/ramdisk-recovery-overlay/system/etc/init/hw/init.rc):
- **Init Binary:** Symlinked from `/init` $\rightarrow$ `/system/bin/init` (AOSP init binary).
- **Recovery Service:**
  ```text
  service recovery /system/bin/recovery
      socket recovery stream 422 system system
      seclabel u:r:recovery:s0
      user root
  ```
- **ADBD Service:**
  ```text
  service adbd /system/bin/adbd --device_banner=recovery
      disabled
      socket adbd stream 660 system system
      seclabel u:r:adbd:s0
      user root
  ```
- **Root Escalation Trigger:**
  ```text
  on property:service.adb.root=1
      restart adbd
  ```

### 3.3 ADB Startup & USB Gadget Configuration
In [`prop.default`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/ramdisk-recovery-overlay/prop.default):
- `persist.sys.usb.config=adb`
- `ro.adb.secure=0` (authentication prompt bypassed in recovery)
- `service.adb.root=1` (forces root daemon execution)
- `ro.recovery.usb.vid=18D1` (Google Android VID)
- `ro.recovery.usb.adb.pid=D001` (Standard Recovery ADB PID)
- `ro.minui.pixel_format=RGBX_8888` (Configures Minui recovery graphics pipeline)

Dual USB gadget drivers are supported in `init.rc`:
- ConfigFS: `/config/usb_gadget/g1` (written on `sys.usb.configfs=1`)
- Legacy Android USB: `/sys/class/android_usb/android0` (written on `sys.usb.configfs=0`)

### 3.4 Recovery Filesystem Table ([`recovery.fstab`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/ramdisk-recovery-overlay/system/etc/recovery.fstab))
Every target partition is mapped by name, matching the device's physical GPT table:
```text
/dev/block/by-name/boot       /boot       emmc    defaults                 defaults
/dev/block/by-name/recovery   /recovery   emmc    defaults                 defaults
/dev/block/by-name/dtbo       /dtbo       emmc    defaults                 defaults
/dev/block/by-name/vbmeta     /vbmeta     emmc    defaults                 defaults
/dev/block/by-name/system     /system     ext4    ro                       wait
/dev/block/by-name/vendor     /vendor     ext4    ro                       wait
/dev/block/by-name/userdata   /data       ext4    noatime,nosuid,nodev     wait,check
/dev/block/by-name/cache      /cache      ext4    noatime,nosuid,nodev     wait,check
/dev/block/by-name/persist    /persist    ext4    noatime,nosuid,nodev     wait,check
/dev/block/by-name/para       /misc       emmc    defaults                 defaults
```

---

## 4. Exact Stock Rollback Commands

### Safe Backup Storage Paths
- **Primary Host Backup:** `/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/`
- **Secondary Safe Copy (Outside Project Dir):** `/home/mreza/TB8505X_backup_safe/brom_pre_unlock/`

### Path A: Rollback via Fastboot (Fastboot Accessible)
Execute directly from the host terminal while the tablet is in Fastboot mode:
```bash
# 1. Restore pristine factory vbmeta (re-enables AVB)
fastboot flash vbmeta /home/mreza/TB8505X_backup_safe/brom_pre_unlock/vbmeta.bin

# 2. Restore factory recovery
fastboot flash recovery /home/mreza/TB8505X_backup_safe/brom_pre_unlock/recovery.bin

# 3. Restore factory boot
fastboot flash boot /home/mreza/TB8505X_backup_safe/brom_pre_unlock/boot.bin

# 4. Reboot tablet to stock Android
fastboot reboot
```

### Path B: Emergency Unbrick via MediaTek Boot ROM (BROM Mode)
If the tablet fails to boot or cannot enter Fastboot:
1. Power tablet OFF (press and hold Power button for 15-20 seconds).
2. Unplug USB cable.
3. Hold **Volume Up + Volume Down** simultaneously, insert USB cable (tablet screen remains black, enters silicon BROM `0e8d:0003`).
4. Execute raw partition writes via MTKClient:
```bash
cd /home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/tools/mtkclient

# Write factory images using the tablet's exact extracted preloader for EMI timings
python3 mtk.py --preloader /home/mreza/TB8505X_backup_safe/brom_pre_unlock/preloader.bin w vbmeta /home/mreza/TB8505X_backup_safe/brom_pre_unlock/vbmeta.bin
python3 mtk.py --preloader /home/mreza/TB8505X_backup_safe/brom_pre_unlock/preloader.bin w recovery /home/mreza/TB8505X_backup_safe/brom_pre_unlock/recovery.bin
python3 mtk.py --preloader /home/mreza/TB8505X_backup_safe/brom_pre_unlock/preloader.bin w boot /home/mreza/TB8505X_backup_safe/brom_pre_unlock/boot.bin

# Hardware reset
python3 mtk.py reset
```

---

## 5. Checksum Manifest (Cryptographic Proof)

### Proposed Gate 3 Flash Artifacts ([`TB8505X-ubuntutouch/out/`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/))
| Image | Size | SHA-256 Checksum |
|---|---|---|
| `vbmeta_disabled.img` | 8,388,608 bytes | `669023be75f5a17299c7564f3e4a700ebfc50b0a3acad68c7b4ae1a79a5dc0d5` |
| `recovery.img` | 33,554,432 bytes | `232903d53332c87031608770b17079bcb8bca009cdfc06dbabfc30992e14e069` |
| `boot.img` | 33,554,432 bytes | `35f85659dde6498864d865d2e11eba8159974324b0a107a30772757809efc6e6` |
| `device_akita_row_call.tar.xz` | 38,846,332 bytes | `22d49f1cc24907f97d2ceb054a590119cb155d6c017aed34371305ac37f5426d` |
| `Module.symvers` | 523,586 bytes | `54bc45aabdd7a88e6109cf608c1a2d781a62f4e2003252ecefa7c950a767c779` |

### Stock Pre-Unlock Backup Images ([`backups/brom_pre_unlock/`](file:///home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/))
| Backup Partition | Size | SHA-256 Checksum |
|---|---|---|
| `vbmeta.bin` | 8,388,608 bytes | `fd6b79ceabaac5eccde98a7756a7c7646b5e7ba097a75e00c6d6e4fafe5cef50` |
| `recovery.bin` | 33,554,432 bytes | `644568746b1f63b2945182ce604e33ba8711a2ec753482c9818302798935e1d2` |
| `boot.bin` | 33,554,432 bytes | `716e8283ad8230fffb629c34fb233adbb98e3febbad6214c1f4963ac3c22f917` |
| `dtbo.bin` | 8,388,608 bytes | `684d5bba65e027526cd2f36685bd454a7b0737b79c7e1559e54faa86890aa5f3` |
| `nvcfg.bin` | 33,554,432 bytes | `afd1fd08523c0a1534ad36c619adfadc1e1dbead7777b5e93ea86c67277fac83` |
| `nvdata.bin` | 67,108,864 bytes | `e2f71d487ca5018c212c584ce4afa13844c544a6866a66e6f7b207f81f9960dc` |
| `nvram.bin` | 67,108,864 bytes | `229ebc4201c1de5114312931e391497492c1a7bed1b4d1abad4264b1d30a6203` |
| `persist.bin` | 50,331,648 bytes | `ba82397af836cf63cc2910fda3b116dc591070d891967f6fc990514465acdc51` |
| `preloader.bin` | 229,224 bytes | `1ee2c7df99cd99e72a9f7531d68cf55718a3a04f4bb84fc3f698a78c5b82326b` |
| `proinfo.bin` | 3,145,728 bytes | `a3e8516454d57a5ba81ab338c61a855befb7607e7b0840fcfc6080433ed3d4fc` |
| `protect1.bin` | 8,388,608 bytes | `48f487c353f343933fa33622038d42726ce8ad81d6b1c5e6dcab1060356c43e1` |
| `protect2.bin` | 9,928,704 bytes | `3db145b8b98281888ddd25831730577dcf23a93b6293bdfca237d67c9a145e54` |
| `seccfg.bin` | 8,388,608 bytes | `5f1f5a1a1aaa3102969bb6372de87e84f7d7a8f950b6b32f6274326d6c0ca415` |

---

## 6. Evidence for Continued Fastboot & BROM Access

1. **Fastboot Partition Independence:**
   - Little Kernel executes from partitions `lk` (`0x100000` / 1 MiB) and `lk2` (`0x100000` / 1 MiB).
   - Fastboot operations target only `vbmeta`, `recovery`, and `boot`.
   - `lk`, `lk2`, and `preloader` partitions are completely untouched.
   - Verified by Fastboot query:
     - `(bootloader) kernel: lk`
     - `(bootloader) fastboot-hotkey: 1`
   - Holding **Volume Down + Power** from powered-off state forces Little Kernel to boot directly into Fastboot mode before loading any boot or recovery images.

2. **Silicon Boot ROM (BROM) Hardware Permanence:**
   - BROM code is masked into the MT6761 silicon die at chip manufacturing. It is physically impossible to erase or overwrite BROM via software or eMMC writing.
   - When **Volume Up + Volume Down** are held during USB insertion, hardware pull-down resistors signal the chip's internal reset logic to jump directly into the BROM download protocol (`VID:PID = 0e8d:0003`).
   - We verified this execution path repeatedly during Gate 1: Kamakiri payload injection and DAA bypass succeeded reliably on this physical unit.

---

## 7. Unresolved Technical Risks & Mitigation Table

| Identified Risk | Severity | Root Cause | Observability & Mitigation |
|---|---|---|---|
| **LCM Display Variant in Recovery** | Medium | Custom defconfig selected `ft8201` panels; stock config also listed `ft8201m` and `nt36523b`. | **Immediate Detection:** If display remains dark upon `fastboot reboot recovery`, ADB will still enumerate (`ro.adb.secure=0`). We can run `adb shell dmesg \| grep lcm` to identify the panel probe status. Instant rollback via `fastboot flash recovery .../recovery.bin`. |
| **Touchscreen Evdev Calibration** | Low | Kernel touch driver is compiled in, but Minui coordinate transformation may need tuning. | **Mitigation:** ADB shell is fully functional as root. Commands can be issued via `adb shell` or `input tap`. |
| **Rootfs Absence on `boot.img`** | High (if boot flashed early) | Halium initramfs requires Ubuntu Touch root filesystem on `/userdata`. | **Enforced Mitigation:** Staged rollout. **Only `vbmeta` and `recovery` are flashed in Stage 1 & 2.** `boot.img` will NOT be flashed until UBports recovery boots and installs the rootfs. |
| **Host-Side Backup Loss** | Negligible | Laptop disk corruption. | **Mitigation Completed:** Redundant copies placed at both [`backups/brom_pre_unlock/`](file:///home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/) and `/home/mreza/TB8505X_backup_safe/brom_pre_unlock/`, backed by read-only tarball (`0400`). |

---

## Final Recommendation

All physical, binary, and cryptographic evidence has been comprehensively audited and verified on the host.

```text
READY FOR FLASH REVIEW
```
