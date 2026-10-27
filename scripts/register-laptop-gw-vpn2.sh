#!/usr/bin/env bash
# Git Bash на ноутбуке: один раз passphrase к ~/.ssh/id_ed25519, затем регистрация peer на VPS-2.
set -euo pipefail
PUB='Zvea0uRRvDJCZAa7OXWHoAVlbeEUt7PnEvp0O1PMODw='
IP='10.200.2.5/32'
HOST='45.144.30.165'
ssh -o StrictHostKeyChecking=accept-new "root@${HOST}" bash -s <<EOF
set -euo pipefail
PUB='${PUB}'
IP='${IP}'
CONF=/etc/wireguard/wg0.conf
wg set wg0 peer "\$PUB" allowed-ips "\$IP"
grep -q "\$PUB" "\$CONF" || printf '\n[Peer]\n# laptop-gw CentOS\nPublicKey = %s\nAllowedIPs = %s\n' "\$PUB" "\$IP" >> "\$CONF"
wg show wg0 | sed -n '/peer: '"${PUB//\//\\/}"'/,/^$/p' || wg show wg0
EOF
echo "OK: laptop-gw registered on ${HOST} as ${IP}"
