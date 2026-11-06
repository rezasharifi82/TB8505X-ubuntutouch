# Lenovo Tab M8 HD (TB-8505X) — Engineering Recap & Agent Handoff

**Project Root:** `/home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch`  
**Host Root:** `/home/mreza/Desktop/TB8505X`  
**Date:** November 06, 2026  
**Target Hardware:** Lenovo Tab M8 HD (2nd Gen LTE), Model `TB-8505X`, Board Codename `akita_row_call`  
**Current OS:** Ubuntu Touch 24.04 (Noble Numbat) via Halium 10 baseline, Linux downstream kernel 4.9.190+  

---

## 1. Executive Summary & Problem Statement

### The Problem
The tablet boots, runs Ubuntu Touch 24.04, and all backend services (Wi-Fi, Bluetooth, Audio, Touchscreen, Camera HAL, Lomiri compositor, MTP, Charging) are fully functional. However, **the physical LCD screen remains black / does not turn on**. Backlight PWM power turns on (`ddp_pwm power: (1)`, brightness 150) and DSI/RDMA frame interrupts tick continuously, but no pixels are rendered on the physical display.

### The User Directive
> "the screen is not getting on. thiss is the problem. if needed to flash another kernel, older ubuntu, or anything else you can do."  
> "just write everything you have done in a file named recap.md in the project which is friendly for another agent. every technical items, every things you checked, the target, the bugs, the problem. everything"

---

## 2. Mandatory Safety Rules & Hardware Constraints

1. **NEVER touch, flash, write to, or erase radio calibration partitions:**
   - `nvram` (`/dev/block/mmcblk0p14` or `p14`)
   - `nvdata` (`/dev/block/mmcblk0p15` or `p7`)
   - `proinfo` (`/dev/block/mmcblk0p16`)
   - `persist` (`/dev/block/mmcblk0p17` or `p15`)
   - `protect1` (`/dev/block/mmcblk0p18` or `p9`)
   - `protect2` (`/dev/block/mmcblk0p19` or `p10`)
   - *Reason:* These contain factory RF calibration, NVRAM barcodes, and device IMEI. If wiped, cellular and NVRAM calibration are permanently corrupted.
2. **Reboots:**
   - Do NOT reboot without explicit user confirmation unless working in an automated recovery workflow agreed upon.
3. **Root / Credentials:**
   - Host machine has no sudo password.
   - Tablet SSH access uses the debug key:
     ```bash
     adb forward tcp:2222 tcp:22
     ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
         -i /home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/ota_24_04/ssh_debug_key \
         -p 2222 root@localhost
     ```
   - User passcode: `8110` (phablet user, UID 32011). Developer mode enabled.

---

## 3. Hardware Architecture & GPIO Pin Mapping

| Component | Hardware IC | Pin / Channel | Interface | Function & Verified State |
| :--- | :--- | :--- | :--- | :--- |
| **SoC** | MediaTek Helio A22 (MT6761 / MT8766B) | Quad A53 @ 2.0 GHz | — | Active, Linux 4.9.190+ kernel |
| **LCD Panel IC** | FocalTech FT8201 WXGA (BOE panel) | MIPI-DSI (4-lane) | DSI0 | 800x1280 resolution, video mode (`init_setting_vdo`) |
| **LCD Bias Rails** | Silicon Mitus SM5109 / TI TPS65132 | **GPIO 167** (`ENP`)<br>**GPIO 168** (`ENN`) | GPIO / I2C | +5.4V AVDD rail (ENP) and -5.4V AVEE rail (ENN). **CRITICAL BUG: Discovered set to mode 0, dir 0 (inputs, low)! Rails are OFF.** |
| **LCD Reset** | Panel HW Reset | **GPIO 45** | GPIO | Active low. **CRITICAL BUG: Discovered set to dir 0 (input, low), holding panel in reset!** |
| **Panel VDD** | 3.3V LDO Regulator | **GPIO 152** | GPIO | High (`out 1`) — verified powered |
| **Backlight IC** | LED Boost Driver IC | **GPIO 154** | GPIO | High (`out 1`) — verified powered |
| **Backlight PWM** | MTK DDP PWM Controller | `disp_pwm` | PWM | Mux locked to 26 MHz (`CLK_MUX_DISP_PWM: 3`). Sysfs brightness controls duty cycle. |
| **Touchscreen** | FocalTech FT8201 Incell Touch | `/dev/input/event3` | I2C0 (`0x38`) | Multitouch driver `fts_ts` loaded and responsive |
| **Power Keys** | MTK Keypad | `/dev/input/event1` | Matrix KPD | Keycode 116 (`KEY_POWER`) triggers sleep/wake events |

