#!/bin/sh

# 1. Mount debugfs if needed
mountpoint -q /sys/kernel/debug 2>/dev/null || mount -t debugfs none /sys/kernel/debug 2>/dev/null || true

# 2. Prevent mtkfb from killing DSI/LCM link on blank (crucial for sleep/wake)
if [ -e /sys/kernel/debug/mtkfb ]; then
    echo "bypass_blank:1" > /sys/kernel/debug/mtkfb 2>/dev/null || true
fi

# 3. Keep power button wake active in MTK KPD driver
echo 2 > /sys/bus/platform/drivers/mtk-kpd/kpd_call_state 2>/dev/null || true
for f in $(find /sys -name kpd_call_state 2>/dev/null); do
    echo 2 > "$f" 2>/dev/null || true
done

# 4. Ensure permissions on lcd-backlight
chmod 0666 /sys/class/leds/lcd-backlight/brightness 2>/dev/null || true
chmod 0666 /sys/class/leds/lcd-backlight/max_brightness 2>/dev/null || true

# 5. Firmware symlinks
mkdir -p /lib/firmware
ln -sf /vendor/firmware/* /lib/firmware/ 2>/dev/null || true

# 6. Bring up Wi-Fi (wait up to 15s if device node not ready yet)
(
    for i in $(seq 1 30); do
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
