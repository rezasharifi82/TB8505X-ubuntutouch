# LineageOS Installation Plan — Lenovo Tab M8 HD (TB-8505X)

**Device:** Lenovo Tab M8 HD (TB-8505X), MediaTek MT6761 / MT8766 (Helio A22), board codename `akita_row_call`  
**Current OS:** Ubuntu Touch 24.04 (Halium 10 pipeline), kernel 4.9.190+  
**Vendor:** Stock Android 10 vendor partition, build `TB-8505X_S301129_230914_BMP`  
**Bootloader:** UNLOCKED (`verifiedbootstate=orange`)  
**Fastboot:** WORKING (device serial `HGR2YTWY`)  
**Backups:** `/home/mreza/Desktop/TB8505X/backups/` (brom_pre_unlock etc.)  
**Partition scheme:** Non-A/B, Treble-compliant, direct `system` + `vendor` partitions, **no `super`** (no dynamic partitions)  
**Target:** LineageOS (official/unofficial build OR a Project Treble GSI)

---

## STATUS: RESEARCH ONLY — DO NOT FLASH, DO NOT MODIFY THE TABLET

This document is an **installation plan only**. No commands here should be executed without explicit coordinator approval. Per the shared context (`/tmp/tablet_agents/CONTEXT.md`), **NEVER** touch `nvram`, `nvdata`, `proinfo`, `persist`, `protect1`, or `protect2` — wiping any of these destroys IMEI/baseband calibration and can hard-brick the MediaTek device.

---

## 1. RESEARCH FINDINGS

### 1a. Is there an official or unofficial LineageOS build for TB-8505X?

**No.** Verified against the official LineageOS device wiki:

- https://wiki.lineageos.org/devices/ — full supported-device list. The **Lenovo** section lists only: `kuntao` (P2), `A6020` (Vibe K5), `kingdom` (Vibe Z2 Pro), `YTX703L/F` (Yoga Tab 3 Plus LTE/Wi-Fi), `heart` (Z5 Pro GT), `zippo` (Z6 Pro). **No TB-8505X / Tab M8 HD / `akita_row_call` entry exists.** Wiki warning states: "Devices not listed are **not supported.** Builds for other devices can **not be used**. Nearly identical is **not** sufficient."
- https://wiki.lineageos.org/devices/akita/ — codename `akita` = **Google Pixel 8a** (Tensor G3), NOT the MediaTek `akita_row_call`. Do not confuse them.
- XDA Developers Lenovo manufacturer index: https://xdaforums.com/c/lenovo.12002/ — forums exist for P11, Legion Y700, Tab K11 Gen2 (TB336FU), Yoga Tab 3 Plus, Z5 Pro GT, Vibe series, etc. **There is NO dedicated Lenovo Tab M8 HD (TB-8505X) forum.** Guessing forum IDs (e.g. `lenovo-tab-m8-hd.10769`) does not resolve to a Tab M8 thread.

**Conclusion:** No official LineageOS build exists, and no known unofficial LineageOS port for TB-8505X was found via wiki/XDA. The only realistic path is a **Project Treble Generic System Image (GSI)**.

### 1b. Does the device appear on the LineageOS supported list (any MT6761 devices)?

**No.** The wiki device list contains no MediaTek MT6761 (Helio A22) device at all. LineageOS officially supports very few MediaTek devices, and none match this SoC. You must treat this as **fully unsupported** — you are on your own.

### 1c. Android version / GSI options — the practical path for unsupported MT6761

| Option | Viability for TB-8505X | Notes |
|--------|------------------------|-------|
| Official LineageOS device build | ❌ None exists | Not on wiki |
| Unofficial LineageOS port | ❌ None found | No XDA/GitHub port located |
| Project Treble GSI (LineageOS/AOSP) | ✅ **Practical path** | Device is Treble (Android 10), non-A/B, has working fastboot |

**GSI version to choose:** The stock vendor is **Android 10**. The safest GSI match is a **LineageOS 17.1 (Android 10) "no-vendor" arm64 a-only GSI** — same Android generation as the vendor, so HIDL HAL versions are most likely compatible. Newer GSIs (LineageOS 20/21/22) may boot but risk HAL-version mismatches (camera, sensors, display) against an Android 10 vendor.