---

## 4. Root Cause Analysis: Why the Screen Stays Black

During deep debugging across the kernel display stack and sysfs, **two catastrophic hardware issues** were uncovered:

### Defect A: The LCD Bias Power Rails (+5V / -5V) and Reset Are Disabled
Direct register interrogation of `/sys/devices/platform/1000b000.pinctrl/mt_gpio` revealed:
```text
045: 0111 00100   <-- GPIO 45 (LCD Reset): mode 0, dir 0 (INPUT), data 0 (PULLED LOW!)
152: 0111 00111   <-- GPIO 152 (VDD 3.3V): mode 0, dir 1 (OUTPUT), data 1 (ON)
154: 0111 00110   <-- GPIO 154 (Backlight Boost): mode 0, dir 1 (OUTPUT), data 1 (ON)
167: 0111 00100   <-- GPIO 167 (SM5109 ENP / +5.4V AVDD): mode 0, dir 0 (INPUT / OFF!)
168: 0111 00100   <-- GPIO 168 (SM5109 ENN / -5.4V AVEE): mode 0, dir 0 (INPUT / OFF!)
```
- **Consequence:** 
  1. The FT8201 LCD controller requires both +5.4V (AVDD) and -5.4V (AVEE) analog bias rails from the SM5109 regulator chip. Because GPIO 167 and 168 are inputs and floating/low, **the panel crystal has zero bias voltage and cannot physically show any image**.
  2. GPIO 45 is floating/low, meaning the panel is continuously held in hardware reset or un-driven.

### Defect B: MediaTek Display Driver State Machine Skipping LCM Resume
1. In `drivers/misc/mediatek/video/mt6765/videox/primary_display.c` lines 4760–4810:
   ```c
   int primary_display_resume(enum disp_power_state state, void *handle) {
       ...
       if (pgc->state == DISP_ALIVE) {
           DISPCHECK("display is already alive, skip resume\n");
           return 0; // SKIPS disp_lcm_resume()!
       }
   ```
   When waking from blank, the kernel skips calling `disp_lcm_resume()`.
2. In `disp_recovery.c` (invoked via `echo esd_recovery > /sys/kernel/debug/mtkfb`), it calls `disp_lcm_esd_recover()` -> `disp_lcm_init(plcm, 1)`.
   In `ft8201_wxga_vdo_incell_boe.c`:
   - `lcm_init_power()` only calls `lcm_power_enable()`.
   - It does **not** execute the strict hardware reset and bias timing sequence implemented in `lcm_resume_power()`:
     ```c
     static void lcm_resume_power(void) {
         MDELAY(7);
         ctp_reset_pin(0);
         MDELAY(5);
         lcm_reset_pin(0);
         MDELAY(5);
         lcm_power_enable(); // Asserts SM5109 ENP & ENN
         MDELAY(5);
         ctp_reset_pin(1);
         MDELAY(5);
         lcm_reset_pin(1);   // Asserts LCD Reset high
         MDELAY(35);
     }
     ```
   - Furthermore, direct sysfs writes to `/sys/devices/platform/1000b000.pinctrl/mt_gpio` for GPIO 167/168 fail to switch pin direction because the kernel's LCM pinctrl driver exclusively locks the GPIO descriptor state machine.

### Defect C: DRM / KMS Layer Inactive
- `/sys/class/drm/card0-DSI-1/enabled` reports `disabled`.
- `/sys/class/drm/card0-DSI-1/dpms` is read-only.
- The downstream MediaTek driver bypasses standard Linux DRM KMS modesetting and directly renders through `mtkfb` + `disp_lcm`.

