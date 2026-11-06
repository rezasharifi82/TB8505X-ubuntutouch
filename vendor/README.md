# Vendor Blobs & Proprietary Binaries

## Redistribution & Legal Notice

Proprietary vendor blobs extracted from the official stock firmware (`vendor.img`) are copyrighted by Lenovo and MediaTek Inc. and are **NOT** redistributed in this Git repository.

## Extraction Instructions

Vendor files must be obtained directly from the verified stock firmware package:
- Package: `TB-8505X_S301129_230914_BMP_SVC`
- Source image: `vendor.img` (ext4)

Because the tablet uses a Treble partition architecture with a separate `vendor` partition (`/dev/block/mmcblk0p36`), the Ubuntu Touch system boots against the **stock, untouched vendor partition on disk**, minimizing the need to extract or re-package proprietary blobs into the rootfs.

Required HAL interfaces utilized by Ubuntu Touch via `libhybris`:
- `hwcomposer.mt6761.so` (Graphics display)
- `gralloc.mt6761.so` (Buffer allocation)
- `audio.primary.mt6761.so` (Audio routing)
- MediaTek RIL / telephony daemons
- WPA Supplicant & Wi-Fi kernel driver
