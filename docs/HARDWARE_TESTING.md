# Hardware Integration & Subsystem Testing Plan — Lenovo TB-8505X

This document establishes the empirical testing protocol, commands, and expected outcomes for validating hardware subsystems on the Lenovo Tab M8 HD (`akita_row_call`).

---

## 1. Subsystem Verification Matrix

| Subsystem | Hardware Controller / Bus | Kernel Node / Interface | User Space Service | Verification Command |
|---|---|---|---|---|
| **Display** | Novatek NT35521 (MIPI-DSI) | `/dev/graphics/fb0`, `/dev/mtk_disp_mgr` | Mir 1.x / Lomiri Shell | `mir-kiosk` or `systemctl status lomiri` |
| **Backlight** | MT6370 PMIC Backlight | `/sys/class/leds/lcd-backlight/brightness` | `repowerd` / `upower` | `echo 128 > /sys/class/leds/lcd-backlight/brightness` |
| **Touchscreen** | FocalTech FT6336U (I2C) | `/dev/input/event1` | Libinput / Qt5 | `evtest /dev/input/event1` |
| **PowerVR GPU** | Rogue GE8300 | `/dev/pvrsrvkm`, `/dev/pvr_sync` | libhybris EGL / GLESv2 | `test_egl` / `glmark2-es2-wayland` |
| **Wi-Fi** | MediaTek CONSYS MT6761 | `wlan0` (nl80211) | NetworkManager / `wpa_supplicant` | `nmcli device wifi list` |
| **Bluetooth** | MT6631 Bluetooth | BlueZ `hci0` | `bluebinder` + `bluetoothd` | `bluetoothctl show` |
| **Audio** | MT6357 PMIC + I2S Codec | `/dev/snd/*` | PulseAudio (`module-droid-card`) | `paplay /usr/share/sounds/freedesktop/stereo/complete.oga` |
| **Cellular Data**| MediaTek MD1 LTE Modem | `/dev/ccci*` | `ofono` + `mtkrild` | `rilctl` / `ofono-test` |
| **Battery / PMIC**| MT6357 Fuel Gauge | `/sys/class/power_supply/battery/` | `upowerd` | `cat /sys/class/power_supply/battery/capacity` |
| **Charge Control**| Lenovo Battery Protect | `/sys/class/power_supply/battery/charging_enable` | System scripts | `echo 0 > /sys/class/power_supply/battery/charging_enable` |

---

## 2. Testing Runbooks

### 2.1 Graphics & Compositor Pipeline
1. Confirm character devices exist with `0666` permissions:
   ```bash
   ls -la /dev/pvrsrvkm /dev/pvr_sync /dev/ion
   ```
2. Run libhybris standalone test:
   ```bash
   test_egl
   ```
3. Test Mir rendering without full shell:
   ```bash
   mir_demo_client_default
   ```

### 2.2 Audio Testing Runbook
1. Verify PulseAudio recognizes the droid card sink:
   ```bash
   pactl list sinks
   ```
2. Test speaker audio output:
   ```bash
   speaker-test -t wav -c 2
   ```
3. Test 3.5mm headphone jack detection:
   ```bash
   evtest /dev/input/event* # Listen for SW_HEADPHONE_INSERT
   ```

### 2.3 Cellular & Telephony Runbook
1. Query oFono modem state:
   ```bash
   /usr/share/ofono/scripts/list-modems
   ```
2. Enable modem:
   ```bash
   /usr/share/ofono/scripts/enable-modem
   /usr/share/ofono/scripts/online-modem
   ```
3. Verify cellular registration and signal strength:
   ```bash
   /usr/share/ofono/scripts/get-serving-cell-information
   ```
