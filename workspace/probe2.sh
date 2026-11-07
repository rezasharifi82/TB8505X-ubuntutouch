#!/bin/bash
exec 2>&1
GP=/sys/devices/platform/1000b000.pinctrl/mt_gpio
say(){ echo; echo "### $*"; }
gpio(){ grep -E "^( *45| *152| *154| *167| *168| *172):" $GP; }
irq(){ grep -E "^ *(208|263|264|265|272):" /proc/interrupts | awk '{print $1, $(NF-1), $NF}'; }

say PRE
echo "brightness=$(cat /sys/class/leds/lcd-backlight/brightness)"
echo "blank=[$(cat /sys/class/graphics/fb0/blank)]"
gpio
irq

say LCDREG_READ
timeout 5 head -c 1200 /sys/kernel/debug/lcdreg 2>&1

say DISP_DUMP
timeout 5 head -c 600 /sys/kernel/debug/disp/dump 2>&1

say BIST_ON
dmesg -c > /dev/null
printf 'dsipattern:1' > /sys/kernel/debug/mtkfb
echo "bist_on_rc=$?"
sleep 2
echo "--- dmesg ---"
dmesg | tail -15
irq
gpio

say DONE_BIST_LEFT_ON
echo "Screen should now show DSI BIST colour bars."
