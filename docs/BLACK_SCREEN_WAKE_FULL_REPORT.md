# Lenovo Tab M8 HD (TB-8505X) — Black Screen After Sleep/Wake
## Complete Investigation Report, Test Log, Root-Cause Analysis and Fix Plan

**Repository:** `TB8505X-ubuntutouch`
**Device:** Lenovo Tab M8 HD LTE, `TB-8505X`, board `akita_row_call`
**SoC:** MediaTek MT6761 / MT8766 (Helio A22 class), arm64
**OS:** Ubuntu Touch 24.04.5 LTS (Halium 10 userspace, Android 10 vendor)
**Kernel:** `4.9.190+ #1 SMP PREEMPT Fri Nov 6 15:32:03 +0330 2026`
**Stock reference:** Android 10, build `TB-8505X_S301129_230914_BMP`
**Report date:** 2026-11-06
**Status:** Root cause narrowed to the display/backlight resume path; final kernel patch not yet flashed.

---

# 1. Executive Summary

After the screen is switched off (power button, inactivity blank, or any display suspend)
and then switched back on, the tablet **stays completely black**. No image and **no
backlight glow at all**. The only reliable recovery is a full reboot.

This report documents:

1. Every diagnostic performed on the live device.
2. The exact hardware and software state at each step.
3. Confirmed facts and rejected hypotheses.
4. The current leading root-cause theory with source-code evidence.
5. The proposed kernel fix and the exact rebuild/flash procedure (not executed yet).
6. A list of open questions for a second reviewer/model.

The single most important confirmed fact:

> The panel is **not** being suspended in the failing scenario (GPIO167/GPIO168 stay HIGH,
> GPIO152 stays HIGH, DSI video keeps streaming), yet the **backlight enable GPIO154 drops
> LOW and never comes back**. Forcing GPIO154 HIGH manually still produced no light, which
> means a second enable condition (bias/AVDD or PWM boost) is also missing.

---

# 2. Symptom (verbatim behaviour)

| Step | Observed |
|---|---|
| Cold boot | Ubuntu Touch desktop is visible and normal. |
| Press power once | Screen goes dark (expected). |
| Press power again | Screen remains **totally black**. No glow, no logo, no lock screen. |
| `echo 4 > /sys/class/graphics/fb0/blank` then `echo 0` | Same result: flicker to dark, then permanently black. |
| Reboot | Screen works again. |
| Compositor restart while black | Still black. |
| `brightness = 255` while black | **No glow at all.** |

---

# 3. Device Access Used During the Investigation

```bash
# USB RNDIS gadget enumerates the tablet with a fixed address:
#   10.15.19.82/24
# Host interface: enxbea1f8092179 = 10.15.19.100/24

SSH="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
     -i /home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/ota_24_04/ssh_debug_key \
     root@10.15.19.82"

# Alternative path when adb sees the device:
adb forward tcp:2222 tcp:22
ssh -p 2222 root@localhost
```

`/dev/mem` does not exist and cannot be created usefully
(`devmem` → `No such device or address`), so raw register access is only possible through
kernel debugfs helpers (`regr:`, `pwm_test:`) or the `mt_gpio` interface.

---

# 4. Relevant Hardware / Display Architecture

## 4.1 Panel

The real panel/LCM name is read from the live device tree:

```bash
strings /sys/firmware/devicetree/base/chosen/atag,videolfb
# -> ft8201_wxga_vdo_incell_boe
```

> **Important correction to older project documentation:** the string
> `atag,videolfb-lcmname = "nt35521_hd_dsi_vdo_truly_rt5081_drv"` is **stale/incorrect**.
> It exists in the DTB overlay but is not the LCM the kernel actually binds.
> The live bound LCM is `ft8201_wxga_vdo_incell_boe`.
>
> This is confirmed independently by the **stock kernel config**, which also contains:
> ```
> CONFIG_CUSTOM_KERNEL_LCM="ft8201_wxga_vdo_incell_boe ft8201_wxga_vdo_incell_inx"
> ```

## 4.2 Display GPIO map (from `akita_row_call.dts`)

| GPIO | Function | Pinctrl state | Verified live |
|---|---|---|---|
| 43 | DISP_PWM output | mode 1 (`DISP_PWM`) | `043: 1000 00100` → mode 1 |
| 45 | LCM reset | `lcm_pins_rst_output0/1` | HIGH in good state |
| 152 | Panel VDD 3.3 V LDO | `lcm_pins_ldo_output0/1` | `5111 00111` (special function, HIGH) |
| 154 | Backlight / LED enable | `lcm_pins_led_output0/1` | HIGH in good state, **LOW after wake** |
| 167 | AVDD / ENP | `lcm_pins_enp_output0/1` | HIGH in good state |
| 168 | AVEE / ENN | `lcm_pins_enn_output0/1` | HIGH in good state |
| 172 | Touch reset (TP) | `tp_pins_rst_output0/1` | claimed by `touch` |

### `mt_gpio` decode

The `mt_gpio` file uses this format:

```
%03d: (MODE)(DIR)(DOUT)(DIN) (DRIVE)(SMT)(IES)(PULL_EN)(PULL_SEL)(R1 R0)
```

Example:

