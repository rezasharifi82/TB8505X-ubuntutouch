# Halium 10 Architecture & Container Integration: Lenovo TB-8505X

**Target Device:** Lenovo Tab M8 HD LTE (`TB-8505X` / `akita_row_call`)  
**Base Android Version:** Android 10 (SDK 29)  
**Halium Release:** Halium 10  
**UBports Userspace:** Ubuntu 20.04 (Focal Fossa) ARM64

---

## 1. Architectural Overview & Component Distinctions

A common pitfall in Android-based Linux ports is confusing the different images and partitions. On the Lenovo TB-8505X, each component has a precise, strictly separated role:

```mermaid
flowchart TD
    subgraph EMMC["eMMC Flash Partitions"]
        P_BOOT["boot (mmcblk0p28) - 32MB"]
        P_VEND["vendor (mmcblk0p36) - 800MB (Stock Factory)"]
        P_SYS["system (mmcblk0p37) - 3896MB (Ubuntu Touch ext4)"]
        P_DATA["userdata (mmcblk0p38) - 23.4GB (User & Container State)"]
    end

    subgraph UT_ROOTFS["Ubuntu Touch Userspace (Running on /)"]
        SYSTEMD["Systemd Init System"]
        LOMIRI["Lomiri Desktop Shell"]
        MIR["Mir Display Server"]
        HYBRIS["libhybris Hardware Translation"]
        OFONO["oFono Cellular Daemon"]
        PULSE["PulseAudio Sound Server"]
        LXC_SERVICE["lxc@android.service"]
    end

    subgraph HAL_CONTAINER["Halium 10 Android Container (in /var/lib/lxc/android)"]
        ANDROID_INIT["Android init (minimal)"]
        SERVICEMANAGER["Service Manager & HWServiceManager"]
        SURFACEFLINGER["SurfaceFlinger / HWComposer"]
        AUDIO_HAL["MediaTek MT6357 Audio HAL"]
        RIL_DAEMON["MediaTek CCCI RIL Daemon"]
        VENDOR_MOUNT["/vendor (Bind-mounted from mmcblk0p36)"]
    end

    P_BOOT -->|Loads Kernel 4.9.190+| SYSTEMD
    P_SYS -->|Mounted as /| UT_ROOTFS
    P_VEND -->|Preserved Untouched| VENDOR_MOUNT
    P_DATA -->|Stores /home and Container Diffs| UT_ROOTFS

    SYSTEMD --> LXC_SERVICE
    LXC_SERVICE -->|Spawns LXC Container| ANDROID_INIT
    VENDOR_MOUNT --> ANDROID_INIT

    ANDROID_INIT --> SURFACEFLINGER
    ANDROID_INIT --> AUDIO_HAL
    ANDROID_INIT --> RIL_DAEMON

    SURFACEFLINGER -->|HWComposer buffers| HYBRIS
    HYBRIS --> MIR
    MIR --> LOMIRI

    AUDIO_HAL -->|PulseAudio droid sink| PULSE
    RIL_DAEMON -->|GBinder / HIDL| OFONO
```

---

## 2. Component Clarification Matrix

| Component | Physical Location | Content | Purpose |
| :--- | :--- | :--- | :--- |
| **`boot.img`** | `/dev/block/mmcblk0p28` | Monolithic Linux 4.9.190+ kernel + `initrd.img-touch-arm64` | Boots hardware, initializes early mounts, pivots to systemd. |
| **Stock `vendor.img`** | `/dev/block/mmcblk0p36` | Untouched factory Android 10 vendor blobs from Lenovo | Provides MediaTek MT6761 hardware HALs and firmware. |
| **Ubuntu Touch `system.img`** | `/dev/block/mmcblk0p37` | Ubuntu 20.04 ARM64 rootfs + Halium adaptation overlay | Host operating system running Lomiri, Mir, and system services. |
| **Halium Container Image** | `/var/lib/lxc/android/android-rootfs.img` | Minimal AOSP 10 container rootfs | Houses Android `init`, `servicemanager`, and runs HAL daemons. |
| **`userdata`** | `/dev/block/mmcblk0p38` | Formatted ext4 partition | User home directories, app data, and persistent container state. |

---

## 3. LXC Android Container Configuration

The container is spawned via `/lib/systemd/system/lxc@android.service`:
- **Rootfs:** `/var/lib/lxc/android/android-rootfs.img` mounted read-only.
- **Vendor Mount:** Read-only bind mount from host `/vendor` (which mounts `/dev/block/by-name/vendor`).
- **Dev Bindings:** `/dev/binder`, `/dev/hwbinder`, `/dev/vndbinder`, `/dev/pvr_sync`, `/dev/pvrsrvkm`, `/dev/mtk_disp_mgr`, `/dev/ccci*`.
- **Cgroups & Namespaces:** The container runs in isolated mount, UTS, IPC, and PID namespaces while sharing the network and IPC devnodes with the host.
