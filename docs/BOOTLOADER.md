# Bootloader & Verified Boot Analysis — Lenovo TB-8505X

## 1. Fastboot State & Properties

Queries executed directly on the physical tablet via Fastboot returned:

```text
product: akita_row_call
unlocked: no
secure: yes
slot-count: 0
is-userspace: no
version: 0.5
kernel: lk
battery-soc-ok: yes
version-baseband: MOLY.LR12A.R3.MP.V109.P6
version-bootloader: akita_row_call-622276bd-20220223142906-20230914134942
```

Android OEM unlock properties:
```text
ro.oem_unlock_supported = 1
sys.oem_unlock_allowed = 1
ro.boot.flash.locked = 1
ro.boot.verifiedbootstate = green
```

---

## 2. Unlocking Procedure & Safety Considerations

The bootloader can be unlocked without third-party unlock codes via standard Fastboot:

```bash
fastboot flashing unlock
```

### Critical Safeguards

> [!CAUTION]
> **Data Loss Warning:** Executing `fastboot flashing unlock` completely erases user data (`/data`) and internal storage.
>
> **Strict Operational Rule:** This command MUST NEVER be automated by scripts or run without the user's explicit written approval.

1. **Hardware Confirmation:** After issuing `fastboot flashing unlock`, the tablet display prompts for physical confirmation via the **Volume Up** key.
2. **Reversibility:** The bootloader can be re-locked using `fastboot flashing lock` (which triggers another factory wipe).
3. **Verified Boot State:** Unlocking transitions `ro.boot.verifiedbootstate` from `green` to `orange`.
4. **Boot Warning:** The tablet will display the standard MediaTek 5-second orange warning screen on boot.

---

## 3. Fastboot 36.x vbmeta Bug & Patch Workaround

When attempting to flash an AVB-disabled `vbmeta` using modern platform-tools (`fastboot 36.x`), the command fails:

```text
$ fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
fastboot: error: Failed to find AVB_MAGIC at offset: 0
```

### Underlying Technical Cause

Modern fastboot client implementations fail to correctly parse the AVB header offsets on certain MediaTek AVB 1.1/2.0 images when passing the `--disable-*` command-line flags, even though the image begins with valid `AVB0` magic.

### Safe Patch Workaround

In the Android Verified Boot (AVB) 2.0 structure, the `flags` field is a big-endian 32-bit unsigned integer located at **offset 120** of the `vbmeta` header.
- Setting the flags to `3` (`AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED | AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED`) completely disables dm-verity and partition verification.
- In big-endian representation, the least significant byte of this 32-bit integer is at **offset 123**. Setting byte `123` to `0x03` disables verification without altering any other structure.

**Linux / Bash Implementation:**
```bash
cp vbmeta.img vbmeta_disabled.img
printf '\x03' | dd of=vbmeta_disabled.img bs=1 seek=123 conv=notrunc
```

Once patched, `vbmeta_disabled.img` can be flashed **without** any `--disable-*` flags:
```bash
fastboot flash vbmeta vbmeta_disabled.img
```
This workaround has been fully tested and validated on build `S301129_230914`.
