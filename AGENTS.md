# AGENTS.md — Developer and AI Agent Guidelines

## 1. Project Overview & Mission

This repository contains the device adaptation, kernel configurations, build scripts, patches, and engineering documentation for porting **Ubuntu Touch (Lomiri)** to the **Lenovo Tab M8 HD (TB-8505X)**, codenamed **`akita_row_call`** (MediaTek MT6761 / MT8766).

The ultimate goal is a fully functional, reproducible, and maintainable Ubuntu Touch port running on the physical tablet.

---

## 2. Strict Safety Rules (Non-Negotiable)

Any human or AI agent operating in this repository **MUST** adhere to these rules:

1. **NO AUTOMATIC FLASHING OR UNLOCKING:**
   - Never run `fastboot flashing unlock`, `fastboot flash`, `fastboot erase`, `fastboot format`, or any other partition write without explicit confirmation from the human developer.
2. **NO PRIVATE DATA IN GIT:**
   - Never commit device serial numbers (e.g., `HGR2YTWY`), IMEI numbers, Wi-Fi/Bluetooth MAC addresses, radio calibration files, or partition dumps (`nvram`, `nvdata`, `nvcfg`, `proinfo`, `persist`, `protect1/2`, `seccfg`).
   - Store all device-specific backups outside the git tree (e.g. in `~/Desktop/TB8505X/backups/`).
3. **NO REDISTRIBUTION OF PROPRIETARY FIRMWARE/BLOBS:**
   - Do not commit multi-gigabyte stock firmware images (`system.img`, `vendor.img`, `boot.img`). Document their download and verification procedures instead.
4. **NO DESTRUCTIVE ACTIONS BY DEFAULT:**
   - All flashing and backup scripts must default to a **dry-run** mode and require explicit confirmation flags to perform actions.

---

## 3. Confirmed Target Hardware

| Property | Value | Notes |
|---|---|---|
| **Manufacturer / Model** | Lenovo TB-8505X | Lenovo Tab M8 HD (2nd Gen LTE) |
| **Board / Codename** | `akita_row_call` | LTE + voice call variant |
| **Android Platform** | `mt6761` | MediaTek Helio A22 |
| **Boot Hardware** | `mt8766` | Tablet-specific SoC revision |
| **CPU Architecture** | `arm64-v8a` (4x Cortex-A53) | 64-bit kernel, 64-bit userspace |
| **RAM / Internal Storage** | 2 GB LPDDR3 / 32 GB eMMC | Model TB-8505X |
| **Display Panel** | Novatek NT35521 MIPI-DSI | 800 x 1280 (HD), 60 Hz, 240 dpi |
| **Touch Controller** | Capacitive Touch at `0x38` on I2C0 | Multi-touch (up to 10 points) |
| **GPU** | Imagination PowerVR GE8300 | Rogue architecture |
| **Connectivity** | MT6631 / MT6635 | Wi-Fi 802.11 a/b/g/n/ac, BT 5.0, FM, GPS |
| **PMIC / Audio Codec** | MediaTek MT6357 | Integrated PMIC and audio codec |
| **Charger IC** | Richtek RT9471 & TI BQ25601 | Dual switching charger support |
| **Stock Android** | Android 10 (SDK 29) | Build: `TB-8505X_S301129_230914_BMP` |
| **Stock Kernel** | Linux 4.9.190+ | MediaTek downstream tree |
| **Partitioning** | Non-A/B, Treble-enabled, No `super` | Direct ext4 partitions (`system`, `vendor`, `data`) |

---

## 4. Architecture & Porting Strategy

The recommended porting architecture is the **UBports Halium 10 Generic Adaptation Pipeline**:

- **Halium 10 Base:** Matches the device's native Android 10 vendor implementation (`vendor/` partition remains untouched stock Android 10 blobs).
- **Standalone Kernel:** Compile downstream Linux 4.9 kernel using Google prebuilt Android Clang/GCC toolchain with AppArmor and Halium configurations enabled.
- **Rootfs:** Ubuntu Touch 20.04 (Focal) arm64 generic rootfs (`ubports/ubuntu-touch`).
- **Adaptation Package:** Built using `halium-generic-adaptation-build-tools`, containing:
  - Device info configuration (`deviceinfo`)
  - Device overlay (`overlay/` containing `udev` rules, `gbinder.conf`, `pulseaudio` configs, `repowerd` settings)
  - `halium-boot.img` (compiled kernel + Halium initramfs)

---

## 5. Development Conventions

1. **Scripts:** All shell scripts must start with `set -euo pipefail`, provide clear `--help` text, validate exit codes, and print informative, color-coded logging.
2. **Documentation:** Keep documentation up-to-date in `docs/`. When a bug or decision is made, update `docs/DECISIONS.md` and `docs/KNOWN_ISSUES.md`.
3. **Git Commits:** Do not push to remote git without explicit authorization from the user.
