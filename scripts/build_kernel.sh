#!/usr/bin/env bash
# ==============================================================================
# Script: build_kernel.sh
# Purpose: Standalone reproducible kernel build wrapper for Lenovo TB-8505X
# Target: MediaTek MT6761 / MT8766B (akita_row_call)
# ==============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

echo "=== Building Monolithic Standalone Kernel for Lenovo TB-8505X ==="

if [ ! -d "$HERE/workdir/downloads/kernel-lenovo-akita" ]; then
    echo "Kernel source tree not found. Running initial setup..."
    ./build.sh -c
fi

# Verify patches are applied
if [ -d "$HERE/patches/kernel" ]; then
    echo "Verifying / applying kernel patches..."
    for patch in "$HERE"/patches/kernel/*.patch; do
        if [ -f "$patch" ]; then
            if (cd "$HERE/workdir/downloads/kernel-lenovo-akita" && git apply --check "$patch" &>/dev/null); then
                echo "Applying: $(basename "$patch")"
                (cd "$HERE/workdir/downloads/kernel-lenovo-akita" && git apply "$patch")
            else
                echo "Already applied or conflict: $(basename "$patch")"
            fi
        fi
    done
fi

# Invoke build with ONLY_KERNEL=true
export ONLY_KERNEL="true"
./build.sh

echo "Kernel build completed successfully. Boot image updated in workdir/tmp/partitions/boot.img"
