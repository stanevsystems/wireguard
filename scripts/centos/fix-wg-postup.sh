#!/bin/bash
set -euo pipefail
PRIV=$(tr -d '\r\n' </root/wg-laptop-gw.private.key)
cat >/etc/wireguard/wg-home3.conf <<EOF
[Interface]
PrivateKey = ${PRIV}
Address = 10.200.2.5/32
PostUp = /etc/wireguard/wg-vps-routes.sh
PostDown = ip rule del to 176.32.32.246/32 table 100 2>/dev/null; ip rule del to 45.144.30.165/32 table 100 2>/dev/null

[Peer]
PublicKey = Tm27HQ9uS4TL0zCguamTTLadS8/MnczmCLOsVaJm6Vk=
AllowedIPs = 0.0.0.0/0
Endpoint = 45.144.30.165:51820
PersistentKeepalive = 25
EOF
chmod 600 /etc/wireguard/wg-home3.conf
cat >/etc/wireguard/wg-home1.conf <<EOF
[Interface]
PrivateKey = ${PRIV}
Address = 10.200.1.5/32
PostUp = /etc/wireguard/wg-vps-routes.sh
PostDown = ip rule del to 176.32.32.246/32 table 100 2>/dev/null; ip rule del to 45.144.30.165/32 table 100 2>/dev/null

[Peer]
PublicKey = As40cjLtsqR9O1Skw4lYw/Pe9YfZBxCzn3rNpie8MTc=
AllowedIPs = 0.0.0.0/0
Endpoint = 176.32.32.246:51820
PersistentKeepalive = 25
EOF
chmod 600 /etc/wireguard/wg-home1.conf
HO_IP=$(ip -4 -o addr show dev ens192 | awk '{print $4}' | cut -d/ -f1)
cat >/etc/squid/squid.conf <<EOF
acl localnet src 192.168.72.0/24
acl adminnet src 192.168.181.0/24
http_port ${HO_IP}:3128
http_access allow localnet
http_access allow adminnet
http_access allow localhost
http_access deny all
visible_hostname laptop-gw
EOF
systemctl restart squid
systemctl restart wg-quick@wg-home3
sleep 2
systemctl is-active wg-quick@wg-home3
wg show
echo "DIRECT=$(curl -4 -s --max-time 15 https://ifconfig.me/ip)"
echo "PROXY=$(curl -4 -s --max-time 15 --proxy http://${HO_IP}:3128 https://ifconfig.me/ip)"
