#!/bin/bash
# Если SSH с хоста недоступен: в консоли CentOS (root) или после ручного ssh:
#   curl -fsS http://192.168.181.1:8877/centos/bootstrap-on-vm-console.sh | bash
set -euo pipefail
BASE="${BASE:-http://192.168.181.1:8877}"
curl -fsS "${BASE}/clients/laptop-gw/private.key" -o /root/wg-laptop-gw.private.key
curl -fsS "${BASE}/centos/setup-laptop-gw.sh" -o /root/setup-laptop-gw.sh
chmod 600 /root/wg-laptop-gw.private.key
sed -i 's/\r$//' /root/setup-laptop-gw.sh
bash /root/setup-laptop-gw.sh
