# CentOS-Router (192.168.181.182) — статус

Обновлено: 2026-10-27.

## Сеть (как в VMware)

| NIC | Интерфейс | Подсеть | Роль |
|-----|-----------|---------|------|
| NAT | **ens160** | 192.168.181.0/24 | Handshake WG к VPS, SSH с хоста |
| Host-only | **ens192** | 192.168.72.0/24 | Corp VM → прокси **192.168.72.128:3128** |

## Сделано

- Bootstrap вариант A, SSH агента: `scripts/clients/centos-ssh/id_ed25519`
- Пакеты, iptables FORWARD, egress-check.timer, sshd drop-in
- **wg-quick@wg-home3** — исправлен PostUp (в `[Interface]`), туннель **active**
- Policy routing к VPS через **ens160** (table 100) — OK

## Peer laptop-gw на VPS-2

**Сделано (2026-10-27):** handshake OK, `10.200.2.5` на hub.

## Блокер egress (Home-3 exit)

`curl ifconfig.me` с CentOS → **`45.144.30.165`** (IP VPS), нужно **`77.242.105.103`** (Home-3).  
Squid **inactive** — egress-check отключает прокси, пока IP не совпадает.

Проверить на **Home-3**: подняты `host2-vpn2`, `Enable-WindowsWgExitNode.ps1 -VpnHub 2`, на VPS-2 у peer Home-3 `AllowedIPs = 10.200.2.2/32, 0.0.0.0/0` (см. `docs/AGENT-HOME-3.md`).

**PowerShell от администратора** (не терминал Cursor):

```powershell
cd D:\exchange\projects\_my_projects\wireguard\scripts
.\Deploy-WireGuardClient.ps1 -ClientName laptop-gw -HostOctet 5 -RegisterOnServers
Get-Service WireGuardTunnel$laptop-gw* | Stop-Service -Force
Get-Service WireGuardTunnel$laptop-gw* | Set-Service -StartupType Manual
```

Затем на CentOS (или напишите агенту):

```bash
systemctl restart wg-quick@wg-home3
/usr/local/sbin/egress-check.sh
curl -4 -s https://ifconfig.me/ip   # ~77.242.105.103
curl -4 -s --proxy http://192.168.72.128:3128 https://ifconfig.me/ip
```

## Prepare-LaptopHost на Windows-хосте

`Run-Prepare-LaptopHost-Logged.ps1` в обычном PS **не elevated** — скрипт не запускался. Нужно окно **«От имени администратора»** (скрипт теперь пишет явную ошибку).