```
045: 0111 00100   -> MODE=0, DIR=1 (out), DOUT=1 (high)
154: 0100 00110   -> MODE=0, DIR=1 (out), DOUT=0 (LOW!)
043: 1000 00100   -> MODE=1 (DISP_PWM alternate function)
```

## 4.3 Backlight path

```
/sys/class/leds/lcd-backlight/brightness
  -> leds-mt65xx / mt65xx_leds_brightness_set()
  -> disp_bls_set_backlight(level)
  -> disp_pwm_set_backlight(DISP_PWM0, level)
  -> disp_pwm_set_backlight_cmdq(id, level, NULL)   /* CPU writes */
  -> disp_pwm_trigger_refresh(id, level == 0)
       + disp_pwm_set_enabled(id, 1)
         -> DISP_PWM_EN = 1
         -> lcm_power_enable_led()  -> GPIO154 HIGH
```

DTS node:

```dts
led6:led@6 {
    compatible = "mediatek,lcd-backlight";
    led_mode = <5>;              /* MT65XX_LED_MODE_CUST_BLS_PWM */
    data = <1>;
    pwm_config = <0 0 0 0 0>;    /* same as stock */
};
```

`queryBL` (via `/sys/kernel/debug/dispsys`) in the **broken** state returned:

```
backlight is on (345), ddp_pwm power:(1)
```

So the **software** believes the backlight is ON, while the physical screen emits no light.

## 4.4 Userspace display stack

* Compositor: `lomiri-system-compositor` (Mir), started by `lightdm` as root.
* It uses:
  * `/dev/mtk_disp_mgr` (MTK display manager ioctls)
  * `/dev/dri/renderD128` (PowerVR GPU render node)
  * vendor `hwcomposer.mt6761.so`, `gralloc.mt6761.so`
* It does **not** hold `/dev/fb0` open.
* Display power-off is requested by `repowerd` over D-Bus:

```
repowerd: LscDisplay: turn_off(all)
repowerd: LscDisplay: turn_on(all)
```

* Brightness is written by repowerd to `/sys/class/leds/lcd-backlight/brightness`.

Relevant `journalctl` excerpt from a failing power-button cycle:

```
07:29:06 repowerd: BacklightBrightnessControl: Transitioning brightness 0.40 => 0.00 done
07:29:06 repowerd: UnityScreenService: dbus_emit_brightness(0.000000), brightness_value=0
07:29:06 repowerd: LscDisplay: turn_off(all)
07:29:06 repowerd: UnityScreenService: dbus_emit_DisplayPowerStateChange(0,2)
07:29:10 repowerd: DefaultStateMachine[c1]: handle_alarm(suspend_delay)
07:29:14 repowerd: DefaultStateMachine[c1]: handle_power_button_press
07:29:14 repowerd: LscDisplay: turn_on(all)
07:29:14 repowerd: BacklightBrightnessControl: Transitioning brightness 0.00 => 0.40 done
07:29:14 repowerd: UnityScreenService: dbus_emit_brightness(0.400000), brightness_value=102
07:29:14 repowerd: UnityScreenService: dbus_emit_DisplayPowerStateChange(1,2)
```

A strace of the compositor (`-f -e trace=openat,ioctl,write`) during the same cycle
captured **zero display-related syscalls**. The compositor did not touch `fb0`,
`mtk_disp_mgr`, or any display sysfs node. The screen darkened only because the
backlight was set to 0.

---

# 5. Static Analysis vs. Stock ROM (Why the "obvious" differences are not the cause)

## 5.1 Kernel config — byte-identical to stock

```bash
kernel-lenovo-akita/scripts/extract-ikconfig workdir/tmp/partitions/boot.img \
  > /tmp/stock.config

diff /tmp/stock.config workdir/downloads/KERNEL_OBJ/.config
# -> no output (0 diff lines, 4783 lines each)
```

**Conclusion:** the kernel `.config` is identical to the stock ROM. The bug is **not** a
missing display/backlight configuration option.

## 5.2 DTB / DTBO — functionally identical to stock

Extracted and decompiled:

* Stock boot DTB: offset `13969408` in `workdir/tmp/partitions/boot.img`
* Stock DTBO: `backups/brom_pre_unlock/dtbo.bin`, FDT at offset `64` (DTBO header is big-endian)
* Tools: `workdir/downloads/KERNEL_OBJ/scripts/dtc/dtc`

Stock overlay `/tmp/dtbo0.dts`:

```dts
atag,videolfb-lcmname = "nt35521_hd_dsi_vdo_truly_rt5081_drv";  /* stale string */
led@6 {
    compatible = "mediatek,lcd-backlight";
    led_mode = <5>;
    data = <1>;
    pwm_config = <0x0 0x0 0x0 0x0 0x0>;
};
```

Our `akita_row_call.dts` overlay has the same values:
`led6 pwm_config = <0 0 0 0 0>`, same pinctrl states, same GPIO numbers.

**Conclusion:** the DTS/DTBO is **not** the delta. The stock ROM uses the same
`pwm_config = <0 0 0 0 0>` and the same GPIO map.

## 5.3 Kernel source modifications present on this build

`git -C workdir/downloads/kernel-lenovo-akita status --short`:

