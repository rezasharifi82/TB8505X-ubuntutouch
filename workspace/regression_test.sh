#!/bin/bash
# TB-8505X (akita_row_call) Focal 20.04 regression test harness
# Critical bug: black-screen-after-sleep/wake (dsi0 IRQ stuck)
# Pass/fail: dsi0 IRQ count in /proc/interrupts MUST advance after suspend+resume

set -o pipefail

ADB_HOST="10.15.19.82"
ADB="adb -s ${ADB_HOST}"
ADB_TIMEOUT="timeout 15"
RESULTS="/home/mreza/Desktop/TB8505X/regression_results.txt"
LOOP=1
LOOP_MODE=0

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --loop) LOOP="$2"; LOOP_MODE=1; shift 2 ;;
        --adb) ADB_HOST="$2"; ADB="adb -s $2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

# Ensure adb uses TCP
$ADB connect "$ADB_HOST" 2>/dev/null || true

log() { echo "$@" | tee -a "$RESULTS"; }
section() { echo "" | tee -a "$RESULTS"; echo "=== $1 ===" | tee -a "$RESULTS"; }
pass() { echo "  [$1] $2" | tee -a "$RESULTS"; }
fail() { echo "  [FAIL] $1" | tee -a "$RESULTS"; }
skip() { echo "  [SKIP] $1" | tee -a "$RESULTS"; }

# Wrapper: run adb shell command with timeout, return output
runcmd() {
    $ADB_TIMEOUT $ADB shell "$@" 2>/dev/null
}

# Check if adb is responsive
check_adb() {
    $ADB_TIMEOUT $ADB shell "echo ok" 2>/dev/null | grep -q ok
}

# Initialize results file
echo "=== TB-8505X Regression Test ===" > "$RESULTS"
echo "Date: $(date -u)" >> "$RESULTS"
echo "ADB: $ADB" >> "$RESULTS"
echo "Loop count: $LOOP" >> "$RESULTS"
echo "" >> "$RESULTS"

if ! check_adb; then
    log "[FATAL] ADB not reachable at $ADB_HOST. Aborting."
    exit 1
fi
log "ADB connected."

# ============================================================
# 1. DISPLAY / WAKE TEST (highest priority)
# ============================================================
section "1. DISPLAY / WAKE TEST"

# Baseline dsi0/rdma0 IRQ count
BASELINE_DSI=$(runcmd "grep -E 'dsi0|rdma0' /proc/interrupts")
log "Baseline /proc/interrupts (dsi0|rdma0):"
log "$BASELINE_DSI"

# Extract dsi0 count numerically
DSI_BASE=$(echo "$BASELINE_DSI" | grep -i 'dsi0' | head -1 | awk -F: '{gsub(/[^0-9]/,"",$2); print $2+0}')
log "Baseline dsi0 IRQ count: $DSI_BASE"

# GPIO state check (defensive)
GPIO_CHECK=$(runcmd "cat /sys/kernel/debug/gpio 2>/dev/null || echo 'NOT_AVAILABLE'")
if echo "$GPIO_CHECK" | grep -qE 'GPIO167|GPIO168|GPIO45'; then
    log "GPIO state (/sys/kernel/debug/gpio):"
    log "$GPIO_CHECK"
else
    skip "GPIO167/168/45 not exposed via /sys/kernel/debug/gpio — skipping"
fi

# Also try /proc/pinctrl
PINTRL=$(runcmd "cat /proc/pinctrl/pinmux-pins 2>/dev/null | grep -iE '167|168|45' || echo 'NOT_AVAILABLE'")
if [ "$PINTRL" != "NOT_AVAILABLE" ]; then
    log "Pinctrl pins 167/168/45:"
    log "$PINTRL"
fi

WAKE_LOOPS=$LOOP
if [ "$LOOP_MODE" -eq 1 ]; then
    log "Loop mode: $WAKE_LOOPS suspend/wake cycles"
