# Установка WireGuard на VPS (hub)

Уже выполнено на обоих серверах; ниже — воспроизведение.

## Серверы

| Имя | SSH | Подсеть |
|-----|-----|---------|
| VPN-1 | `root@176.32.32.246` | `10.200.1.1/24` |
| VPN-2 | `root@45.144.30.165` | `10.200.2.1/24` |

## Скрипт

Из Git Bash на машине с SSH-ключом:

```bash
(Get-Content /d/Exchange/projects/wireguard-setup/setup-server1.sh -Raw).Replace("`r`n","`n") | ssh root@176.32.32.246 "bash -s"
(Get-Content /d/Exchange/projects/wireguard-setup/setup-server2.sh -Raw).Replace("`r`n","`n") | ssh root@45.144.30.165 "bash -s"
```

Копии: `_my_projects/wireguard/scripts/setup-server1.sh`, `setup-server2.sh`.

## Firewall

Один раз на каждом VPS:

```bash
firewall-cmd --zone=public --add-port=51820/udp --permanent
firewall-cmd --reload
```

## Peers

Добавление клиента:

```bash
wg set wg0 peer '<CLIENT_PUBKEY>' allowed-ips 10.200.1.N/32
# и persist в /etc/wireguard/wg0.conf
```

Или автоматически с Windows: `-RegisterOnServers` в `Deploy-WireGuardClient.ps1`.

## Проверка

```bash
systemctl status wg-quick@wg0
wg show wg0
```
