# Architecture Decision Records (ADR) — Lenovo TB-8505X

This document logs critical architectural, technical, and process decisions made throughout the project lifecycle.

---

### ADR-001: Selection of Standalone Kernel Adaptation over Full AOSP Build

- **Date:** 2026-11-05
- **Status:** **ACCEPTED**
- **Context:** Building Ubuntu Touch historically offered two paths: (A) Synchronizing full Android/Halium source trees (>250 GB) and building a customized system image, or (B) Compiling the standalone kernel and pairing it with a generic Halium adaptation package using `halium-generic-adaptation-build-tools`.
- **Decision:** Adopt the **Standalone Kernel + UBports Generic Adaptation** workflow.
- **Consequences:**
  - Avoids downloading >200 GB of legacy Android 10 sources.
  - Avoids severe toolchain incompatibilities on modern Ubuntu 26 hosts (Python 3.14, GCC 15, Java 25).
  - Matches modern official UBports community porting standards (e.g. Lenovo Tab M10 `lenovo-m10-hd` and `lenovo-x606`).
  - Kernel compile time reduced to <10 minutes.

---

### ADR-002: Reusing Stock Vendor Partition In-Place (`mmcblk0p36`)

- **Date:** 2026-11-05
- **Status:** **ACCEPTED**
- **Context:** Ubuntu Touch requires Android HALs and firmware blobs. These could either be extracted, repackaged, and shipped inside the rootfs, or mounted directly from the device's factory `/vendor` partition on disk.
- **Decision:** Mount `/dev/block/mmcblk0p36` in-place inside the Android container.
- **Consequences:**
  - Avoids copyright and redistribution liabilities.
  - Reduces the device adaptation package size from >1 GB to <100 MB.
  - Ensures 100% binary compatibility with the tablet's factory calibration, Wi-Fi firmware, and modem stack.

---

### ADR-003: Resolution of Fastboot 36.x vbmeta Verification Bug

- **Date:** 2026-11-05
- **Status:** **ACCEPTED**
- **Context:** Modern `fastboot 36.x` fails with `Failed to find AVB_MAGIC at offset: 0` when executing `--disable-verity --disable-verification flash vbmeta vbmeta.img`.
- **Decision:** Patch byte `123` of `vbmeta.img` directly to `0x03` (`HASHTREE_DISABLED | VERIFICATION_DISABLED`) using `dd`, and flash without `--disable-*` flags.
- **Consequences:**
  - Eliminates fastboot client parsing errors.
  - Reliably disables verified boot on Android 10 MediaTek targets.
  - Fully tested and verified on build `S301129_230914`.

---

### ADR-004: Hermetic Android Toolchain Isolation for Kernel Builds

- **Date:** 2026-11-05
- **Status:** **ACCEPTED**
- **Context:** The host development system runs Ubuntu 26.04.1 with GCC 15.2 and Python 3.14. Linux 4.9 cannot be compiled directly with host GCC 15 due to C23 language specification changes.
- **Decision:** Use Google's prebuilt Android Clang (`clang-r353983c`) and GCC (`aarch64-linux-android-4.9`) toolchains.
- **Consequences:**
  - Completely isolates kernel compilation from host GCC versions.
  - Produces bit-for-bit reproducible kernel binaries.
  - Avoids polluting the host operating system with legacy compiler packages.

---

### ADR-005: Strict Safety Policy on Partition Flashing

- **Date:** 2026-11-05
- **Status:** **ACCEPTED**
- **Context:** MediaTek devices feature sensitive NVRAM, calibration, and security partitions that can be irreparably damaged by unauthorized or automated flashing commands.
- **Decision:** Autonomous tools must default to dry-run mode and never execute partition writes (`flash`, `erase`, `format`, `unlock`) without explicit human confirmation.
- **Consequences:**
  - Complete protection against device bricking or radio data loss.
  - Full transparency for the human developer.

---

### ADR-006: Pre-Unlock BROM Acquisition via `mtkclient`

- **Date:** 2026-11-05
- **Status:** **ACCEPTED**
- **Context:** Radio calibration partitions (`nvram`, `nvdata`, `proinfo`, `persist`) must be backed up before any flashing. ADB dumping requires root (`su`), which requires bootloader unlocking, but unlocking triggers an immediate factory wipe of `/data` and risks bricking identity before the backup exists.
- **Decision:** Adopt MediaTek Boot ROM (BROM) acquisition using `mtkclient` on Linux as the primary backup strategy.
- **Consequences:**
  - Enables 100% read-only acquisition while the bootloader remains locked.
  - Preserves unique factory calibration and IMEI before any wipe.
  - Requires physical interaction (holding Volume Up + Volume Down while plugging USB).

---

### ADR-007: Explicit Non-Dynparts Halium Ramdisk Selection

- **Date:** 2026-11-05
- **Status:** **ACCEPTED**
- **Context:** The TB-8505X has discrete partitions (`system` 3.8 GiB, `vendor` 800 MiB) without Android dynamic partitions (`super`). UBports build tools default to downloading `dynparts` ramdisks unless explicitly configured.
- **Decision:** Explicitly configure `deviceinfo_prebuilt_boot_ramdisk_source` to point to the non-dynparts `continuous` release of `initrd.img-touch-arm64`, and remove all `/dev/mapper` parameters from `deviceinfo_kernel_cmdline`.
- **Consequences:**
  - Initramfs boots directly to the discrete `/dev/block/by-name/system` partition.
  - Prevents boot hangs caused by searching for nonexistent device-mapper super tables.

