#!/bin/bash
# flash_new_focal.sh - Flash Focal 20.04 on TB-8505X (akita_row_call)
# Usage: ./flash_new_focal.sh [-n]   (-n = dry run, print only)
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "-n" ] && DRY_RUN=1

OUT=/home/mreza/Desktop/TB8505X
BOOT_IMG="$OUT/lenovo-tab-m8/out/boot.img"
DTBO_IMG="$OUT/lenovo-tab-m8/out/dtbo.img"
SYS_IMG="$OUT/focal_build/out/system.img"
VBMETA_IMG="$OUT/focal_build/out/vbmeta.img"
MTK_DIR="$OUT/TB8505X-ubuntutouch/tools/mtkclient"
PRELOADER="$MTK_DIR/preloader_akita_row_call.bin"

PASS=0; FAIL=0
ok(){ echo "[PASS] $*"; PASS=$((PASS+1)); }
bad(){ echo "[FAIL] $*"; FAIL=$((FAIL+1)); }
info(){ echo "[INFO] $*"; }
run(){ if [ "$DRY_RUN" = "1" ]; then echo "[DRY-RUN] $*"; else info "exec: $*"; "$@"; fi; }

echo "=== flash_new_focal.sh  (dry-run=$DRY_RUN) ==="

# --- preconditions ---
for f in "$BOOT_IMG" "$DTBO_IMG" "$SYS_IMG" "$VBMETA_IMG" "$MTK_DIR/mtk.py" "$PRELOADER"; do
  if [ -f "$f" ]; then ok "found: $f"; else bad "MISSING: $f"; fi
done

# --- 1. reboot to fastboot ---
info "=== Step 1: reboot to fastboot ==="
run adb connect 10.15.19.82 || true
run adb forward tcp:2222 tcp:22 || true
run adb reboot bootloader || true

info "Waiting for fastboot device (up to 20s)..."
if [ "$DRY_RUN" = "0" ]; then
  for i in $(seq 1 20); do
    if fastboot devices | grep -q '[0-9a-f]\{4\}:[0-9a-f]\{4\}'; then
      ok "fastboot device detected"; break
    fi
    sleep 1
  done
  if ! fastboot devices | grep -q '[0-9a-f]\{4\}:[0-9a-f]\{4\}'; then
    bad "no fastboot device after 20s"; exit 1
  fi
else
  echo "[DRY-RUN] would poll fastboot devices"
fi

# --- 2. sanity check ---
info "=== Step 2: fastboot getvar all ==="
if [ "$DRY_RUN" = "0" ]; then
  FB_OUT=$(fastboot getvar all 2>&1) || { bad "fastboot getvar all failed"; echo "$FB_OUT"; exit 1; }
  echo "$FB_OUT"
  echo "$FB_OUT" | grep -q 'unlocked: yes' && ok "bootloader unlocked" || bad "bootloader NOT unlocked"
  echo "$FB_OUT" | grep -q 'product: akita_row_call' && ok "product=akita_row_call" || bad "product mismatch"
  echo "$FB_OUT" | grep -q 'partition-size:system: f3800000' && ok "system partition size OK" || warn "system partition size not f3800000"
else
  echo "[DRY-RUN] fastboot getvar all"
fi

# --- 3. flash boot ---
info "=== Step 3: flash boot ==="
run fastboot flash boot "$BOOT_IMG" || { bad "flash boot failed"; exit 1; }
ok "boot flashed"

# --- 4. flash dtbo ---
info "=== Step 4: flash dtbo ==="
run fastboot erase dtbo || true
run fastboot flash dtbo "$DTBO_IMG" || { bad "flash dtbo failed"; exit 1; }
ok "dtbo flashed"

# --- 5. flash system (fastboot first, mtkclient fallback) ---
info "=== Step 5: flash system ==="
if [ "$DRY_RUN" = "0" ]; then
  if fastboot flash system "$SYS_IMG" 2>&1; then
    ok "system flashed via fastboot"
  else
    info "fastboot system flash failed (>3GB?) — falling back to mtkclient"
    info "Entering BROM mode: power off tablet, hold VolUp+VolDown, plug USB"
    info "Host should see 0e8d:0003"
    read -r -p "Press Enter when BROM mode is detected (0e8d:0003)..." _
    cd "$MTK_DIR"
    python3 mtk.py --preloader "$PRELOADER" printgpt || { bad "mtkclient printgpt failed"; exit 1; }
    ok "mtkclient sees GPT"
    python3 mtk.py --preloader "$PRELOADER" w system "$SYS_IMG" || { bad "mtkclient write system failed"; exit 1; }
    ok "system written via mtkclient"
    cd - > /dev/null
  fi
else
  echo "[DRY-RUN] fastboot flash system $SYS_IMG  (or mtkclient fallback)"
fi

# --- 6. flash vbmeta ---
info "=== Step 6: flash vbmeta ==="
run fastboot flash vbmeta "$VBMETA_IMG" || { bad "flash vbmeta failed"; exit 1; }
ok "vbmeta flashed"

# --- 7. wipe userdata ---
info "=== Step 7: wipe userdata ==="
run fastboot -w || { bad "fastboot -w failed"; exit 1; }
run fastboot erase userdata || true
run fastboot format userdata || true
ok "userdata wiped"

# --- 8. reboot ---
info "=== Step 8: reboot ==="
run fastboot reboot || { bad "fastboot reboot failed"; exit 1; }
ok "reboot issued"

echo ""
echo "================ SUMMARY ================"
echo "PASS: $PASS   FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && { echo "ALL CHECKS PASSED"; exit 0; } || { echo "SOME CHECKS FAILED"; exit 1; }