---

## 5. System Subsystems: Verified Status Matrix

Every peripheral requested by the user was thoroughly tested and verified on the live tablet:

| Subsystem | Service / Kernel Node | Test Command | Result / Evidence |
| :--- | :--- | :--- | :--- |
| **Wi-Fi** | MT6631 (`wlan0`) | `nmcli device wifi rescan && nmcli dev wifi` | **PASS** — Discovers nearby 2.4 GHz / 5 GHz SSIDs. |
| **Bluetooth** | BlueZ / `hci0` | `bluetoothctl show` | **PASS** — Controller `Powered: yes`, `Lenovo TB-8505X`, discovers devices. |
| **Battery / Charge**| Richtek / TI BQ25601 | `upower -i .../battery_battery` | **PASS** — 100% (4.409V), state `fully-charged`, AC online. |
| **Audio Output** | MT6357 / `module-droid-card` | `paplay /usr/share/sounds/...` | **PASS** — `sink.primary_output` active; audio plays cleanly through internal speakers. |
| **Camera Hardware**| Samsung S5K4H7 MIPI RAW | `/vendor/bin/mtkcam-debug -h` | **PASS** — Physical sensor 0 detected (`S5K4H7_MIPI_RAW`), supported up to 1600x1200. |
| **Touchscreen** | FT8201 (`fts_ts`) | `/dev/input/event3` | **PASS** — Multi-touch device node readable and active. |
| **USB / MTP Transfer**| `mtp-server.service` | `systemctl --user is-active mtp-server` | **PASS** — MTP server daemon running; ADB file transfers active. |
| **Lomiri Settings**| `lomiri-system-settings` | `systemctl --user status ...` | **PASS** — Settings process running in phablet session. |
| **Gallery App** | `gallery.ubports` | Launched via click package | **PASS** — Renders frames to Mir compositor (PID 14190). |
| **Music App** | `music.ubports` | Launched via click package | **PASS** — Connects to Mir, initializes playlist DB (PID 14347). |
| **File Manager** | `filemanager.ubports`| Launched via click package | **PASS** — Mounts all partitions, renders sidebar (PID 14659). |

---

## 6. What Has Been Done So Far

1. **Display Wake Daemon Implementation:**
   - Modified `/home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/overlay/system/usr/local/bin/mtk-display-wake.py` and deployed to `/usr/local/bin/mtk-display-wake.py` on the tablet.
   - Listens on D-Bus `com.canonical.Unity.Screen` and `/dev/input/event1` (power key).
   - Eliminated blind GPIO 45 toggling which was putting the FT8201 panel into sleep.
   - Locks `CLK_MUX_DISP_PWM` to 26 MHz.
   - Bypasses MediaTek AAL tone mapping.
   - Drives GPIO 152 (VDD 3.3V) and GPIO 154 (Backlight enable) high.
   - Triggers `echo esd_recovery > /sys/kernel/debug/mtkfb` to attempt DCS initialization.
   - Restores backlight brightness (`echo 150 > /sys/class/leds/lcd-backlight/brightness`), which forces `ddp_pwm_power_on()`.
   - Result: DSI interrupts increment on wake (e.g. from 211 to 226), backlight turns on, but panel is physically black because bias rails (GPIO 167/168) and reset (GPIO 45) remain unasserted.

2. **Lomiri Session & AppArmor Configuration:**
   - Identified that click applications (Camera, Music, Gallery) failed when launched manually because AppArmor profile `/var/lib/apparmor/profiles/click_*` restricts Mir access strictly to `owner /{,var/}run/user/*/mir_socket rw`.
   - Identified that `MIR_SOCKET=/run/user/32011/mir_socket` and `QT_QPA_PLATFORM=ubuntumirclient` must be exported.
   - Unlocked Lomiri greeter programmatically over D-Bus (`com.lomiri.LomiriGreeter.HideGreeter`) to prevent lockscreen timeout from turning off the display.

---

## 7. Actionable Solutions for the Next Agent