---

### ADR-008: Hermetic Clang In-Tree AppArmor Bug Mitigations

- **Date:** 2026-11-05
- **Status:** **ACCEPTED**
- **Context:** Compiling Linux 4.9 AppArmor with Google Android Clang `r353983c` revealed two compiler failures: extraneous parentheses in `domain.c` triggering `-Werror,-Wparentheses-equality`, and a variable-length array inside a structure (`VLAIS`) in `crypto.c` rejected by Clang.
- **Decision:** Author and maintain two clean in-tree patches ([`0002`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/patches/kernel/0002-fix-apparmor-clang-parentheses-equality.patch) and [`0003`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/patches/kernel/0003-fix-apparmor-crypto-vla-in-struct-for-clang.patch)) that clean up the syntax and adopt `<crypto/hash.h>` `SHASH_DESC_ON_STACK(desc, apparmor_tfm)` instead of disabling security or compiler checks.
- **Consequences:**
  - Maintains strict compiler warning standards (`-Werror`).
  - Retains full AppArmor cryptographic hash validation for Click and Snap confinement.
  - Automatically applied by `build.sh` prior to compilation.

---

### ADR-009: Inclusion of Unified UBports Recovery in Deviceinfo Specification

- **Date:** 2026-11-05
- **Status:** **ACCEPTED**
- **Context:** The tablet features a dedicated 32 MiB physical `recovery` partition (`mmcblk0p2`). Without `deviceinfo_use_unified_recovery="true"`, build tools omitted recovery ramdisk downloads, causing `mkbootimg.py` to fail on an empty ramdisk argument.
- **Decision:** Enable `deviceinfo_use_unified_recovery="true"` in `deviceinfo` to pull the official UBports generic ARM64 recovery ramdisk and build a signed 32 MiB `recovery.img` alongside `boot.img`.
- **Consequences:**
  - Generates a matched, bootable `recovery.img` equipped with Halium ADB sideloading and rootfs extraction capabilities.
  - Matches the physical partition size (33,554,432 bytes) with AVB 1.0 footer.


---

### Decision 11: Reconstructed Physical Partition Map & Minor Number Resolution
- **Context:** Previous development reports contained conflicting partition numbers (system reported as p35, boot as p31, recovery as p32, userdata as p44).
- **Decision:** Cross-referenced hardware sysfs `/dev/block/platform/bootdevice/by-name/` with Little Kernel `fastboot getvar all` to establish definitive partition numbers:
  - `boot` = `mmcblk0p28` (32 MiB)
  - `recovery` = `mmcblk0p2` (32 MiB)
  - `vendor` = `mmcblk0p36` (800 MiB)
  - `system` = `mmcblk0p37` (3896 MiB)
  - `userdata` = `mmcblk0p38` (23.46 GiB)
- **Rationale:** Prevents catastrophic brick scenarios (e.g. flashing boot to `mmcblk0p31` which is TrustZone `tee2`, or flashing system to `mmcblk0p35` which is 32MB `product`).

### Decision 12: Recovery Ramdisk Overlay & `recovery.fstab`
- **Context:** Generic UBports unified recovery ramdisk contained no device-specific partition table, rendering `system-image-upgrader` unable to mount eMMC partitions.
- **Decision:** Added `ramdisk-recovery-overlay/system/etc/recovery.fstab` containing explicit mappings for `/boot`, `/recovery`, `/system`, `/vendor`, `/data`, `/cache`, and `/misc`.
- **Rationale:** Ensures recovery environment can mount partitions and perform automated system installation and OTA upgrades.

### Decision 13: Static Binder Devnodes on Linux 4.9.190
- **Context:** Previous reports claimed `CONFIG_ANDROID_BINDERFS=y`. Audit revealed kernel 4.9 does not support BinderFS.
- **Decision:** Use static binder nodes configured via `CONFIG_ANDROID_BINDER_IPC=y` and `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder,anbox-binder,anbox-hwbinder,anbox-vndbinder"`.
- **Rationale:** Matches Linux 4.9 Android 10 kernel implementation bit-for-bit without requiring complex out-of-tree VFS backports.

### Decision 14: Overhaul of udev Rules for Least-Privilege
- **Context:** `70-akita.rules` contained extraneous Qualcomm definitions and permissive `0666` modes across sensitive nodes.
- **Decision:** Purged all Qualcomm entries; assigned MediaTek display, GPU, audio, and modem nodes to standard Linux groups (`video`, `audio`, `input`, `dialout`, `plugdev`) with minimal privileges.
- **Rationale:** Enhances security container isolation while satisfying Lomiri and Mir hardware requirements.

### Decision 15: Official UBports Focal (20.04 OTA-12) Rootfs Integration
- **Context:** Requirement to obtain verified, reproducible Ubuntu Touch ARM64 root filesystem.
- **Decision:** Standardized on official UBports signed pool release: `https://system-image.ubports.com/pool/rootfs-5df07ff97f843f279147b2347c8ac151df3cf2a4554df4b6779d588e01a2a87b.tar.xz` (SHA-256: `890982ce86b2597aa56bb424e81f92eeffae2afa51c3d3509a048a80ad407558`).
- **Rationale:** Production-tested rootfs with full Lomiri desktop shell and Halium 9+ container support.
