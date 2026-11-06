# Standalone Kernel Validation Report: Lenovo TB-8505X

**Kernel Version:** Linux 4.9.190+  
**Target Board:** `akita_row_call` (Lenovo Tab M8 HD LTE / TB-8505X)  
**Compiler:** Google Android NDK Clang 9.0.3 (`r353983c`) with `aarch64-linux-android-4.9` binutils  
**Defconfig:** `akita_row_call_defconfig`  
**Automated Test Tool:** [`scripts/validate_kernel.sh`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/scripts/validate_kernel.sh)

---

## 1. Monolithic Kernel vs Vendor Module Architecture

The built kernel is strictly **monolithic** (`grep "=m" .config` returns **0**).

### Technical Justification for Zero Modules with Stock Android 10 Vendor:
1. **Stock Vendor Module Inspection:** In factory stock Android 10 (`TB-8505X_S301129_230914_BMP`), MediaTek compiles core drivers (display, touch, GPU, Wi-Fi, PMIC, audio, and modem CCCI) directly into `boot.img`. The `/vendor/lib/modules` directory in stock firmware contains no critical hardware drivers required for basic boot, display, touch, or storage.
2. **UBports System Stability:** In Ubuntu Touch Halium ports, dynamic module loading during early userspace frequently fails due to module-version mismatches (vermagic) and missing module dependencies in the minimal Android LXC container. Compiling all drivers built-in (`=y`) guarantees immediate hardware availability when the kernel boots, eliminating race conditions before systemd and the container start.
3. **Marker File:** In [`device_akita_row_call.tar.xz`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/out/device_akita_row_call.tar.xz), the marker `/opt/halium-overlay/lib/modules/.halium-override-dir` instructs the Halium container not to search for loose modules, preventing init loop errors.

---

## 2. Kernel Patch Audit

Three patches were authored and applied cleanly to the base commit `07692302d5db321648a8036ed751f9224e45b9ff`:

| Patch File | SHA-256 Checksum | Purpose / Fix Description |
| :--- | :--- | :--- |
| [`0001-enable-apparmor-defconfig.patch`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/patches/kernel/0001-enable-apparmor-defconfig.patch) | `af866bfb89539374857250e6401b822bb667514501d0c9030536f9710e53ec6b` | Enables AppArmor LSM, Namespaces, Cgroups, DEVTMPFS, and OverlayFS in `akita_row_call_defconfig`. |
| [`0002-fix-apparmor-clang-parentheses-equality.patch`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/patches/kernel/0002-fix-apparmor-clang-parentheses-equality.patch) | `ca3882240da59b2491661048ecc14d6d7043f80a703b5d11a5488dc4067697e3` | Fixes Clang 9 `-Wparentheses-equality` compiler error in `security/apparmor/domain.c:110`. |
| [`0003-fix-apparmor-crypto-vla-in-struct-for-clang.patch`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/patches/kernel/0003-fix-apparmor-crypto-vla-in-struct-for-clang.patch) | `43d16e87d1c54706d840b564e9bcc75bb778c9ad1d3b1572daf3ca4d5cb5b68b` | Eliminates Variable-Length Array in Structure (VLAIS) in `security/apparmor/crypto.c:37` using `SHASH_DESC_ON_STACK`. |

---

## 3. Subsystem Kconfig Verification

```text
[OK] CONFIG_SECURITY_APPARMOR=y
[OK] CONFIG_DEFAULT_SECURITY_APPARMOR=y
[OK] CONFIG_NAMESPACES=y
[OK] CONFIG_USER_NS=y
[OK] CONFIG_PID_NS=y
[OK] CONFIG_NET_NS=y
[OK] CONFIG_CGROUPS=y
[OK] CONFIG_DEVTMPFS=y
[OK] CONFIG_DEVTMPFS_MOUNT=y
[OK] CONFIG_ANDROID_BINDER_IPC=y
[OK] CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder,anbox-binder,anbox-hwbinder,anbox-vndbinder"
[OK] CONFIG_MTK_GPU_SUPPORT=y
[OK] CONFIG_TOUCHSCREEN_MTK_FOCALTECH_TS=y
[OK] CONFIG_MTK_PMIC_CHIP_MT6357=y
```

---

## 4. PowerVR Rogue GE8300 Graphics Driver Architecture

- **Kernel Driver:** PowerVR DDK 1.9 (`rgx clark m1.9ED4971894`) built directly into the kernel. Exposes `/dev/pvrsrvkm` and `/dev/pvr_sync`.
- **Userspace Interface:** MediaTek proprietary user DDK binaries reside in `/vendor/lib64/egl/` and `/vendor/lib64/hw/gralloc.mt6761.so`.
- **Ubuntu Touch Hybris Translation:** `libhybris` wraps the 64-bit Android EGL/GLES drivers and surfaces standard Wayland / Mir buffers to Lomiri, avoiding the need for reverse-engineered open-source PowerVR drivers.
