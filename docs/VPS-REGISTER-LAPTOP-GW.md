# Регистрация laptop-gw на VPS (если с ноутбука нет SSH root)

**PublicKey CentOS (laptop-gw):** `Zvea0uRRvDJCZAa7OXWHoAVlbeEUt7PnEvp0O1PMODw=`

## VPN-2 (обязательно для wg-home3) — `45.144.30.165`

Выполнить **на Home-3** или любой машине, где уже есть `ssh root@45.144.30.165`:

```bash
PUB='Zvea0uRRvDJCZAa7OXWHoAVlbeEUt7PnEvp0O1PMODw='
IP='10.200.2.5/32'
ssh root@45.144.30.165 "wg set wg0 peer \$PUB allowed-ips \$IP; grep -q \"\$PUB\" /etc/wireguard/wg0.conf || printf '\n[Peer]\n# laptop-gw CentOS\nPublicKey = %s\nAllowedIPs = %s\n' \$PUB \$IP >> /etc/wireguard/wg0.conf"
```

## VPN-1 (позже, для wg-home1) — `176.32.32.246`

```bash
PUB='Zvea0uRRvDJCZAa7OXWHoAVlbeEUt7PnEvp0O1PMODw='
IP='10.200.1.5/32'
ssh root@176.32.32.246 "wg set wg0 peer \$PUB allowed-ips \$IP; grep -q \"\$PUB\" /etc/wireguard/wg0.conf || printf '\n[Peer]\n# laptop-gw CentOS\nPublicKey = %s\nAllowedIPs = %s\n' \$PUB \$IP >> /etc/wireguard/wg0.conf"
```

**Не** добавляйте `0.0.0.0/0` для laptop-gw — exit только у Home-1/Home-3.

После VPN-2 на CentOS: `systemctl restart wg-quick@wg-home3` → `wg show` должен показать **received > 0**.
