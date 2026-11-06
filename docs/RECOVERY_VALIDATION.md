# Factory Recovery & Disaster Restoration Strategy — Lenovo TB-8505X

## 1. Official Factory Firmware Baseline

The authoritative stock factory firmware package corresponding to the physical tablet:

| Property | Value |
|---|---|
| **Build Fingerprint** | `Lenovo/LenovoTB-8505X/TB-8505X:10/QP1A.190711.020/S301129_230914_BMP:user/release-keys` |
| **Android Version** | Android 10 (API 29) |
| **Security Patch** | `2023-08-05` |
| **SoC / Scatter** | MediaTek MT6761 (`MT6761_Android_scatter.txt`) |
| **Lenovo Service Package** | `TB-8505X_S301129_230914_BMP_SVC.zip` |
| **Acquisition Source** | Lenovo RSA (Rescue and Smart Assistant) / Software Fix |

---

## 2. Partition Image Manifest & Scatter Layout

The factory firmware archive provides the following bit-accurate images:

| Image Name | Scatter Partition | Offset | Size (Hex) | Purpose |
|---|---|---|---|---|
| `preloader_akita.bin` | `preloader` | `0x0` | `0x40000` | eMMC Boot Block 0 Initializer |
| `lk.bin` | `lk` | `0x1600000` | `0x100000` | Little Kernel primary bootloader |
| `lk2.bin` | `lk2` | `0x1700000` | `0x100000` | Little Kernel secondary bootloader |
| `boot.img` | `boot` | `0x3880000` | `0x2000000` | Factory Linux 4.9.190+ kernel |
| `recovery.img` | `recovery` | `0x80000` | `0x2000000` | Factory Android recovery |
| `dtbo.img` | `dtbo` | `0x5880000` | `0x800000` | Device tree blob overlay |
| `vbmeta.img` | `vbmeta` | `0x1e80000` | `0x800000` | Stock AVB 2.0 verification tree |
| `system.img` | `system` | `0x9180000` | `0xf3800000` | Factory Android 10 system (3.8 GiB) |
| `vendor.img` | `vendor` | `0xfc980000` | `0x32000000` | Factory MediaTek vendor HALs (800 MiB) |
| `product.img` | `product` | `0x12e980000` | `0x2000000` | Factory product customizations |
| `md1img.img` | `md1img` | `0x7800000` | `0x6400000` | MediaTek cellular modem DSP firmware |
| `spmfw.img` | `spmfw` | `0x1c80000` | `0x100000` | System power manager firmware |
| `scp.img` | `scp1` / `scp2` | `0x1a80000` | `0x100000` | Sensor co-processor firmware |
| `sspm.img` | `sspm_1` / `sspm_2` | `0x1880000` | `0x100000` | Secure co-processor firmware |
| `tee.img` | `tee1` / `tee2` | `0x6080000` | `0x500000` | Microtrust / Beanpod TEE trustlets |

---

## 3. Tiered Disaster Recovery Runbooks

### Tier 1: Fastboot Accessible (Soft Brick / Non-Booting Rootfs)
If the tablet can enter Fastboot mode (`fastboot devices` responds):
```bash
# 1. Restore stock boot and AVB tree
fastboot flash boot stock_images/boot.img
fastboot flash vbmeta stock_images/vbmeta.img
fastboot flash recovery stock_images/recovery.img

# 2. Restore system and vendor if modified
fastboot flash system stock_images/system.img
fastboot flash vendor stock_images/vendor.img

# 3. Wipe userdata and cache
fastboot erase userdata
fastboot erase cache

# 4. Reboot to factory Android
fastboot reboot
```

### Tier 2: Bootloader Damaged / Hard Loop (MediaTek BROM Mode)
If Little Kernel does not start or hangs before Fastboot:
1. Power tablet OFF.
2. Hold **Volume Up + Volume Down**, connect USB.
3. Use MTKClient to flash core partitions:
   ```bash
   python3 tools/mtkclient/mtk.py w \
     boot,recovery,vbmeta,dtbo \
     stock_images/boot.img,stock_images/recovery.img,stock_images/vbmeta.img,stock_images/dtbo.img
   ```
4. Reset device via MTKClient:
   ```bash
   python3 tools/mtkclient/mtk.py reset
   ```

### Tier 3: Radio / Identity Restoration (NVRAM Corruption)
If cellular signal is missing, IMEI displays `000000000000000`, or Wi-Fi MAC is randomized:
1. Power tablet OFF, hold **Volume Up + Volume Down**, connect USB.
2. Restore the pre-unlock calibration backup:
   ```bash
   python3 tools/mtkclient/mtk.py w \
     nvram,nvdata,nvcfg,proinfo,persist,protect1,protect2 \
     ~/Desktop/TB8505X/backups/brom_pre_unlock/nvram.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/nvdata.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/nvcfg.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/proinfo.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/persist.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/protect1.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/protect2.bin
   ```

---

## 4. Remaining Uncertainties & Mitigations

| Risk / Uncertainty | Severity | Technical Assessment | Mitigation |
|---|---|---|---|
| **eMMC Preloader Wiping** | High | If `preloader_a` / `mmcblk0boot0` is wiped, the SoC cannot init DRAM. | `mtkclient` read/write commands target the `user` partition by default and do not touch `boot0`/`boot1` unless `--parttype boot1` is explicitly passed. |
| **Anti-Rollback (ARB) Trip** | Medium | Flashing an older Android build can blow eFuses or trigger LK refusal. | The project uses the exact matching build ID (`S301129_230914_BMP`). Never flash pre-2022 firmware. |
| **Fastboot 36.x AVB Header Bug** | Low | Fastboot client fails to disable verity with `--disable-*` flags. | Disproven for our workflow; we use manual byte-patching or `avbtool` hash footers. |
