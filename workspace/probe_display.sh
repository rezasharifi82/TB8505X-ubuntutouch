#!/bin/bash
# Display wake probe for TB-8505X
exec 2>&1
D=/sys/kernel/debug
GP=/sys/devices/platform/1000b000.pinctrl/mt_gpio

say() { echo; echo "### $*"; }

gpio() { grep -E "^( *45| *152| *154| *167| *168| *172):" $GP; }

say "PRE"
echo "brightness=$(cat /sys/class/leds/lcd-backlight/brightness)"
echo "blank=[$(cat /sys/class/graphics/fb0/blank)]"
gpio
echo "loadavg=$(cat /proc/loadavg)"

say "DEBUGFS TOP"
ls $D
say "DPREC"
ls -l $D/dprec 2>/dev/null || echo "no dprec dir"
ls /proc/dprec* 2>/dev/null || true

say "IRQ RAW"
grep -E "dsi0|rdma0|ovl0|mtk_cmdq" /proc/interrupts

say "DPREC DUMP (before)"
if [ -f $D/dprec/dump ]; then head -c 1500 $D/dprec/dump; else echo "(none)"; fi

say "STEP1: fb blank=4 (POWERDOWN)"
timeout 25 sh -c 'echo 4 > /sys/class/graphics/fb0/blank'
echo "rc=$?"
sleep 1
echo "blank=[$(cat /sys/class/graphics/fb0/blank)]"
gpio
grep -E "dsi0|rdma0|ovl0" /proc/interrupts

say "STEP2: fb blank=0 (UNBLANK)"
timeout 30 sh -c 'echo 0 > /sys/class/graphics/fb0/blank'
echo "rc=$?"
sleep 1
echo "blank=[$(cat /sys/class/graphics/fb0/blank)]"
gpio

say "STEP3: brightness 150 + FBIOBLANK"
echo 150 > /sys/class/leds/lcd-backlight/brightness
python3 -c "import fcntl; f=open('/dev/fb0','wb'); fcntl.ioctl(f,0x4611,0); print('ioctl_ok')"
sleep 1
echo "brightness=$(cat /sys/class/leds/lcd-backlight/brightness)"

say "IRQ AFTER"
grep -E "dsi0|rdma0|ovl0|mtk_cmdq" /proc/interrupts

say "DPREC DUMP (after)"
if [ -f $D/dprec/dump ]; then head -c 6000 $D/dprec/dump; else echo "(none)"; fi

say "DMESG"
dmesg | tail -40

say "FB HASH"
python3 - <<'PY'
import hashlib
W,H=800,1280
f=open('/dev/fb0','rb'); d=f.read(W*H*4); f.close()
print("hash=%s nonzero=%d" % (hashlib.sha256(d).hexdigest()[:16], sum(1 for b in d if b)))
PY

say "END"