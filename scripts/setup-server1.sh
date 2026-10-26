#!/bin/bash
set -euo pipefail
WG_DIR=/etc/wireguard
mkdir -p "$WG_DIR"
chmod 700 "$WG_DIR"
if [[ ! -f "$WG_DIR/server.key" ]]; then
  wg genkey | tee "$WG_DIR/server.key" | wg pubkey > "$WG_DIR/server.pub"
  chmod 600 "$WG_DIR/server.key"
fi
SERVER_PRIV=$(cat "$WG_DIR/server.key")
SERVER_PUB=$(cat "$WG_DIR/server.pub")
HOST2_PUB="evDWUnedmoUyfCr15AVu9y0ghWpF8ML/ixedK32U338="
cat > "$WG_DIR/wg0.conf" <<EOF
[Interface]
Address = 10.200.1.1/24
ListenPort = 51820
PrivateKey = ${SERVER_PRIV}
PostUp = sysctl -w net.ipv4.ip_forward=1
# порт 51820/udp открывается один раз вручную через firewall-cmd (см. README)

[Peer]
# host2 (Windows)
PublicKey = ${HOST2_PUB}
AllowedIPs = 10.200.1.2/32
EOF
chmod 600 "$WG_DIR/wg0.conf"
sysctl -w net.ipv4.ip_forward=1
grep -q '^net.ipv4.ip_forward' /etc/sysctl.d/99-wireguard.conf 2>/dev/null || echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-wireguard.conf
sysctl --system >/dev/null 2>&1 || true
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0
systemctl is-active wg-quick@wg0
wg show wg0
echo "SERVER1_PUB=${SERVER_PUB}"
