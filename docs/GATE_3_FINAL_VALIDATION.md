# Gate 3 Final Validation: Deep Technical Evidence & Pre-Flash Audit

**Target Device:** Lenovo Tab M8 HD LTE (`TB-8505X` / `akita_row_call`)  
**SoC Platform:** MediaTek MT6761 (Helio A22 / MT8766B, Hardware Code: `0x0717`)  
**Host Platform:** Linux x86_64 (`Phantom`)  
**Current Physical State:** Fastboot mode (`HGR2YTWY fastboot`), connected via USB.  
**Bootloader Security State:** `unlocked: yes`, `secure: no`, `kernel: lk`, `product: akita_row_call`.  
**Safety Protocol:** Read-Only Audit. Zero flashing, zero erasing, zero formatting, zero reboots, zero device modifications.

---

## 1. LK Firmware Build & Binary Extraction Provenance

### 1.1 Fastboot Reported Bootloader Build
Queried directly from device hardware via Fastboot:
- `(bootloader) kernel: lk`
- `(bootloader) version-bootloader: akita_row_call-622276bd-20220223142906-20230914134942`
- `(bootloader) version-baseband: MOLY.LR12A.R3.MP.V109.P6`
- `(bootloader) product: akita_row_call`
- `(bootloader) hw-revision: ca01`
- `(bootloader) unlocked: yes`

### 1.2 Binary Extraction Provenance
During Gate 1 (MediaTek BROM Calibration Backup), the backup procedure was strictly scoped to the 12 approved calibration, identity, and boot partitions:
`nvram, nvdata, nvcfg, proinfo, persist, protect1, protect2, seccfg, boot, recovery, vbmeta, dtbo` (plus SRAM preloader dump `preloader_akita_row_call.bin`).

Partitions `lk` (`/dev/block/mmcblk0p15`, size: 1 MiB) and `lk2` (`/dev/block/mmcblk0p16`, size: 1 MiB) were **not** extracted during Gate 1. Furthermore, no offline stock firmware archive containing an extracted `lk.bin` file exists in the host workspace.

**Status:** The physical `lk.bin` binary is not present on the host filesystem. Consequently, its physical SHA-256 checksum cannot be calculated, and direct machine-code disassembly of the compiled binary on the host cannot be performed.

---

## 2. libavb Source-to-Binary Correspondence

The source code analyzed in this audit is Google AOSP `libavb` v1.1.0 (`workdir/downloads/avb/libavb/`), which is the standard implementation integrated across MediaTek Android 10 (Q) BSPs (`alps-mp-q0.mp1-V9.56_lenovo.m8.q0mp1.tb8788p1.64.bsp_P4`). The release string embedded in the stock `vbmeta.bin` header confirms toolchain alignment:
```text
Release String: 'avbtool 1.1.0'
```

**Explicit Statement on Source-to-Binary Correspondence:**  
Because the physical `lk.bin` binary was not dumped to the host, **source-to-binary correspondence cannot be proven at the machine-code level**. While the architecture and API signatures conform to standard AOSP libavb v1.0/1.1, we cannot definitively rule out proprietary OEM modifications introduced into Little Kernel by Lenovo or MediaTek without empirical on-device execution.

---

## 3. Complete Execution Path: Unlocked Device with Patched VBMeta

For an unlocked device booting with `out/vbmeta_disabled.img` (where byte offset 123 is `0x03` and the Authentication Data Block signature is mathematically invalid):

```
[Little Kernel Initialization]
    │
    ▼
boot_linux_from_storage() / avb_boot()
    │
    ├─> Queries seccfg / unlock state -> unlocked: yes
    │   Sets verify_flags = AVB_SLOT_VERIFY_FLAGS_ALLOW_VERIFICATION_ERROR
    │
    ▼
avb_slot_verify(ops, requested_partitions, ab_suffix, verify_flags, hashtree_error_mode, &slot_data)
    │
    ├─> bool allow_verification_error = (flags & AVB_SLOT_VERIFY_FLAGS_ALLOW_VERIFICATION_ERROR);
    │   (Evaluates to TRUE)
    │
    ▼
load_and_verify_vbmeta(ops, requested_partitions, ..., "vbmeta", ..., slot_data, ...)
    │
    ├─> ops->read_from_partition(ops, "vbmeta", 0, vbmeta_size, vbmeta_buf, &vbmeta_num_read)
    │
    ├─> avb_vbmeta_image_verify(vbmeta_buf, vbmeta_num_read, &pk_data, &pk_len)
    │     │
    │     ├─> Computes SHA-256 over Header (bytes 0..255) + Auxiliary Block (bytes 576..3839).
    │     ├─> Computed: bf8cc20d... != Stored in Auth Block: c0941cc6...
    │     └─> Returns: AVB_VBMETA_VERIFY_RESULT_HASH_MISMATCH
    │
    ├─> Evaluates switch (vbmeta_ret):
    │     case AVB_VBMETA_VERIFY_RESULT_HASH_MISMATCH:
    │     case AVB_VBMETA_VERIFY_RESULT_SIGNATURE_MISMATCH:
    │       ret = AVB_SLOT_VERIFY_RESULT_ERROR_VERIFICATION;
    │       avb_errorv(full_partition_name, ": Error verifying vbmeta image\n", NULL);
    │       if (!allow_verification_error) {
    │         goto out; // ONLY halts if locked!
    │       }
    │       break;    // Continues because allow_verification_error == TRUE!
    │
    ├─> Evaluates top-level flags (Lines 920-934):
    │     if (vbmeta_header.flags & AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED) {
    │       // BIT 1 (0x02) IS SET!
    │       sub_ret = load_requested_partitions(ops, requested_partitions, ab_suffix, slot_data);
    │       if (sub_ret != AVB_SLOT_VERIFY_RESULT_OK) {
    │         ret = sub_ret;
    │         goto out;
    │       }
    │       ret = AVB_SLOT_VERIFY_RESULT_OK;
    │       goto out; // COMPLETELY SKIPS ALL DESCRIPTOR VALIDATION!
    │     }
    │
    ▼
load_requested_partitions(ops, requested_partitions, ab_suffix, slot_data)
    │
    ├─> Iterates requested_partitions ("boot" or "recovery")
    ├─> Calls load_full_partition(ops, part_name, image_size, &image_buf, &image_preloaded)
    ├─> Directly reads partition into DRAM without signature, hash, or public key checks.
    └─> Appends image buffer to slot_data->loaded_partitions. Returns AVB_SLOT_VERIFY_RESULT_OK.
    │
    ▼
avb_slot_verify() returns AVB_SLOT_VERIFY_RESULT_OK to Little Kernel
    │
    ▼
Little Kernel jumps to Linux kernel entry point at 0x40080000.
```

