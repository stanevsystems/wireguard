#!/bin/bash
# CentOS Stream laptop-gw: WireGuard exit, firewall, Squid, egress-check, sshd baseline.
# Run as root on the router VM: bash setup-laptop-gw.sh
set -euo pipefail

WG_PRIV_FILE="${WG_PRIV_FILE:-/root/wg-laptop-gw.private.key}"
EXPECTED_EGRESS_FILE=/etc/wireguard/expected-egress.conf
HOSTONLY_CIDR="${HOSTONLY_CIDR:-192.168.181.0/24}"
HOSTONLY_IP="${HOSTONLY_IP:-192.168.181.182}"
NAT_DEV="${NAT_DEV:-}"
HOSTONLY_DEV="${HOSTONLY_DEV:-}"
DEFAULT_EXIT="${DEFAULT_EXIT:-home3}"

VPS1=176.32.32.246
VPS2=45.144.30.165
HUB1_PUB='As40cjLtsqR9O1Skw4lYw/Pe9YfZBxCzn3rNpie8MTc='
HUB2_PUB='Tm27HQ9uS4TL0zCguamTTLadS8/MnczmCLOsVaJm6Vk='
WG_OCTET=5

log() { echo "[setup-laptop-gw] $*"; }

detect_ifaces() {
  if [[ -n "${NAT_DEV}" && -n "${HOSTONLY_DEV}" ]]; then
    return
  fi
  local d gw
  while read -r d; do
    [[ -z "$d" ]] && continue
    gw=$(ip -4 route show dev "$d" 2>/dev/null | awk '/^default/ {print $3; exit}')
    if [[ -n "$gw" ]]; then
      NAT_DEV="$d"
    fi
  done < <(ip -4 -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth')
  while read -r d; do
    [[ "$d" == "$NAT_DEV" ]] && continue
    ip -4 addr show dev "$d" 2>/dev/null | grep -q 'inet ' && HOSTONLY_DEV="$d" && break
  done < <(ip -4 -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth')
  [[ -n "$NAT_DEV" && -n "$HOSTONLY_DEV" ]] || {
    log "Could not detect NAT/host-only ifaces. Set NAT_DEV and HOSTONLY_DEV."
    ip -4 addr; ip -4 route; exit 1
  }
  HOSTONLY_IP=$(ip -4 -o addr show dev "$HOSTONLY_DEV" | awk '{print $4}' | cut -d/ -f1 | head -1)
  [[ -n "$HOSTONLY_IP" ]] || HOSTONLY_IP="192.168.181.182"
  HOSTONLY_CIDR="${HOSTONLY_IP%.*}.0/24"
  log "NAT=$NAT_DEV host-only=$HOSTONLY_DEV ip=$HOSTONLY_IP cidr=$HOSTONLY_CIDR"
}

install_packages() {
  log "Installing packages..."
  dnf -y install epel-release || true
  dnf -y install wireguard-tools curl iptables-services squid policycoreutils-python-utils 2>/dev/null || \
  dnf -y install wireguard-tools curl iptables-services squid
  systemctl enable --now iptables || true
}

write_wg_routes() {
  cat >/etc/wireguard/wg-vps-routes.sh <<EOF
#!/bin/bash
set -euo pipefail
VPS1=${VPS1}
VPS2=${VPS2}
DEV_NAT=${NAT_DEV}
GW=\$(ip -4 route show dev "\${DEV_NAT}" | awk '/default/ {print \$3; exit}')
[[ -n "\${GW}" ]] || exit 1
ip rule add to "\${VPS1}/32" table 100 2>/dev/null || true
ip rule add to "\${VPS2}/32" table 100 2>/dev/null || true
ip route replace default via "\${GW}" dev "\${DEV_NAT}" table 100
EOF
  chmod 755 /etc/wireguard/wg-vps-routes.sh
}

write_wg_confs() {
  [[ -f "$WG_PRIV_FILE" ]] || { log "Missing $WG_PRIV_FILE"; exit 1; }
  local priv
  priv=$(tr -d '\r\n' <"$WG_PRIV_FILE")
  write_wg_routes
  cat >/etc/wireguard/wg-home1.conf <<EOF
[Interface]
PrivateKey = ${priv}
Address = 10.200.1.${WG_OCTET}/32
PostUp = /etc/wireguard/wg-vps-routes.sh
PostDown = ip rule del to ${VPS1}/32 table 100 2>/dev/null; ip rule del to ${VPS2}/32 table 100 2>/dev/null

[Peer]
PublicKey = ${HUB1_PUB}
AllowedIPs = 0.0.0.0/0
Endpoint = ${VPS1}:51820
PersistentKeepalive = 25
EOF
  cat >/etc/wireguard/wg-home3.conf <<EOF
[Interface]
PrivateKey = ${priv}
Address = 10.200.2.${WG_OCTET}/32
PostUp = /etc/wireguard/wg-vps-routes.sh
PostDown = ip rule del to ${VPS1}/32 table 100 2>/dev/null; ip rule del to ${VPS2}/32 table 100 2>/dev/null

[Peer]
PublicKey = ${HUB2_PUB}
AllowedIPs = 0.0.0.0/0
Endpoint = ${VPS2}:51820
PersistentKeepalive = 25
EOF
  chmod 600 /etc/wireguard/wg-home*.conf
}

write_expected_egress() {
  if [[ ! -f "$EXPECTED_EGRESS_FILE" ]]; then
    cat >"$EXPECTED_EGRESS_FILE" <<'EOF'
# One IP per line (Home-1 / Home-3 WAN). Home-3 from EGRESS-IPS.example.md:
77.242.105.103
EOF
  fi
  chmod 600 "$EXPECTED_EGRESS_FILE"
}

configure_firewall() {
  log "iptables FORWARD policy..."
  sysctl -w net.ipv4.ip_forward=1
  grep -q '^net.ipv4.ip_forward' /etc/sysctl.d/99-wireguard.conf 2>/dev/null || \
    echo 'net.ipv4.ip_forward=1' >/etc/sysctl.d/99-wireguard.conf
  sysctl --system >/dev/null 2>&1 || true

  iptables -C FORWARD -i "$HOSTONLY_DEV" -o "$NAT_DEV" -j DROP 2>/dev/null || \
    iptables -A FORWARD -i "$HOSTONLY_DEV" -o "$NAT_DEV" -j DROP
  iptables -C FORWARD -i "$HOSTONLY_DEV" -o wg+ -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$HOSTONLY_DEV" -o wg+ -j ACCEPT
  iptables -C FORWARD -i wg+ -o "$HOSTONLY_DEV" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i wg+ -o "$HOSTONLY_DEV" -m state --state RELATED,ESTABLISHED -j ACCEPT

  service iptables save 2>/dev/null || iptables-save >/etc/sysconfig/iptables
}

configure_squid() {
  log "Squid on ${HOSTONLY_IP}:3128..."
  cat >/etc/squid/squid.conf <<EOF
acl localnet src ${HOSTONLY_CIDR}
acl adminnet src 192.168.181.0/24
http_port ${HOSTONLY_IP}:3128
http_access allow localnet
http_access allow adminnet
http_access allow localhost
http_access deny all
visible_hostname laptop-gw
EOF
  setsebool -P squid_connect_any 1 2>/dev/null || true
  if command -v semanage >/dev/null; then
    semanage port -a -t squid_port_t -p tcp 3128 2>/dev/null || \
      semanage port -m -t squid_port_t -p tcp 3128 2>/dev/null || true
  fi
  setsebool -P httpd_can_network_connect 1 2>/dev/null || true
  systemctl enable squid
  systemctl stop squid
}

write_egress_check() {
  cat >/usr/local/sbin/egress-check.sh <<'EOF'
#!/bin/bash
set -euo pipefail
EXPECTED=/etc/wireguard/expected-egress.conf
IP=$(curl -4 -s --max-time 12 https://ifconfig.me/ip || true)
[[ -n "$IP" ]] || { systemctl stop squid; exit 0; }
if grep -qxF "$IP" "$EXPECTED"; then
  systemctl start squid
else
  systemctl stop squid
fi
EOF
  chmod 755 /usr/local/sbin/egress-check.sh

  cat >/etc/systemd/system/egress-check.service <<'EOF'
[Unit]
Description=Verify egress IP before enabling Squid
After=network-online.target wg-quick@wg-home3.service wg-quick@wg-home1.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/egress-check.sh
EOF

  cat >/etc/systemd/system/egress-check.timer <<'EOF'
[Unit]
Description=Periodic egress IP check

[Timer]
OnBootSec=45s
OnUnitActiveSec=60s
Persistent=true

[Install]
WantedBy=timers.target
EOF
  systemctl daemon-reload
  systemctl enable --now egress-check.timer
}

harden_sshd() {
  log "sshd baseline..."
  local f=/etc/ssh/sshd_config.d/99-laptop-gw.conf
  cat >"$f" <<'EOF'
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UseDNS no
X11Forwarding no
AllowUsers root
EOF
  restorecon -Rv /root/.ssh 2>/dev/null || true
  chmod 700 /root/.ssh
  [[ -f /root/.ssh/authorized_keys ]] && chmod 600 /root/.ssh/authorized_keys
  systemctl enable --now sshd
  systemctl reload sshd
}

enable_wg_exit() {
  systemctl disable --now wg-quick@wg-home1 2>/dev/null || true
  systemctl disable --now wg-quick@wg-home3 2>/dev/null || true
  if [[ "$DEFAULT_EXIT" == home1 ]]; then
    systemctl enable --now wg-quick@wg-home1
  else
    systemctl enable --now wg-quick@wg-home3
  fi
}

register_note() {
  log "Ensure VPS peers allow 10.200.1.${WG_OCTET}/32 and 10.200.2.${WG_OCTET}/32 (laptop-gw pubkey on hub)."
}

main() {
  [[ $(id -u) -eq 0 ]] || { log "Run as root"; exit 1; }
  detect_ifaces
  install_packages
  write_wg_confs
  write_expected_egress
  harden_sshd
  configure_firewall
  configure_squid
  write_egress_check
  enable_wg_exit
  register_note
  log "Done. Tests: curl -4 ifconfig.me/ip ; curl -4 --proxy http://127.0.0.1:3128 ifconfig.me/ip"
}

main "$@"
