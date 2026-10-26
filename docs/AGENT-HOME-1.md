# Инструкции для AI-агента: Home-1

**Машина:** стационарный Windows или Linux в РФ (уточнить у пользователя имя хоста и ОС).  
**Роль:** **exit node** для **VPN-1** (`176.32.32.246`, `10.200.1.0/24`).  
**Симметрия:** Home-3 обслуживает VPN-2; Home-1 — VPN-1.

## Предусловия

- Уникальный **octet** в `config/PEERS.example.md` (рекомендация: **1** → `10.200.1.1` занят hub, клиент **`10.200.1.1` нельзя**; использовать **N=6** или другой свободный).
- Установка WG: `D:\Exchange\projects\wireguard-setup\Deploy-WireGuardClient.ps1 -ClientName home1 -HostOctet <N> -RegisterOnServers` (Windows) или `deploy-wireguard-client-macos.sh` / `wg-quick` на Linux.

## Чеклист (параллельно Home-3)

### 1. Регистрация peer на обоих VPS

Скрипт деплоя создаёт `10.200.1.N` и `10.200.2.N`. Для **exit VPN-1** критичен hub **176.32.32.246**; второй туннель можно держать split `/24` для резерва/диагностики.

### 2. VPS VPN-1: exit через Home-1

На `176.32.32.246`, `/etc/wireguard/wg0.conf`:

```ini
[Peer]
# Home-1 exit
PublicKey = <HOME1_PUBLIC_KEY>
AllowedIPs = 10.200.1.N/32, 0.0.0.0/0
```

Применить `wg syncconf` или restart `wg-quick@wg0`. Шаблон: `scripts/vps-set-exit-peer.sh 1`.

### 3. NAT на Home-1

**Windows** (как Home-3):

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
D:\Exchange\projects\_my_projects\wireguard\scripts\Enable-WindowsWgExitNode.ps1 -VpnHub 1
```

**Linux** (если Home-1 — не Windows):

```bash
sysctl -w net.ipv4.ip_forward=1
# WAN=eth0, WG=wg0 — подставить фактические имена
iptables -t nat -A POSTROUTING -o "$WAN" -j MASQUERADE
iptables -A FORWARD -i wg0 -o "$WAN" -j ACCEPT
iptables -A FORWARD -i "$WAN" -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

Сохранить правила через `firewalld`/`nftables` persistent по политике хоста.

### 4. Публичный IP для egress-check

Снять `(Invoke-RestMethod https://ifconfig.me/ip)` или `curl -4 ifconfig.me` на Home-1, передать значение для конфига CentOS (см. `config/EGRESS-IPS.example.md`).

### 5. Проверка

- С ноутбука (CentOS): профиль **Egress-Home-1** — full tunnel только VPN-1, `curl ifconfig.me` = IP Home-1.
- Ping `10.200.1.1`, `wg show` latest handshake.

## Отличия от Home-3

| | Home-1 | Home-3 |
|---|--------|--------|
| Primary exit hub | VPN-1 | VPN-2 |
| VPS | 176.32.32.246 | 45.144.30.165 |
| WG IP (host2 эталон) | N/A (свой octet) | `.1.2`, `.2.2` |
| VMware corp | по месту | эталон corp-proxy |

## Не делать

- Не назначать второму peer на **том же** VPS `AllowedIPs = 0.0.0.0/0` (конфликт маршрутизации на hub).
- Не публиковать ключи в git.

## Связанные документы

- `docs/LAPTOP-GW-ARCHITECTURE.md`
- `docs/AGENT-HOME-3.md`
- `docs/AGENT-LAPTOP.md`
