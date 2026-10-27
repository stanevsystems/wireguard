# Инструкции для AI-агента: Home-3 (Windows, host2)

**Машина:** `Home-3`, эталонный узел **exit NAT** для **VPN-2** (`45.144.30.165`, `10.200.2.0/24`).  
**WG IP:** `10.200.1.2` и `10.200.2.2` (туннели `host2-vpn1` / `host2-vpn2`).  
**Рабочая копия скриптов:** `D:\Exchange\projects\_my_projects\wireguard\` и зеркало `D:\Exchange\projects\wireguard-setup\`.

## Роль в новой схеме

- **Exit node** для клиентов hub VPN-2 (в первую очередь CentOS-шлюз на ноутбуке): трафик `0.0.0.0/0` с VPS приходит на Home-3 и **SNAT** в домашний WAN (`Ethernet`).
- Старый **Host2VpnForwardProxy :3128** для удалённых WG-клиентов **не** является частью походной схемы; не ломать без запроса пользователя (может использоваться локально на Home-3).

## Предусловия

- WireGuard tunnels уже установлены (`install-host2-tunnels.ps1` или conf в `C:\Program Files\WireGuard\Data\Configurations\`).
- SSH с Home-3 к VPS: `root@45.144.30.165`, `root@176.32.32.246` (для правки `wg0.conf` на сервере).
- Агент запускает **PowerShell от администратора** (иначе `wg show` → Permission denied).

## VPS-2: firewalld (relay между peers)

Если CentOS видит **`45.144.30.165`** вместо WAN Home-3: на hub **`wg0` должен быть в `trusted`** (`scripts/vps-fix-wg0-firewalld.sh`). Иначе ping `10.200.2.5` с Home-3 даёт «net unreachable» от `10.200.2.1`.

## Статус на 2026-10-27 (Home-3)

| Шаг | Статус |
|-----|--------|
| VPS-2 peer Home-3 `AllowedIPs = …, 0.0.0.0/0` | **OK** |
| VPS-2 `wg0` → firewalld **trusted** | **OK** (2026-10-27) |
| `Enable-WindowsWgExitNode.ps1 -VpnHub 2` | **OK** (+ `IPEnableRouter`) |
| CentOS + laptop-gw на TECHO-1 | **готово**; ping `10.200.2.5` с Home-3 OK |
| **E2E curl + Squid** | **ждёт проверки с TECHO-1** (SSH-ключ `centos-ssh` не на Home-3) |
| WAN для egress-check | **`77.242.105.103`** → `config/EGRESS-IPS.example.md` |

**Активный чеклист агента:** `docs/NEXT-HOME-3-E2E.md`

## Чеклист подготовки exit (VPN-2)

### 1. VPS VPN-2: маршрут интернета через Home-3

На `45.144.30.165` в `/etc/wireguard/wg0.conf` у peer Home-3 **заменить** строку `AllowedIPs` (публичный ключ host2 — см. `wg show` на Home-3 или `config/host2-vpn2.conf.example`):

```ini
[Peer]
# Home-3 exit
PublicKey = <HOST2_PUBLIC_KEY>
AllowedIPs = 10.200.2.2/32, 0.0.0.0/0
```

Применить:

```bash
wg syncconf wg0 <(wg-quick strip wg0)
# или: systemctl restart wg-quick@wg0
```

Шаблон и пояснения: `scripts/vps-set-exit-peer.sh` (аргумент `2` = VPN-2).

**Важно:** на одном hub только **один** peer с `0.0.0.0/0`. Primary exit для VPN-2 — Home-3.

### 2. Home-3: IP forwarding + NAT

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
D:\Exchange\projects\_my_projects\wireguard\scripts\Enable-WindowsWgExitNode.ps1 -VpnHub 2
```

Скрипт:

- включает forwarding на интерфейсах WireGuard;
- создаёт/обновляет `NetNat` для `10.200.0.0/16` (оба hub-subnet);
- добавляет правила firewall для forward с WG.

Повторный запуск идempotent. После смены адаптеров WAN — проверить `Get-NetNat`.

### 3. Проверка с Home-3

Админ PowerShell:

```powershell
& "C:\Program Files\WireGuard\wg.exe" show
ping 10.200.2.1
```

После появления CentOS на ноутбуке (peer `.2.5` или выбранный octet) — с CentOS `curl ifconfig.me` через full tunnel VPN-2 должен показать **публичный IP провайдера Home-3**, не VPS.

### 4. Зафиксировать публичный IP

Записать текущий WAN IP (для `egress-check` на CentOS):

```powershell
(Invoke-RestMethod -Uri 'https://ifconfig.me/ip' -TimeoutSec 15).Trim()
```

Значение внести в секреты ноутбука / `config/EGRESS-IPS.example.md` (создаёт агент на ноутбуке).

## Не делать без явного запроса

- Не менять `AllowedIPs = 10.200.x.0/24` на **клиентских** conf Home-3, если пользователь не просит full tunnel **с самой** Home-3.
- Не открывать 3128 в интернет/RFC1918 ширше WG без ACL.
- Не коммитить приватные ключи и `proxy-secrets.local.ps1`.

## VMware на Home-3

- VMnet8 / corp VM — **отдельный** контур; exit NAT для WG не подменяет corp-proxy на `.140`.
- Проекты: `wireguard-setup/host2-forward-proxy/`, `_my_projects/cvpn/`.

## Связанные файлы

| Файл | Назначение |
|------|------------|
| `docs/LAPTOP-GW-ARCHITECTURE.md` | Общая схема |
| `docs/AGENT-HOME-1.md` | Зеркало для VPN-1 |
| `docs/AGENT-LAPTOP.md` | CentOS + VMnet |
| `scripts/Enable-WindowsWgExitNode.ps1` | NAT на Windows |
