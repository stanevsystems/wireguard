#!/bin/bash
# VPS-2 (and VPS-1): wg0 must be in firewalld trusted zone or hub cannot relay between peers / exit.
set -euo pipefail
command -v firewall-cmd >/dev/null || { echo 'firewalld not installed'; exit 1; }
firewall-cmd --permanent --zone=trusted --add-interface=wg0
firewall-cmd --reload
firewall-cmd --get-zone-of-interface=wg0
echo 'OK: wg0 in trusted (forward between peers, exit relay).'
