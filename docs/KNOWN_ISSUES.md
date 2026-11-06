# Known Issues Registry — Lenovo TB-8505X

This document tracks identified bugs, hardware quirks, build errors, and their verified mitigations.

---

### ISSUE-001: Fastboot 36.x `--disable-verity` AVB Header Parse Failure
- **Component:** Fastboot Client / Android Verified Boot (AVB)
- **Symptoms:** `fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img` exits with error: `fastboot: error: Failed to find AVB_MAGIC at offset: 0`.
- **Root Cause:** Fastboot 36.x platform tools bug when passing `--disable-*` flags to MediaTek AVB 1.1/2.0 headers.
- **Applied Fix:** Manually patch byte `123` of `vbmeta.img` to `0x03` (`HASHTREE_DISABLED | VERIFICATION_DISABLED`) and flash without the `--disable-*` flags.
- **Test Result:** Verified working; boots with `ro.boot.verifiedbootstate=orange`.

---

### ISSUE-002: Host Toolchain Incompatibility on Ubuntu 26 Host
- **Component:** Host Build System (Python 3.14 / GCC 15 / OpenJDK 25)
- **Symptoms:** Full AOSP 10 or LineageOS 17.1 source trees fail to configure or build due to deprecated `distutils`, syntax changes in C23, and Java version mismatches.
- **Root Cause:** Android 10 build infrastructure was engineered for Python 2.7/3.8, GCC 8/9, and OpenJDK 8/9.
- **Applied Fix:** Adopt Standalone Kernel Adaptation workflow using Google Android hermetic Clang (`clang-r353983c`) and GCC (`aarch64-linux-android-4.9`).
- **Test Result:** Host dependency checks pass cleanly without modifying system-wide packages.

---

### ISSUE-003: AppArmor Inode Initialization Race Condition
- **Component:** Linux Kernel 4.9 (AppArmor LSM)
- **Symptoms:** Kernel crashes with null pointer dereference or deadlock when AppArmor policy is enforced on mount.
- **Root Cause:** Race condition between inode deallocation and security filesystem traversal present in early 4.9 AppArmor backports.
- **Applied Fix:** Apply upstream AppArmor fix: `apparmor: fix race between freeing data and fs accessing it` (present in UBports `kernel-lenovo-amar`).
- **Test Result:** Documented and verified in UBports MediaTek 4.9 trees.

---

### ISSUE-004: 3.5mm Headphone Jack Auto-Mute Quirk
- **Component:** Audio Routing (MediaTek MT6357 PMIC)
- **Symptoms:** Plugging in wired headphones routes audio to headphones but does not mute the internal loudspeaker.
- **Root Cause:** MediaTek's `audio.primary.mt6761.so` expects SurfaceFlinger / Android AudioManager broadcast events to trigger hardware speaker muting.
- **Proposed Fix:** Implement PulseAudio udev event rule and jack-detection script (`sound-script` hook in `/usr/share/halium-overlay/usr/libexec/lxc-android-config/`).
- **Status:** In progress; tracked for Phase 6.

---

### ISSUE-005: Android Keystore / Keymaster Blocking Standalone Boot
- **Component:** Android Init / LXC Container
- **Symptoms:** Halium container hangs during boot waiting for `wait_for_keymaster` or `keystore`.
- **Root Cause:** MediaTek Beanpod TEE keymaster daemon fails to communicate without Android trustlet services, blocking `init` completion.
- **Applied Fix:** Provide `droid-system-overlay` init overrides disabling `keystore` and `wait_for_keymaster` in `/etc/init/keystore.rc`.
- **Test Result:** Verified in `who53` adaptation tree; unblocks boot completion.

---

### ISSUE-006: Display Screensaver Interfering with Kiosk / Dock Mode
- **Component:** Power & Display Management
- **Symptoms:** Tablet display blanks or starts screensaver while plugged into dock or power source.
- **Root Cause:** Default Android/Lomiri screensaver policy activating on dock.
- **Applied Fix:** Disable dock screensaver in `repowerd` configuration (`config-default.xml`).
- **Status:** Resolved in adaptation overlay configuration.

