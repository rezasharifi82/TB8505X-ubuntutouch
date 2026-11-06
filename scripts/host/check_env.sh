#!/usr/bin/env bash
# ==============================================================================
# Script: check_env.sh
# Purpose: Inspect host development environment, verify hardware resources,
#          toolchains, and Android/Halium porting prerequisites.
# Target Host: Ubuntu 26.04 LTS (or compatible modern Linux)
# ==============================================================================

set -euo pipefail

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

log_info()  { echo -e "${CYAN}[INFO]${RESET} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${RESET} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${RESET} $*"; }
log_err()   { echo -e "${RED}[ERROR]${RESET} $*"; }
log_title() { echo -e "\n${BOLD}=== $* ===${RESET}"; }

log_title "Checking Host Environment for Lenovo TB-8505X Ubuntu Touch Port"

# 1. OS & Kernel Check
log_title "1. Operating System & Kernel"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log_ok "OS: $NAME $VERSION"
    log_info "Codename: ${VERSION_CODENAME:-unknown}"
else
    log_warn "Could not read /etc/os-release"
fi
KERNEL_VER=$(uname -r)
ARCH=$(uname -m)
log_ok "Host Kernel: $KERNEL_VER ($ARCH)"

if [ "$ARCH" != "x86_64" ]; then
    log_warn "Host architecture is $ARCH. x86_64 is recommended for Android cross-compilers."
fi

# 2. Hardware Resources (RAM & Disk)
log_title "2. Hardware Resources"
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
AVAIL_RAM_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(awk "BEGIN {printf \"%.1f\", $TOTAL_RAM_KB/1048576}")
AVAIL_RAM_GB=$(awk "BEGIN {printf \"%.1f\", $AVAIL_RAM_KB/1048576}")

log_info "Total RAM: ${TOTAL_RAM_GB} GiB (Available: ${AVAIL_RAM_GB} GiB)"
if (( $(awk "BEGIN {print ($TOTAL_RAM_KB < 8388608)}") )); then
    log_warn "Host has less than 8 GiB RAM. Android builds require swap or container memory limits."
else
    log_ok "RAM is sufficient for standalone kernel builds and adaptation packaging."
fi

FREE_DISK_KB=$(df -k . | awk 'NR==2 {print $4}')
FREE_DISK_GB=$(awk "BEGIN {printf \"%.1f\", $FREE_DISK_KB/1048576}")
log_info "Available Disk Space in workspace: ${FREE_DISK_GB} GiB"

if (( $(awk "BEGIN {print ($FREE_DISK_KB < 20971520)}") )); then
    log_warn "Less than 20 GiB disk available. Standalone kernel + rootfs requires ~15 GiB."
elif (( $(awk "BEGIN {print ($FREE_DISK_KB < 157286400)}") )); then
    log_ok "Disk space is ample for Standalone Kernel & Halium Adaptation (~15-30 GiB)."
    log_info "Note: Full AOSP 10 tree synchronization requires >150-250 GiB."
else
    log_ok "Disk space is abundant (>150 GiB)."
fi

# 3. Development Tools Verification
log_title "3. Development Tools & Toolchain Checks"

check_tool() {
    local cmd="$1"
    local desc="$2"
    local required="$3"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        local ver
        ver=$("$cmd" --version 2>&1 | head -n 1 || echo "installed")
        log_ok "$desc ($cmd): $ver"
        return 0
    else
        if [ "$required" = "true" ]; then
            log_err "$desc ($cmd) is NOT installed. (Required)"
            return 1
        else
            log_warn "$desc ($cmd) is NOT installed. (Optional/Recommended)"
            return 0
        fi
    fi
}

MISSING=0
check_tool "git" "Git Version Control" "true" || MISSING=$((MISSING+1))
check_tool "python3" "Python 3 Interpreter" "true" || MISSING=$((MISSING+1))
check_tool "gcc" "GNU C Compiler" "true" || MISSING=$((MISSING+1))
check_tool "make" "GNU Make" "true" || MISSING=$((MISSING+1))
check_tool "adb" "Android Debug Bridge" "true" || MISSING=$((MISSING+1))
check_tool "fastboot" "Android Fastboot" "true" || MISSING=$((MISSING+1))
check_tool "docker" "Docker Container Engine" "false" || true
check_tool "java" "Java Runtime / OpenJDK" "false" || true
check_tool "curl" "cURL Transfer Tool" "true" || MISSING=$((MISSING+1))
check_tool "aria2c" "Aria2 Download Utility" "false" || true

# 4. Host Compatibility Assessment for Android 10 / Halium 10
log_title "4. Android 10 Toolchain Compatibility Warning"
if command -v python3 >/dev/null 2>&1; then
    PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    log_info "Host Python version: $PY_VER"
    # Python 3.12+ deprecated distutils and imp modules used heavily in AOSP 10 build scripts
    if (( $(echo "$PY_VER >= 3.12" | bc -l 2>/dev/null || echo 1) )); then
        log_warn "Host Python ($PY_VER) is newer than Python 3.8. Legacy AOSP 10 build scripts will fail natively."
        log_info "Resolution: Use Standalone Kernel workflow with prebuilt Clang OR Docker container (Ubuntu 18.04/20.04)."
    fi
fi

if command -v gcc >/dev/null 2>&1; then
    GCC_VER=$(gcc -dumpfullversion -dumpversion || gcc -dumpversion)
    log_info "Host GCC version: $GCC_VER"
    GCC_MAJOR=$(echo "$GCC_VER" | cut -d. -f1)
    if [ "$GCC_MAJOR" -gt 10 ]; then
        log_warn "Host GCC ($GCC_VER) is too modern for direct compilation of Android 4.9 kernel."
        log_info "Resolution: Kernel compilation MUST use Google Android prebuilt Clang/GCC (aarch64-linux-android-4.9)."
    fi
fi

# 5. Connected Devices Check (Read-Only)
log_title "5. Tablet Connectivity Check (Non-destructive)"
if command -v fastboot >/dev/null 2>&1; then
    FB_DEVS=$(fastboot devices || true)
    if [ -n "$FB_DEVS" ]; then
        log_ok "Fastboot device detected! (Tablet is in bootloader/fastboot mode)"
    else
        log_info "No device in Fastboot mode detected."
    fi
fi

if command -v adb >/dev/null 2>&1; then
    ADB_DEVS=$(adb devices | grep -v "List of devices attached" | grep -v "^$" || true)
    if [ -n "$ADB_DEVS" ]; then
        log_ok "ADB device detected: $(echo "$ADB_DEVS" | wc -l) device(s) connected."
    else
        log_info "No active ADB device detected (expected if tablet is in Fastboot mode)."
    fi
fi

log_title "Summary"
if [ "$MISSING" -eq 0 ]; then
    log_ok "Host environment check completed successfully! Ready for porting workflows."
    exit 0
else
    log_err "Missing $MISSING required host packages. Please install them before proceeding."
    exit 1
fi