fi

WAKE_PASS=0
WAKE_FAIL=0

for CYCLE in $(seq 1 "$WAKE_LOOPS"); do
    if [ "$WAKE_LOOPS" -gt 1 ]; then
        log "--- Wake cycle $CYCLE/$WAKE_LOOPS ---"
    fi

    # Suspend via power keyevent (primary method)
    log "Suspending (power keyevent)..."
    $ADB_TIMEOUT $ADB shell "input keyevent POWER" 2>/dev/null
    sleep 8

    # Wake via power keyevent
    log "Waking (power keyevent)..."
    $ADB_TIMEOUT $ADB shell "input keyevent POWER" 2>/dev/null
    sleep 8

    # After wake: check dsi0
    AFTER_DSI=$(runcmd "grep -E 'dsi0|rdma0' /proc/interrupts")
    log "After wake /proc/interrupts (dsi0|rdma0):"
    log "$AFTER_DSI"
    DSI_AFTER=$(echo "$AFTER_DSI" | grep -i 'dsi0' | head -1 | awk -F: '{gsub(/[^0-9]/,"",$2); print $2+0}')
    log "After wake dsi0 IRQ count: $DSI_AFTER"

    if [ "$DSI_AFTER" -gt "$DSI_BASE" ]; then
        pass "PASS" "Cycle $CYCLE: dsi0 IRQ advanced ($DSI_BASE -> $DSI_AFTER) — black-screen fix ACTIVE"
        WAKE_PASS=$((WAKE_PASS + 1))
    else
        fail "FAIL" "Cycle $CYCLE: dsi0 IRQ stuck at $DSI_BASE (expected >$DSI_BASE) — BLACK SCREEN BUG PRESENT"
        WAKE_FAIL=$((WAKE_FAIL + 1))
    fi

    # Update baseline for next cycle
    DSI_BASE=$DSI_AFTER
done

if [ "$WAKE_FAIL" -gt 0 ]; then
    fail "FAIL" "Wake test: $WAKE_FAIL/$WAKE_LOOPS cycles FAILED (dsi0 did not advance)"

    # Fallback: FB blank cycle (runbook §3d)
    log "Attempting FB blank fallback (echo 4 -> echo 0 > /sys/class/graphics/fb0/blank)..."
    $ADB_TIMEOUT $ADB shell "echo 4 > /sys/class/graphics/fb0/blank" 2>/dev/null
    sleep 2
    $ADB_TIMEOUT $ADB shell "echo 0 > /sys/class/graphics/fb0/blank" 2>/dev/null
    sleep 2
    FB_DSI=$(runcmd "grep -E 'dsi0|rdma0' /proc/interrupts")
    FB_DSI_COUNT=$(echo "$FB_DSI" | grep -i 'dsi0' | head -1 | awk -F: '{gsub(/[^0-9]/,"",$2); print $2+0}')
    log "dsi0 after FB blank fallback: $FB_DSI_COUNT"
    if [ "$FB_DSI_COUNT" -gt "$DSI_BASE" ]; then
        pass "PASS" "FB blank fallback succeeded (dsi0 advanced to $FB_DSI_COUNT)"
    else
        fail "FAIL" "FB blank fallback also failed (dsi0 still stuck)"
    fi
else
    pass "PASS" "Wake test: $WAKE_PASS/$WAKE_LOOPS cycles PASSED (dsi0 advanced every time)"
fi

# Also check GPIO167/168/45 after wake
GPIO_AFTER=$(runcmd "cat /sys/kernel/debug/gpio 2>/dev/null")
if echo "$GPIO_AFTER" | grep -qE 'GPIO167|GPIO168|GPIO45'; then
    log "GPIO state after wake:"
    log "$GPIO_AFTER"
fi

# FB blank check
FB_BLANK=$(runcmd "cat /sys/class/graphics/fb0/blank 2>/dev/null || echo 'N/A'")
log "fb0 blank state: $FB_BLANK"