**GSI sources:**
- https://github.com/TrebleDroid/treble_experimentations — community successor to phhusson's `treble_experimentations`, builds TrebleDroid GSI (AOSP/LineageOS-based). XDA threads by phhusson: https://forum.xda-developers.com/search.php?do=finduser&u=1915408&starteronly=1
- https://github.com/phhusson/treble_experimentations — **archived** by owner on 2025-01-27, read-only. Original source of the well-known phh Treble GSI patches.
- Official LineageOS GSI: LineageOS does **not** host official GSI images under a stable, well-known SourceForge project (the commonly cited `sourceforge.net/projects/treble-experiences` path returned 404 — do not rely on it). Prebuilt GSI images must be sourced from community builds (XDA/Telegram) or built from source via `build-rom.sh`.

**GSI variant for MT6761:** `arm64` + `a-only` (non-A/B) + `no-vendor` (keep stock vendor) + optionally `-go` (low-RAM; Tab M8 HD is typically 2–3 GB RAM). If the GSI includes its own `boot.img`, evaluate whether to use it (see section 2).

### 1d. Exact flash steps — unlock status, tools, partition layout, vbmeta

**Unlock status:** Already unlocked (`verifiedbootstate=orange`), fastboot works. No unlocking step needed. **Do NOT relock the bootloader** after flashing a GSI — relocking with a non-stock/verity-disabled vbmeta will brick the device.