---

### ISSUE-007: UBports Ramdisk Dynparts Default on Discrete Partition Tablet
- **Component:** Initramfs / Boot Image Generation (`halium-generic-adaptation-build-tools`)
- **Symptoms:** Halium initramfs attempts to mount `/dev/mapper/system` using device-mapper linear tables and hangs, failing to find rootfs.
- **Root Cause:** Build tools default to downloading dynamic partition ramdisks (`initrd.img-touch-arm64` from `dynparts` release) if unspecified or if `systempart=/dev/mapper/system` appears in cmdline.
- **Applied Fix:** Explicitly set `deviceinfo_prebuilt_boot_ramdisk_source="https://github.com/halium/initramfs-tools-halium/releases/download/continuous/initrd.img-touch-arm64"` and strip `/dev/mapper` references from `deviceinfo_kernel_cmdline`.
- **Status:** Verified and resolved in `deviceinfo`.

---

### ISSUE-008: Pre-Unlock Calibration Backup Catch-22
- **Component:** Device Backup & Partition Extraction
- **Symptoms:** Attempting to dump radio partitions (`nvram`, `nvdata`, `proinfo`) via ADB requires root permissions, which requires unlocking the bootloader. Unlocking the bootloader wipes `/data` and risks bricking identity before the backup exists.
- **Root Cause:** Fastboot Little Kernel (LK) does not implement the fastboot `upload` or `read` protocol command.
- **Applied Fix:** Use MediaTek Boot ROM (BROM) mode via `mtkclient` on Linux (tablet off, hold Volume Up + Volume Down, plug USB). This bypasses the bootloader and allows 100% read-only acquisition of partitions while the bootloader remains securely locked.
- **Status:** Verified and documented in `docs/BACKUP_AND_RESTORE.md`.

---

### ISSUE-009: Clang `-Wparentheses-equality` Compiler Error in AppArmor
- **Component:** Linux Kernel 4.9 (AppArmor `domain.c`)
- **Symptoms:** Kernel build fails during compilation with `error: equality comparison with extraneous parentheses [-Werror,-Wparentheses-equality]` on `((ns == profile->ns))`.
- **Root Cause:** Upstream 4.9 AppArmor tree contained redundant outer parentheses in `security/apparmor/domain.c` that Google Clang treats as a compiler error under `-Werror`.
- **Applied Fix:** Authored [`patches/kernel/0002-fix-apparmor-clang-parentheses-equality.patch`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/patches/kernel/0002-fix-apparmor-clang-parentheses-equality.patch) to remove the extraneous parentheses.
- **Status:** Resolved and verified in clean kernel build.

---

### ISSUE-010: Clang Variable-Length Array in Structure (VLAIS) Error in AppArmor
- **Component:** Linux Kernel 4.9 (AppArmor `crypto.c`)
- **Symptoms:** Kernel build fails with `error: fields must have a constant size: 'variable length array in structure' extension will never be supported` on `char ctx[crypto_shash_descsize(apparmor_tfm)]`.
- **Root Cause:** Legacy GCC allowed VLAIS as an extension, but Clang strictly prohibits variable-length arrays inside structures.
- **Applied Fix:** Authored [`patches/kernel/0003-fix-apparmor-crypto-vla-in-struct-for-clang.patch`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/patches/kernel/0003-fix-apparmor-crypto-vla-in-struct-for-clang.patch) replacing the local struct with the crypto subsystem's `SHASH_DESC_ON_STACK(desc, apparmor_tfm)`.
- **Status:** Resolved and verified in clean kernel build.

---

