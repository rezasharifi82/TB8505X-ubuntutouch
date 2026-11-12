#!/usr/bin/env bash
# ==============================================================================
# Script: deploy_ubuntu_touch.sh
# Purpose: Deploys Ubuntu Touch 24.04 (Noble) onto Lenovo Tab M8 HD LTE (TB-8505X)
#          Fully audited with strict hardware guards, partition identity validation,
#          archive integrity checks, and error trapping.
# Target: Lenovo Tab M8 HD LTE (TB-8505X / akita_row_call)
# SAFETY: DO NOT EXECUTE WITHOUT EXPLICIT USER AUTHORIZATION.
# ==============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OTA_DIR="$HERE/out/ota_24_04"
DEVICE_OVERLAY="$HERE/out/device_akita_row_call_usrmerge.tar.xz"
EXPECTED_SYSTEM_DEV="/dev/block/mmcblk0p37"
EXPECTED_SYSTEM_BYTES=4085252096
EXPECTED_PRODUCT="akita_row_call"
TARGET_MOUNT="/target"

if [ ! -f "$DEVICE_OVERLAY" ]; then
    DEVICE_OVERLAY="$HERE/out/device_akita_row_call.tar.xz"
fi

echo "================================================================================"
echo " Ubuntu Touch 24.04 Production Deployment Suite"
echo " Target Device: Lenovo Tab M8 HD LTE (TB-8505X / akita_row_call)"
echo " Guarded Block Target: $EXPECTED_SYSTEM_DEV ($EXPECTED_SYSTEM_BYTES bytes)"
echo "================================================================================"

# ------------------------------------------------------------------------------
# 1. Host Archive & Integrity Validation
# ------------------------------------------------------------------------------
echo "[1/6] Auditing local host deployment artifacts..."

if [ ! -d "$OTA_DIR" ] || [ ! -f "$OTA_DIR/rootfs.tar.xz" ] || [ ! -f "$OTA_DIR/halium_halium_arm64.tar.xz" ]; then
    echo "[FATAL] Required OTA artifacts missing in $OTA_DIR!"
    echo "        Run ./scripts/prepare_ubuntu_touch_24_04_ota.sh first."
    exit 1
fi

if [ ! -f "$DEVICE_OVERLAY" ]; then
    echo "[FATAL] Device overlay tarball missing: $DEVICE_OVERLAY"
    exit 1
fi

echo "[+] Verifying local archive integrity via tar test..."
tar -tf "$OTA_DIR/rootfs.tar.xz" >/dev/null || { echo "[FATAL] rootfs.tar.xz is corrupted!"; exit 1; }
tar -tf "$OTA_DIR/halium_halium_arm64.tar.xz" >/dev/null || { echo "[FATAL] halium_halium_arm64.tar.xz is corrupted!"; exit 1; }
tar -tf "$DEVICE_OVERLAY" >/dev/null || { echo "[FATAL] Device overlay tarball is corrupted!"; exit 1; }
echo "[OK] Local archive integrity confirmed."

# ------------------------------------------------------------------------------
# 2. Recovery Connection & Hardware Identity Verification
# ------------------------------------------------------------------------------
echo ""
echo "[2/6] Verifying recovery environment and device hardware identity..."

echo "[*] Waiting for device to enter recovery mode (adb wait-for-recovery)..."
adb wait-for-recovery

DEVICE_STATE=$(adb get-state 2>/dev/null || echo "offline")
if [ "$DEVICE_STATE" != "recovery" ]; then
    echo "[FATAL] Device is not in recovery mode (current state: '$DEVICE_STATE')."
    echo "        Expected: adb devices reports '<serial> recovery'"
    echo "        To boot recovery from Fastboot: fastboot reboot recovery"
    exit 1
fi

# Query hardware properties from recovery
DEV_PRODUCT=$(adb shell getprop ro.product.device 2>/dev/null | tr -d '\r\n' || echo "")
DEV_BOARD=$(adb shell getprop ro.build.product 2>/dev/null | tr -d '\r\n' || echo "")
DEV_SERIAL=$(adb shell getprop ro.serialno 2>/dev/null | tr -d '\r\n' || echo "")

echo "[*] Connected Device Identity:"
echo "    - ro.product.device: '$DEV_PRODUCT'"
echo "    - ro.build.product:  '$DEV_BOARD'"
echo "    - ro.serialno:       '$DEV_SERIAL'"

if [ "$DEV_PRODUCT" != "$EXPECTED_PRODUCT" ] && [ "$DEV_BOARD" != "$EXPECTED_PRODUCT" ]; then
    echo "[FATAL] Hardware mismatch! Expected '$EXPECTED_PRODUCT', detected '$DEV_PRODUCT' / '$DEV_BOARD'."
    echo "        Aborting to protect against flashing wrong physical hardware."
    exit 1
fi
echo "[OK] Hardware identity verified: akita_row_call confirmed."

# ------------------------------------------------------------------------------
# 3. Block Device Resolution & Capacity Verification
# ------------------------------------------------------------------------------
echo ""
echo "[3/6] Verifying physical partition block devices..."

