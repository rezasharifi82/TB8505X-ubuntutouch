#!/usr/bin/env python3
# ==============================================================================
# Script: monitor_usb.py
# Purpose: Passive USB detection monitor for Lenovo TB-8505X.
# Strictly passive: listens to Linux kernel netlink / udev events.
# Zero interaction with USB bus, zero endpoints opened, zero commands sent.
# ==============================================================================

import sys
import os
import subprocess
import datetime
import re

KNOWN_MODES = {
    ("0e8d", "0003"): "MediaTek Boot ROM (BROM) Mode",
    ("0e8d", "2000"): "MediaTek Preloader VCOM Mode",
    ("0e8d", "2007"): "MediaTek META Mode (CDC ACM ttyACM)",
    ("0e8d", "20ff"): "MediaTek Preloader / Off-Mode Charging",
    ("0e8d", "0c01"): "MediaTek Fastboot Mode",
    ("0e8d", "0c02"): "MediaTek Android ADB / MTP Mode",
    ("18d1", "4ee7"): "Android Fastboot Mode",
    ("18d1", "d00d"): "Android Fastboot Mode",
}

def log(msg):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
    print(f"[{now}] {msg}", flush=True)

def parse_product(product_str):
    parts = product_str.split('/')
    if len(parts) >= 2:
        try:
            vid = f"{int(parts[0], 16):04x}"
            pid = f"{int(parts[1], 16):04x}"
            return vid, pid
        except ValueError:
            return parts[0].zfill(4).lower(), parts[1].zfill(4).lower()
    return None, None

def print_current_devices():
    log("=== CURRENTLY CONNECTED USB DEVICES ===")
    try:
        output = subprocess.check_output(["lsusb"], text=True)
        for line in output.strip().splitlines():
            # Bus 001 Device 017: ID 0e8d:20ff MediaTek Inc. ...
            m = re.search(r"Bus (\d+) Device (\d+): ID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\s*(.*)", line)
            if m:
                bus, dev, vid, pid, desc = m.groups()
                vid_lower = vid.lower()
                pid_lower = pid.lower()
                known = KNOWN_MODES.get((vid_lower, pid_lower), "")
                extra = f" [{known}]" if known else ""
                log(f"[PRESENT] VID:PID={vid_lower}:{pid_lower} | Bus {bus} Dev {dev} | {desc}{extra}")
            else:
                log(f"[PRESENT] {line}")
    except Exception as e:
        log(f"Error checking lsusb: {e}")
    log("=========================================\n")

def main():
    log("=== PASSIVE USB DETECTION MONITOR ACTIVE ===")
    log("Safety Guarantee: PASSIVE ONLY. Zero writes, zero exploits, zero payloads, zero I/O.")
    log("Monitoring kernel uevents for attach/detach events...\n")
    print_current_devices()

    cmd = ["udevadm", "monitor", "--udev", "--property", "--subsystem-match=usb"]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)

    current_props = {}

    for line in iter(proc.stdout.readline, ''):
        line = line.strip()
        if not line:
            if current_props:
                handle_event(current_props)
                current_props = {}
            continue

        if "=" in line:
            k, v = line.split("=", 1)
            current_props[k] = v

    if current_props:
        handle_event(current_props)

def handle_event(props):
    devtype = props.get("DEVTYPE")
    if devtype != "usb_device":
        return

    action = props.get("ACTION", "").upper()
    devname = props.get("DEVNAME", "N/A")
    devpath = props.get("DEVPATH", "N/A")
    
    vid = props.get("ID_VENDOR_ID", "").lower()
    pid = props.get("ID_MODEL_ID", "").lower()

    if not vid or not pid:
        product = props.get("PRODUCT", "")
        if product:
            p_vid, p_pid = parse_product(product)
            vid = vid or p_vid
            pid = pid or p_pid

    vendor = props.get("ID_VENDOR_FROM_DATABASE") or props.get("ID_VENDOR") or ""
    model = props.get("ID_MODEL_FROM_DATABASE") or props.get("ID_MODEL") or ""
    
    desc = f"{vendor} {model}".strip()
    known = KNOWN_MODES.get((vid, pid), "")
    if known:
        desc = f"{desc} [{known}]" if desc else known

    vid_pid = f"{vid}:{pid}" if vid and pid else "UNKNOWN"

    if action == "ADD":
        log(f"[ATTACH] {action:<6} VID:PID={vid_pid:<9} | {desc:<45} | Node: {devname}")
    elif action == "REMOVE":
        log(f"[DETACH] {action:<6} VID:PID={vid_pid:<9} | {desc:<45} | Node: {devname}")
    elif action in ("BIND", "UNBIND"):
        log(f"[{action}] {action:<6} VID:PID={vid_pid:<9} | Node: {devname}")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("Monitor terminated.")
        sys.exit(0)
