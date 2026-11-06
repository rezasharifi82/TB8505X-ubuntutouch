#!/usr/bin/env bash
# ==============================================================================
# Build Script for Lenovo TB-8505X Ubuntu Touch Adaptation
# Wraps UBports halium-generic-adaptation-build-tools
# ==============================================================================

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# Ensure host environment passes basic sanity checks
if [ -f "$HERE/scripts/host/check_env.sh" ]; then
    bash "$HERE/scripts/host/check_env.sh"
fi

if [ ! -d "$HERE/build" ]; then
    echo "Cloning UBports halium-generic-adaptation-build-tools..."
    git clone https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools.git "$HERE/build"
fi

# If repositories are not yet cloned and not doing clone-only, ensure setup is completed
if [ "${1:-}" != "-c" ] && [ ! -d "$HERE/workdir/downloads/kernel-lenovo-akita" ]; then
    echo "Initial setup: fetching repositories and toolchains..."
    "$HERE/build/build.sh" -c
fi

# Apply kernel patches if applicable
if [ -d "$HERE/workdir/downloads/kernel-lenovo-akita" ] && [ -d "$HERE/patches/kernel" ]; then
    for patch in "$HERE"/patches/kernel/*.patch; do
        if [ -f "$patch" ]; then
            if (cd "$HERE/workdir/downloads/kernel-lenovo-akita" && git apply --check "$patch" &>/dev/null); then
                echo "Applying kernel patch: $(basename "$patch")..."
                (cd "$HERE/workdir/downloads/kernel-lenovo-akita" && git apply "$patch")
            fi
        fi
    done
fi

echo "Invoking UBports adaptation build pipeline..."
exec "$HERE/build/build.sh" "$@"
