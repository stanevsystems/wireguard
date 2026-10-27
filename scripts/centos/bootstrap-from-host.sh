#!/usr/bin/env bash
# Запуск из Git Bash на ноутбуке (один раз введите passphrase для ~/.ssh/id_ed25519).
set -euo pipefail
HOST="${1:-192.168.181.182}"
BASE="http://192.168.181.1:8877"
AGENT_PUB='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIM7XyByhBX+8djs2g9I4Ne5OkuRd590MqNxXTbPMNTZ1 stane@TECHO-1'

ssh "root@${HOST}" "grep -qF '${AGENT_PUB}' /root/.ssh/authorized_keys 2>/dev/null || { mkdir -p /root/.ssh; echo '${AGENT_PUB}' >> /root/.ssh/authorized_keys; chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys; restorecon -Rv /root/.ssh 2>/dev/null || true; }"

ssh "root@${HOST}" "curl -fsS ${BASE}/clients/laptop-gw/private.key -o /root/wg-laptop-gw.private.key && \
  curl -fsS ${BASE}/centos/setup-laptop-gw.sh -o /root/setup-laptop-gw.sh && \
  chmod 600 /root/wg-laptop-gw.private.key && sed -i 's/\\r\$//' /root/setup-laptop-gw.sh && bash /root/setup-laptop-gw.sh"

echo "Bootstrap finished on ${HOST}"
