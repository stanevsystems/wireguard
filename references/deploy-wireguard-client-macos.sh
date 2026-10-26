#!/usr/bin/env bash
# Разворачивает два split-tunnel WireGuard (VPN-1 + VPN-2) на macOS.
# Запуск: sudo ./deploy-wireguard-client-macos.sh --name macbook --octet 5 --register
#
# Требования: SSH root@176.32.32.246 и root@45.144.30.165 (для --register).
# Установит wireguard-tools через Homebrew, если нет wg.

set -euo pipefail

VPN1_SERVER='176.32.32.246'
VPN2_SERVER='45.144.30.165'
VPN1_SUBNET='10.200.1'
VPN2_SUBNET='10.200.2'
VPN1_HUB_PUB='As40cjLtsqR9O1Skw4lYw/Pe9YfZBxCzn3rNpie8MTc='
VPN2_HUB_PUB='Tm27HQ9uS4TL0zCguamTTLadS8/MnczmCLOsVaJm6Vk='
LISTEN_PORT='51820'
KEEPALIVE='25'
WG_DIR='/etc/wireguard'
LAUNCHD_PREFIX='com.wireguard.dual'

CLIENT_NAME=''
HOST_OCTET=''
REGISTER='0'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR=''

usage() {
  cat <<'EOF'
Usage:
  sudo ./deploy-wireguard-client-macos.sh --name NAME --octet N [--register]

  --name NAME    Имя хоста (латиница), туннели: NAME-vpn1, NAME-vpn2
  --octet N      Последний октет (host2=2 → 10.200.1.2 и 10.200.2.2)
  --register     Добавить peer на оба VPS по SSH

Example:
  sudo ./deploy-wireguard-client-macos.sh --name macbook --octet 5 --register
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) CLIENT_NAME="$2"; shift 2 ;;
    --octet) HOST_OCTET="$2"; shift 2 ;;
    --register) REGISTER='1'; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1"; usage ;;
  esac
done

