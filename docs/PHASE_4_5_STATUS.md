# Phase 4.5 Status Report — Build Artifact Validation & Pre-Unlock Backup Preparation

| Status Dimension | Assessment | Notes |
|---|---|---|
| **Phase Milestone** | **Phase 4.5 Completed — Phase 2 Pre-Unlock Backup Ready** | All build deliverables verified, architecture clarified, backup commands corrected. |
| **Artifact Validation** | **100% Passed** | Bit-level inspection of `boot.img`, `recovery.img`, and `device_akita_row_call.tar.xz`. |
| **Kernel Verification** | **100% Passed** | Monolithic build, zero modules (`=m`), AppArmor active, PowerVR GE8300 active. |
| **MTKClient Verification** | **100% Passed** | BROM code `0x6761` verified, 1-to-1 syntax corrected, physical connection documented. |
| **Backup Storage** | **100% Ready** | `~/Desktop/TB8505X/backups/brom_pre_unlock/` created with `0700` permissions outside Git. |
| **Device State** | **Locked & Unmodified** | Bootloader locked (`unlocked: no`), battery healthy (**3874 mV**), zero writes made. |

---

## 1. Summary of Verified Deliverables

1. **[`out/boot.img`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/boot.img):**
   - Header v2, base `0x40000000`, kernel `0x40080000`, ramdisk `0x51b00000`, DTB `0x47880000`.
   - Linux 4.9.190+ compiled with Google Clang `r353983c`.
   - Discrete Halium 10 initramfs with automatic userdata mounting and journal recovery.
   - AVB 1.0 footer appended, total size exactly `33,554,432` bytes (32 MiB).
2. **[`out/recovery.img`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/recovery.img):**
   - Matching Header v2 bootloader layout.
   - Unified UBports ARM64 recovery ramdisk with root `adbd`, `fastbootd`, `system-image-upgrader`.
   - Total size exactly `33,554,432` bytes (32 MiB).
3. **[`out/device_akita_row_call.tar.xz`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/device_akita_row_call.tar.xz):**
   - Complete adaptation archive containing `partitions/` and `/opt/halium-overlay/`.
   - Hardware udev rules ([`70-akita.rules`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/overlay/system/usr/lib/udev/rules.d/70-akita.rules)) for PowerVR GPU, ION, sync fences.
   - PulseAudio 48kHz configuration, GBinder API 29 configuration, Android Keystore init overrides.
4. **[`scripts/backup/validate_backup.sh`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/scripts/backup/validate_backup.sh):**
   - Automated test script validating partition dumps against physical GPT sizes and non-zero entropy.

---

## 2. In-Tree Patches and Source Traceability

- **Kernel Repository:** [`who53/kernel-lenovo-akita`](https://github.com/who53/kernel-lenovo-akita.git) (`main` branch)
- **Base Commit Hash:** `07692302d5db321648a8036ed751f9224e45b9ff`
- **Patches Applied:**
  - `0001-enable-apparmor-defconfig.patch` (`af866bfb...`): Enables AppArmor LSM and default security model.
  - `0002-fix-apparmor-clang-parentheses-equality.patch` (`ca388224...`): Fixes Clang `-Wparentheses-equality` error in `domain.c`.
  - `0003-fix-apparmor-crypto-vla-in-struct-for-clang.patch` (`43d16e87...`): Fixes Clang VLAIS error via `SHASH_DESC_ON_STACK` in `crypto.c`.

---

## 3. Deployment Dependency Status

```text
[x] 1. Kernel Binary (boot.img)               --> BUILT & VALIDATED
[x] 2. Recovery Environment (recovery.img)     --> BUILT & VALIDATED
[x] 3. Adaptation Overlay (tar.xz)             --> BUILT & VALIDATED
[x] 4. Factory Vendor Partition (/vendor)      --> PRESERVED ON PHYSICAL DEVICE
[ ] 5. Pre-Unlock BROM Calibration Backup      --> AWAITING PHYSICAL USB HANDSHAKE
[ ] 6. Little Kernel Bootloader Unlock         --> REQUIRES USER AUTHORIZATION
[ ] 7. Halium 10 GSI Container (system.img)    --> PENDING DOWNLOAD IN PHASE 5
[ ] 8. Ubuntu Touch Rootfs (rootfs.img)        --> PENDING DOWNLOAD IN PHASE 5
```

---

## 4. Next Operational Steps

1. **Step 1:** User conducts physical BROM handshake (hold Vol+ and Vol-, plug USB) while host executes corrected MTKClient backup command.
2. **Step 2:** Host executes `./scripts/backup/validate_backup.sh` to confirm 100% integrity of all 12 dumped partitions.
3. **Step 3:** Request explicit user written approval to unlock the bootloader (`fastboot flashing unlock`).
4. **Step 4:** Acquire generic Halium 10 GSI and Ubuntu Touch rootfs, and deploy to physical device.