### ISSUE-011: Halium Build Tools Toolchain Prefix Mismatch (`arm64-` vs `aarch64-`)
- **Component:** UBports Build Tools (`halium-generic-adaptation-build-tools`)
- **Symptoms:** When `deviceinfo_kernel_arch="arm64"` was set, build tools constructed toolchain prefixes as `arm64-linux-android-` and `arm64-linux-gnu-`, triggering `Cannot use CONFIG_CC_STACKPROTECTOR_STRONG: -fstack-protector-strong not supported by compiler` because no such assembler/linker existed in `aarch64-linux-android-4.9`.
- **Root Cause:** Google Android NDK binutils uses the `aarch64-` prefix. `build-kernel.sh` expects `deviceinfo_kernel_arch="aarch64"` and translates it to `ARCH="arm64"` internally.
- **Applied Fix:** Set `deviceinfo_kernel_arch="aarch64"` in [`deviceinfo`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/deviceinfo).
- **Status:** Resolved and verified.

---

### ISSUE-012: Overlaystore Packaging Failure on Monolithic Kernel
- **Component:** Halium Build Tools (`build-kernel.sh` & `make-bootimage.sh`)
- **Symptoms:** In monolithic kernel configurations (`deviceinfo_kernel_disable_modules="true"`), `make modules_install` is skipped, leaving `${INSTALL_MOD_PATH}/lib/modules` nonexistent. `touch .halium-override-dir` subsequently failed with `No such file or directory`. Furthermore, without `RECOVERY_RAMDISK` defined, `mkbootimg.py` crashed on `--ramdisk ''`.
- **Root Cause:** Build tools assumed loadable modules exist and recovery ramdisks are always populated when `deviceinfo_has_recovery_partition="true"`.
- **Applied Fix:** Added `mkdir -p ${INSTALL_MOD_PATH}/lib/modules` to `build-kernel.sh`, guarded recovery creation in `make-bootimage.sh`, and set `deviceinfo_use_unified_recovery="true"` in `deviceinfo` to pull the official UBports ARM64 recovery ramdisk.
- **Status:** Resolved; produces bit-accurate `boot.img`, `recovery.img`, and complete `out/device_akita_row_call.tar.xz`.


---

### ISSUE-011: Erroneous Claim of Zero-Byte Ramdisk in boot.img
- **Component:** Build Documentation / Halium Boot Architecture
- **Symptoms:** Previous report claimed `boot.img` was a SAR (System-as-Root) image with a 0-byte ramdisk.
- **Root Cause:** Incomplete inspection of artifact. In reality, `make-bootimage.sh` automatically packages `initrd.img-touch-arm64` (4,106,247 bytes) into `boot.img`.
- **Resolution:** Re-audited artifact using `unpack_bootimg.py`. Confirmed Halium initramfs (`scripts/halium`) is present and functional.

---

### ISSUE-012: Missing `recovery.fstab` in Generic Recovery Ramdisk
- **Component:** Recovery Environment (`out/recovery.img`)
- **Symptoms:** UBports generic unified recovery ramdisk lacks eMMC partition mappings for TB-8505X.
- **Root Cause:** No device-specific `ramdisk-recovery-overlay` was provided in repository root.
- **Resolution:** Created `ramdisk-recovery-overlay/system/etc/recovery.fstab` with explicit GPT by-name paths. Rebuilt `recovery.img` (now verified containing `recovery.fstab`).

---

### ISSUE-013: Conflicting Partition Minor Numbers in Documentation
- **Component:** Partition Documentation (`docs/PARTITION_MAP.md`)
- **Symptoms:** Early reports listed `system` as `p35`, `boot` as `p31`, `recovery` as `p32`, and `userdata` as `p44`.
- **Root Cause:** Unverified assumptions from other MediaTek devices.
- **Resolution:** Reconstructed definitive 40-partition table from physical hardware `/dev/block/by-name/` and Little Kernel `fastboot getvar all`.

---

### ISSUE-014: ModemManager Interference with MTK BROM Serial Handshake
- **Component:** Host USB Communication / BROM Download Mode
- **Symptoms:** Plugging device in BROM mode (`0E8D:0003`) fails to trigger Kamakiri payload or causes SoC watchdog reset.
- **Root Cause:** Host ModemManager daemon attempts AT command probe on `/dev/ttyACM0` upon connection.
- **Resolution:** Documented mandatory requirement to execute `sudo systemctl stop ModemManager` (or apply udev rule `ENV{ID_MM_DEVICE_IGNORE}="1"`) prior to physical BROM connection.
