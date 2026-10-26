#!/bin/bash
# Run ON the VPS (root). Sets WireGuard exit routing for a home station peer.
# Usage: ./vps-set-exit-peer.sh <1|2> <PEER_WG_IP> <PEER_PUBLIC_KEY>
# Example VPN-2 / Home-3: ./vps-set-exit-peer.sh 2 10.200.2.2 evDWUnedmoUyfCr15AVu9y0ghWpF8ML/ixedK32U338=
set -euo pipefail

HUB="${1:?hub 1 or 2}"
WG_IP="${2:?peer /32 e.g. 10.200.2.2}"
PUB="${3:?peer public key base64}"

CONF=/etc/wireguard/wg0.conf
if [[ ! -f "$CONF" ]]; then
  echo "Missing $CONF" >&2
  exit 1
fi

cp -a "$CONF" "${CONF}.bak.$(date +%Y%m%d%H%M%S)"

# Append or document: operator should ensure only ONE peer has 0.0.0.0/0 on this hub.
grep -q "$PUB" "$CONF" || {
  cat >> "$CONF" <<EOF

[Peer]
# exit node (added by vps-set-exit-peer.sh)
PublicKey = ${PUB}
AllowedIPs = ${WG_IP}/32, 0.0.0.0/0
EOF
}

echo "Review $CONF — merge duplicate [Peer] blocks if pubkey already existed."
echo "Apply: wg syncconf wg0 <(wg-quick strip wg0)  OR  systemctl restart wg-quick@wg0"
wg show wg0 2>/dev/null || true