# ============================================================
# 2. CAMERA
# ============================================================
section "2. CAMERA"

CAM_DMESG=$(runcmd "dmesg | grep -iE 'imgsensor|isp|camera' | head -20")
if [ -n "$CAM_DMESG" ]; then
    log "Camera dmesg:"
    log "$CAM_DMESG"
else
    skip "No camera dmesg entries found"
fi

CAM_PROCS=$(runcmd "ps -ef | grep -iE 'camera|cameraserver|imgsensor' | grep -v grep")
if [ -n "$CAM_PROCS" ]; then
    log "Camera processes:"
    log "$CAM_PROCS"
    pass "PASS" "Camera processes running"
else
    fail "FAIL" "No camera processes found"
fi

# Try launching camera app
CAM_LAUNCH=$(runcmd "lomiri-camera-app 2>&1 & sleep 2; echo launched" 2>/dev/null)
log "Camera app launch attempt: $CAM_LAUNCH"

# ============================================================
# 3. FILE MANAGER
# ============================================================
section "3. FILE MANAGER"

FM_PROCS=$(runcmd "ps -ef | grep -iE 'filemanager|file-manager' | grep -v grep")
if [ -n "$FM_PROCS" ]; then
    log "File manager processes:"
    log "$FM_PROCS"
else
    skip "File manager not running (may not auto-start)"
fi

# Create test file
FM_CREATE=$(runcmd "touch ~/Documents/regression_test.txt && echo ok" 2>&1)
if echo "$FM_CREATE" | grep -q ok; then
    pass "PASS" "Created ~/Documents/regression_test.txt"
else
    fail "FAIL" "Could not create test file: $FM_CREATE"
fi

# Verify exists
FM_EXISTS=$(runcmd "ls -la ~/Documents/regression_test.txt 2>&1")
if echo "$FM_EXISTS" | grep -q regression_test.txt; then
    pass "PASS" "Test file verified on device"
else
    fail "FAIL" "Test file not found after creation"
fi

# Rename
FM_RENAME=$(runcmd "cd ~/Documents && mv regression_test.txt regression_test_renamed.txt && echo ok" 2>&1)
if echo "$FM_RENAME" | grep -q ok; then
    pass "PASS" "File renamed"
else
    fail "FAIL" "Rename failed: $FM_RENAME"
fi

# Copy
FM_COPY=$(runcmd "cd ~/Documents && cp regression_test_renamed.txt regression_test_copy.txt && echo ok" 2>&1)
if echo "$FM_COPY" | grep -q ok; then
    pass "PASS" "File copied"
else
    fail "FAIL" "Copy failed: $FM_COPY"
fi

# Delete
FM_DELETE=$(runcmd "cd ~/Documents && rm -f regression_test_renamed.txt regression_test_copy.txt regression_test.txt && echo ok" 2>&1)
if echo "$FM_DELETE" | grep -q ok; then
    pass "PASS" "Test files deleted"
else
    fail "FAIL" "Delete failed: $FM_DELETE"
fi

# Verify cleanup
FM_CLEAN=$(runcmd "ls ~/Documents/regression_test* 2>&1")
if echo "$FM_CLEAN" | grep -q "No such file"; then
    pass "PASS" "Cleanup verified"
else
    skip "Cleanup may be incomplete: $FM_CLEAN"
fi

# ============================================================
# 4. RECENT FILES / CONTENT HUB
# ============================================================
section "4. RECENT FILES / CONTENT HUB"

UM_LOG=$(runcmd "journalctl -u lomiri-upload-manager --no-pager -n 20 2>&1")
if [ -n "$UM_LOG" ] && ! echo "$UM_LOG" | grep -q "No journal files"; then
    log "lomiri-upload-manager journal:"
    log "$UM_LOG"
else
    skip "lomiri-upload-manager journal not available"
fi