---

## 4. Flag Semantics & dm-verity Kernel Command-Line Behavior

In the AVB 2.0 header specification (`libavb/avb_vbmeta_image.h`):
- `AVB_VBMETA_IMAGE_FLAGS_HASHTREE_DISABLED = (1 << 0)` (`0x01`)
- `AVB_VBMETA_IMAGE_FLAGS_VERIFICATION_DISABLED = (1 << 1)` (`0x02`)
- Combined Flags: `0x01 | 0x02 = 0x03`

### 4.1 Semantics of `VERIFICATION_DISABLED`
In `avb_slot_verify.c` (lines 924-934 and 1536-1546):
- Bypasses cryptographic signature verification on all chained partitions (`boot`, `recovery`, `system`, `vendor`).
- Inhibits appending `androidboot.veritymode` or verified boot command-line arguments to the kernel parameters.

### 4.2 Semantics of `HASHTREE_DISABLED`
In `avb_slot_verify.c` (lines 1074-1085):
- Evaluates `kernel_cmdline_desc.flags`. Any command-line snippet tagged with `AVB_KERNEL_CMDLINE_FLAGS_USE_ONLY_IF_HASHTREE_NOT_DISABLED` is dropped.
- In Android userspace `init` (`fs_mgr/libdm`):
  During `first_stage_mount`, `fs_mgr` reads `/dev/block/by-name/vbmeta`. When `HASHTREE_DISABLED` is set, `fs_mgr` bypasses creating dm-verity device-mapper targets (`/dev/block/dm-0`). Instead, it mounts `/system` and `/vendor` directly as standard ext4 read-only filesystems.

---

## 5. Reassessment: Will Stock Android Boot After Flashing `vbmeta_disabled.img`?

### What the Source Code Establishes (Theory)
1. Little Kernel's `avb_slot_verify()` loads the factory stock `boot` partition into memory and returns `OK`.
2. Because the stock `boot`, `system`, and `vendor` partitions are unmodified factory ext4 filesystems with valid superblocks, Android `first_stage_mount` can mount them directly without dm-verity hashtrees.
3. In standard AOSP implementations, stock Android boots normally into userspace with AVB disabled.

### What Requires Real Device Testing (Empirical Reality)
1. **Proprietary TEE / Keymaster Dependencies:** Lenovo Android 10 uses Microtrust / Beanpod Keymaster (`android.hardware.keymaster@4.0-service.beanpod`). If the proprietary TEE checks `ro.boot.vbmeta.digest` against a factory attestation key stored in RPMB/SEJ before unlocking `/data` encryption keys, stock userspace might encounter a decryption error on `/data`.
2. **OEM Little Kernel Policy:** While standard LK ignores the hash mismatch when `unlocked: yes`, we cannot guarantee without testing that Lenovo has not added an unadvertised OEM assert in Little Kernel.
3. **Conclusion:** While theory and community MT6761 precedents indicate stock Android will boot, **guaranteeing normal boot on this physical unit requires an empirical device test**.

---

## 6. Fastboot Rollback Procedure & Availability Proof

### 6.1 Original VBMeta Backup Availability
The pristine factory `vbmeta.bin` is verified and available at two locations on the host:
- Primary: `/home/mreza/Desktop/TB8505X/backups/brom_pre_unlock/vbmeta.bin`
- Duplicate Safe: `/home/mreza/TB8505X_backup_safe/brom_pre_unlock/vbmeta.bin`
- Size: Exactly `8,388,608 bytes` (8 MiB).
- Verified SHA-256: `fd6b79ceabaac5eccde98a7756a7c7646b5e7ba097a75e00c6d6e4fafe5cef50`.

### 6.2 Rollback Without Booting Android
- **Connection Status:** Verified active right now: `HGR2YTWY fastboot`.
- Fastboot runs entirely in Little Kernel SRAM/DRAM. It operates before and independent of Android.
- If `fastboot flash vbmeta out/vbmeta_disabled.img` is executed, the tablet **remains in Fastboot mode**.
- To reverse the operation immediately without ever leaving Fastboot or booting Android:
  ```bash
  fastboot flash vbmeta /home/mreza/TB8505X_backup_safe/brom_pre_unlock/vbmeta.bin
  ```
- **Validation:** LK Fastboot directly flashes `vbmeta` to `/dev/block/mmcblk0p13`, restoring the factory OEM signature.

---

## Final Status Conclusion

Because the physical `lk.bin` binary was not extracted during Gate 1, direct machine-code disassembly of Lenovo's compiled Little Kernel cannot be performed on the host. While the execution path conforms to standard AOSP libavb v1.0/1.1 specifications, source-to-binary correspondence remains unproven at the binary level.

```text
PARTIALLY CONFIRMED
```

*(No flash commands have been executed. Strict safety enforced).*
