#!/usr/bin/env bash
# ==============================================================================
# Script: build_ubuntu_touch.sh
# Purpose: Top-level orchestration script for building the complete Ubuntu Touch
#          port for Lenovo Tab M8 HD LTE (TB-8505X / akita_row_call).
# ==============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

echo "=== Building Ubuntu Touch Adaptation for Lenovo TB-8505X ==="

# Step 1: Host check
if [ -f "$HERE/scripts/host/check_env.sh" ]; then
    bash "$HERE/scripts/host/check_env.sh"
fi

# Step 2: Build Kernel & Adaptation Tarball
./build.sh

# Step 3: Validate Kernel
bash "$HERE/scripts/validate_kernel.sh"

# Step 4: Validate Installation Package
bash "$HERE/scripts/validate_installation_package.sh"

echo "=== Build & Validation Pipeline Completed Successfully ==="
