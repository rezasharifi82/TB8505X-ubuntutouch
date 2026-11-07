# TB-8505X — Overnight Session Status

Written 2026-11-06 ~04:50 (+0330). Read this first.

---

## 1. ACTION REQUIRED: the tablet is stuck and needs a physical power cycle

The tablet rebooted on its own at **04:01** and is now parked in the **Halium
initramfs** USB gadget, not the booted Ubuntu Touch system.

| Check | Expected (booted) | Actual now |
|---|---|---|
| USB gadget | `18d1:d001` UbuntuTouch | **`1209:0004` LENOVO** |
| adb | device present | **none** |
| ping 10.15.19.82 | replies | **dead** |
| SSH localhost:2222 | listening | **none** |
| RNDIS rx/tx | moving | **frozen at 19/36** |

It has been in this state since 04:01 and does not recover on its own.

**To recover:**

1. Hold the power button **15–20 seconds** until the tablet powers off.
2. Wait 5 seconds.
3. Press power once to boot normally.

Then report: did it reach the Lomiri desktop, or come up black?

Remote recovery was impossible from here — host sudo requires an interactive
password (`sudo: interactive authentication is required`), so the
`192.168.2.1/24` initramfs subnet could not be added host-side to reach the
device at `192.168.2.15`.

**Cause:** almost certainly a watchdog/panic around the `dsipattern:1` (DSI BIST
pattern) write issued at ~03:52. That was an unnecessary risk to take while
nobody was present to power-cycle. Not repeated.

---

## 2. What was actually proven about the black-screen bug

All measured on the live device before it dropped off.

### 2.1 Lomiri/Mir is innocent
The framebuffer held a complete, stable desktop while the screen was black:

- `/dev/fb0`: 800x1280, stride 3200, 32bpp
- non-zero bytes: **3,961,351 / 4,096,000 (96.7%)**
- 256 distinct byte values, purple UI pixels (`BGRA 124,40,97,255`)
- frame-to-frame hash over 2 s: **identical**

Do not chase the compositor. The image is being rendered.

### 2.2 Every rail was nominally ON and the screen was still zero light

| Signal | Value |
|---|---|
| `lcd-backlight/brightness` | 150 / 255 |
| GPIO 154 (backlight driver enable) | out=1 |
| GPIO 167 (+5V AVDD) | out=1 |
| GPIO 168 (-5V AVEE) | out=1 |
| GPIO 045 (panel reset) | out=1 |

User confirmed: "truly zero light — panel looks dead".
So **brightness != 0 and GPIO154 high are false success signals here.**

### 2.3 The DSI link is idle — this is the real signal

```
rdma0 : 543073 interrupts since boot
 dsi0 :      4 interrupts since boot
```

The display controller reads frames; the DSI output is not streaming them to
the panel. **Use the `dsi0` IRQ count as the pass/fail criterion for any fix.**
It must advance. Nothing else is trustworthy.

### 2.4 `echo resume > /sys/kernel/debug/mtkfb` is a NO-OP
The documented Phase 1 step does not work in the broken state.
`primary_display_resume()` early-exits:

```c
if (pgc->state == DISP_ALIVE) {
        DISPCHECK("primary display path is already resume, skip\n");
        goto done;
}
```

The path still reports `DISP_ALIVE`, so `disp_lcm_resume()` — the thing that
re-sends the FT8201 DSI init table — is never called. The write returns rc=0
in under a millisecond and nothing changes. Roadmap corrected.

### 2.5 The one userspace lever verified to move hardware

```bash
echo 4 > /sys/class/graphics/fb0/blank   # FB_SUSPEND -> GPIO167/168 go LOW (0100)
echo 0 > /sys/class/graphics/fb0/blank   # FB_RESUME  -> GPIO167/168 go HIGH (0111)
```

Only this clears the LCM power-state guard and reaches `disp_lcm_resume()`.
It was **not** confirmed to produce a visible image before the device left the
network. Unproven.

### 2.6 Real kernel defect found

Every resume logs:

```
pin GPIO172 already requested by touch; cannot claim for lcm_gpio
pin-172 (lcm_gpio) status -22
lcm_mode1 lcm_gpio: Error applying setting, reverse things back
```

The `lcm_gpio` pinctrl group claims the **touch** reset pin (GPIO172,
`tp_pins_rst_output*`), but the FocalTech touch driver already owns it. The
state apply fails and the kernel rolls back the whole group — taking the LCD
bias rails with it.

Also suspect a naming mismatch: DTS says `state_rst_output0/1` and
`state_tp_rst_output0/1`; `sm5109.c` looks up `state_reset_output0/1` and
`state_tp_reset_output0/1`. If those names do not resolve, the transitions
fail silently even without the ownership conflict.

**This needs a DTS + kernel rebuild — a userspace daemon cannot fix it.**

---

## 3. Changes committed to the repo this session

| File | Change | Verified |
|---|---|---|
| `docs/SLEEP_WAKE_DEBUG_STATE_AND_ROADMAP.md` | New section **7b** with all findings above + corrections to Phase 1 | yes (real diff) |
| `scripts/apply_sleep_wake_fix.sh` L185 | `bypass_blank:1` → **`bypass_blank:0`** | yes (grep) |
| `scripts/apply_sleep_wake_fix.sh` L69 | `REPOWERD_MOCKSUSPEND=1` → **commented out** | yes (grep) |
| `overlay/system/usr/local/bin/mtk-display-wake.py` | Wake daemon, force real FB suspend/resume cycle | syntax OK, **untested** |
| `overlay/system/etc/systemd/system/mtk-display-wake.service` | Unit for the above | not installed |
| `overlay/system/etc/default/repowerd` | MOCKSUSPEND off | not installed |
| `overlay/system/etc/systemd/logind.conf.d/10-powerkey.conf` | HandlePowerKey=ignore | not installed |

Why the two script fixes matter: `bypass_blank:1` makes `mtkfb_blank()` return
before `primary_display_set_power_mode()`, disabling the only working wake
lever. The old script set exactly that.

---

## 4. What is NOT done — no spin

- The wake daemon has **never been run on hardware**. Do not assume it works.
- Nothing is deployed to the device. Overlay files are in the repo only.
- The full checklist (wifi, bluetooth, camera, audio, charging, file transfer,
  music, photos, settings) is **not verified**. I never got past the display
  blocker, so none of it can be called tested.

---

## 5. Next session, in order

1. Power-cycle the tablet (section 1). Confirm it boots.
2. Re-establish SSH on port 2222.
3. Run `mtk-display-wake.py` by hand — do **not** install the unit yet — and
   watch `grep dsi0 /proc/interrupts` before/after. If the count does not
   advance, the daemon does not fix it and the DTS fix in 2.6 is mandatory.
4. Only if (3) succeeds: install the unit, then move to the peripheral
   checklist.
5. Consider fixing the DTS/`sm5109.c` pin conflict regardless — it is a real
   bug and it corrupts the bias rails on every resume.
