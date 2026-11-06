#!/usr/bin/env bash
# ==============================================================================
# Script: apply_sleep_wake_fix.sh (v3)
# Purpose: Comprehensive Sleep/Wake, Backlight, WiFi, BT, and Keypad Fix for Lenovo TB-8505X
# Target: Lenovo Tab M8 HD LTE (TB-8505X / akita_row_call)
# ==============================================================================

set -euo pipefail

echo "================================================================================"
echo " Ubuntu Touch Sleep/Wake, Backlight & Connectivity Fix Suite v3"
echo " Target: Lenovo Tab M8 HD LTE (TB-8505X / akita_row_call)"
echo "================================================================================"

echo "[*] Waiting for device in Fastboot or Recovery mode..."
while true; do
    if fastboot devices 2>/dev/null | grep -q "fastboot"; then
        echo "[*] Device detected in Fastboot mode. Rebooting to Recovery..."
        fastboot reboot recovery || true
        sleep 5
        break
    elif adb devices 2>/dev/null | grep -q "recovery"; then
        echo "[*] Device detected in Recovery mode."
        break
    elif adb devices 2>/dev/null | grep -q "device"; then
        echo "[*] Device detected in user/phablet mode. Rebooting to Recovery..."
        adb reboot recovery || true
        sleep 5
        break
    fi
    sleep 1
done

echo "[*] Waiting for device in Recovery mode (adb wait-for-recovery)..."
adb wait-for-recovery

DEV_STATE=$(adb get-state 2>/dev/null || echo "unknown")
echo "[*] Device state: $DEV_STATE"

SYSTEM_DEV="/dev/block/by-name/system"
RESOLVED_SYSTEM=$(adb shell "readlink -f $SYSTEM_DEV" | tr -d '\r\n')
echo "[*] Target /system: $RESOLVED_SYSTEM"

if [ "$RESOLVED_SYSTEM" != "/dev/block/mmcblk0p37" ]; then
    echo "[FATAL] System partition mismatch! Expected /dev/block/mmcblk0p37, got '$RESOLVED_SYSTEM'."
    exit 1
fi

SYSTEM_MOUNT="/cache/system"
echo "[*] Mounting $RESOLVED_SYSTEM to $SYSTEM_MOUNT..."
adb shell "mkdir -p $SYSTEM_MOUNT"
adb shell "mount -t ext4 -o rw,noatime $RESOLVED_SYSTEM $SYSTEM_MOUNT"

MOUNTED=$(adb shell "mountpoint -q $SYSTEM_MOUNT && echo YES || echo NO" | tr -d '\r\n')
if [ "$MOUNTED" != "YES" ]; then
    echo "[FATAL] Failed to mount $SYSTEM_MOUNT!"
    exit 1
fi
echo "[OK] System partition mounted."

echo "[1/8] Configuring repowerd mocksuspend and debug logging..."
adb shell "mkdir -p $SYSTEM_MOUNT/etc/default"
adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/default/repowerd
# repowerd configuration for Lenovo TB-8505X
# REPOWERD_MOCKSUSPEND=1 makes repowerd fake the suspend handshake instead of
# using logind. Verified on-device 2026-11-06: with it enabled the display
# state machine and the kernel display path disagree about whether the panel
# is suspended, so wake never re-initialises the FT8201 over DSI. Keep off.
#REPOWERD_MOCKSUSPEND=1
REPOWERD_QUIRK_NORMAL_BEFORE_DISPLAY_ON_AUTOBRIGHTNESS=always
REPOWERD_LOG=syslog
REPOWERD_LOG_LEVEL=debug
EOF"

