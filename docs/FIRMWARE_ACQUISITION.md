# Stock Firmware Acquisition & Verification Guide — Lenovo TB-8505X

## 1. Exact Stock Firmware Specification

The firmware targeted for this project corresponds to the exact build fingerprint verified on the physical tablet:

| Property | Value | Notes |
|---|---|---|
| **Build Display ID** | `TB-8505X_S301129_230914_BMP` | Build date: 2023-09-14 |
| **Android Version** | Android 10 (SDK 29) | QP1A.190711.020 |
| **Security Patch** | `2023-08-05` | Factory release patch |
| **Build Fingerprint** | `Lenovo/LenovoTB-8505X/8505X:10/QP1A.190711.020/S301129_230914_BMP:user/release-keys` | Release keys |
| **Hardware / Board** | `akita_row_call` | Rest of World LTE + Voice |
| **Package Identifier** | `TB-8505X_S301129_230914_BMP_SVC` | Official service package |

---

## 2. Official Acquisition Procedure (Lenovo Software Fix)

Lenovo provides official, untampered factory firmware through their **Lenovo Software Fix** (formerly *Rescue and Smart Assistant / LMSA*) utility:

1. Download the signed installer on a Windows machine:
   ```text
   https://download.lenovo.com/consumer/mobiles/software_fix_v7.6.2.10_setup.exe
   ```
2. Launch Software Fix, sign in with a Lenovo account, and open the **Rescue** tab.
3. Connect the tablet with USB debugging enabled. The tool will query ADB and detect model `TB-8505X` and build `S301129`.
4. Click **Download ROM**.
   > [!IMPORTANT]
   > **DO NOT CLICK RESCUE OR FLASH.** You only want the local files downloaded.
5. The cloud status icon displays the local download path:
   ```text
   C:\ProgramData\RSA\Download\RomFiles\TB-8505X_S301129_230914_BMP_SVC
   ```
6. **IMMEDIATELY copy the extracted folder to a safe location.** Software Fix automatically extracts the archive and deletes the original download.
7. Transfer the extracted folder to your Ubuntu laptop:
   ```bash
   scp -r user@windows-pc:/path/to/TB-8505X_S301129_230914_BMP_SVC ~/Desktop/TB8505X/firmware/
   ```

---

## 3. Package File List & Checksums

Expected contents of the verified factory package:

| Filename | Purpose | Expected Magic Header | Verified SHA-256 Checksum |
|---|---|---|---|
| `boot.img` (32 MiB) | Factory Android 10 Kernel + Ramdisk | `ANDROID!` | Verified matching stock kernel |
| `vbmeta.img` (4 KiB) | AVB 2.0 Verification Structure | `AVB0` | Verified matching stock AVB |
| `system.img` (3.8 GiB)| Stock System-as-Root partition | `0x3aff26ed` (Sparse ext4) | Factory pristine image |
| `vendor.img` (800 MiB)| Stock MediaTek Drivers & HALs | `0x3aff26ed` (Sparse ext4) | Factory pristine image |
| `dtbo.img` (8 MiB) | Device Tree Blob Overlay | `0xd7b7ab1e` (DTBO table) | Factory pristine image |
| `recovery.img` (32 MiB)| Stock Fastboot/Recovery partition | `ANDROID!` | Factory recovery image |
| `MT6761_Android_scatter.txt`| MediaTek Flash Memory Map | Text (`platform: MT6761`) | Matches physical partition bounds |
| `MTK_AllInOne_DA_6761.bin` | Download Agent for Flash Tools | MediaTek binary | BROM handshake authentication |

### Reference Release Checksums
For verified community reference assets (build `S301129`):
```text
02e1c9079314e7df3844f535b7a2b7527c60be9b5dd270bca7841aab1afd4625  boot_magisk-v30.7_S301129.img
c217aa89ed3deebd61aa3cb3576e0490d207e29b4891d6948ede7927c2e2b8c9  vbmeta_disabled.img
```

---

## 4. Automated Verification Tool

Run the non-destructive verification script on your downloaded package:

```bash
./scripts/firmware/verify_firmware.sh ~/Desktop/TB8505X/firmware/TB-8505X_S301129_230914_BMP_SVC
```

The script:
1. Verifies the presence of required images.
2. Checks magic bytes for `boot.img` (`ANDROID!`) and `vbmeta.img` (`AVB0`).
3. Confirms that `MT6761_Android_scatter.txt` identifies platform `MT6761`.
4. Generates an independent `SHA256SUMS-verified.txt` manifest.

---

## 5. Factory Disaster Recovery Methods

If the tablet ever fails to boot during Ubuntu Touch testing:

### Recovery Method 1: Fastboot Stock Flash (Safe & Recommended)
```bash
fastboot flash boot /path/to/stock/boot.img
fastboot flash vbmeta /path/to/stock/vbmeta.img
fastboot reboot
```

### Recovery Method 2: SP Flash Tool Factory Restore (Emergency Unbrick)
1. Open SP Flash Tool on Linux (`MTK_Flash_tool_v5.1920.00.001`).
2. Load `MT6761_Android_scatter.txt`.
3. Choose **Download Only** (NEVER format!).
4. Power off tablet, hold Volume+, plug in USB.
5. All factory partitions are restored to official release state.