```
 M arch/arm64/configs/akita_row_call_defconfig
 M drivers/misc/mediatek/lcm/ft8201_wxga_vdo_incell_boe/ft8201_wxga_vdo_incell_boe.c
 M drivers/misc/mediatek/video/mt6765/videox/primary_display.c
 M security/apparmor/crypto.c
 M security/apparmor/domain.c
 D debian/*
```

### Modification A — `lcm_init_power()` (ft8201 driver)

Added a full reset sequence at boot:

```c
static void lcm_init_power(void)
{
    pr_debug("[LCM][GPIO]lcm_init_power !\n");
    lcm_power_enable();
    pr_debug("[LCM][GPIO]lcm_init_power full reset sequence !\n");
    MDELAY(7);
    ctp_reset_pin(0);
    MDELAY(5);
    lcm_reset_pin(0);
    MDELAY(5);
    MDELAY(5);
    ctp_reset_pin(1);
    MDELAY(5);
    lcm_reset_pin(1);
    MDELAY(35);
}
```

This only runs at boot (`lcm_init_power`), not on resume.

### Modification B — `primary_display_resume()`

Removed the "already alive → skip" early return so the LCM resume sequence always runs:

```c
/* BEFORE */
if (pgc->state == DISP_ALIVE) {
    DISPCHECK("primary display path is already resume, skip\n");
    goto done;
}

/* AFTER (current) */
/* SKIP-WHEN-ALIVE CHECK REMOVED: always invoke disp_lcm_resume()
 * so the LCM reset + bias sequence runs on every resume/wake. */
```

This change is intended to *help*, not harm. It guarantees that `disp_lcm_resume()` /
`lcm_resume_power()` runs on every resume.

### Modification C — AppArmor config

Only additive (`CONFIG_SECURITY_APPARMOR...`, `CONFIG_DEFAULT_SECURITY="apparmor"`).
Unrelated to display.

**Conclusion:** none of our source modifications appears capable of causing the black
screen; the baseline stock kernel has the same display/backlight code.

---

# 6. Live Test Log (chronological, with results)

## Test 1 — Kernel fb-blank suspend/resume (bypass OFF)

```bash
echo 4 > /sys/class/graphics/fb0/blank   # FB_BLANK_POWERDOWN
# ... observe ...
echo 0 > /sys/class/graphics/fb0/blank   # FB_BLANK_UNBLANK
```

Result:

| Phase | GPIO167 (ENP) | GPIO168 (ENN) | Screen |
|---|---|---|---|
| Before | `0111` (HIGH) | `0111` (HIGH) | visible |
| `blank=4` | `0100` (**LOW**) | `0100` (**LOW**) | dark |
| `blank=0` | `0111` (HIGH) | `0111` (HIGH) | **still black** |

**Conclusion:** the kernel does execute the suspend and resume GPIO sequences, but the
panel never comes back. This path calls `primary_display_suspend()` and
`primary_display_resume()`.

## Test 2 — Verify the `bypass_blank` kernel workaround

`bypass_blank` is a global in `videox/debug.c`:

```c
int bypass_blank;   /* default 0 */
```

Set at runtime:

```bash
echo "bypass_blank:1" > /sys/kernel/debug/mtkfb
```

Then repeat Test 1:

| Phase | GPIO167 | GPIO168 | Screen |
|---|---|---|---|
| `blank=4` | `0111` (HIGH) | `0111` (HIGH) | stays on |
| `blank=0` | `0111` (HIGH) | `0111` (HIGH) | stays on |

With `bypass_blank:0`, the same command produced `0100` (LOW).

**Conclusion:** `bypass_blank` works. It prevents the kernel's
`primary_display_suspend()`/`primary_display_resume()` path entirely.

## Test 3 — Power button with `bypass_blank=1` (the decisive test)

Setup: `bypass_blank=1`, brightness forced to 200, wake daemon stopped and disabled,
a 0.5 s monitor logging brightness / GPIO / PWM clock / IRQ.

User pressed power off, waited ~8 s, pressed power on.

Observed:

* brightness: `200` → `0` → `102`
* GPIO45/152/167/168: **stayed HIGH the whole time**
* PWM clock `disp_pwm_sel`: `enable_count=1` throughout
* Result: **screen totally black, no glow**

**Conclusion:** the panel was **never suspended**. The failure is reproduced by the
backlight path alone. Therefore the kernel `primary_display_suspend/resume` path is
**not required** to reproduce the bug — it is a second, separate way to kill the screen.

## Test 4 — Backlight / PWM state in the broken state

```bash
echo "pwm_test:queryBL" > /sys/kernel/debug/dispsys
cat /sys/kernel/debug/dispsys
```

Output:

```
backlight is on (345), ddp_pwm power:(1)
```

Sysfs: `brightness = 255`, `max_brightness = 255`.
GPIO: `154: 0111` at one point, then `154: 0100` (LOW) after a later suspend test.

**Conclusion:** the software backlight state says ON, but there is **no light**.
The physical enable is missing.

## Test 5 — Direct PWM register writes

```bash
echo "pwm_test:pwmmux:3"                 > /sys/kernel/debug/dispsys
echo "pwm_test:set:28,56295424,536805376" > /sys/kernel/debug/dispsys  # CON_1 duty
echo "pwm_test:set:0,1,1"                 > /sys/kernel/debug/dispsys  # PWM_EN = 1
echo "backlight:255"                      > /sys/kernel/debug/dispsys
```