echo "[2/8] Creating repowerd device XML configs (halium_arm64, akita_row_call, default)..."
adb shell "mkdir -p $SYSTEM_MOUNT/usr/share/repowerd/device-configs"
adb shell "cat << 'EOF' > $SYSTEM_MOUNT/usr/share/repowerd/device-configs/config-halium_arm64.xml
<?xml version=\"1.0\" encoding=\"utf-8\"?>
<resources xmlns:xliff=\"urn:oasis:names:tc:xliff:document:1.2\">
    <bool name=\"config_automatic_brightness_available\">false</bool>
    <integer name=\"config_criticalBatteryWarningLevel\">0</integer>
    <integer name=\"config_shutdownBatteryTemperature\">680</integer>
    <integer name=\"config_screenBrightnessSettingMinimum\">10</integer>
    <integer name=\"config_screenBrightnessSettingMaximum\">255</integer>
    <integer name=\"config_screenBrightnessSettingDefault\">128</integer>
    <integer name=\"config_screenBrightnessDim\">20</integer>
</resources>
EOF"
adb shell "cp -f $SYSTEM_MOUNT/usr/share/repowerd/device-configs/config-halium_arm64.xml $SYSTEM_MOUNT/usr/share/repowerd/device-configs/config-halium.xml"
adb shell "cp -f $SYSTEM_MOUNT/usr/share/repowerd/device-configs/config-halium_arm64.xml $SYSTEM_MOUNT/usr/share/repowerd/device-configs/config-akita_row_call.xml"
adb shell "cp -f $SYSTEM_MOUNT/usr/share/repowerd/device-configs/config-halium_arm64.xml $SYSTEM_MOUNT/usr/share/repowerd/device-configs/config-akita.xml"

echo "[3/8] Writing complete deviceinfo YAML configurations..."
adb shell "mkdir -p $SYSTEM_MOUNT/etc/deviceinfo/devices $SYSTEM_MOUNT/usr/share/deviceinfo/devices"

# Complete deviceinfo for halium_arm64 and akita_row_call
adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/deviceinfo/devices/halium_arm64.yaml
halium_arm64:
  Names:
    - halium_arm64
    - akita_row_call
    - akita
    - Lenovo Tab M8 HD
    - TB-8505X
    - TB-8505FS
    - TB-8505F
  Name: halium_arm64
  PrettyName: Lenovo Tab M8 HD
  DeviceType: tablet
  GridUnit: 21
  WebkitDpr: 2
  PrimaryOrientation: Portrait
  BacklightSysfsPath: /sys/class/leds/lcd-backlight
EOF"

adb shell "cp -f $SYSTEM_MOUNT/etc/deviceinfo/devices/halium_arm64.yaml $SYSTEM_MOUNT/etc/deviceinfo/devices/halium.yaml"
adb shell "cp -f $SYSTEM_MOUNT/etc/deviceinfo/devices/halium_arm64.yaml $SYSTEM_MOUNT/etc/deviceinfo/devices/akita_row_call.yaml"
adb shell "cp -f $SYSTEM_MOUNT/etc/deviceinfo/devices/halium_arm64.yaml $SYSTEM_MOUNT/etc/deviceinfo/devices/akita.yaml"
adb shell "cp -f $SYSTEM_MOUNT/etc/deviceinfo/devices/halium_arm64.yaml $SYSTEM_MOUNT/usr/share/deviceinfo/devices/halium_arm64.yaml"
adb shell "cp -f $SYSTEM_MOUNT/etc/deviceinfo/devices/halium_arm64.yaml $SYSTEM_MOUNT/usr/share/deviceinfo/devices/halium.yaml"
adb shell "cp -f $SYSTEM_MOUNT/etc/deviceinfo/devices/halium_arm64.yaml $SYSTEM_MOUNT/usr/share/deviceinfo/devices/akita_row_call.yaml"