DM_LOG=$(runcmd "journalctl -u lomiri-download-manager --no-pager -n 20 2>&1")
if [ -n "$DM_LOG" ] && ! echo "$DM_LOG" | grep -q "No journal files"; then
    log "lomiri-download-manager journal:"
    log "$DM_LOG"
else
    skip "lomiri-download-manager journal not available"
fi

CH_PROCS=$(runcmd "ps -ef | grep -iE 'content-hub|upload-manager|download-manager' | grep -v grep")
if [ -n "$CH_PROCS" ]; then
    log "Content hub / manager processes:"
    log "$CH_PROCS"
    pass "PASS" "Content hub processes running"
else
    skip "No content hub processes found"
fi

# Check for errors in content hub logs
CH_ERR=$(runcmd "journalctl -u lomiri-upload-manager -p err --since '5 minutes ago' --no-pager 2>&1 | tail -10")
if [ -n "$CH_ERR" ] && ! echo "$CH_ERR" | grep -q "No journal files"; then
    fail "FAIL" "Content hub errors found: $CH_ERR"
else
    pass "PASS" "No recent content hub errors"
fi

# ============================================================
# 5. CONNECTIVITY
# ============================================================
section "5. CONNECTIVITY"

# Network state
NET_STATE=$(runcmd "nmcli -t -f STATE,CONNECTIVITY general 2>&1")
if [ -n "$NET_STATE" ]; then
    log "Network state: $NET_STATE"
    if echo "$NET_STATE" | grep -qE "connected|fully"; then
        pass "PASS" "Network connected"
    else
        skip "Network not fully connected: $NET_STATE"
    fi
else
    skip "nmcli not available or no output"
fi

# Wi-Fi
WIFI_LIST=$(runcmd "nmcli device wifi list 2>&1 | head -10")
if [ -n "$WIFI_LIST" ]; then
    log "Wi-Fi scan (first 10 lines):"
    log "$WIFI_LIST"
else
    skip "Wi-Fi scan returned no output"
fi

# IMEI / modem
IMEI=$(runcmd "getprop ro.ril.imei 2>&1")
log "IMEI: $IMEI"
if [ -n "$IMEI" ] && [ "$IMEI" != "" ]; then
    pass "PASS" "IMEI present: $IMEI"
else
    fail "FAIL" "IMEI missing or empty"
fi

# Modem processes
MODEM_PROCS=$(runcmd "ps -ef | grep -iE 'lomiri-telephony|ofono|rild|modem' | grep -v grep")
if [ -n "$MODEM_PROCS" ]; then
    log "Modem/telephony processes:"
    log "$MODEM_PROCS"
    pass "PASS" "Modem stack running"
else
    skip "No modem processes found"
fi

# SIM check
SIM_STATUS=$(runcmd "getprop gsm.operator.numeric 2>&1")
log "MCCMNC: $SIM_STATUS"
if [ -n "$SIM_STATUS" ] && [ "$SIM_STATUS" != "" ]; then
    pass "PASS" "SIM recognized (MCCMNC: $SIM_STATUS)"
else
    skip "SIM not detected or no MCCMNC"
fi

# ============================================================
# 6. AUDIO
# ============================================================
section "6. AUDIO"

APLAY=$(runcmd "aplay -l 2>&1")
if [ -n "$APLAY" ]; then
    log "Sound cards:"
    log "$APLAY"
    if echo "$APLAY" | grep -qE "card|PCM"; then
        pass "PASS" "Audio devices enumerated"
    else
        skip "aplay returned no PCM devices"
    fi
else
    fail "FAIL" "aplay -l returned no output"
fi

PULSE=$(runcmd "ps -ef | grep -iE 'pulseaudio|pipewire|pulse' | grep -v grep")
if [ -n "$PULSE" ]; then
    log "Audio daemon processes:"
    log "$PULSE"
    pass "PASS" "Audio daemon running"
