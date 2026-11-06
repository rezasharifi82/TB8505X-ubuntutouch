# Kernel and System Patches

This directory contains device-specific patches applied during the build process:

- `kernel/`:
  - AppArmor support backport and race condition fixes for Linux 4.9 MediaTek tree.
  - Namespace and cgroup configuration fixes.
  - DTB overlay adjustments for standalone Halium boot.
- `halium/`:
  - Android init scripts overrides (disabling Android keystore/keymaster daemons that block standalone boot).
  - PowerVR Rogue DDK workarounds if required.