[[ -n "$CLIENT_NAME" && "$CLIENT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || usage
[[ -n "$HOST_OCTET" && "$HOST_OCTET" -ge 2 && "$HOST_OCTET" -le 254 ]] || usage

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Запустите с sudo." >&2
  exit 1
fi

STATE_DIR="${SCRIPT_DIR}/clients/${CLIENT_NAME}"
mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

ensure_wg() {
  if command -v wg >/dev/null 2>&1 && command -v wg-quick >/dev/null 2>&1; then
    return
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "Установите Homebrew или wireguard-tools вручную." >&2
    exit 1
  fi
  echo "Установка wireguard-tools..."
  sudo -u "${SUDO_USER:-$(whoami)}" brew install wireguard-tools
}

ensure_wg
WG_QUICK="$(command -v wg-quick)"
WG_BIN="$(command -v wg)"

get_or_create_keys() {
  local priv pub
  if [[ -f "${STATE_DIR}/private.key" && -f "${STATE_DIR}/public.key" ]]; then
    priv="$(cat "${STATE_DIR}/private.key")"
    pub="$(cat "${STATE_DIR}/public.key")"
  else
    priv="$("$WG_BIN" genkey)"
    pub="$(printf '%s' "$priv" | "$WG_BIN" pubkey)"
    printf '%s' "$priv" > "${STATE_DIR}/private.key"
    printf '%s' "$pub" > "${STATE_DIR}/public.key"
    chmod 600 "${STATE_DIR}/private.key"
  fi
  CLIENT_PRIV="$priv"
  CLIENT_PUB="$pub"
}

write_conf() {
  local file="$1" priv="$2" addr="$3" hub_pub="$4" allowed="$5" endpoint="$6"
  cat > "$file" <<EOF
[Interface]
PrivateKey = ${priv}
Address = ${addr}/32

[Peer]
PublicKey = ${hub_pub}
AllowedIPs = ${allowed}
Endpoint = ${endpoint}:${LISTEN_PORT}
PersistentKeepalive = ${KEEPALIVE}
EOF
  chmod 600 "$file"
}

register_peer() {
  local ssh_host="$1" pub="$2" ip32="$3" comment="$4"
  ssh -o BatchMode=yes -o ConnectTimeout=15 "root@${ssh_host}" bash -s <<REMOTE
set -euo pipefail
CONF=/etc/wireguard/wg0.conf
PUB='${pub}'
IP='${ip32}'
if grep -q "\${PUB}" "\${CONF}" 2>/dev/null; then
  wg set wg0 peer "\${PUB}" allowed-ips "\${IP}" 2>/dev/null || true
  exit 0
fi
wg set wg0 peer "\${PUB}" allowed-ips "\${IP}"
printf '\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s\n' '${comment}' "\${PUB}" "\${IP}" >> "\${CONF}"
REMOTE
  echo "Peer на ${ssh_host} → ${ip32}"
}

install_launchdaemon() {
  local tunnel="$1"
  local plist="/Library/LaunchDaemons/${LAUNCHD_PREFIX}.${tunnel}.plist"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHD_PREFIX}.${tunnel}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${WG_QUICK}</string>
    <string>up</string>
    <string>${tunnel}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>/var/log/wireguard-${tunnel}.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/wireguard-${tunnel}.err</string>
</dict>
</plist>
EOF
  chmod 644 "$plist"
  launchctl bootout "system/${LAUNCHD_PREFIX}.${tunnel}" 2>/dev/null || true
  launchctl bootstrap system "$plist"
  launchctl enable "system/${LAUNCHD_PREFIX}.${tunnel}"
  launchctl kickstart -k "system/${LAUNCHD_PREFIX}.${tunnel}" || "$WG_QUICK" up "$tunnel"
}

get_or_create_keys
IP1="${VPN1_SUBNET}.${HOST_OCTET}"
IP2="${VPN2_SUBNET}.${HOST_OCTET}"

if [[ "$REGISTER" == '1' ]]; then
  register_peer "$VPN1_SERVER" "$CLIENT_PUB" "${IP1}/32" "${CLIENT_NAME} (macOS)"
  register_peer "$VPN2_SERVER" "$CLIENT_PUB" "${IP2}/32" "${CLIENT_NAME} (macOS)"
else
  echo "WARNING: peer на серверах не добавлены. Запустите с --register или добавьте вручную:"
  echo "  PublicKey: ${CLIENT_PUB}"
  echo "  VPN-1: ${IP1}/32"
  echo "  VPN-2: ${IP2}/32"
fi

mkdir -p "$WG_DIR"
T1="${CLIENT_NAME}-vpn1"
T2="${CLIENT_NAME}-vpn2"

write_conf "${WG_DIR}/${T1}.conf" "$CLIENT_PRIV" "$IP1" "$VPN1_HUB_PUB" "${VPN1_SUBNET}.0/24" "$VPN1_SERVER"
write_conf "${WG_DIR}/${T2}.conf" "$CLIENT_PRIV" "$IP2" "$VPN2_HUB_PUB" "${VPN2_SUBNET}.0/24" "$VPN2_SERVER"

cp "${WG_DIR}/${T1}.conf" "${STATE_DIR}/"
cp "${WG_DIR}/${T2}.conf" "${STATE_DIR}/"

"$WG_QUICK" down "$T1" 2>/dev/null || true
"$WG_QUICK" down "$T2" 2>/dev/null || true
"$WG_QUICK" up "$T1"
"$WG_QUICK" up "$T2"

install_launchdaemon "$T1"
install_launchdaemon "$T2"

echo ""
echo "=== wg show ==="
"$WG_BIN" show
echo ""
ping -c 2 "${VPN1_SUBNET}.1" || true
ping -c 2 "${VPN2_SUBNET}.1" || true
echo ""
echo "Готово. Автозапуск: LaunchDaemons ${LAUNCHD_PREFIX}.${T1} / ${T2}"
echo "Ключи и копии: ${STATE_DIR}"
