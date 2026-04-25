
# Requirements:

- [chroot-distro](https://github.com/sabamdarif/chroot-distro/) on rooted Android phone, with some distro installed e.g. via:

```sh
# first time setup
chroot-distro download debian
chroot-distro install debian

# once set up
chroot-distro login debian
```

- Android Phone UI config:
  - Default USB connection: tethering

- Connect phone to Raspberry Pi via USB

- Raspberry Pi network config, something like running:

```sh
# install iptables and make it persistent
sudo apt update
sudo apt install -y iptables iptables-persistent

# enable IP forwarding permanently
echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-usb-tether.conf
sudo sysctl -p /etc/sysctl.d/99-usb-tether.conf

# --- plug in phone + enable USB tethering now (see Step 3) ---
# verify usb0 appears:
ip link

# configure usb0 statically via NetworkManager (Bookworm default)
sudo nmcli connection add type ethernet ifname usb0 con-name usb-tether \
  ipv4.method manual \
  ipv4.addresses 192.168.42.1/24 \
  ipv4.never-default yes \
  connection.autoconnect yes
sudo nmcli connection up usb-tether

# NAT traffic from phone out via eth0
sudo iptables -t nat -A POSTROUTING -s 192.168.42.0/24 -o eth0 -j MASQUERADE
sudo iptables -A FORWARD -i usb0 -o eth0 -j ACCEPT
sudo iptables -A FORWARD -i eth0 -o usb0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# save iptables rules so they survive reboot
sudo netfilter-persistent save
```


# Setup on Raspberry Pi boot

Just run the `startup.sh` script on the Raspberry Pi

# Using the chroot

See `chroot.sh help`

Run commands with `chroot.sh run`

# References

- <https://github.com/sabamdarif/chroot-distro/>
- <https://openwrt.org/docs/guide-user/network/wan/smartphone.usb.reverse.tethering>
- <https://ruuucker.github.io/articles/Android-USB-reverse-tethering/>