else
    skip "No audio daemon process found"
fi

# ============================================================
# 7. SENSORS
# ============================================================
section "7. SENSORS"

IIO=$(runcmd "ls /sys/bus/iio/devices/ 2>&1")
if [ -n "$IIO" ]; then
    log "IIO devices:"
    log "$IIO"
    pass "PASS" "IIO sensor devices present"
else
    skip "No IIO devices found at /sys/bus/iio/devices/"
fi

# Check for specific sensors
ACCEL=$(runcmd "cat /sys/bus/iio/devices/*/in_accel_x_raw 2>/dev/null || echo 'N/A'")
if [ "$ACCEL" != "N/A" ]; then
    pass "PASS" "Accelerometer readable"
else
    skip "Accelerometer not readable via sysfs"
fi

ALS=$(runcmd "cat /sys/bus/iio/devices/*/in_illuminance_raw 2>/dev/null || echo 'N/A'")
if [ "$ALS" != "N/A" ]; then
    pass "PASS" "Ambient light sensor readable"
else
    skip "ALS not readable via sysfs"
fi

# ============================================================
# 8. POWER / ROBUSTNESS
# ============================================================
section "8. POWER / ROBUSTNESS"

UPTIME=$(runcmd "uptime 2>&1")
log "Uptime: $UPTIME"

# Battery level
BATT=$(runcmd "cat /sys/class/power_supply/*/capacity 2>/dev/null || upower -d 2>/dev/null | grep -i 'percentage' | head -3 || echo 'N/A'")
log "Battery: $BATT"
if [ -n "$BATT" ] && [ "$BATT" != "N/A" ]; then
    pass "PASS" "Battery level readable"
else
    skip "Battery level not available"
fi

# Check for battery hardware presence
BATT_PRESENT=$(runcmd "cat /sys/class/power_supply/*/present 2>/dev/null || echo 'N/A'")
log "Battery present: $BATT_PRESENT"

# Thermal
THERMAL=$(runcmd "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -5 || echo 'N/A'")
log "Thermal zones: $THERMAL"

# ============================================================
# 9. JOURNALCTL ERRORS
# ============================================================
section "9. JOURNALCTL ERRORS"

JCTL_ERR=$(runcmd "journalctl -p err --since '5 minutes ago' --no-pager 2>&1 | tail -50")
if [ -n "$JCTL_ERR" ] && ! echo "$JCTL_ERR" | grep -q "No journal files"; then
    log "Recent journal errors:"
    log "$JCTL_ERR"
    ERR_COUNT=$(echo "$JCTL_ERR" | wc -l)
    if [ "$ERR_COUNT" -gt 5 ]; then
        fail "FAIL" "High error count in journal ($ERR_COUNT lines)"
    else
        skip "Minor errors in journal ($ERR_COUNT lines) — review manually"
    fi
else
    pass "PASS" "No journal errors in last 5 minutes"
fi

# ============================================================
# SUMMARY
# ============================================================
section "SUMMARY"
echo "Test completed: $(date -u)" | tee -a "$RESULTS"
echo "Results written to: $RESULTS" | tee -a "$RESULTS"

# Count pass/fail/skip
PASS_COUNT=$(grep -c '\[PASS\]' "$RESULTS" 2>/dev/null || echo 0)
FAIL_COUNT=$(grep -c '\[FAIL\]' "$RESULTS" 2>/dev/null || echo 0)
SKIP_COUNT=$(grep -c '\[SKIP\]' "$RESULTS" 2>/dev/null || echo 0)
echo "PASS: $PASS_COUNT | FAIL: $FAIL_COUNT | SKIP: $SKIP_COUNT" | tee -a "$RESULTS"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "OVERALL: FAIL ($FAIL_COUNT failures)" | tee -a "$RESULTS"
    exit 1
else
    echo "OVERALL: PASS" | tee -a "$RESULTS"
    exit 0
fi
