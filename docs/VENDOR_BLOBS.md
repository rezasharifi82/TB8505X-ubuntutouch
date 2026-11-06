# Stock Vendor Preservation & Blob Dependencies: Lenovo TB-8505X

**Target Device:** Lenovo Tab M8 HD LTE (`TB-8505X` / `akita_row_call`)  
**Partition:** `/dev/block/mmcblk0p36` (`vendor`, 800 MiB)  
**Factory Build:** `TB-8505X_S301129_230914_BMP`

---

## 1. Preservation Strategy

The vendor partition is **preserved 100% factory untouched**.

### Rationale:
1. **Proprietary MT6761 Blobs:** MediaTek hardware HALs (PowerVR Rogue GPU DDK, Focaltech touch processing, MT6357 audio tuning, MT6631 Wi-Fi NVRAM calibration, and CCCI modem drivers) are compiled against Android 10 Treble HAL interfaces.
2. **Treble Compliance:** Android 10 enforces strict separation between `/system` and `/vendor` via HIDL. Halium 10 interfaces with `/vendor` across the Binder boundary without requiring vendor partition modifications.
3. **Safety & Zero Risk:** Leaving `/vendor` untouched prevents any risk of bricking proprietary hardware calibration or wiping NVRAM mappings.

---

## 2. Essential Vendor HALs and Service Matrix

| Hardware Function | Vendor Service Binary / HAL | HIDL Interface | Ubuntu Touch Host Consumer |
| :--- | :--- | :--- | :--- |
| **Graphics (Gralloc & Composer)** | `/vendor/bin/hw/android.hardware.graphics.composer@2.2-service` | `android.hardware.graphics.composer@2.2` | `libhybris` (`libhardware`, `libEGL_hybris.so`) -> Mir / Lomiri |
| **Audio Subsystem** | `/vendor/bin/hw/android.hardware.audio@5.0-service-mediatek` | `android.hardware.audio@5.0` | `pulseaudio-modules-droid` (`arm_droid_card_custom.pa`) |
| **Cellular Modem & RIL** | `/vendor/bin/hw/rild` | `android.hardware.radio@1.4` | `oFono` + `gbinder` (`/etc/gbinder.conf`) |
| **Wi-Fi Connectivity** | `/vendor/bin/wmt_loader`, `6631_launcher` | Direct WMT driver interface | Linux kernel `wlan_gen4m` -> `NetworkManager` |
| **Bluetooth Subsystem** | `/vendor/bin/hw/android.hardware.bluetooth@1.0-service-mediatek` | `android.hardware.bluetooth@1.0` | BlueZ / `hciattach` (`/dev/stpbt`) |
| **Power Management** | `/vendor/bin/hw/vendor.mediatek.hardware.mtkpower@1.0-service` | `vendor.mediatek.hardware.mtkpower@1.0` | `powerd` |
| **Sensors** | `/vendor/bin/hw/android.hardware.sensors@2.0-service.multihal` | `android.hardware.sensors@2.0` | `sensorfw` -> Lomiri auto-rotation |
| **Cameras** | `/vendor/bin/hw/android.hardware.camera.provider@2.4-service-mediatek` | `android.hardware.camera.provider@2.4` | `droidmedia` (Future Phase) |

---

## 3. ABI Compatibility Verification

- **Architecture:** 64-bit ARM (`aarch64` / `arm64-v8a`).
- **Binder Protocol:** 64-bit MediaTek Binder protocol verified in `overlay/system/etc/gbinder.conf`.
- **Vndbinder Interface:** `/dev/vndbinder` used for vendor-internal IPC.
