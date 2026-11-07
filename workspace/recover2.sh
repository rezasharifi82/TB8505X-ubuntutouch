#!/bin/bash
# Host-side recovery for TB-8505X stuck in Halium initramfs gadget
IF=enx32aa2a3b49bc
DEV=/sys/bus/usb/devices/1-1

echo "=== $(date) ==="
echo "--- before ---"
cat $DEV/idVendor $DEV/idProduct 2>/dev/null | tr '\n' ':' ; echo
timeout 5 adb devices -l 2>&1 | tail -3

echo "--- add initramfs subnets ---"
sudo ip addr add 192.168.2.1/24 dev $IF 2>&1 || echo '(2.1 exists)'
sudo ip addr add 10.0.0.1/24 dev $IF 2>&1 || echo '(10.0.0.1 exists)'
sudo ip link set $IF up
ip -br -4 addr show $IF

echo "--- probe initramfs addresses ---"
for ip in 192.168.2.15 192.168.2.2 192.168.2.1 10.0.0.2 10.0.0.15 10.15.19.82; do
  if ping -c1 -W1 $ip >/dev/null 2>&1; then echo "ALIVE $ip"; fi
done
ip neigh show dev $IF

echo "--- USB gadget reset (authorized 0->1) ---"
if [ -w $DEV/authorized ]; then
  sudo sh -c "echo 0 > $DEV/authorized" && echo 'deauthorized'
  sleep 2
  sudo sh -c "echo 1 > $DEV/authorized" && echo 'reauthorized'
else
  echo 'authorized node not writable'
fi
sleep 6

echo "--- after reset ---"
cat $DEV/idVendor $DEV/idProduct $DEV/product 2>/dev/null | tr '\n' ':' ; echo
ip -br -4 addr show $IF
timeout 8 adb devices -l 2>&1 | tail -4

echo "--- probe again ---"
for ip in 192.168.2.15 10.0.0.2 10.15.19.82; do
  if ping -c2 -W1 $ip >/dev/null 2>&1; then echo "ALIVE $ip"; fi
done
ip neigh show dev $IF

echo "--- recent kernel usb ---"
journalctl -k -n 25 --no-pager 2>/dev/null | grep -iE 'usb 1-1|rndis' | tail -8
echo DONE
