# Phase 2 Preflight & Implementation Checklist — Lenovo TB-8505X

This checklist details the exact operational steps required to transition from Phase 1.5 (Validation) to Phase 2 (Firmware & Backup) and Phase 3 (Kernel Build).

---

## Preflight Gate: Non-Destructive Operations

### Stage 1: Host Environment & Tooling Preparation
- [x] Host environment checked via [`scripts/host/check_env.sh`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/scripts/host/check_env.sh) (Ubuntu 26.04.1, 10.9 GiB RAM, 172 GiB disk).
- [x] Non-destructive device detection tested via [`scripts/device/detect_device.sh`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/scripts/device/detect_device.sh).
- [x] Firmware verification tooling ready at [`scripts/firmware/verify_firmware.sh`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/scripts/firmware/verify_firmware.sh).
- [x] Safe backup scripts ready at [`scripts/backup/backup_partitions.sh`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/scripts/backup/backup_partitions.sh).
- [ ] Install `mtkclient` on host Linux (`pip3 install pyusb libusb pycryptodome`).

### Stage 2: Factory Firmware Acquisition
- [ ] Download `software_fix_v7.6.2.10_setup.exe` from Lenovo.
- [ ] Connect tablet to Lenovo Software Fix, select Rescue, and download ROM `TB-8505X_S301129_230914_BMP_SVC`.
- [ ] Copy extracted firmware folder to `~/Desktop/TB8505X/firmware/`.
- [ ] Run `./scripts/firmware/verify_firmware.sh ~/Desktop/TB8505X/firmware/TB-8505X_S301129_230914_BMP_SVC`.
- [ ] Verify magic bytes (`ANDROID!` on `boot.img`, `AVB0` on `vbmeta.img`).

### Stage 3: Pre-Unlock BROM Partition Backup
- [ ] Power OFF the tablet completely.
- [ ] Connect USB cable while holding **Volume Up + Volume Down**.
- [ ] Run `python3 mtk r nvram,nvdata,nvcfg,proinfo,persist,protect1,protect2,seccfg,boot,vbmeta ~/Desktop/TB8505X/backups/brom_pre_unlock/`.
- [ ] Validate dumped file sizes against scatter map.
- [ ] Validate non-zero entropy for `nvram.bin`, `proinfo.bin`, `persist.bin`.
- [ ] Generate and verify `SHA256SUMS.txt` outside Git.

### Stage 4: Kernel Source Preparation
- [x] Extract authoritative factory kernel `.config` from stock `boot.img` ([`kernel/stock_kernel.config`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/kernel/stock_kernel.config)).
- [ ] Clone candidate tree `https://github.com/who53/kernel-lenovo-akita.git`.
- [ ] Apply AppArmor LSM configuration (`CONFIG_SECURITY_APPARMOR=y`) to `akita_row_call_defconfig`.
- [ ] Apply AppArmor race fix from `kernel-lenovo-amar` to `security/apparmor/apparmorfs.c`.
- [ ] Download hermetic Android Clang `clang-r353983c` and `aarch64-linux-android-4.9` toolchains.
- [ ] Execute test compilation of `Image.gz-dtb` on host (without flashing).

---

## Authorization Gate: Destructive Hardware Operations

> [!CAUTION]
> **STOP. DO NOT PROCEED TO STAGE 5 WITHOUT EXPLICIT USER WRITTEN APPROVAL.**

### Stage 5: Bootloader Unlock & Device Testing
- [ ] Request and receive explicit human authorization to unlock bootloader.
- [ ] Execute `fastboot flashing unlock` and confirm via hardware **Volume Up** on tablet.
- [ ] Patch `vbmeta.img` byte 123 -> `0x03` to disable verification.
- [ ] Flash patched `vbmeta_disabled.img`.
- [ ] Flash compiled `halium-boot.img`.
- [ ] Deploy Ubuntu Touch 20.04 rootfs to `system` partition.
- [ ] Capture boot logs via USB serial / `dmesg`.
