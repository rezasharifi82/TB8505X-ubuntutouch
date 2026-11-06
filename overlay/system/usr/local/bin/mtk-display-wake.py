#!/usr/bin/env python3
"""
MediaTek Display Wake Daemon - Lenovo Tab M8 HD LTE (TB-8505X)
Synchronizes hardware bias, LDO, PWM clock, AAL bypass, LCM DSI resume,
and backlight power on wake events.
"""

import fcntl
import os
import sys
import time

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

MT_GPIO_PATH = "/sys/devices/platform/1000b000.pinctrl/mt_gpio"
MTKFB_DEBUG_PATH = "/sys/kernel/debug/mtkfb"
DISPSYS_DEBUG_PATH = "/sys/kernel/debug/dispsys"
FB_BLANK_PATH = "/sys/class/graphics/fb0/blank"
BACKLIGHT_PATH = "/sys/class/leds/lcd-backlight/brightness"
LOG_PATH = "/var/log/mtk-display-wake.log"

FBIOBLANK = 0x4611
FB_BLANK_UNBLANK = 0
FB_BLANK_POWERDOWN = 4

GPIO_ENP = 167   # +5V AVDD
GPIO_ENN = 168   # -5V AVEE
GPIO_LED = 154   # Backlight boost enable
GPIO_LDO = 152   # Panel VDD 3.3V
GPIO_RST = 45    # Panel reset

MIN_BRIGHTNESS = 60
DEFAULT_BRIGHTNESS = 150

_wake_in_progress = False

def log(msg):
    line = "%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg)
    try:
        with open(LOG_PATH, "a") as f:
            f.write(line)
    except OSError:
        pass
    sys.stderr.write(line)
    sys.stderr.flush()

def write_path(path, value):
    try:
        with open(path, "w") as f:
            f.write(str(value))
        return True
    except OSError as exc:
        log("write %s <- %r failed: %s" % (path, value, exc))
        return False

def read_path(path, default=None):
    try:
        with open(path, "r") as f:
            return f.read().strip()
    except OSError:
        return default

def set_gpio(pin, val):
    return write_path(MT_GPIO_PATH, "out %d %d\n" % (pin, val))

def set_brightness(value):
    max_b = read_path(BACKLIGHT_PATH.replace("brightness", "max_brightness"), "255")
    try:
        max_b = int(max_b)
    except ValueError:
        max_b = 255
    value = max(0, min(int(value), max_b))
    return write_path(BACKLIGHT_PATH, "%d\n" % value)

def unblank_fb_ioctl():
    try:
        fd = os.open("/dev/fb0", os.O_RDWR)
    except OSError as exc:
        log("open /dev/fb0 failed: %s" % exc)
        return False
    try:
        fcntl.ioctl(fd, FBIOBLANK, FB_BLANK_UNBLANK)
        return True
    except OSError as exc:
        log("FBIOBLANK failed: %s" % exc)
        return False
    finally:
        os.close(fd)

def dsi_irq_count():
    try:
        with open("/proc/interrupts", "r") as f:
            for line in f:
                if line.rstrip().endswith("dsi0"):
                    fields = line.split()
                    return sum(int(x) for x in fields[1:-3] if x.isdigit())
    except (OSError, ValueError):
        pass
    return None


PWM_CLK_RATE_PATH = "/sys/kernel/debug/clk/disp_pwm_sel/clk_rate"

def pwm_clk_rate():
    try:
        with open(PWM_CLK_RATE_PATH) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return None

def fix_pwm_clock_and_backlight(tag="wake"):
    """Re-lock DISP_PWM mux to 26MHz and force PWM/LED backlight on.

    Root cause (live-verified 2026-10-13): DTS lcd-backlight pwm_config
    is <0 0 0 0 0>, so the kernel muxes DISP_PWM to ULPOSC1_D8. Blank
    turns ULPOSC off (ddp_pwm_power_off -> ulposc_off) and every
    FB_RESUME re-runs disp_pwm_config_init -> disp_pwm_set_pwmmux(0),
    leaving disp_pwm_sel rate at 0. PWM_EN/duty registers and bias
    rails survive, but with no clock the backlight gets zero output
    (black screen, zero glow) while DSI keeps ticking. Any redundant
    unblank re-breaks it, so this must run LAST and be re-applied
    after a delay to win the race against Mir's own unblank.
    Brightness sysfs is cache-blind (LED + primary_display +
    disp_pwm all skip same-value writes), so force via dispsys
    backlight: (direct disp_bls_set_backlight) with a two-step
    level change to bust the disp_pwm cache.
    """
    rate_before = pwm_clk_rate()
    write_path(DISPSYS_DEBUG_PATH, "pwm_test:pwmmux:3\n")
    write_path(DISPSYS_DEBUG_PATH, "aal_test:bypass:1\n")
    set_gpio(GPIO_LED, 1)
    # Cache-busting forced backlight levels (1024-scale).
    write_path(DISPSYS_DEBUG_PATH, "backlight:800\n")
    write_path(DISPSYS_DEBUG_PATH, "backlight:859\n")
    time.sleep(0.05)
    rate_after = pwm_clk_rate()
    log("pwm clock %s: disp_pwm_sel rate %s -> %s" %
        (tag, rate_before, rate_after))
    return rate_after


def pwm_watchdog():
    """Periodic guard: any FB_RESUME (e.g. Mir's own unblank, which can
    land after wake_display finishes) re-muxes DISP_PWM to dead ULPOSC
    (rate 0). Re-lock to 26MHz whenever the clock is found dead."""
    rate = pwm_clk_rate()
    if rate == 0:
        log("watchdog: disp_pwm_sel rate 0 (dead ULPOSC), re-locking")
        fix_pwm_clock_and_backlight(tag="watchdog")
    return True

