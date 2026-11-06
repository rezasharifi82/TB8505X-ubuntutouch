# Standalone Kernel Build Guide — Lenovo TB-8505X

**Target Architecture:** ARM64 (`aarch64`)  
**Target Board:** `akita_row_call` (Lenovo Tab M8 HD LTE)  
**Target SoC:** MediaTek Helio A22 (MT6761 / MT8766B)  
**Baseline Kernel:** Linux 4.9.117 / 4.9.190+ downstream MediaTek BSP  

---

## 1. Toolchain Isolation & Hermetic Environment

To compile Linux 4.9 without depending on modern host compilers (which fail due to C23 language incompatibilities in GCC 15 and Python 3.14 deprecations), this project strictly isolates the toolchains using Google Android prebuilts:

| Toolchain Component | Exact Version / Identifier | Google Source Branch | Role |
|---|---|---|---|
| **Android Clang** | `clang-r353983c` (Clang 9.0.3) | `android10-gsi` | Primary C compiler (`CC=clang`) |
| **GNU Cross-Compiler (64-bit)** | `aarch64-linux-android-4.9` | `pie-gsi` | Binutils (as, ld, objcopy, strip) |
| **GNU Cross-Compiler (32-bit)** | `arm-linux-androideabi-4.9` | `pie-gsi` | ARM32 compat vDSO & crypto routines |

---

## 2. Kernel Source & Branch Configuration

- **Remote Repository:** `https://github.com/who53/kernel-lenovo-akita.git`
- **Active Branch:** `main` (commit `07692302d` / features DRM CRTC vblank, binder optimizations, and membrane driver)
- **Defconfig File:** `arch/arm64/configs/akita_row_call_defconfig`
- **Output Target:** `arch/arm64/boot/Image.gz-dtb`

---

## 3. Ubuntu Touch Configuration Prerequisites

The following options are strictly mandatory and enabled via [`patches/kernel/0001-enable-apparmor-defconfig.patch`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/patches/kernel/0001-enable-apparmor-defconfig.patch):

```ini
# Container & Process Namespaces
CONFIG_NAMESPACES=y
CONFIG_USER_NS=y
CONFIG_PID_NS=y
CONFIG_NET_NS=y
CONFIG_IPC_NS=y
CONFIG_UTS_NS=y

# Early Devtmpfs & Console
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_VT=y
CONFIG_VT_CONSOLE=y

# AppArmor Security Module
CONFIG_SECURITY=y
CONFIG_SECURITY_NETWORK=y
CONFIG_SECURITY_APPARMOR=y
CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE=1
CONFIG_SECURITY_APPARMOR_HASH=y
CONFIG_SECURITY_APPARMOR_HASH_DEFAULT=y
CONFIG_DEFAULT_SECURITY_APPARMOR=y
CONFIG_AUDIT=y
CONFIG_AUDITSYSCALL=y

# Android Binder IPC Nodes
CONFIG_ANDROID_BINDER_IPC=y
CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder,anbox-binder,anbox-hwbinder,anbox-vndbinder"

# Display & Synchronization
CONFIG_SW_SYNC=y
CONFIG_SW_SYNC_USER=y
CONFIG_SYNC_FILE=y
```

---

## 4. Build Execution Procedure

### Method A: Automated UBports Build Wrapper (Recommended)
From the repository root:

```bash
# 1. Fetch toolchains and kernel sources
./build.sh -c

# 2. Compile kernel and package boot image only
./build.sh -k

# 3. Or build complete adaptation package
./build.sh
```

### Method B: Manual Standalone Compilation
If compiling manually in an interactive environment:

```bash
export ARCH=arm64
export SUBARCH=arm64
export CLANG_PATH="$(pwd)/workdir/downloads/linux-x86/clang-r353983c"
export GCC64_PATH="$(pwd)/workdir/downloads/aarch64-linux-android-4.9"
export GCC32_PATH="$(pwd)/workdir/downloads/arm-linux-androideabi-4.9"

export PATH="$CLANG_PATH/bin:$GCC64_PATH/bin:$GCC32_PATH/bin:$PATH"

export CC=clang
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-android-
export CROSS_COMPILE_ARM32=arm-linux-androideabi-

cd workdir/downloads/kernel-lenovo-akita
mkdir -p out

# 1. Apply Defconfig
make O=out akita_row_call_defconfig

# 2. Compile Monolithic Kernel & DTB
make O=out -j$(nproc)
```

---

## 5. Artifact Verification & Inspection

Upon completion, verify the following artifacts:

| Artifact | Expected Location | Expected Characteristics |
|---|---|---|
| `Image.gz-dtb` | `out/arch/arm64/boot/Image.gz-dtb` | Size: ~10 - 15 MiB; Valid gzip header concatenated with DTB |
| `akita_row_call.dtb` | `out/arch/arm64/boot/dts/mediatek/akita_row_call.dtb` | Size: ~90 - 110 KiB; DTB magic `0xd00dfeed` |
| `boot.img` | `workdir/tmp/partitions/boot.img` | Size: Exactly 32 MiB; Header v2; Base `0x40000000` |
