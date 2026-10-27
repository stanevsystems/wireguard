# Статус Windows-хоста (TECHO-1)

Обновлено: 2026-10-26. **VMware не меняли** — corp VM по-прежнему через провайдера (VMnet8 и т.д.).

## Скрипт Prepare-LaptopHost (2026-10-27)

Если после `Start-Process powershell -Verb RunAs ...` по-прежнему **host3-vpn1/vpn2** — вложенный `Start-Process` открыл **второе** окно и закрыл его; результат не виден. Запускайте **в том же** elevated-окне:

```powershell
cd D:\exchange\projects\_my_projects\wireguard\scripts
.\Run-Prepare-LaptopHost-Logged.ps1 -RegisterOnServers -RetireHost3Tunnels
notepad ..\docs\prepare-laptop-host.log
```

## Сделано на хосте (2026-10-27)

| Компонент | Статус |
|-----------|--------|
| **laptop-vpn2** | Running, peer `.2.4` на VPS-2 |
| **laptop-vpn1** | Running; VPS-1 не используем — handshake нет |
| **host3-*** | удалены |
| Prepare-LaptopHost | выполнен (admin PS + ssh-agent) |

## Ранее

| Компонент | Статус |
|-----------|--------|
| WireGuard | Установлен |
| Доступ к hub split-tunnel | **host3-vpn1/vpn2** (10.200.1.3 / 10.200.2.3), ping hub OK |
| Ключи **laptop-gw** (octet 5, CentOS) | `scripts/clients/laptop-gw/` + шаблоны `centos/` |
| Ключи **laptop** (octet 4, хост) | `scripts/clients/laptop/` |
| Скрипт подготовки | `scripts/Prepare-LaptopHost.ps1` |

## Осталось (нужны права администратора + SSH к VPS)

Запуск **от администратора** (PowerShell):

```powershell
Start-Process powershell -Verb RunAs -Wait -ArgumentList @(
  '-NoProfile','-ExecutionPolicy','Bypass',
  '-File','D:\exchange\projects\_my_projects\wireguard\scripts\Prepare-LaptopHost.ps1',
  '-RegisterOnServers','-RetireHost3Tunnels'
)
```

Это:

1. Добавит peer **laptop-gw** (.1.5 / .2.5) и **laptop** (.1.4 / .2.4) на оба VPS.
2. Поставит split-tunnel **laptop-vpn1/vpn2** на хост вместо legacy **host3-***.
3. Остановит службы WG для laptop-gw на Windows (WG для corp — только на CentOS).

Если SSH к VPS ещё не настроен: один раз `ssh root@176.32.32.246` / `root@45.144.30.165`, затем повторить команду с `-RegisterOnServers`.

Публичные ключи (для ручной регистрации на VPS, если нет SSH):

| Peer | PublicKey |
|------|-----------|
| laptop-gw (.5) | `Zvea0uRRvDJCZAa7OXWHoAVlbeEUt7PnEvp0O1PMODw=` |
| laptop (.4) | `evgkLEoUtqS9BqZmlthBwpKIS2GI4wAku1rC13vUHHM=` |

Файлы: `scripts/clients/*/public.key`

## Не трогаем (по договорённости)

- Virtual Network Editor / VMnet-gw
- Сетевые настройки corp VM в VMware

## Следующий шаг

CentOS-шлюз: `docs/AGENT-LAPTOP.md` (§2 WireGuard, §3 firewall, §4 Squid + egress-check).
