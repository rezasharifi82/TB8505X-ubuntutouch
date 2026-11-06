# Linux Kernel Analysis & Requirements — Lenovo TB-8505X

## 1. Stock Kernel Audit

The running stock kernel on the physical tablet reports:

```text
Linux localhost 4.9.190+ #1 SMP PREEMPT Thu Sep 14 13:49:10 CST 2023 aarch64
```

- **Kernel Version:** 4.9.190 LTS downstream
- **Architecture:** `arm64` (aarch64)
- **Compiler:** Android Clang version 9.0.3 / GCC 4.9
- **Build Date:** September 14, 2023

---

## 2. Identified Open Source Kernel Repositories

Three functional kernel trees were audited for viability:

| Repository URL | Branch | Base Version | Evaluation & Suitability |
|---|---|---|---|
| `https://github.com/who53/kernel-lenovo-akita.git` ⭐ | `droidian-a9` / `main` | 4.9.117 | **Primary Target:** Contains verified `akita_row_call_defconfig`, device tree overlays, PowerVR Rogue driver integration, and Linux-on-mobile adjustments. |
| `https://github.com/CoderCharmander/tb8505f-kernel.git` | `master` | 4.9.117 | Clean Lenovo open-source release tarball mirror for Tab M8 Wi-Fi (TB-8505F). Useful as a clean diff reference. |
| `https://gitlab.com/ubports/porting/community-ports/android11/lenovo-tab-m10-hd/kernel-lenovo-amar.git` | `halium-11` | 4.9.117 | Reference UBports tree for MediaTek Helio P22/A22 family. Contains the exact AppArmor race-condition fixes and UBports defconfig flags. |

---

## 3. Ubuntu Touch Kernel Configuration Audit (`check-kernel-config`)

For Ubuntu Touch (Lomiri) to boot and run applications securely, the kernel must satisfy specific subsystem requirements:

### A. General & Virtual Terminal
```ini
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y
CONFIG_SYSVIPC=y
CONFIG_IKCONFIG=y
CONFIG_IKCONFIG_PROC=y
```

### B. Namespaces & Control Groups (LXC Container Support)
```ini
CONFIG_NAMESPACES=y
CONFIG_UTS_NS=y
CONFIG_IPC_NS=y
CONFIG_USER_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_CGROUPS=y
CONFIG_CGROUP_FREEZER=y
CONFIG_CGROUP_DEVICE=y
CONFIG_CPUSETS=y
CONFIG_CGROUP_CPUACCT=y
CONFIG_MEMCG=y
CONFIG_MEMCG_SWAP=y
```

### C. Android Binder IPC
```ini
CONFIG_ANDROID=y
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder,anbox-binder,anbox-hwbinder,anbox-vndbinder"
CONFIG_ASHMEM=y
CONFIG_ION=y
```

### D. AppArmor LSM Security Confinement
```ini
CONFIG_SECURITY=y
CONFIG_SECURITY_APPARMOR=y
CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE=1
CONFIG_SECURITY_APPARMOR_HASH=y
CONFIG_SECURITY_APPARMOR_UNCONFINED_INIT=y
CONFIG_DEFAULT_SECURITY_APPARMOR=y
CONFIG_AUDIT=y
```
> **AppArmor Backport Note:** In Linux 4.9 downstream MediaTek trees, AppArmor requires backporting race-condition patches from upstream 4.14/4.19 (as documented in UBports `kernel-lenovo-amar`) to prevent crashes during LSM inode initialization.

---

## 4. Cross-Compilation Toolchain Requirements

Host GCC 15 (found on Ubuntu 26.04) strictly refuses to compile Linux 4.9 due to C23 syntax changes and legacy warning flags. 

The build pipeline must use Google's official Android prebuilt toolchains:
1. **Clang:** `clang-r353983c` (from Android 10 GSI branch) or Clang 6.0 / 9.0.
2. **GCC Companion:** `aarch64-linux-android-4.9` (for assembler, linker, and libgcc runtime).
3. **ARM32 Companion:** `arm-linux-androideabi-4.9` (for MediaTek 32-bit vDSO components).
