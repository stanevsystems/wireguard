# Ноутбук: CentOS-шлюз + corp VM без прямого интернета

Схема с **октября 2026** (corp split и «прокси только corp-домены на host2» для походного ноутбука **не используются**).

## Цель

- На ноутбуке: **3 corp VM** (2× Win10, 1× Ubuntu) + **1× CentOS без GUI** (шлюз).
- Corp VM **не имеют** собственного выхода в интернет.
- Весь их HTTP(S) — через **прокси на CentOS**, который **принимает соединения только когда** исходящий IP уже идёт через **Home-1** или **Home-3** (exit node + проверка).
- Маскировка: внешний IP и DNS-контур — как у провайдера выбранного дома (не VPS, не Wi‑Fi кафе).

## Топология

```text
┌─ VMware на ноутбуке ─────────────────────────────────────────────┐
│  VMnet-gw (host-only, напр. 192.168.220.0/24)                     │
│    Win10 #1, Win10 #2, Ubuntu corp  →  GW 192.168.220.1         │
│                              │                                    │
│                         [ CentOS gw ]                             │
│                         eth0: .1 (host-only)                      │
│                         eth1: NAT (только для самого CentOS)      │
│                              │                                    │
│                         wg0 / wg1 full tunnel                     │
└──────────────────────────────┼────────────────────────────────────┘
                               ▼
                    VPS-1 (176.32.32.246)  VPS-2 (45.144.30.165)
                               │                    │
                               ▼                    ▼
                         Home-1 exit            Home-3 exit
                         (NAT WAN)             (NAT WAN)
                               │                    │
                               └──────── ISP ────────┘
```

## VMware: сети

| VMnet | Режим | Кто подключён |
|-------|--------|----------------|
| **VMnet-gw** (новый, host-only) | Host-only, **без** DHCP на хосте или DHCP от CentOS | Corp VM + **eth0** CentOS |
| **VMnet8** (или отдельный NAT) | NAT | Только **eth1** CentOS — handshake WG к VPS, обновления CentOS по политике |

**Corp VM:** одна сетевая карта → **только VMnet-gw**. Шлюз `192.168.220.1`, DNS `192.168.220.1` (или прокси-only без DNS наружу — см. CentOS).

**CentOS:**

- `FORWARD`: разрешить `eth0 → wg*`, **запретить** `eth0 → eth1` (corp не уходит в NAT ноутбука).
- Policy routing: маршруты к `176.32.32.246/32` и `45.144.30.165/32` через **eth1** (чтобы туннель не «зарыт» full default через WG).
- Default route: через **активный** WG-интерфейс (один primary exit за раз: Home-1 **или** Home-3).

## WireGuard

| Hub | Подсеть | Exit (primary) | WG IP Home (пример) |
|-----|---------|----------------|---------------------|
| VPN-1 | `10.200.1.0/24` | **Home-1** | `10.200.1.N` |
| VPN-2 | `10.200.2.0/24` | **Home-3** | `10.200.2.2` |

**CentOS (клиент):** octet зарезервировать в `config/PEERS.example.md` (например **5** → `.1.5` / `.2.5`).

На **VPS** у peer exit-узла расширить `AllowedIPs` (см. `scripts/vps-set-exit-peer.sh`). На **Home-1/Home-3** — NAT + forwarding (`scripts/Enable-WindowsWgExitNode.ps1`).

**Клиент CentOS (режим маскировки):** `AllowedIPs = 0.0.0.0/0` на выбранном `[Peer]`; второй туннель — либо down, либо split только `/32` hub для мониторинга (детали в `docs/AGENT-LAPTOP.md`).

## Прокси на CentOS

Рекомендация: **Squid** или **3proxy** (listen `192.168.220.1:3128`, доступ только с `192.168.220.0/24`).

**Gate («активен только когда замaskировано»):**

1. Сервис `egress-check` (timer/cron каждые N сек): `curl -s --interface wg0 https://ifconfig.me` (или свой URL) → сравнить с **ожидаемым** публичным IP Home-1 или Home-3.
2. Если совпало — `systemctl start squid` (или открыть iptables REDIRECT); иначе — **stop** + reject на `:3128`.
3. Опционально: DNS на CentOS (dnsmasq) **upstream только когда** check OK; иначе NXDOMAIN / локальный stub.

Corp VM: системный прокси `http://192.168.220.1:3128` (PAC при необходимости). **Без** второго NIC и **без** bridged Wi‑Fi.

## Что не используем на походном ноутбуке

- Split WG «только /24» для corp.
- Прямой `:3128` на Home-3 с ACL corp-доменов для ноутбука (эталон host2 остаётся для **локальной** истории / других клиентов, если нужно).

## Проверки

| Где | Команда / действие | Ожидание |
|-----|-------------------|----------|
| CentOS | `curl -s --proxy http://127.0.0.1:3128 ifconfig.me` | IP провайдера Home-1 или Home-3 |
| Corp VM | `curl ifconfig.me` **без** прокси | timeout / fail |
| Corp VM | через прокси | тот же домашний IP |
| CentOS | `curl --interface eth1 ifconfig.me` | IP кафе/отеля (только для диагностики leak) |

## Документы для агентов

| Хост | Файл |
|------|------|
| Home-3 (сейчас) | `docs/AGENT-HOME-3.md` |
| Home-1 | `docs/AGENT-HOME-1.md` |
| Походной ноутбук | `docs/AGENT-LAPTOP.md` |
