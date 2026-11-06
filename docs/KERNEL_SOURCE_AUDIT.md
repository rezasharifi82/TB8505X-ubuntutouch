# Kernel Source Audit & Configuration Analysis — Lenovo TB-8505X

This document provides a line-by-line audit of the candidate Linux kernel sources against the factory kernel extracted directly from the physical tablet's firmware.

---

## 1. Candidate Kernel Sources Comparison

| Repository | Source Origin | Version | Target Defconfig | Status / Evaluation |
|---|---|---|---|---|
| **Stock Binary Extracted** ⭐ | Factory `boot.img` on device | **4.9.190+** | Extracted `.config` (3,883 active options) | **Authoritative baseline.** Proves factory options and monolithic driver structure. |
| **`who53/kernel-lenovo-akita`** ⭐ | Community adaptation for akita | **4.9.117** | `akita_row_call_defconfig` (557 options) | **Primary candidate.** Contains necessary Linux namespaces, VT, devtmpfs, and PowerVR integration. |
| **`CoderCharmander/tb8505f-kernel`** | Official Lenovo Open Source mirror | **4.9.117** | `akita_row_wifi_defconfig` | Clean GPL reference. Proves untouched OEM baseline. |
| **`ubports/kernel-lenovo-amar`** | UBports community port (TB-X306) | **4.9.117** | `amar_row_lte_ubuntu_defconfig` | Reference for UBports AppArmor 3 backport and race fixes on MediaTek 4.9. |

---

## 2. Factory Stock Kernel `.config` Audit

Extracted directly from decompressed binary memory via `IKCONFIG` (preserved in [`kernel/stock_kernel.config`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/kernel/stock_kernel.config)):

### Compiler Banner
```text
Linux version 4.9.190+ (nobody@android-build) 
(Android (5484270 based on r353983c) clang version 9.0.3 
(https://android.googlesource.com/toolchain/clang 745b335211bb9eadfa6aa6301f84715cee4b37c5) 
(https://android.googlesource.com/toolchain/llvm 60cf23e54e46c807513f7a36d0a7b777920b5881) 
(based on LLVM 9.0.3svn)) #1 SMP PREEMPT Thu Sep 14 13:49:10 CST 2023
```
- **Toolchain Proven:** Built using Google's **`clang-r353983c`** (Android 10 GSI branch).

### Monolithic Driver Structure (Zero Loadable Modules)
- `CONFIG_MODULES=y` is set, but **zero drivers are built as loadable modules (`=m`)**.
- PowerVR GPU, MT6631 Wi-Fi, MT6357 Audio, and Touch drivers are all compiled directly into the kernel binary (`Image.gz-dtb`).
- **Consequence:** Because there are no `.ko` files loaded from `/vendor`, the version discrepancy between 4.9.117 and 4.9.190 does **not** trigger symbol version mismatches (`vermagic`).

---

## 3. Stock Kernel vs. `who53` Defconfig Comparison

```text
Feature Subsystem            Stock Factory 4.9.190+    who53 akita_row_call    Ubuntu Touch Requirement
-------------------------    ----------------------    --------------------    ------------------------
CONFIG_NAMESPACES            is not set                y                       MANDATORY (LXC container)
CONFIG_USER_NS               is not set                y                       MANDATORY (Rootless LXC)
CONFIG_PID_NS                is not set                y                       MANDATORY (Process isolation)
CONFIG_NET_NS                is not set                y                       MANDATORY (Network isolation)
CONFIG_DEVTMPFS              is not set                y                       MANDATORY (Early /dev mount)
CONFIG_DEVTMPFS_MOUNT        is not set                y                       MANDATORY (systemd boot)
CONFIG_VT                    is not set                y                       MANDATORY (Virtual terminal)
CONFIG_VT_CONSOLE            is not set                y                       MANDATORY (Console output)
CONFIG_SECURITY_SELINUX      y                         is not set              OPTIONAL (Disabled for UT)
CONFIG_SECURITY_APPARMOR     is not set                is not set              MANDATORY (App confinement)
CONFIG_ANDROID_BINDER_IPC    y                         y                       MANDATORY (HAL communication)
CONFIG_ANDROID_BINDER_DEVICES "binder,hwbinder,vndbinder" "binder,hwbinder,vndbinder,anbox-binder..." MANDATORY
```

---

## 4. Required Kernel Modifications for Ubuntu Touch

To prepare `who53/kernel-lenovo-akita` for a successful Ubuntu Touch build, the following changes are required:

### A. Enable AppArmor in Defconfig
Add the following options to `arch/arm64/configs/akita_row_call_defconfig`:
```ini
CONFIG_SECURITY=y
CONFIG_SECURITY_APPARMOR=y
CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE=1
CONFIG_SECURITY_APPARMOR_HASH=y
CONFIG_SECURITY_APPARMOR_UNCONFINED_INIT=y
CONFIG_DEFAULT_SECURITY_APPARMOR=y
CONFIG_AUDIT=y
```

### B. Apply AppArmor Race Fix from `kernel-lenovo-amar`
MediaTek 4.9 kernels contain a race condition in early `securityfs` registration that causes kernel panic during inode deallocation:
- Commit: `apparmor: fix race between freeing data and fs accessing it`
- Upstream reference: `security/apparmor/apparmorfs.c` traversal locking fix.

### C. Verify Display Synchronization Fences
Ensure the following are enabled for smooth Mir/Wayland frame pacing:
```ini
CONFIG_SW_SYNC=y
CONFIG_SYNC_FILE=y
```