Result: **no light**.

PWM register offsets used:

```
DISP_PWM_EN_OFF    = 0x00
DISP_PWM_RST_RX    = 0x04
DISP_PWM_CON_0_OFF = 0x18
DISP_PWM_CON_1_OFF = 0x1C
DISP_PWM_DEBUG     = 0x80
```

Physical base `0x1100E000`; kernel ioremap VA found in `/proc/vmallocinfo`:

```
0xffffff8009b85000-0xffffff8009b87000  phys=1100e000 ioremap
```

Note: `regr:` from `/sys/kernel/debug/dispsys` only accepts addresses inside the DDP
module table (`is_reg_addr_valid(1, addr)`), so reading the PWM block through `regr:`
is rejected. There is no `CONFIG_DEVMEM`.

## Test 6 — Compositor isolation

* `strace -f -e trace=openat,ioctl,write -p <mir-pid>` during a power cycle:
  **no display-related syscalls at all**.
* `systemctl restart lightdm` (full compositor restart) while black:
  **screen still black**; only the notification LED changed.
* DSI0 interrupt count keeps increasing (~800 per 2 s).
* RDMA0 / OVL0 interrupt counts are **frozen** (no new frames submitted).

**Conclusion:** the DSI link is alive and scanning out a static frame, but the compositor
is not submitting new frames. However, restarting the compositor does **not** restore
either the image or the backlight, so this is not merely a stuck compositor.

## Test 7 — Force display resume / ESD recovery from the kernel

```bash
echo "resume"       > /sys/kernel/debug/mtkfb
echo "esd_recovery" > /sys/kernel/debug/mtkfb
```

Result: no change. At that moment GPIO154 read:

```
154: 0100 00110   -> output LOW
```

This led to Test 8.

## Test 8 — Force backlight enable pin HIGH manually

```bash
echo "out 154 1" > /sys/devices/platform/1000b000.pinctrl/mt_gpio
echo 200 > /sys/class/leds/lcd-backlight/brightness
```

Result:

```
154: 0111 00110   -> output HIGH (confirmed)
```

Screen: **still no light**.

**Conclusion:** GPIO154 LOW is *a* fault, but not the only one. Raising it does not
restore the backlight. The boost converter / bias rail has another missing enable
condition.

---

# 7. Confirmed Facts (evidence-backed)

| # | Fact | Evidence |
|---|---|---|
| F1 | Real LCM is `ft8201_wxga_vdo_incell_boe`. | live `atag,videolfb`; stock config |
| F2 | Kernel config is identical to stock. | `diff` = 0 lines |
| F3 | DTB/DTBO content is functionally identical to stock. | decompiled DTS comparison |
| F4 | Kernel cmdline has `lcd_bias_id=0`, `lcd_bias_sw_id=0`, `pa_id=2`. | `/proc/cmdline` |
| F5 | `fb0` blank suspends the panel (GPIO167/168 LOW) and resume does **not** restore the image. | Test 1 |
| F6 | `bypass_blank=1` prevents the kernel suspend path. | Test 2 |
| F7 | Power-button blanking does **not** suspend the panel (GPIOs stay HIGH) but still kills the screen. | Test 3 |
| F8 | repowerd implements screen off as brightness→0 + D-Bus `turn_off(all)`; it does not fb-blank. | journal + strace |
| F9 | The compositor issues no display syscalls during the transition. | strace |
| F10 | Software backlight state says ON while there is no physical light. | `queryBL` |
| F11 | GPIO154 (backlight enable) can end up LOW and can stay LOW. | `mt_gpio` |
| F12 | Forcing GPIO154 HIGH does not restore light. | Test 8 |
| F13 | DSI video keeps streaming; no new RDMA/OVL frames. | `/proc/interrupts` sampling |
| F14 | Compositor restart does not recover the screen. | Test 6 |
| F15 | No system suspend occurred during the failing power-button test. | journal, `/sys/power/state` |
| F16 | GPIO172 is permanently claimed by `touch`, so LCM pinctrl states 6/7 always fail. | dmesg |

---

# 8. Source-Code Findings (the likely software bugs)

## 8.1 `primary_display_setbacklight()` has a `last_level` cache

File: `drivers/misc/mediatek/video/mt6765/videox/primary_display.c:7851`

```c
int primary_display_setbacklight(unsigned int level)
{
    static unsigned int last_level;
    ...
    if (last_level == level)
        return 0;                       /* <-- silent skip */

    ...
    if (pgc->state == DISP_SLEPT) {
        DISPWARN("Sleep State set backlight invald\n");
    } else {
        ...
        if (primary_display_cmdq_enabled()) {
            _set_backlight_by_cmdq(level);
            atomic_set(&delayed_trigger_kick, 1);
        } else {
            _set_backlight_by_cpu(level);
        }
        last_level = level;
    }
    ...
}
```

Two hazards:

1. If the last successful write was already `level`, a later restore is skipped.
2. `last_level` is **not updated** while `pgc->state == DISP_SLEPT`, so the cache can drift
   from the hardware.

## 8.2 `_set_backlight_by_cmdq()` waits for a frame-done token

