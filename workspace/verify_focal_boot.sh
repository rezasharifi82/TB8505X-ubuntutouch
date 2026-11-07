#!/bin/bash
# verify_focal_boot.sh - Post-boot verification for Focal 20.04 on TB-8505X
set -uo pipefail

OUT=/home/mreza/Desktop/TB8505X
NEW_SSH_KEY="$OUT/lenovo-tab-m8/out/ssh_debug_key"
OLD_SSH_KEY="$OUT/TB8505X-ubuntutouch/out/ota_24_04/ssh_debug_key"
ADB="adb"
PASS=0; FAIL=0

ok(){ echo "[PASS] $*"; PASS=$((PASS+1)); }
bad(){ echo "[FAIL] $*"; FAIL=$((FAIL+1)); }
info(){ echo "[INFO] $*"; }
section(){ echo ""; echo "=== $* ==="; }

echo "=== verify_focal_boot.sh  $(date -u) ==="

# ensure adb connection
$ADB connect 10.15.19.82 2>/dev/null || true
$ADB forward tcp:2222 tcp:22 2>/dev/null || true

section "2a. OS release (expect 20.04 focal)"
OS=$(adb shell cat /etc/os-release 2>/dev/null || true)
echo "$OS"
echo "$OS" | grep -q 'VERSION="20.04 (Focal Fossa)"' && ok "VERSION=20.04 focal" || bad "VERSION not 20.04 focal"
echo "$OS" | grep -q 'NAME="Ubuntu Touch"' && ok "NAME=Ubuntu Touch" || bad "NAME mismatch"

section "2b. Device identity (expect akita_row_call)"
DEV=$(adb shell getprop ro.product.device 2>/dev/null || true)
echo "ro.product.device = $DEV"
[ "$DEV" = "akita_row_call" ] && ok "product.device=akita_row_call" || bad "product.device=$DEV"

section "2c. Kernel (expect mreza@Phantom, Nov 7 2026+)"
KV=$(adb shell cat /proc/version 2>/dev/null || true)
echo "$KV"
echo "$KV" | grep -q 'mreza@Phantom' && ok "kernel built by mreza@Phantom" || bad "kernel builder not mreza@Phantom"
echo "$KV" | grep -qE 'Nov  7 2026|Nov  8 2026|Nov  9 2026|Nov 10 2026|Nov 11 2026' && ok "kernel date Nov 7+ 2026" || bad "kernel date not Nov 7+ 2026"
echo "$KV" | grep -qE '4\.9' && ok "kernel 4.9.x" || bad "kernel version not 4.9.x"

section "2d. LTE modem IMEI"
IMEI=$(adb shell getprop ro.ril.imei 2>/dev/null || true)
echo "ro.ril.imei = $IMEI"
[ -n "$IMEI" ] && [ "$IMEI" != "" ] && ok "IMEI present" || bad "IMEI blank"
echo "$IMEI" | grep -qE '^[0-9]{15}$' && ok "IMEI is 15 digits" || info "IMEI format unexpected (check manually)"

section "2e. Display DSI path"
DSI=$(adb shell cat /sys/class/drm/card0/card0-DSI-1/enabled 2>/dev/null || true)
echo "card0-DSI-1/enabled = $DSI"
[ "$DSI" = "enabled" ] && ok "DSI-1 enabled" || bad "DSI-1 not enabled ($DSI)"

section "2f. DSI0 IRQ baseline"
IRQ=$(adb shell grep -E 'dsi0|rdma0' /proc/interrupts 2>/dev/null || true)
echo "$IRQ"
echo "$IRQ" | grep -q 'dsi0' && ok "dsi0 IRQ present" || bad "dsi0 IRQ missing"
DSI0_COUNT=$(echo "$IRQ" | awk '/dsi0 :/ {print $NF}' | head -1)
echo "dsi0 baseline count: $DSI0_COUNT"

section "2g. SSH via adb forward"
SSH_KEY="$NEW_SSH_KEY"
[ -f "$SSH_KEY" ] || SSH_KEY="$OLD_SSH_KEY"
info "using SSH key: $SSH_KEY"
if [ -f "$SSH_KEY" ]; then
  SSH_OUT=$(timeout 15 ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" -p 2222 root@127.0.0.1 'echo SSH_OK; uname -a' 2>&1 || true)
  echo "$SSH_OUT"
  echo "$SSH_OUT" | grep -q 'SSH_OK' && ok "SSH login works" || bad "SSH login failed"
  echo "$SSH_OUT" | grep -q 'mreza@Phantom' && ok "SSH uname shows patched kernel" || info "SSH uname kernel check inconclusive"
else
  bad "no SSH debug key found"
fi

section "2h. Additional checks"
LCD=$(adb shell getprop ro.boot lcd_size 2>/dev/null || true)
echo "ro.boot lcd_size = $LCD"
[ "$LCD" = "800x1280" ] && ok "lcd_size=800x1280" || info "lcd_size=$LCD (expected 800x1280)"

FB=$(adb shell cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || true)
echo "fb0 virtual_size = $FB"

BL=$(adb shell cat /sys/class/leds/lcd-backlight/brightness 2>/dev/null || true)
echo "lcd-backlight = $BL"

section "SUMMARY"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && { echo "ALL CHECKS PASSED"; exit 0; } || { echo "SOME CHECKS FAILED — review above"; exit 1; }
