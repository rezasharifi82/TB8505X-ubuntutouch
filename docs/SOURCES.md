# Source Register & External Repositories — Lenovo TB-8505X

This register documents all upstream repositories, references, toolchains, and firmware sources used in this project.

| Source Name | URL | Description / Relevance | Verification Status | Last Checked |
|---|---|---|---|---|
| **UBports Adaptation Build Tools** | `https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools.git` | Official build engine for compiling kernels and packaging device adaptations. | Verified active upstream. | 2026-11-05 |
| **UBports Lenovo M10 HD Port** | `https://gitlab.com/ubports/porting/community-ports/android11/lenovo-tab-m10-hd/lenovo-m10-hd.git` | Reference adaptation repository for MediaTek tablet (`amar_row_lte`/`wifi`). | Verified active upstream. | 2026-11-05 |
| **UBports Lenovo M10 Kernel** | `https://gitlab.com/ubports/porting/community-ports/android11/lenovo-tab-m10-hd/kernel-lenovo-amar.git` | MediaTek 4.9 kernel tree with UBports AppArmor race-condition patches. | Verified active upstream. | 2026-11-05 |
| **UBports Lenovo X606 Port** | `https://gitlab.com/ubports/porting/community-ports/android9/lenovo-tab-m10-fhd-plus/lenovo-x606.git` | Reference adaptation and build scripts for Lenovo tablet on Halium 9/10. | Verified active upstream. | 2026-11-05 |
| **Akita Kernel (who53)** | `https://github.com/who53/kernel-lenovo-akita.git` | Linux 4.9.117 downstream tree for TB-8505X with `akita_row_call_defconfig`. | Verified working remote. | 2026-11-05 |
| **Akita Droidian Adaptation** | `https://github.com/who53/droidian-lenovo-akita.git` | Hardware adaptation package, udev rules (`70-akita.rules`), audio fixes. | Verified working remote. | 2026-11-05 |
| **Akita Build Pipeline** | `https://github.com/who53/droidian-akita-build.git` | Image generation blueprints and community device definitions for akita. | Verified working remote. | 2026-11-05 |
| **TB-8505F Kernel Mirror** | `https://github.com/CoderCharmander/tb8505f-kernel.git` | Official Lenovo open source kernel code mirror for Tab M8 Wi-Fi. | Verified working remote. | 2026-11-05 |
| **TWRP Akita Device Tree** | `https://github.com/HemanthJabalpuri/twrp_Lenovo_TB8505F.git` | TWRP custom recovery device tree for partition maps and boot flags. | Verified working remote. | 2026-11-05 |
| **Hardware Reference Repo** | `https://github.com/udaysinh-git/root-lenovo-tab-m8.git` | Hardware testing, stock firmware notes, and vbmeta patch reference. | Verified working remote. | 2026-11-05 |
| **Google Prebuilt GCC 4.9** | `https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9` | Official Android cross-compiler for 64-bit ARM. Branch: `pie-gsi`. | Verified Google remote. | 2026-11-05 |
| **Google Prebuilt Clang** | `https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86` | Official Android Clang compiler (`clang-r353983c`). Branch: `android10-gsi`. | Verified Google remote. | 2026-11-05 |
| **Halium Initramfs Releases**| `https://github.com/halium/initramfs-tools-halium/releases/download/continuous/` | Continuous prebuilt initrd ramdisks for Ubuntu Touch (`initrd.img-touch-arm64`).| Verified active release. | 2026-11-05 |
| **MediaTek BROM mtkclient** | `https://github.com/bkerler/mtkclient.git` | MediaTek SoC exploitation and partition read/write tool for BROM/DA mode. | Verified active upstream. | 2026-11-05 |
| **Lenovo Software Fix** | `https://download.lenovo.com/consumer/mobiles/software_fix_v7.6.2.10_setup.exe` | Official free OEM rescue tool to download stock `S301129_230914_BMP_SVC`. | Verified active download. | 2026-11-05 |