File: `primary_display.c:7736`

```c
if (primary_display_is_video_mode()) {
    cmdqRecReset(cmdq_handle_backlight);
    _cmdq_insert_wait_frame_done_token_mira(cmdq_handle_backlight);  /* <-- waits for vsync/frame */
    disp_lcm_set_backlight(pgc->plcm, cmdq_handle_backlight, level);
    _cmdq_flush_config_handle_mira(cmdq_handle_backlight, 0);
}
```

If the compositor has stopped pushing frames (RDMA/OVL frozen), the frame-done token
never fires and the backlight write never reaches hardware. `delayed_trigger_kick` is
used to trigger the queue later (`primary_display.c:2914`, `2960`, `2965`, `5321`, `7889`).

## 8.3 `disp_pwm_set_enabled()` caches its state

File: `drivers/misc/mediatek/video/common/pwm10/ddp_pwm.c:399`

```c
static void disp_pwm_set_enabled(struct cmdqRecStruct *cmdq,
                                 enum disp_pwm_id_t id, int enabled)
{
    ...
    old_en = atomic_xchg(&g_pwm_en[index], enabled);
    if (old_en == enabled)
        return;                       /* <-- skips PWM_EN write AND driver-IC enable */
    ...
    if (enabled) {
        DISP_REG_MASK(NULL, reg_base + DISP_PWM_EN_OFF, 0x1, 0x1);
        disp_pwm_set_drverIC_en(id, 1);   /* -> lcm_power_enable_led() -> GPIO154 HIGH */
    } else {
        ...
        disp_pwm_set_drverIC_en(id, 0);   /* -> lcm_power_disable_led() -> GPIO154 LOW */
    }
}
```

If `g_pwm_en` says "already enabled" but the hardware EN bit / GPIO154 were lost,
the early return prevents recovery.

## 8.4 `disp_pwm_set_backlight()` only forces an immediate trigger for OFF

File: `ddp_pwm.c:548`

```c
int disp_pwm_set_backlight(enum disp_pwm_id_t id, int level_1024)
{
    ...
    ret = disp_pwm_set_backlight_cmdq(id, level_1024, NULL);   /* CPU writes */
    if (ret >= 0)
        disp_pwm_trigger_refresh(id, (level_1024 == 0));       /* immediate only for 0 */
    return 0;
}
```

Turning **off** is triggered immediately; turning **on** is left to the next frame/vsync.

## 8.5 The bias IC I2C programming is commented out

File: `drivers/misc/mediatek/lcm/sm5109.c`

```c
/* set AVDD */
/*4.0V + 20* 100mV*/
//ret = SM5109_REG_MASK(0x00, 20, (0x1F << 0));
//if (ret < 0)
```

`lcm_power_enable()` only toggles ENP/ENN GPIOs (167/168) and does **not** reprogram the
SM5109 bias voltage registers. `I2C_LCD_BIAS` is present at `i2c-5` address `0x11`.

If the bias IC ever loses power (rails cycled by the suspend path), the kernel cannot
restore its programmed voltages. This is consistent with "only a reboot recovers".

## 8.6 `lcm_power_enable_led()` / `lcm_power_disable_led()`

```c
int lcm_power_enable_led(void)
{
    pr_debug("[LCM]backlight enable led_en pin\n");
    mdelay(80);
    pinctrl_select_state(_lcm_gpio, _lcm_gpio_mode[11]);   /* GPIO154 HIGH */
    return 0;
}

int lcm_power_disable_led(void)
{
    pr_debug("[LCM]backlight disable led_en pin\n");
    pinctrl_select_state(_lcm_gpio, _lcm_gpio_mode[10]);   /* GPIO154 LOW */
    return 0;
}
```

DTS confirms `lcm_pins_led_output1` is GPIO154.

## 8.7 GPIO172 pinctrl conflict (secondary bug)

```
mediatek-mt6761-pinctrl 1000b000.pinctrl: pin GPIO172 already requested by touch;
    cannot claim for lcm_gpio
lcm_mode1 lcm_gpio: Error applying setting, reverse things back
```

The `lcm` node includes touch-reset states 6/7 (`tp_pins_rst_output0/1`, GPIO172) in its
own pinctrl table, but the touch driver claims GPIO172 first. Every `ctp_reset_pin()`
call therefore fails and **reverts the whole pinctrl state**. This is triggered by
`lcm_resume_power()` calling `ctp_reset_pin()`.

This may not be the primary black-screen cause (LCM reset on GPIO45 uses separate states),
but it is a real defect and should be fixed.

---

# 9. Root-Cause Analysis

## 9.1 What is *not* the cause

| Hypothesis | Verdict |
|---|---|
| Wrong LCM driver | Rejected — stock uses the same `ft8201...` LCM. |
| Missing/incorrect DTS | Rejected — overlay identical to stock. |
| Missing kernel config | Rejected — `.config` byte-identical to stock. |
| Only a stuck compositor | Rejected — compositor restart does not recover. |
| System suspend/resume | Rejected — no system suspend occurred; `/sys/power/state` untouched. |
| `/dev/mem` / register access | Irrelevant — investigation limitation only. |
| GPIO154 alone | Rejected — forcing it HIGH does not restore light. |

## 9.2 Current leading theory (confidence: high for the mechanism, medium for the exact final blocker)