**Tools available:**
1. **fastboot** (already working, device `HGR2YTWY`) — can flash partitions the MTK fastboot implementation exposes (typically `boot`, `recovery`, sometimes `system`/`vendor`, `vbmeta`). May be limited on MediaTek.
2. **SP Flash Tool** (Windows) / **Flash Tool** — the reliable MediaTek way to flash raw partitions (`system`, `vendor`, `boot`, `vbmeta`, `preloader`, `lk`, etc.) via scatter file. Best for full system/vendor replacement.
3. **mtkclient** (Python, https://github.com/bkerler/mtkclient) — works in MTK metadata/BOOTROM/preloader modes; can read/write partitions when fastboot is insufficient. Good fallback/rescue tool.

**Partition layout (typical MediaTek non-A/B Treble, MT6761):**
- `boot`, `recovery`, `system`, `vendor`, `vbmeta`, `vbmeta_system` (if present), `userdata`, `cache`
- MTK-specific (DO NOT WIPE): `nvram`, `nvdata`, `proinfo`, `persist`, `protect1`, `protect2`, `seccfg`, `frp`, `tee1`, `tee2`
- **No `super`** — no dynamic partitions to resize; `system` and `vendor` are fixed-size partitions. Verify GSI `system.img` fits the stock `system` partition size before flashing.

**vbmeta / verity:** A GSI has its own `vbmeta` with verification disabled. You must flash vbmeta **with** `--disable-verity --disable-verification`, otherwise Android will refuse to boot (verity failure / "your device is corrupt"). On fastboot:
```
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
```
If a `vbmeta_system` partition exists, handle it identically (disable verification on it too).

### 1e. Known gotchas on MT6761 with AOSP + stock vendor blobs

| Area | Expected behavior | Risk |
|------|-------------------|------|
| **RIL / telephony** | TB-8505X is typically Wi-Fi-only; no cellular modem → telephony N/A. If an LTE variant exists, the MTK RIL depends on `nvram`/`nvdata` + vendor RIL HAL; GSI + stock vendor RIL often breaks IMEI/data. | High if LTE; never touch `nvram`/`nvdata` |
| **Camera HAL** | MT6761 camera uses vendor-specific proprietary HALs (often `mediacodec`/`mtk-camera` HIDL). Stock Android 10 vendor camera HAL may not match a newer GSI's camera framework → camera preview/capture broken. | High |
| **Sensors** | Sensor HAL (accelerometer, gyro, light, proximity) is vendor-implemented. May work if HIDL versions match; otherwise sensors missing/wrong. | Medium |
| **Display / backlight / touch** | Display panel driver lives in the **kernel** (stock 4.9.190+). GSI userspace talks to kernel via gralloc/hwcomposer HALs from vendor. Mismatch → no display, wrong resolution, no backlight. Existing UT issue: power button cannot wake screen (kernel display patch in progress by coordinator). | High |
| **Audio** | MTK audio HAL (audio.primary.mt6761 etc.) is vendor-specific. Stock vendor audio HAL + GSI audio policy may mismatch → no speaker/mic (UT already reports speakers not working). | High |
| **Kernel mismatch** | Stock kernel 4.9.190+ may lack drivers/config needed by newer GSI userspace. Keeping stock `boot.img` risks boot loop or missing hardware; using GSI `boot.img` risks losing MTK-specific kernel drivers (charging, display, touch). | High |

**Bottom line:** A GSI + stock vendor on MT6761 is **experimental**. Expect camera/audio/sensors/display to be partially or fully broken. The tablet already has several hardware issues under UT; a GSI may improve software but will not fix missing kernel drivers.

---

## 2. FEASIBILITY: FLASH GSI `system.img` KEEPING VENDOR + BOOT?

**Is it feasible?** In principle, **yes** — this is exactly what a `no-vendor` Treble GSI is designed for: flash GSI `system` over the existing `system`, keep stock `vendor` + stock `boot` (kernel), wipe data, disable verity/verification. Because the device is Treble and non-A/B with direct `system`/`vendor`, there is no `super` to complicate things.

**Caveats that make it NOT guaranteed:**

1. **Android version match.** Stock vendor ships Android 10. Use a **LineageOS 17.1 (A10)** GSI for the best HAL match. A LineageOS 20+ GSI runs newer HIDL HAL versions against an Android 10 vendor → likely HAL mismatch (camera/sensors/display break).
2. **Kernel.** Stock `boot.img` = kernel 4.9.190+. If that kernel has all needed MTK drivers and a compatible defconfig, the GSI userspace may boot. If not, you need the GSI's own `boot.img` (generic kernel), which may lack MTK-specific drivers → hardware (display/touch/charging) may not work.
3. **Partition sizes.** `system.img` GSI must fit in the stock `system` partition. Check with `fastboot getvar` / SP Flash Tool scatter or by reading the partition size from backups before flashing.
4. **Data must be wiped.** GSI requires a clean `/data` (format `userdata` / `fastboot erase userdata`), otherwise old UT metadata conflicts.

**Safest concrete plan (recommended):**

1. **Backup first.** Verify backups exist in `/home/mreza/Desktop/TB8505X/backups/` (especially `boot`, `system`, `vendor`, `vbmeta`, and the brom_pre_unlock backup). Never wipe radio partitions.
2. **Test boot to fastboot.** Confirm `fastboot devices` sees `HGR2YTWY` and `fastboot getvar all` works (gives partition/slot info and `verifiedbootstate`).
3. **Flash LineageOS 17.1 (A10) arm64 a-only no-vendor GSI `system.img`** → `system` partition.
4. **Keep stock `vendor` and stock `boot`** initially (least invasive — preserves MTK kernel + vendor HALs).
5. **Flash vbmeta with verification disabled.**
6. **Format/wipe `userdata`** (and `cache`).
7. **Reboot.** If it boots → good. If boot loop / no display:
   - Try the GSI's own `boot.img` (flash `boot`), keeping stock `vendor`.
   - If still broken, flash GSI `vendor.img` too (full GSI replacement).
   - If still broken, restore stock `system`/`vendor`/`boot` from backups and abort — return to UT.
8. **Never flash/modify** `nvram`, `nvdata`, `proinfo`, `persist`, `protect1`, `protect2`.

---

## 3. RECOMMENDED PATH

**Recommended:** LineageOS 17.1 (Android 10) **arm64 a-only no-vendor GSI**, flashed over stock Android 10 vendor + stock kernel boot, with verity/verification disabled and data wiped.

**Why this over alternatives:**
- Official/Unofficial device build: none exists.
- Newer GSI (A11+): higher risk of vendor HAL mismatch.
- Full GSI (system+vendor+boot): more invasive; stock MTK vendor HALs + kernel are more likely to support MT6761 hardware than a generic GSI kernel/vendor.

**Fallback if GSI fails:** Restore stock Android 10 (or current UT) from backups via SP Flash Tool / fastboot and remain on Ubuntu Touch. Do not force an unsupported GSI if basic hardware (display/touch) fails.

---

## 4. STEP-BY-STEP FLASH INSTRUCTIONS (READ-ONLY PLAN)

> ⚠️ **Do not execute without coordinator approval.** These commands are for reference. The tablet must remain unmodified.

### Phase 0 — Preparation (host PC, no tablet modification)

1. Install platform-tools (fastboot/adb) on host.
2. Verify backups: `ls -la /home/mreza/Desktop/TB8505X/backups/`
3. Download the GSI: LineageOS 17.1 `lineage-17.1-*-arm64-aonly-novendor.img` (or `.img.xz` to decompress), and its matching `vbmeta.img` if bundled. Keep a copy of stock `boot.img`/`vendor.img`/`system.img` from backups.
4. On the tablet: boot to bootloader/fastboot (method varies; on Lenovo typically Vol- + Power while connecting USB, or `adb reboot bootloader` if adb works — **adB over RNDIS is available per CONTEXT**).

### Phase 1 — Verify fastboot & read partition info

```
fastboot devices
# expect: HGR2YTWY fastboot

fastboot getvar all
# note: verifiedbootstate, partition sizes (system/vendor), max-download-size
```

### Phase 2 — Disable verity/verification and flash vbmeta

```
# Flash vbmeta with verification OFF (required for GSI)
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img

# If vbmeta_system exists:
fastboot --disable-verity --disable-verification flash vbmeta_system vbmeta_system.img
```

### Phase 3 — Flash GSI system (keep stock vendor + boot)

```
# Option A (fastboot, if MTK fastboot exposes system):
fastboot flash system lineage-17.1-arm64-aonly-novendor.img

# Option B (if fastboot rejects system — MediaTek fastboot is often limited):
# Use SP Flash Tool with the MT6761 scatter file to write system.img to the SYSTEM partition,
# OR use mtkclient in metadata mode:
#   python mtk.py e system lineage-17.1-arm64-aonly-novendor.img   (write)
# See mtkclient docs for the correct mode (bootrom/metadata/preloader).
```

Keep stock `vendor` and `boot` (do **not** flash them yet).

### Phase 4 — Wipe data (required for GSI)

```
fastboot erase userdata
fastboot format userdata   # if supported; otherwise erase is enough
fastboot erase cache
```

### Phase 5 — Reboot

```
fastboot reboot
```

### Phase 6 — If it does not boot (iterate, one change at a time)

1. Reboot to fastboot, flash GSI `boot.img` (replace stock kernel), keep stock `vendor`:
   `fastboot flash boot lineage-17.1-...-boot.img`
2. If still broken, also flash GSI `vendor.img` (full GSI vendor), keep stock `boot`:
   `fastboot flash vendor lineage-17.1-...-vendor.img`
3. If still broken, restore stock from backups and stop.

### Phase 7 — Post-boot verification (see Section 7)

---

## 5. RISKS & SAFETY

### Radio / calibration partitions — MUST NOT BE WIPED (enforced by CONTEXT.md)

| Partition | What it holds | Consequence of wiping |
|-----------|---------------|-----------------------|
| `nvram` | Modem/RF calibration, MAC, IMEI config | Lost IMEI, no cellular/Wi-Fi calibration, possible hard brick |
| `nvdata` | Modem NVRAM data | Same as nvram |
| `proinfo` | Product/region info, boot args | Boot failure, wrong region |
| `persist` | Persistent vendor data, sensors calibration | Sensor/camera calibration lost |
| `protect1` / `protect2` | TrustZone/DRM/anti-theft | DRM breakage, possible brick |

**Rule:** Any `fastboot erase`, `fastboot format`, or SP Flash Tool operation must **exclude** these partitions. Only `system`, `vendor`, `boot`, `recovery`, `vbmeta`, `vbmeta_system`, `userdata`, `cache` may be touched.

### Other risks

- **Brick / boot loop:** Unsupported GSI on MT6761 may not boot. Have stock backups ready and SP Flash Tool/mtkclient available to restore.
- **No display/touch:** If the kernel display driver (already faulty under UT — power button can't wake screen) doesn't match GSI gralloc/hwcomposer, you get a black screen. You may flash blind.
- **No camera/audio/sensors:** Very likely partially broken due to MTK vendor HAL mismatch.
- **Data loss:** Wiping `userdata` deletes everything on internal storage. Back up personal data first.
- **Verity/verification:** Forgetting `--disable-verity --disable-verification` on vbmeta → Android refuses to boot ("corrupt").
- **Relocking bootloader:** Never relock with a GSI/verity-disabled vbmeta → hard brick.

### Safety checklist before any flash
- [ ] Backups verified (boot, system, vendor, vbmeta, preloader)
- [ ] Bootloader confirmed unlocked (`verifiedbootstate=orange`)
- [ ] fastboot sees device `HGR2YTWY`
- [ ] Radio partitions (`nvram`,`nvdata`,`proinfo`,`persist`,`protect1`,`protect2`) excluded from all operations
- [ ] vbmeta flashed with `--disable-verity --disable-verification`
- [ ] `userdata` wiped/formatted
- [ ] Recovery plan: know how to restore stock via SP Flash Tool/mtkclient if boot fails

---

## 6. DOWNLOAD LINKS (verified URLs)

| Resource | URL | Notes |
|----------|-----|-------|
| LineageOS device wiki (confirm no TB-8505X) | https://wiki.lineageos.org/devices/ | Verified: Lenovo section has no Tab M8 |
| LineageOS `akita` page (NOT this device — it's Pixel 8a) | https://wiki.lineageos.org/devices/akita/ | Codename collision warning |
| LineageOS FAQ | https://wiki.lineageos.org/faq.html | "Devices not listed are not supported" |
| TrebleDroid GSI (successor to phhusson) | https://github.com/TrebleDroid/treble_experimentations | Build TrebleDroid/Lineage GSI via `build-rom.sh` |
| phhusson treble_experimentations (archived) | https://github.com/phhusson/treble_experimentations | Archived 2025-01-27, original GSI patches |
| phhusson XDA threads | https://forum.xda-developers.com/search.php?do=finduser&u=1915408&starteronly=1 | GSI release threads |
| XDA Lenovo manufacturer index (no TB-8505X forum) | https://xdaforums.com/c/lenovo.12002/ | Verified: no Tab M8 HD forum |
| mtkclient (MediaTek fallback/rescue) | https://github.com/bkerler/mtkclient | Read/write MTK partitions outside fastboot |
| SP Flash Tool (MediaTek flashing) | https://spflashtool.com/ | Windows; needs MT6761 scatter file |

**No official LineageOS GSI download URL could be verified.** The commonly cited `sourceforge.net/projects/treble-experiences` returned 404 — do not use it. Obtain a LineageOS 17.1 arm64 a-only no-vendor GSI from a trusted community build or build it yourself from the TrebleDroid/phhusson sources.

---

## 7. VERIFICATION STEPS (after boot, if it boots)

1. `adb shell getprop ro.build.version.release` — expect `10` (LineageOS 17.1)
2. `adb shell getprop ro.lineage.device` / `ro.product.model` — should report a GSI/generic model, not TB-8505X
3. `adb shell ls -l /system` / `/vendor` — confirm GSI system mounted
4. Test: display/backlight, touch, Wi-Fi, audio (speaker/mic), cameras, sensors (`dumpsys sensorservice`)
5. `adb shell dmesg` — check for kernel/driver probe failures (MTK camera/audio/display)
6. If anything critical fails, revert to stock backups rather than force the GSI.

---

## 8. COMMAND QUICK-REFERENCE (do not execute without approval)

```
fastboot devices
fastboot getvar all
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
fastboot flash system lineage-17.1-arm64-aonly-novendor.img
fastboot erase userdata
fastboot erase cache
fastboot reboot
# fallback:
fastboot flash boot lineage-17.1-...-boot.img
fastboot flash vendor lineage-17.1-...-vendor.img
# NEVER:
fastboot erase nvram   # FORBIDDEN
fastboot erase nvdata  # FORBIDDEN
fastboot erase proinfo # FORBIDDEN
fastboot erase persist # FORBIDDEN
fastboot erase protect1 # FORBIDDEN
fastboot erase protect2 # FORBIDDEN
```

---

## DISCLAIMER

This is a **research plan only**. No flashing or tablet modification was performed. The TB-8505X (MT6761) has no official or known unofficial LineageOS support; a Treble GSI is experimental and camera/audio/sensors/display are likely broken. Proceed only with coordinator approval, verified backups, and a working restore path (SP Flash Tool / mtkclient). The author is not responsible for bricked devices, data loss, or lost IMEI.
