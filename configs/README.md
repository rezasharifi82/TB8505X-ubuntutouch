# Device Configurations

This directory contains runtime configuration files, overlays, and hardware adaptation definitions for the Lenovo TB-8505X tablet:

- `udev/`: Hardware permission rules (e.g., `70-akita.rules`, PowerVR Rogue GPU node permissions `pvrsrvkm`, touchscreen `v4l-touch`, audio/ccci nodes).
- `binder/`: `gbinder.conf` configuration matching Android 10 Binder IPC (`/dev/binder`, `/dev/hwbinder`, `/dev/vndbinder`).
- `pulseaudio/`: Custom PulseAudio routing rules and daemon tuning for MT6357 PMIC.
- `power/`: `repowerd` backlight and sleep/wake configuration for the Novatek NT35521 panel.
- `ofono/`: Cellular modem configuration for MediaTek RIL telephony.