The failure is a **backlight + display resume ordering problem** that exists because
Ubuntu Touch's power management is not the Android early-suspend flow.

1. `repowerd` turns the screen "off" by writing brightness `0` and sending
   `turn_off(all)` to the compositor. It does **not** call `FBIOBLANK` and does **not**
   suspend the panel through the kernel fb-blank path.
2. Brightness `0` runs `disp_pwm_set_enabled(0)` → `lcm_power_disable_led()` →
   **GPIO154 LOW**. This is a real hardware state change.
3. On wake, brightness is restored to `102`. The restore goes through
   `primary_display_setbacklight()` → `_set_backlight_by_cmdq()`, which waits for a
   **frame-done CMDQ token**. The compositor is not submitting frames, so the token never
   fires and the `disp_pwm_set_enabled(1)` / `lcm_power_enable_led()` side effects do not
   reach hardware.
4. Result: GPIO154 remains LOW; PWM EN may also remain 0; the panel is alive (DSI
   streaming) but there is no light.
5. A second, independent breakage exists in the kernel fb-blank path: suspending the
   panel and resuming it also fails to restore the image (Test 1), likely because the
   SM5109 bias I2C registers are not reprogrammed after the bias rails are cycled, and/or
   because the DSI/panel re-init sequence is incomplete.

## 9.3 Why a reboot fixes it

A cold boot lets LK (the bootloader) fully power and program the panel + bias IC, and the
kernel's `lcm_init()`/`lcm_init_power()` runs from a clean state. Nothing in the runtime
resume paths reproduces that full initialization.

---

# 10. Workarounds Tried and Their Results

| Workaround | Result |
|---|---|
| Userspace wake daemon (`mtk-display-wake.py`) issuing `FBIOBLANK(UNBLANK)` + `esd_recovery` + `pwm_test:pwmmux:3` + brightness restore | Did not fix; race-prone. |
| `bypass_blank=1` (runtime) | Prevents the fb-blank suspend path, but the screen still dies via the backlight/`turn_off` path. |
| Forcing PWM registers directly (`pwm_test:set`) | No light. |
| Forcing GPIO154 HIGH | No light. |
| `backlight:255` debug command | No light; software says ON. |
| Restarting `lomiri-system-compositor` / `lightdm` | No light. |
| Kernel `resume` / `esd_recovery` debug hooks | No change. |
| Direct framebuffer white-frame page flipping (224 successful `FBIOPAN_DISPLAY`) | No light (panel path already dead). |
| Reboot | Recovers reliably. |

---

# 11. Proposed Fix

The fix should be a kernel-side change (matching the request to use the stock ROM as a
reference), not another userspace daemon.

## 11.1 Fix A — make the backlight restore deterministic (required)

In `disp_pwm.c`:

1. **Remove the `g_pwm_en` cache short-circuit**, or force a hardware refresh when the
   cached state and hardware may disagree:

```c
/* disp_pwm_set_enabled() */
old_en = atomic_xchg(&g_pwm_en[index], enabled);
- if (old_en == enabled)
-     return;
+ /* Always re-program hardware: the display may have lost its registers
+  * across suspend, and the cached state can be stale. */
```

2. **Trigger the refresh immediately for ON as well as OFF**:

```c
/* disp_pwm_set_backlight() */
- disp_pwm_trigger_refresh(id, (level_1024 == 0));
+ disp_pwm_trigger_refresh(id, 1);
```

3. Consider always using `_set_backlight_by_cpu()` during resume (avoid the frame-done
   CMDQ dependency when no frames are being submitted).

## 11.2 Fix B — remove the `last_level` cache hazard

In `primary_display_setbacklight()`:

* Update `last_level` even in the `DISP_SLEPT` branch, or drop the cache and let the PWM
  layer deduplicate.
* On resume, force a backlight refresh regardless of the cached value.

## 11.3 Fix C — pair display suspend/resume with system suspend

In `mtkfb.c`, the PM callbacks are effectively stubs:

```c
static int mtkfb_suspend(struct platform_device *pdev, pm_message_t mesg)
{
    ovl2mem_wait_done();
    return 0;
}

static int mtkfb_resume(struct platform_device *pdev)
{
    return 0;
}
```

Because UT may enter system suspend without first fb-blanking the display, the display
controller and panel registers can be lost. Make the PM path explicit:

```c
static int mtkfb_pm_suspend(struct device *dev)  /* or platform .suspend */
{
    if (!primary_display_is_sleepd())
        primary_display_suspend();
    return 0;
}

static int mtkfb_pm_resume(struct device *dev)
{
    primary_display_resume();
    return 0;
}
```

(Exact wiring must match the existing `dev_pm_ops` / `platform_driver` structure in this
tree.)

## 11.4 Fix D — re-enable SM5109 bias programming on resume

In `sm5109.c`, the AVDD/AVEE I2C writes are commented out. If the bias rails are ever
cycled, those registers must be reprogrammed. Restore the writes (with correct values for
this panel) inside `lcm_power_enable()`.

## 11.5 Fix E — remove the GPIO172 pinctrl conflict

Either:

* Remove `pinctrl-6`/`pinctrl-7` (TP reset) from the `&lcm` node in
  `akita_row_call.dts`, or
