# Kernel Source Information

This directory documents the Linux kernel source requirements and configurations for Lenovo TB-8505X:

- **Target Kernel:** Linux 4.9.117 / 4.9.190+ (ARM64)
- **Defconfig:** `akita_row_call_defconfig` (with Ubuntu Touch / AppArmor enhancements)
- **Toolchain:** Google Android Clang (e.g. clang-r353983c / clang-6.0) + GCC 4.9 cross-compiler (`aarch64-linux-android-4.9`).
- **Target Output:** `Image.gz-dtb`
- **Primary Source Repositories:**
  - `https://github.com/who53/kernel-lenovo-akita.git`
  - `https://github.com/CoderCharmander/tb8505f-kernel.git`
  - Lenovo Open Source Code portal releases for Tab M8.