# Resolve /dev/block/by-name/system
RESOLVED_SYSTEM=$(adb shell "readlink -f /dev/block/by-name/system" | tr -d '\r\n')
echo "[*] Target /dev/block/by-name/system resolves to: '$RESOLVED_SYSTEM'"

if [ "$RESOLVED_SYSTEM" != "$EXPECTED_SYSTEM_DEV" ]; then
    echo "[FATAL] Target block device mismatch!"
    echo "        Expected '$EXPECTED_SYSTEM_DEV', but by-name points to '$RESOLVED_SYSTEM'."
    echo "        Aborting to protect adjacent partitions."
    exit 1
fi

# Check block device size
BLOCK_SIZE_BYTES=$(adb shell "blockdev --getsize64 $RESOLVED_SYSTEM" | tr -d '\r\n' || echo "0")
echo "[*] Target partition physical capacity: $BLOCK_SIZE_BYTES bytes"

if [ "$BLOCK_SIZE_BYTES" -ne "$EXPECTED_SYSTEM_BYTES" ]; then
    echo "[FATAL] Partition size mismatch! Expected $EXPECTED_SYSTEM_BYTES bytes, got $BLOCK_SIZE_BYTES bytes."
    exit 1
fi
echo "[OK] Block device path and capacity verified with 100% precision."

# ------------------------------------------------------------------------------
# 4. Partition Formatting & Mount Preparation
# ------------------------------------------------------------------------------
echo ""
echo "[4/6] Formatting and preparing filesystem on $RESOLVED_SYSTEM..."

# Ensure target is unmounted first
adb shell "umount /cache/system 2>/dev/null || true"
adb shell "umount $RESOLVED_SYSTEM 2>/dev/null || true"

# Format ext4 with disabled metadata checksum (ensures compatibility with legacy e2fsck and Linux 4.9)
echo "[*] Formatting ext4 filesystem..."
adb shell "mke2fs -t ext4 -F -O ^metadata_csum -b 4096 $RESOLVED_SYSTEM"

# Mount target to official UBports recovery location /cache/system
# (Archives contain 'system/...', extracting from /cache places payload directly at /cache/system/ root)
SYSTEM_MOUNT="/cache/system"
echo "[*] Mounting $RESOLVED_SYSTEM to $SYSTEM_MOUNT..."
adb shell "mkdir -p $SYSTEM_MOUNT"
adb shell "mount -t ext4 -o rw,noatime $RESOLVED_SYSTEM $SYSTEM_MOUNT"

# Verify mount
MOUNT_CHECK=$(adb shell "mountpoint -q $SYSTEM_MOUNT && echo MOUNTED || echo NOT_MOUNTED" | tr -d '\r\n')
if [ "$MOUNT_CHECK" != "MOUNTED" ]; then
    echo "[FATAL] Failed to mount $RESOLVED_SYSTEM at $SYSTEM_MOUNT!"
    exit 1
fi
echo "[OK] Target partition successfully formatted and mounted at $SYSTEM_MOUNT."

# ------------------------------------------------------------------------------
# 5. Native Fast-Stream Extraction via Host Decompression and Device bsdtar
# ------------------------------------------------------------------------------
echo ""
echo "[5/6] Streaming and extracting OS payloads..."

# 5.1 Extract Rootfs (Host xz decompression piped to native bsdtar)
echo "[*] Extracting Ubuntu Touch 24.04 (Noble) rootfs..."
if ! xz -dc "$OTA_DIR/rootfs.tar.xz" | adb shell "cd /cache && bsdtar --numeric-owner -Ppxf -"; then
    echo "[FATAL] Rootfs extraction failed or was interrupted!"
    adb shell "umount $SYSTEM_MOUNT 2>/dev/null || true"
    exit 1
fi

# 5.2 Extract Halium GSI Container
echo "[*] Extracting Halium 10 Generic Container..."
if ! xz -dc "$OTA_DIR/halium_halium_arm64.tar.xz" | adb shell "cd /cache && bsdtar --numeric-owner -Ppxf -"; then
    echo "[FATAL] Halium GSI extraction failed or was interrupted!"
    adb shell "umount $SYSTEM_MOUNT 2>/dev/null || true"
    exit 1
fi

# 5.3 Extract Device Adaptation Overlay
echo "[*] Extracting device adaptation overlay..."
if ! xz -dc "$DEVICE_OVERLAY" | adb shell "cd /cache && bsdtar --numeric-owner -Ppxf -"; then
    echo "[FATAL] Device overlay extraction failed or was interrupted!"
    adb shell "umount $SYSTEM_MOUNT 2>/dev/null || true"
    exit 1
fi

# Clean up any temporary /cache/partitions created by device overlay
adb shell "rm -rf /cache/partitions"

# 5.4 Align LXC Android Container Image Name
adb shell "if [ -e $SYSTEM_MOUNT/var/lib/lxc/android/system.img ]; then mv -f $SYSTEM_MOUNT/var/lib/lxc/android/system.img $SYSTEM_MOUNT/var/lib/lxc/android/android-rootfs.img; fi"

