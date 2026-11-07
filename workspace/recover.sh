#!/bin/bash
IF=enx32aa2a3b49bc
OUT=/tmp/recover.out
: > $OUT
exec >> $OUT 2>&1
echo "=== $(date) ==="
echo "--- usb ids ---"
for f in idVendor idProduct product manufacturer serial; do printf "%s=" $f; cat /sys/bus/usb/devices/1-1/$f 2>/dev/null; done
echo "--- ping sweep 10.15.19.0/24 ---"
for i in $(seq 1 254); do ( ping -c1 -W1 10.15.19.$i >/dev/null 2>&1 && echo "ALIVE 10.15.19.$i" ) & done
wait
echo "--- arp neigh ---"
ip neigh show dev $IF
echo "--- monitor 100s ---"
for i in $(seq 1 10); do
  vid=$(cat /sys/bus/usb/devices/1-1/idVendor 2>/dev/null)
  pid=$(cat /sys/bus/usb/devices/1-1/idProduct 2>/dev/null)
  rx=$(cat /sys/class/net/$IF/statistics/rx_packets 2>/dev/null)
  tx=$(cat /sys/class/net/$IF/statistics/tx_packets 2>/dev/null)
  echo "t=$((i*10))s usb=$vid:$pid rx=$rx tx=$tx"
  sleep 10
done
echo "--- adb ---"
timeout 10 adb devices -l 2>&1
echo "--- ssh port ---"
timeout 4 bash -c 'exec 3<>/dev/tcp/127.0.0.1/2222' 2>/dev/null && echo LISTEN || echo NONE
echo "--- dmesg usb ---"
journalctl -k -n 40 --no-pager 2>/dev/null | grep -iE 'usb 1-1|rndis|cdc_' | tail -12
echo DONE
