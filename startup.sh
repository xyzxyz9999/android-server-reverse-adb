#!/usr/bin/env bash
set -euo pipefail

# Script to run on Linux server (e.g. Raspberry Pi) on startup to recover connection with Android phone
# Assumes that previously a (one-off) basic setup has been made
# In case not, run this one-off setup:
# ```
# # install iptables and make it persistent
# sudo apt update
# sudo apt install -y iptables iptables-persistent
# 
# # enable IP forwarding permanently
# echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-usb-tether.conf
# sudo sysctl -p /etc/sysctl.d/99-usb-tether.conf
# 
# # --- plug in phone + enable USB tethering now (see Step 3) ---
# # verify usb0 appears:
# ip link
# 
# # configure usb0 statically via NetworkManager (Bookworm default)
# sudo nmcli connection add type ethernet ifname usb0 con-name usb-tether \
#   ipv4.method manual \
#   ipv4.addresses 192.168.42.1/24 \
#   ipv4.never-default yes \
#   connection.autoconnect yes
# sudo nmcli connection up usb-tether
# 
# # NAT traffic from phone out via eth0
# sudo iptables -t nat -A POSTROUTING -s 192.168.42.0/24 -o eth0 -j MASQUERADE
# sudo iptables -A FORWARD -i usb0 -o eth0 -j ACCEPT
# sudo iptables -A FORWARD -i eth0 -o usb0 -m state --state RELATED,ESTABLISHED -j ACCEPT
# 
# # save iptables rules so they survive reboot
# sudo netfilter-persistent save
# ```

setup_adb_server() {
  sudo adb kill-server 2>/dev/null || true   # sanity: kill any previously running server
  sudo adb devices &>/dev/null # start adb server as root
}

# run commands in Android device
#   multi-line supported e.g.
#   ```
#   adb_run "cd /sdcard
#   ls -la
#   echo done"
#   ```
adb_run() {
  sudo adb shell -T <<< "$*"
}

# To run heredocs,  use this instead:
#   ```
#   adb shell <<EOF
#   xyz
#   EOF
#   ```



verify_root() {
  user=$(adb_run whoami | tr -d '[:space:]')
  if [ "$user" != "root" ]; then
    echo "ERROR: adb shell is not root (got: '$user')" >&2
    exit 1
  fi
}

# Network setup

USB_INTERFACE="usb0"  # the one on the Linux server
LOCAL_USB_IP=""
ANDROID_USB_IP=""
ANDROID_USB_INTERFACE="rndis0"

detect_usb_ip() {
  LOCAL_USB_IP=$(ip -4 addr show "$USB_INTERFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
  [[ -z "$LOCAL_USB_IP" ]] && { echo "ERROR: no IP on $USB_INTERFACE" >&2; exit 1; }
  ANDROID_USB_IP=$(echo "$LOCAL_USB_IP" | sed 's/\.[0-9]*$/.50/')
}

android_ip_setup() {
  echo "Setting IP: $ANDROID_USB_IP at $ANDROID_USB_INTERFACE"

  adb_run "
ip addr flush dev $ANDROID_USB_INTERFACE
ip link set $ANDROID_USB_INTERFACE up
ip addr add $ANDROID_USB_IP/24 dev $ANDROID_USB_INTERFACE


ip route add $LOCAL_USB_IP dev $ANDROID_USB_INTERFACE table local_network
ip route add default via $LOCAL_USB_IP dev $ANDROID_USB_INTERFACE table local_network
"
}

verify_lan() {
  result=$(adb_run ping -c 1 $LOCAL_USB_IP 2>&1 | grep '1 received')
  if [ -z "$result" ]; then
    echo "ERROR: gateway is unreachable from device" >&2
    exit 1
  fi
}

verify_internet() {
  result=$(adb_run ping -c 1 9.9.9.9 2>&1 | grep '1 received')
  if [ -z "$result" ]; then
    echo "ERROR: internet is unreachable from device" >&2
    exit 1
  fi
}

android_dns_setup() {
  LOCAL_IFACE="eth0" # the one on the Linux server
  LOCAL_DNS_SERVER=$(ip route show dev $LOCAL_IFACE | awk '/default/ {print $3}')
  PID_FILE="/data/local/tmp/dnsmasq.pid"

  # First, cleanup
  echo "Killing any existing dnsmasq processes..."
  adb_run killall dnsmasq

  adb_run "
if [ -f \"$PID_FILE\" ]; then
  pid=\$(cat \"$PID_FILE\")
  if [ -n \"\$pid\" ] && kill -0 \"\$pid\" 2>/dev/null; then
    kill \"\$pid\"
  fi
  rm -f \"$PID_FILE\"
fi
"
  # Restart dnsmasq
  echo "Starting custom dnsmasq with $LOCAL_DNS_SERVER ..."

  # Exiting this often times out, ignore it
  # we need to use `adb shell` to work with `timeout`
  timeout 3 adb shell "
/system/bin/dnsmasq \
  --listen-address=127.0.0.1 \
  --port=53 \
  --server=$LOCAL_DNS_SERVER \
  --server=1.1.1.1 \
  --no-resolv \
  --no-hosts \
  --bind-interfaces \
  --pid-file=/data/local/tmp/dnsmasq.pid
echo dnsmasq started # sanity check
" || true  # timeout exit 124 is expected

  # point the system resolver at localhost
  adb_run setprop net.dns1 127.0.0.1

# check what's on port 53 — Android's tethering dnsmasq is already bound
# there, but mark-filters traffic so it won't answer us
# ss -tlnp | grep ':53'
# test (use any hostname not in /etc/hosts)
# ping wikipedia.org
}

verify_dns() {
  result=$(adb_run nslookup wikipedia.org 2>&1 | grep -A1 "^Name:")
  if [ -z "$result" ]; then
    echo "ERROR: DNS resolution failed on device" >&2
    exit 1
  fi
}



# Execution

main() {
  echo "Setting up local ADB server..."
  setup_adb_server

  echo "Checking Android shell access"
  verify_root

  echo "Setting up IP..."
  detect_usb_ip
  android_ip_setup
  verify_lan
  verify_internet
  echo "Android IP setup"

  echo "Setting up DNS..."
  android_dns_setup
  verify_dns
  echo "Android DNS setup"

  echo "Android device connected"
}


[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
