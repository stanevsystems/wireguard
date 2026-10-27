# Распределение WireGuard IP (ведите здесь)

Две **независимые** /24 (VPN-1 и VPN-2). Один клиент = один octet **N** на обеих сетях.

| Имя | Octet N | VPN-1 `10.200.1.N` | VPN-2 `10.200.2.N` | Роль / где физически |
|-----|---------|--------------------|--------------------|----------------------|
| host2 / Home-3 | 2 | .2 | .2 | Windows HOME-3, **exit VPN-2**, VMware + corp VM |
| host3 | 3 | .3 | .3 | legacy на TECHO-1 (заменить на **laptop** .4) |
| laptop | 4 | .4 | .4 | **TECHO-1** Windows-хост, split /24 |
| laptop-gw | 5 | .5 | .5 | **CentOS** на ноутбуке, WG + прокси для corp VM |
| Home-1 | 6? | … | … | **exit VPN-1** (octet зафиксировать при деплое) |

Регистрация: `scripts/Deploy-WireGuardClient.ps1 -RegisterOnServers` или `scripts/deploy-wireguard-client-macos.sh --register`.

SSH на VPS (с машины, где уже есть ключ): `root@176.32.32.246`, `root@45.144.30.165`.

Публичные ключи **hub** (в клиентских конфигах `[Peer] PublicKey`):

- VPN-1: `As40cjLtsqR9O1Skw4lYw/Pe9YfZBxCzn3rNpie8MTc=`
- VPN-2: `Tm27HQ9uS4TL0zCguamTTLadS8/MnczmCLOsVaJm6Vk=`

Приватные ключи клиентов — только в `wireguard-setup/clients/<имя>/` или `C:\Program Files\WireGuard\…`, **не** коммитить в новые репозитории.