# Overwrite default.yaml so all fallbacks have BacklightSysfsPath
adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/deviceinfo/default.yaml
defaults:
  default:
    Name: generic
    PrettyName: Generic device
    DeviceType: tablet
    GridUnit: 21
    SupportedOrientations:
      - Portrait
      - InvertedPortrait
      - Landscape
      - InvertedLandscape
    PrimaryOrientation: Portrait
    PortraitOrientation: Portrait
    InvertedPortraitOrientation: InvertedPortrait
    LandscapeOrientation: Landscape
    InvertedLandscapeOrientation: InvertedLandscape
    WebkitDpr: 2
    BacklightSysfsPath: /sys/class/leds/lcd-backlight

  halium:
    Name: halium_arm64
    PrettyName: Lenovo Tab M8 HD
    DeviceType: tablet
    GridUnit: 21
    WebkitDpr: 2
    PrimaryOrientation: Portrait
    BacklightSysfsPath: /sys/class/leds/lcd-backlight

  phone:
    GridUnit: 21
    WebkitDpr: 2
    PrimaryOrientation: Portrait
    BacklightSysfsPath: /sys/class/leds/lcd-backlight

  tablet:
    GridUnit: 21
    WebkitDpr: 2
    PrimaryOrientation: Portrait
    BacklightSysfsPath: /sys/class/leds/lcd-backlight

  desktop:
    GridUnit: 8
    PrimaryOrientation: Landscape
    BacklightSysfsPath: /sys/class/leds/lcd-backlight
EOF"

echo "[4/8] Installing mtk-power-wake hardware script and systemd service..."
adb shell "mkdir -p $SYSTEM_MOUNT/usr/local/bin $SYSTEM_MOUNT/etc/systemd/system/basic.target.wants $SYSTEM_MOUNT/etc/systemd/system/graphical.target.wants"

adb shell "cat << 'EOF' > $SYSTEM_MOUNT/usr/local/bin/mtk-power-wake.sh
#!/bin/sh

# 1. Mount debugfs if needed
mountpoint -q /sys/kernel/debug 2>/dev/null || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true

# 2. Do NOT bypass FB blank. bypass_blank:1 makes mtkfb_blank() return before
#    primary_display_set_power_mode(), which disables the only userspace path
#    that reaches disp_lcm_resume() and re-initialises the FT8201 over DSI.
#    Verified on-device 2026-11-06: this must be 0.
if [ -e /sys/kernel/debug/mtkfb ]; then
    echo "bypass_blank:0" > /sys/kernel/debug/mtkfb 2>/dev/null || true
fi

# 3. Keep power button wake active in MTK KPD driver
echo 2 > /sys/bus/platform/drivers/mtk-kpd/kpd_call_state 2>/dev/null || true
for f in \$(find /sys -name kpd_call_state 2>/dev/null); do
    echo 2 > "\$f" 2>/dev/null || true
done

# 4. Ensure permissions on lcd-backlight
chmod 0666 /sys/class/leds/lcd-backlight/brightness 2>/dev/null || true
chmod 0666 /sys/class/leds/lcd-backlight/max_brightness 2>/dev/null || true