def delayed_pwm_reapply():
    fix_pwm_clock_and_backlight(tag="delayed-reapply")
    return False

def wake_display(reason="signal"):
    global _wake_in_progress
    if _wake_in_progress:
        log("wake already in progress, ignoring (%s)" % reason)
        return
    _wake_in_progress = True
    try:
        log("--- wake begin (%s) ---" % reason)
        irq_before = dsi_irq_count()

        # 1. Disable unblank bypass
        write_path(MTKFB_DEBUG_PATH, "bypass_blank:0\n")

        # 1b. Unblank framebuffer early so DSI is enabled (verified fix:
        #     previously FBIOBLANK UNBLANK was never issued, leaving
        #     card0-DSI-1 disabled / black screen on wake)
        fb_ok = unblank_fb_ioctl()
        log("FBIOBLANK UNBLANK ioctl result: %s" % fb_ok)
        if os.path.exists(FB_BLANK_PATH):
            write_path(FB_BLANK_PATH, "0")

        # 2. Configure PWM clock (26MHz) and bypass AAL
        write_path(DISPSYS_DEBUG_PATH, "pwm_test:pwmmux:3\n")
        write_path(DISPSYS_DEBUG_PATH, "aal_test:bypass:1\n")

        # 3. Enable hardware power rails: LDO 3.3V, AVDD +5V, AVEE -5V, Backlight IC
        set_gpio(GPIO_LDO, 1)
        set_gpio(GPIO_ENP, 1)
        set_gpio(GPIO_ENN, 1)
        set_gpio(GPIO_LED, 1)
        time.sleep(0.02)

        # 4. Trigger kernel ESD recovery: cleanly resets FT8201 and re-transmits
        #    the complete init_setting_vdo DSI packet table over MIPI DSI.
        write_path(MTKFB_DEBUG_PATH, "esd_recovery\n")
        time.sleep(0.05)

        # 5. Ensure PWM and rails remain active
        write_path(DISPSYS_DEBUG_PATH, "pwm_test:pwmmux:3\n")
        write_path(DISPSYS_DEBUG_PATH, "aal_test:bypass:1\n")
        set_gpio(GPIO_LED, 1)

        # 6. Restore brightness
        cur = read_path(BACKLIGHT_PATH, "0")
        try:
            cur_i = int(cur)
        except ValueError:
            cur_i = 0
        last = read_path("/run/mtk-display-wake.last-brightness", "0")
        try:
            last_i = int(last)
        except ValueError:
            last_i = 0
        target = max(cur_i, last_i, DEFAULT_BRIGHTNESS)
        set_brightness(target)

        # 6b. Re-lock PWM clock to 26MHz + force backlight (must be LAST:
        #     every FB_RESUME re-muxes PWM to dead ULPOSC; Mir may unblank
        #     again after us, so re-apply delayed as well).
        fix_pwm_clock_and_backlight(tag="wake")
        GLib.timeout_add(2000, delayed_pwm_reapply)
        GLib.timeout_add(5000, delayed_pwm_reapply)

        time.sleep(0.05)
        irq_after = dsi_irq_count()
        log("wake done: brightness=%s dsi_irq %s -> %s" %
            (read_path(BACKLIGHT_PATH, "?"), irq_before, irq_after))
    finally:
        _wake_in_progress = False

def sleep_display(reason="signal"):
    log("--- sleep (%s) ---" % reason)
    try:
        cur = int(read_path(BACKLIGHT_PATH, "0") or 0)
    except ValueError:
        cur = 0
    if cur >= MIN_BRIGHTNESS:
        write_path("/run/mtk-display-wake.last-brightness", "%d\n" % cur)
    set_gpio(GPIO_LED, 0)

def on_display_power_state_change(state, reason_code):
    try:
        state = int(state)
    except (TypeError, ValueError):
        return
    log("DisplayPowerStateChange state=%d reason=%s" % (state, reason_code))
    if state == 1:
        GLib.idle_add(lambda: (wake_display("unity-screen"), False)[1])
    elif state == 0:
        GLib.idle_add(lambda: (sleep_display("unity-screen"), False)[1])

def on_prepare_for_sleep(going_to_sleep):
    log("PrepareForSleep going_to_sleep=%s" % going_to_sleep)
    if not going_to_sleep:
        GLib.idle_add(lambda: (wake_display("logind-resume"), False)[1])

def main():
    log("mtk-display-wake starting (pid %d)" % os.getpid())
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()

    bus.add_signal_receiver(
        on_display_power_state_change,
        signal_name="DisplayPowerStateChange",
        dbus_interface="com.canonical.Unity.Screen",
        path="/com/canonical/Unity/Screen",
    )

    try:
        bus.add_signal_receiver(
            on_prepare_for_sleep,
            signal_name="PrepareForSleep",
            dbus_interface="org.freedesktop.login1.Manager",
            path="/org/freedesktop/login1",
        )
    except dbus.DBusException as exc:
        log("could not subscribe to PrepareForSleep: %s" % exc)

    # Trigger wake once at startup
    GLib.timeout_add(500, lambda: (wake_display("startup"), False)[1])

    log("listening on com.canonical.Unity.Screen + logind")
    GLib.timeout_add(5000, pwm_watchdog)
    GLib.MainLoop().run()

if __name__ == "__main__":
    main()
