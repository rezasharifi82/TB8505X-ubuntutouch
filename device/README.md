# Device Tree & Board Definitions

This directory documents and organizes the device trees (`dts`/`dtsi`) for `akita_row_call`:

- Device Tree: `akita_row_call.dts` (and included `cust.dtsi`)
- Base SoC DTSI: `mt6761.dtsi` / `mt8766.dtsi`
- Pin Control: `pinctrl` for LCM, Touch, Cameras, OTG, and PMIC.
- Peripheral mappings: Novatek NT35521 panel, Capacitive Touch (0x38 on I2C0), RT9471/BQ25601 chargers.
