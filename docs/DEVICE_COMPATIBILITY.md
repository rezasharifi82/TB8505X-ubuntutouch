# Hardware Compatibility Matrix — Lenovo TB-8505X

This document tracks the expected and verified functional support for each hardware component under Ubuntu Touch (Lomiri).

## Compatibility Status Overview

| Component | Status | Driver / Interface | Engineering Assessment & Strategy |
|---|---|---|---|
| **Lomiri UI & Shell** | 🟢 Likely Supported | Mir 1.x / Wayland / libhybris | Rendered via PowerVR GLES 3.2 on HWC2. |
| **Display Panel** | 🟢 Likely Supported | Novatek NT35521 (MIPI-DSI) | Native kernel framebuffer driver; 60 Hz 800x1280. |
| **Touchscreen** | 🟢 Likely Supported | Cap Touch @ 0x38 (`i2c0`) | Standard Linux `evdev` touch input node. |
| **Wi-Fi** | 🟢 Likely Supported | MT6631 (`wlan0`) | Linux standard `cfg80211` / `wpa_supplicant`. |
| **Bluetooth (Basic)** | 🟢 Likely Supported | MT6631 (`bluebinder`) | Bluetooth HIDL HAL connected to BlueZ. |
| **Audio (Speaker)** | 🟢 Likely Supported | MT6357 PMIC + Amp @ 0x34 | PulseAudio `module-droid-card` routing to HAL. |
| **Battery & Charging** | 🟢 Likely Supported | RT9471 / BQ25601 | Standard Linux `power_supply` sysfs class. |
| **USB Debugging / OTG**| 🟢 Confirmed Working | Linux Android Gadget (`configfs`) | ADB over USB and USB Host/OTG supported. |
| **Suspend / Resume** | 🟡 Requires Validation | `repowerd` / Linux PM | Needs testing with MTK deep sleep states (`spm`). |
| **Cellular (Data/RIL)**| 🟡 Requires Integration | MediaTek MD1 / Ofono | MediaTek RIL protocol requires `mtk.conf` in ofono. |
| **Audio (Headphone)** | 🟡 Requires Integration | MT6357 Jack Detect | Auto-switching often requires `sound-script` hook. |
| **Camera (Rear/Front)**| 🟠 Development Needed | MediaTek ISP (`camerahalserver`) | libhybris camera stack requires specific format bindings. |
| **GPS / GNSS** | 🟠 Development Needed | MT6631 GPS EMI | AGPS daemon integration with `geoclue`. |
| **Offline Charging** | 🔴 Low Priority / Untested| Preloader / LK | MediaTek fastboot charging mode. |

---

## Component-Specific Implementation Details

### 1. Display & Mir Compositor
- **Resolution:** 800x1280 portrait (landscape default for tablet dock).
- **Pixel Density:** 240 dpi (`GridUnit` scale in `deviceinfo/halium.yaml`).
- **Buffer Management:** `gralloc.mt6761.so` uses ashmem/ion buffer handles.

### 2. Audio Routing Architecture
- Under stock Android, audio routing is handled by `audioserver` calling `audio.primary.mt6761.so`.
- Under Ubuntu Touch, PulseAudio uses `module-droid-card` to communicate with the Android audio HAL.
- A known quirk on this SoC (noted in reference repo and community threads) is that 3.5mm jack insertion may not automatically mute internal speakers without a custom udev/PulseAudio routing rule.

### 3. Cellular Telephony (LTE Voice & Data)
- TB-8505X includes a full LTE Cat-4 modem with voice capability (`akita_row_call`).
- Ubuntu Touch manages cellular connections through **Ofono**.
- Ofono talks to the MediaTek `rild` daemon via Binder using the `ril_subscription.d/mtk.conf` plugin configuration.