* Remove the `ctp_reset_pin()` calls from the LCM resume path.

The touch driver must own GPIO172 exclusively.

---

# 12. Build and Flash Procedure (NOT executed — requires explicit user confirmation)

## 12.1 Build

```bash
cd /home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch

# 1. Edit the kernel sources listed in section 11.
# 2. Build kernel + boot image:
./build_kernel.sh
# (or the project's established build path)
```

Expected outputs:

```
workdir/tmp/partitions/boot_new.img       # packaged boot image
workdir/tmp/partitions/boot_new_raw.img   # raw variant
```

## 12.2 Validate before flashing

```bash
./validate_kernel.sh

# Confirm the stock kernel config still matches (sanity):
kernel-lenovo-akita/scripts/extract-ikconfig workdir/tmp/partitions/boot_new.img \
  | diff - workdir/downloads/KERNEL_OBJ/.config
```

## 12.3 Flash (dry-run / explicit confirmation)

Per `AGENTS.md` §2, **no flashing is performed automatically**. The command, once the
user explicitly confirms, is:

```bash
fastboot flash boot workdir/tmp/partitions/boot_new.img
fastboot reboot
```

Safety rules that remain in force:

* Never touch `nvram`, `nvdata`, `proinfo`, `persist`, `protect1`, `protect2`.
* Keep a backup of the current boot image before flashing:
  `backups/boot_orig_20261106_153417.img` already exists.
* Do not lock/unlock the bootloader automatically.

---

# 13. Open Questions for a Second Reviewer / Model

1. **What actually powers the backlight boost IC?** GPIO154 is the DTS "LED enable", but
   forcing it HIGH does not light the panel. Is the boost supplied by the SM5109 bias IC
   (`i2c-5 0x11`), by an external buck (`ext_buck_lp4`/`lp4x`), or by the MT6357 PMIC?
   Which rail must be re-enabled after a backlight-off event?
2. **Does brightness 0 → 200 alone (no power button, fresh boot) kill the backlight?**
   This isolates the PWM/LED-enable path from the compositor/repowerd path.
3. **Why does the kernel fb-blank resume not restore the panel even when the bias rails
   were cycled and re-enabled?** Is the DSI re-init sequence (`init_setting_vdo`) complete,
   or is a DSI PHY/clock reset required?
4. **Is `g_pwm_en` stale after a suspend?** Read the real `DISP_PWM_EN` bit at
   `0x1100E000` (requires a kernel helper or a rebuilt kernel with debug prints).
5. **Is the SM5109 I2C programming required after ENP/ENN are cycled?** The code is
   commented out; the stock LK programs it once at boot.
6. **Does the stock Android ever reach this state?** If not, which HWC power-mode call
   does it use that UT's Mir does not? (Mir's `turn_off/turn_on` produced no kernel
   syscalls in strace.)
7. **Is GPIO154 actually active-high for this board variant?** The DTS says so, but the
   board may have an inverter.

---

# 14. Appendix A — Key Files and Paths

## Kernel sources

```
workdir/downloads/kernel-lenovo-akita/
├── drivers/misc/mediatek/lcm/ft8201_wxga_vdo_incell_boe/ft8201_wxga_vdo_incell_boe.c
├── drivers/misc/mediatek/lcm/sm5109.c
├── drivers/misc/mediatek/video/mt6765/videox/mtkfb.c
├── drivers/misc/mediatek/video/mt6765/videox/primary_display.c
├── drivers/misc/mediatek/video/mt6765/videox/debug.c
├── drivers/misc/mediatek/video/mt6765/dispsys/ddp_debug.c
├── drivers/misc/mediatek/video/common/pwm10/ddp_pwm.c
├── arch/arm64/boot/dts/mediatek/akita_row_call.dts
└── arch/arm64/configs/akita_row_call_defconfig
```

## Built artifacts / references

```
workdir/downloads/KERNEL_OBJ/.config                 # byte-identical to stock
workdir/downloads/KERNEL_OBJ/scripts/dtc/dtc         # working dtc
workdir/tmp/partitions/boot.img                      # stock boot image
workdir/tmp/partitions/boot_new.img                  # our packaged boot image
backups/boot_orig_20261106_153417.img                # current boot backup
backups/brom_pre_unlock/dtbo.bin                     # stock DTBO partition
```

## Decompiled references (temporary)

```
/tmp/stock.config            # stock kernel config
/tmp/stockboot.dts           # stock boot DTB
/tmp/dtbo0.dts               # stock DTBO overlay
/tmp/stock.dts               # stock vendor DTB
/tmp/wrapped.dts             # Halium-wrapped DTB
```

## Userspace overlay

```
overlay/system/usr/local/bin/mtk-display-wake.py
overlay/system/etc/systemd/system/mtk-display-wake.service
overlay/system/etc/default/repowerd
overlay/system/etc/systemd/logind.conf.d/10-powerkey.conf
```

---

# 15. Appendix B — Raw GPIO / State Snapshots

## Working state (after cold boot)