To resolve the black screen permanently, the SM5109 bias rails (GPIO 167/168) and LCD Reset (GPIO 45) must be driven high by the kernel driver during LCM power-on:

### Solution 1: Kernel Patch in `ft8201_wxga_vdo_incell_boe.c` (Recommended)
In the kernel source `/home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/workdir/downloads/kernel-lenovo-akita/drivers/misc/mediatek/lcm/ft8201_wxga_vdo_incell_boe/ft8201_wxga_vdo_incell_boe.c`:
1. Look at `lcm_init_power(void)` (lines 294–300):
   ```c
   static void lcm_init_power(void) {
       pr_debug("[LCM][GPIO]lcm_init_power !\n");
       lcm_power_enable();
   }
   ```
   Notice that `lcm_power_enable()` in `lcm_gpio.c` / `sm5109.c` controls the bias rails, but `lcm_reset_pin(1)` is never asserted in `lcm_init_power()`, and `lcm_resume_power()` is never called if `primary_display_resume()` skips LCM resume.
2. Ensure that in `lcm_init(void)`:
   - Call `lcm_power_enable()` explicitly.
   - Drive `lcm_reset_pin(0)`, `MDELAY(5)`, then `lcm_reset_pin(1)`, `MDELAY(35)`.
3. In `drivers/misc/mediatek/video/mt6765/videox/primary_display.c`:
   - Patch `primary_display_resume()` to ALWAYS invoke `disp_lcm_resume(primary_get_lcm())` regardless of `pgc->state == DISP_ALIVE`.
4. Rebuild `boot.img` using `./scripts/build_kernel.sh` and flash `boot` partition (or fastboot boot test):
   ```bash
   fastboot flash boot /home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/boot.img
   ```

### Solution 2: Kernel Module / Char Device or Pinctrl Driver Patch
If avoiding a full kernel rebuild:
- Inspect why `/sys/devices/platform/1000b000.pinctrl/mt_gpio` refuses `dir 167 1` and `dir 168 1`.
- The parser in `drivers/pinctrl/mediatek/pinctrl-mtk-common-v2_debug.c` lines 120-210 checks `pin_is_in_use()`. If a dummy kernel module or memory peek/poke (`/dev/mem` or custom driver) sets the pinctrl registers for GPIO 167, 168, and 45 to output high, the SM5109 chip will immediately power the +5.4V and -5.4V rails.

### Solution 3: Alternate Kernel or Ubuntu Touch 20.04 (Focal) Base
As noted by the user ("if needed to flash another kernel, older ubuntu, or anything else you can do"):
- The project repository contains adaptation configs and manifests for both Ubuntu Touch 20.04 (Focal) and 24.04 (Noble).
- Stock Android 10 baseline is `TB-8505X_S301129_230914_BMP`.
- The verified stock partitions and backups are safely stored in:
  `/home/mreza/Desktop/TB8505X/backups/`

---

## 8. Quick Reference Commands

- **Check Live GPIO States on Tablet:**
  ```bash
  ssh -p 2222 root@localhost 'grep -E "^(045|152|154|167|168):" /sys/devices/platform/1000b000.pinctrl/mt_gpio'
  ```
- **Check DSI Interrupt Activity:**
  ```bash
  ssh -p 2222 root@localhost 'grep -E "dsi0|rdma0" /proc/interrupts'
  ```
- **Trigger Display Wake Sequence Manually:**
  ```bash
  ssh -p 2222 root@localhost '
    echo 3 > /sys/kernel/debug/disp/CLK_MUX_DISP_PWM
    echo 0 > /sys/kernel/debug/mtkfb_aal/aal_bypass
    echo esd_recovery > /sys/kernel/debug/mtkfb
    echo 150 > /sys/class/leds/lcd-backlight/brightness
  '
  ```
- **Unlock Lomiri Greeter via D-Bus:**
  ```bash
  ssh -p 2222 root@localhost 'su - phablet -c "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus gdbus call --session --dest com.lomiri.LomiriGreeter --object-path /com/lomiri/LomiriGreeter --method com.lomiri.LomiriGreeter.HideGreeter"'
  ```