# 5. Link vendor firmware to /lib/firmware for MT6631 Wi-Fi, BT, Audio
mkdir -p /lib/firmware
ln -sf /vendor/firmware/* /lib/firmware/ 2>/dev/null || true

# 6. Bring up Wi-Fi chip via MediaTek WMT
(
    for i in \$(seq 1 30); do
        if [ -e /dev/wmtWifi ]; then
            echo 1 > /dev/wmtWifi 2>/dev/null || true
            break
        fi
        sleep 0.5
    done
) &

# 7. Unblock and bring up Bluetooth
(
    sleep 3
    rfkill unblock bluetooth 2>/dev/null || true
    hciconfig hci0 up 2>/dev/null || true
) &

exit 0
EOF"

adb shell "chmod +x $SYSTEM_MOUNT/usr/local/bin/mtk-power-wake.sh"

adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/systemd/system/mtk-kpd-wake.service
[Unit]
Description=MediaTek MT6761 Keypad Wake, Display and Hardware Init Fix
DefaultDependencies=no
Before=repowerd.service display-manager.service network-pre.target
After=systemd-udev-settle.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/mtk-power-wake.sh

[Install]
WantedBy=basic.target graphical.target
EOF"

adb shell "ln -sf /etc/systemd/system/mtk-kpd-wake.service $SYSTEM_MOUNT/etc/systemd/system/basic.target.wants/mtk-kpd-wake.service"
adb shell "ln -sf /etc/systemd/system/mtk-kpd-wake.service $SYSTEM_MOUNT/etc/systemd/system/graphical.target.wants/mtk-kpd-wake.service"

echo "[5/8] Configuring tmpfiles and udev rules..."
adb shell "mkdir -p $SYSTEM_MOUNT/etc/tmpfiles.d $SYSTEM_MOUNT/etc/udev/rules.d"
adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/tmpfiles.d/lcd-backlight.conf
z /sys/class/leds/lcd-backlight/brightness 0666 root root -
z /sys/class/leds/lcd-backlight/max_brightness 0666 root root -
w- /sys/bus/platform/drivers/mtk-kpd/kpd_call_state - - - - 2
w- /sys/power/autosleep - - - - off
EOF"

adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/udev/rules.d/70-akita.rules
# MediaTek WMT Connectivity (WiFi, Bluetooth, GPS, FM)
KERNEL==\"wmtWifi\", MODE=\"0666\", GROUP=\"netdev\"
KERNEL==\"stpwmt\", MODE=\"0666\", GROUP=\"netdev\"
KERNEL==\"wmtdetect\", MODE=\"0666\", GROUP=\"netdev\"
KERNEL==\"stpbt\", MODE=\"0666\", GROUP=\"bluetooth\"
KERNEL==\"stpgps\", MODE=\"0666\", GROUP=\"gps\"
KERNEL==\"fm\", MODE=\"0666\", GROUP=\"audio\"

# Input and Backlight
KERNEL==\"uinput\", MODE=\"0666\", GROUP=\"input\"
SUBSYSTEM==\"leds\", ACTION==\"add\", KERNEL==\"lcd-backlight\", ATTR{brightness}=\"128\", RUN+=\"/bin/chmod 0666 /sys/class/leds/lcd-backlight/brightness /sys/class/leds/lcd-backlight/max_brightness\"
ACTION==\"add\", SUBSYSTEM==\"platform\", DRIVERS==\"mtk-kpd\", ATTR{kpd_call_state}=\"2\"
EOF"

adb shell "cp -f $SYSTEM_MOUNT/etc/udev/rules.d/70-akita.rules $SYSTEM_MOUNT/usr/lib/udev/rules.d/70-akita.rules"

echo "[6/8] Masking deep sleep targets..."
adb shell "mkdir -p $SYSTEM_MOUNT/etc/systemd/system"
adb shell "ln -sf /dev/null $SYSTEM_MOUNT/etc/systemd/system/suspend.target"
adb shell "ln -sf /dev/null $SYSTEM_MOUNT/etc/systemd/system/hibernate.target"
adb shell "ln -sf /dev/null $SYSTEM_MOUNT/etc/systemd/system/hybrid-sleep.target"
adb shell "ln -sf /dev/null $SYSTEM_MOUNT/etc/systemd/system/suspend-then-hibernate.target"

echo "[7/8] Verifying logind power key configuration & dconf power settings..."
adb shell "mkdir -p $SYSTEM_MOUNT/etc/systemd/logind.conf.d"
adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/systemd/logind.conf.d/10-powerkey.conf
[Login]
HandlePowerKey=ignore
HandlePowerKeyLongPress=poweroff
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
EOF"

adb shell "mkdir -p $SYSTEM_MOUNT/etc/dconf/db/local.d $SYSTEM_MOUNT/etc/dconf/profile"
adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/dconf/db/local.d/01-power
[org/gnome/desktop/session]
idle-delay=uint32 0

[org/gnome/desktop/screensaver]
idle-activation-enabled=false
EOF"

adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/dconf/profile/user
user-db:user
system-db:local
EOF"

echo "[8/8] Syncing and unmounting..."
adb shell "sync"
adb shell "umount $SYSTEM_MOUNT"
echo "[OK] System partition unmounted cleanly."

echo "================================================================================"
echo " [SUCCESS] All fixes applied! Rebooting into Ubuntu Touch..."
echo "================================================================================"
adb reboot