```
043: 1000 00100   # DISP_PWM alternate function
045: 0111 00100   # LCM reset HIGH
152: 5111 00111   # LDO / panel VDD HIGH
154: 0111 00110   # backlight enable HIGH
167: 0111 00100   # ENP (AVDD) HIGH
168: 0111 00100   # ENN (AVEE) HIGH
172: 0111 00100   # touch reset HIGH
brightness: 102 / 255
fb0/blank: (empty)
disp_pwm_sel: rate=26000000, enable_count=1, prepare_count=1
dsi0 IRQ: increasing
```

## Broken state (after wake)

```
043: 1000 00100
045: 0111 00100
152: 5111 00111
154: 0100 00110   # <-- backlight enable LOW
167: 0111 00100   # panel power rails still HIGH
168: 0111 00100
172: 0111 00100
brightness: 200 / 255 (sysfs)
queryBL: "backlight is on (345), ddp_pwm power:(1)"
dsi0 IRQ: increasing
rdma0/ovl0 IRQ: frozen
```

---

# 16. Appendix C — Exact Diagnostic Commands

```bash
# Panel / LCM identity
strings /sys/firmware/devicetree/base/chosen/atag,videolfb
cat /proc/cmdline

# GPIO snapshot
grep -E "^(043|045|152|154|167|168|172):" \
  /sys/devices/platform/1000b000.pinctrl/mt_gpio

# Force a GPIO output
echo "out 154 1" > /sys/devices/platform/1000b000.pinctrl/mt_gpio

# Backlight state
cat /sys/class/leds/lcd-backlight/brightness
cat /sys/class/leds/lcd-backlight/max_brightness
echo "pwm_test:queryBL" > /sys/kernel/debug/dispsys
cat /sys/kernel/debug/dispsys

# PWM clocks
cat /sys/kernel/debug/clk/disp_pwm_sel/clk_rate
cat /sys/kernel/debug/clk/disp_pwm_sel/clk_enable_count

# Kernel display debug hooks
echo "bypass_blank:1" > /sys/kernel/debug/mtkfb
echo "resume"          > /sys/kernel/debug/mtkfb
echo "esd_recovery"    > /sys/kernel/debug/mtkfb

# Framebuffer blank (kernel early-suspend path)
echo 4 > /sys/class/graphics/fb0/blank
echo 0 > /sys/class/graphics/fb0/blank

# IRQ activity
grep -E "dsi0|rdma0|ovl0" /proc/interrupts

# Compositor / repowerd logs
journalctl -u repowerd --no-pager -n 40
journalctl --no-pager --since "-15 min" | grep -iE "mir|compositor|display|suspend"

# Extract stock kernel config
workdir/downloads/kernel-lenovo-akita/scripts/extract-ikconfig \
  workdir/tmp/partitions/boot.img

# Decompile DTB / DTBO
DTC=workdir/downloads/KERNEL_OBJ/scripts/dtc/dtc
tail -c +13969409 workdir/tmp/partitions/boot.img > /tmp/stockboot.dtb
$DTC -f -I dtb -O dts -o /tmp/stockboot.dts /tmp/stockboot.dtb
tail -c +65 backups/brom_pre_unlock/dtbo.bin > /tmp/dtbo0.dtb
$DTC -f -I dtb -O dts -o /tmp/dtbo0.dts /tmp/dtbo0.dtb
```

---

# 17. Appendix D — Safety / Constraints Honoured

* No partition was flashed during this investigation.
* No radio calibration partition (`nvram`, `nvdata`, `proinfo`, `persist`,
  `protect1`, `protect2`) was read from or written to.
* The tablet was rebooted only after explicit user approval.
* All changes to the kernel tree are uncommitted and reversible.
* No git push was performed.
* The wake daemon was stopped and disabled during live tests.

---

# 18. One-Paragraph Summary for a Second Model

> Lenovo TB-8505X running Ubuntu Touch 24.04 (Halium 10, kernel 4.9.190). Screen works at
> boot but goes permanently black (no image, no backlight glow) after any sleep/wake.
> Kernel config and DTB are byte-identical to the stock Android ROM, and the real LCM is
> `ft8201_wxga_vdo_incell_boe` (confirmed by live DT and stock config). Ubuntu Touch's
> repowerd turns the screen off by writing brightness 0 and sending a D-Bus `turn_off` to
> Mir; it does not fb-blank the display. With `bypass_blank=1` the panel is confirmed NOT
> to suspend (GPIO167/168 stay HIGH, DSI keeps streaming), yet the screen still dies:
> GPIO154 (backlight enable) goes LOW and never recovers, and forcing it HIGH manually
> still gives no light. The composition path also stops submitting frames (RDMA/OVL IRQs
> frozen) and a compositor restart does not help. Source inspection shows
> `primary_display_setbacklight()` has a `last_level` cache, `_set_backlight_by_cmdq()`
> waits for a frame-done CMDQ token that never fires when no frames are submitted,
> `disp_pwm_set_enabled()` caches `g_pwm_en` and can skip the hardware EN write and
> `lcm_power_enable_led()`, and the SM5109 bias IC I2C voltage programming is commented
> out. The proposed fix is kernel-side: always reprogram PWM/backlight on resume, trigger
> immediately for ON as well as OFF, pair display suspend/resume with system suspend,
> re-enable the SM5109 bias programming, and remove the GPIO172 touch/LCM pinctrl conflict.
> A full clean reboot restores the screen; no runtime workaround tried so far does.
