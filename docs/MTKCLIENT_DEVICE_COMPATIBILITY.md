# MTKClient Device Compatibility & Protocol Analysis — Lenovo TB-8505X

## 1. Local MTKClient Environment & Version

| Parameter | Value | Verification Reference |
|---|---|---|
| **Software Version** | **MTK Flash/Exploit Client V2.1.4 (c) B.Kerler 2018-2026** | [`tools/mtkclient/mtk.py:12`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/tools/mtkclient/mtk.py#L12) |
| **Local Repository Path**| [`tools/mtkclient/`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/tools/mtkclient/) | Cloned in project tree |
| **Python Backend** | Python 3.14.4 + `pyusb`, `pycryptodome`, `pyserial`, `colorama` | Host user-space environment |
| **USB Access Library** | Native `libusb-1.0` via Linux kernel `usbfs` | Non-root access via udev rules |

---

## 2. Hardware Identification & SoC Configuration

| Hardware Attribute | Value | Verification Data |
|---|---|---|
| **Platform BSP** | MediaTek MT6761 (Helio A22) | Verified from fastboot and stock kernel banner |
| **Silicon Stepping** | MediaTek MT8766B (Quad-core ARM Cortex-A53) | Physical sysfs hardware probe (`partitions.txt`) |
| **BROM Hardware Code**| **`0x6761`** (`dacode=0x6761`) | [`brom_config.py:1380`](file:///home/mreza/Desktop/TB8505X/TB8505X-ubuntutouch/tools/mtkclient/mtkclient/config/brom_config.py#L1380) |
| **Chipconfig Entry** | `MT6761/MT6762/MT3369/MT8766B/MT8761/AC8259/AC8257` | Verified in local MTKClient database |
| **BROM Payload** | `mt6761_payload.bin` (612 bytes) | Verified present in `mtkclient/payloads/` |
| **DA Architecture** | XFLASH (`damode=DAmodes.XFLASH`) | Supported natively |

---

## 3. USB Interface & Security Configuration

### USB Device Identifiers
- **Boot ROM (BROM) Mode:** USB ID **`0E8D:0003`** (`MediaTek Inc. MT65xx Preloader / Boot ROM`).
- **Fastboot Mode:** USB ID **`0E8D:201C`** (`MediaTek Inc.`) / **`18D1:4EE0`** (`Google Inc.`).

### Security Flags & Silicon Protection
Empirically documented on this exact Lenovo hardware (`references/docs/01-firmware-and-backup.md:60`):
- **SBC (Secure Boot Check):** **ON** (Enabled in eFuse).
- **SLA (Serial Link Authentication):** **OFF** (No vendor challenge-response key required for serial handshake).
- **DAA (Download Agent Authentication):** **ON** (Requires signature verification for official Download Agents).

### Exploit Mechanism & Silicon Safety
Because **DAA is enabled**, standard unauthenticated Download Agents cannot be injected directly.
1. **Kamakiri BROM Exploit:** MTKClient sends a malformed USB control request (`USB_REQ_GET_DESCRIPTOR`) that triggers an integer buffer overflow in the MediaTek Boot ROM USB stack.
2. **SRAM Execution:** The payload (`mt6761_payload.bin`) is loaded into SRAM at `0x100A00` to disable the hardware DAA enforcement register.
3. **Payload Injection:** MTKClient streams its custom open-source Download Agent into DRAM.
4. **Read Safety:** Flash read operations (`r`, `rl`, `ro`) execute entirely in volatile DRAM and read raw eMMC sectors without issuing write or erase commands.
5. **Non-Persistence:** The moment the USB cable is unplugged or the battery power-cycles, the SRAM/DRAM state vanishes completely. Silicon fuses and eMMC contents remain 100% untouched.

---

## 4. Critical Parser Correction: Command Line Syntax

In MTKClient V2.1.4, the `r` command parser is defined as:

```python
# tools/mtkclient/mtk.py:157-158
cmd_parsers["r"].add_argument("partitionname", help="Partitions (comma sep)")
cmd_parsers["r"].add_argument("filename", help="Output files (comma sep)")
```

And enforced in the execution handler:

```python
# tools/mtkclient/mtkclient/Library/DA/mtk_da_handler.py:332-337
filenames = filename.split(",")
partitions = partitionname.split(",")
if len(partitions) != len(filenames):
    if display:
        self.error("You need to gives as many filenames as given partitions.")
    self.close()
```

### The Previous Error
The previously proposed command:
```bash
# INVALID SYNTAX (Will fail immediately):
python3 tools/mtkclient/mtk.py r nvram,nvdata,... ~/Desktop/TB8505X/backups/brom_pre_unlock/
```
Failed because `partitions` contained 10 items, while `filenames` contained only 1 item (a directory path). MTKClient aborts with:
`ERROR: You need to gives as many filenames as given partitions.`

### The Corrected Syntax
Each partition must have a corresponding, distinct output filename:

```bash
# CORRECT SYNTAX (1-to-1 Mapping):
python3 tools/mtkclient/mtk.py r \
  nvram,nvdata,nvcfg,proinfo,persist,protect1,protect2,seccfg,boot,recovery,vbmeta,dtbo \
  ~/Desktop/TB8505X/backups/brom_pre_unlock/nvram.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/nvdata.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/nvcfg.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/proinfo.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/persist.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/protect1.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/protect2.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/seccfg.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/boot.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/recovery.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/vbmeta.bin,\
~/Desktop/TB8505X/backups/brom_pre_unlock/dtbo.bin
```

Alternatively, partition reads can be performed individually per partition command.
