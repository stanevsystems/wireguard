# WireGuard: домашние exit + CentOS-шлюз на ноутбуке

Сжатый «пакет смысла» для человека и для нового диалога с AI. Реализация host2 (3proxy, corp-proxy, v2rayN) — **`d:\Exchange\projects\wireguard-setup\`**. Актуальная **походная** схема — ниже и в **`docs/LAPTOP-GW-ARCHITECTURE.md`**.

## Зачем (с 2026-10-26)

На ноутбуке в VMware: **corp VM без прямого интернета** (host-only) → **CentOS-шлюз** (два WG, full tunnel через дом) → **Home-1 / Home-3** (NAT в ISP) → интернет с **домашним IP и DNS-контуром**. Прокси на CentOS **включается только** после проверки egress IP.

Corp split и удалённый `:3128` с ACL на Home-3 для ноутбука **больше не целевой путь**.

## Что уже на VPS / Home-3

| Компонент | Статус |
|-----------|--------|
| VPN-1 `176.32.32.246`, VPN-2 `45.144.30.165` | `wg0`, UDP **51820**, `10.200.1.0/24`, `10.200.2.0/24` |
| **Home-3** (host2) | WG `.1.2` / `.2.2`; подготовка **exit VPN-2** — `docs/AGENT-HOME-3.md` |
| **Home-1** | exit VPN-1 — `docs/AGENT-HOME-1.md` |
| CentOS laptop-gw | octet **5** — `docs/AGENT-LAPTOP.md` |

## Схема

```text
[ Corp Win10 / Ubuntu ×3 ] ── host-only ──► [ CentOS gw :3128 + WG ]
                                                  │
                    ┌─────────────────────────────┴─────────────────────────────┐
                    ▼                                                           ▼
            VPS-1 → Home-1 exit                                      VPS-2 → Home-3 exit
```

## Инструкции для AI-агентов

| Машина | Документ |
|--------|----------|
| Home-3 | **`docs/AGENT-HOME-3.md`** |
| Home-1 | **`docs/AGENT-HOME-1.md`** |
| Походной ноутбук | **`docs/AGENT-LAPTOP.md`** |
| Общий контекст | **`AGENT-CONTEXT.md`** |

## Структура каталога

| Путь | Назначение |
|------|------------|
| **`docs/LAPTOP-GW-ARCHITECTURE.md`** | Целевая архитектура ноутбука |
| **`docs/AGENT-*.md`** | Runbook по хостам |
| **`docs/TARGET-ARCHITECTURE.md`** | Предыдущая corp-split схема (история) |
| **`docs/DEPRECATED-PLANS.md`** | Отвергнутые ветки |
| **`scripts/Enable-WindowsWgExitNode.ps1`** | NAT exit на Windows |
| **`scripts/vps-set-exit-peer.sh`** | Peer exit на VPS |
| **`config/`** | Peers, пример egress IP |

## Быстрые команды (Home-3, админ)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
D:\Exchange\projects\_my_projects\wireguard\scripts\Enable-WindowsWgExitNode.ps1 -VpnHub 2
& "C:\Program Files\WireGuard\wg.exe" show
```

VPS VPN-2: см. **`scripts/vps-set-exit-peer.sh`** и **`docs/AGENT-HOME-3.md`**.

## Безопасность

- В **`config/*.example`** могут быть ключи — не публиковать каталог.
- Ожидаемые WAN IP — **`config/EGRESS-IPS.example.md`** (шаблон).

## Связанные проекты

- Corp VPN в VM: **`_my_projects/cvpn/`**
- Legacy host2 proxy: **`wireguard-setup/host2-forward-proxy/`**