# 5.5 Inject Display Wake & Headless Access Drop-ins
echo ""
echo "[*] Injecting display wake on boot service..."
adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/systemd/system/display-wake-on-boot.service
[Unit]
Description=Early Display Wake for MTK FB
After=graphical.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'sleep 3; echo 4 > /sys/class/graphics/fb0/blank; sleep 1; echo 0 > /sys/class/graphics/fb0/blank; echo 150 > /sys/class/leds/lcd-backlight/brightness; echo esd_recovery > /sys/kernel/debug/mtkfb 2>/dev/null || true'
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF"

adb shell "mkdir -p $SYSTEM_MOUNT/etc/systemd/system/multi-user.target.wants"
adb shell "ln -sf /etc/systemd/system/display-wake-on-boot.service $SYSTEM_MOUNT/etc/systemd/system/multi-user.target.wants/display-wake-on-boot.service"
adb shell "ln -sf /lib/systemd/system/adbd.service $SYSTEM_MOUNT/etc/systemd/system/multi-user.target.wants/adbd.service"

echo "[*] Configuring usb-moded to default to mtp_adb..."
adb shell "mkdir -p $SYSTEM_MOUNT/etc/usb-moded"
adb shell "echo -e '[usbmode]\nmode=mtp_adb\n' > $SYSTEM_MOUNT/etc/usb-moded/90-device-specific-config.ini"
adb shell "if [ -f $SYSTEM_MOUNT/etc/usb-moded/10-ubports-defaults.ini ]; then sed -i 's/mode=mtp/mode=mtp_adb/g' $SYSTEM_MOUNT/etc/usb-moded/10-ubports-defaults.ini; fi"

echo "[*] Permitting PAM adbd session..."
adb shell "cat << 'EOF' > $SYSTEM_MOUNT/etc/pam.d/adbd-pam-session
#%PAM-1.0
auth sufficient pam_permit.so
account sufficient pam_permit.so
session sufficient pam_permit.so
EOF"

echo "[*] Configuring root SSH access..."
adb shell "mkdir -p $SYSTEM_MOUNT/root/.ssh && chmod 700 $SYSTEM_MOUNT/root/.ssh"
if [ -f "$OTA_DIR/ssh_debug_key.pub" ]; then
    cat "$OTA_DIR/ssh_debug_key.pub" | adb shell "cat > $SYSTEM_MOUNT/root/.ssh/authorized_keys"
    adb shell "chmod 600 $SYSTEM_MOUNT/root/.ssh/authorized_keys"
fi
adb shell "echo -e '\nPermitRootLogin yes\nStrictModes no\n' >> $SYSTEM_MOUNT/etc/ssh/sshd_config"

# ------------------------------------------------------------------------------
# 6. Post-Extraction Verification & Unmount
# ------------------------------------------------------------------------------
echo ""
echo "[6/6] Executing post-extraction filesystem verification..."

REQUIRED_FILES=(
    "$SYSTEM_MOUNT/init"
    "$SYSTEM_MOUNT/usr/lib/systemd/systemd"
    "$SYSTEM_MOUNT/var/lib/lxc/android/android-rootfs.img"
    "$SYSTEM_MOUNT/opt/halium-overlay/usr/lib/udev/rules.d/70-akita.rules"
    "$SYSTEM_MOUNT/usr/lib/systemd/system/ssh.service"
    "$SYSTEM_MOUNT/etc/systemd/system/multi-user.target.wants/ssh.service"
)

ALL_PRESENT=true
for rf in "${REQUIRED_FILES[@]}"; do
    EXISTS=$(adb shell "[ -f $rf -o -L $rf ] && echo YES || echo NO" | tr -d '\r\n')
    if [ "$EXISTS" = "YES" ]; then
        echo "  [OK] Found: $rf"
    else
        echo "  [FAIL] Missing: $rf"
        ALL_PRESENT=false
    fi
done

if [ "$ALL_PRESENT" != "true" ]; then
    echo "[FATAL] Critical system files missing after extraction! System partition is inconsistent."
    adb shell "umount $SYSTEM_MOUNT 2>/dev/null || true"
    exit 1
fi

# Sync and unmount
echo "[*] Syncing filesystem buffers..."
adb shell "sync"
echo "[*] Unmounting $SYSTEM_MOUNT..."
adb shell "umount $SYSTEM_MOUNT"

echo ""
echo "================================================================================"
echo " [SUCCESS] Ubuntu Touch 24.04 Deployment to /system Completed Successfully!"
echo " Target partition mmcblk0p37 is clean, verified, and unmounted."
echo ""
echo " Next Steps to boot Ubuntu Touch:"
echo " 1. Reboot back to Fastboot:  adb reboot bootloader"
echo " 2. Flash Halium boot kernel: fastboot flash boot out/boot.img"
echo " 3. Reboot into Ubuntu Touch: fastboot reboot"
echo "================================================================================"
