# Инструкции для AI-агента: походной ноутбук

**Хост:** Ubuntu (или Windows) с **VMware Workstation**.  
**Гости:** 2× Win10, 1× Ubuntu (corp) + **1× CentOS Stream minimal** (шлюз, без GUI).

Полная схема: `docs/LAPTOP-GW-ARCHITECTURE.md`.

## Итоговое поведение

| VM | Сеть | Интернет |
|----|------|----------|
| Win10 / Ubuntu corp | Только **host-only** VMnet-gw | Только HTTP(S) через прокси CentOS |
| CentOS gw | eth0 host-only + eth1 NAT | WG к VPS; default через exit Home-1 **или** Home-3 |

## 1. VMware

1. **Edit → Virtual Network Editor**
   - Добавить **VMnet10** (имя условное): **Host-only**, подсеть **`192.168.220.0/24`**, **не** подключать corp VM к VMnet8/bridged.
2. **CentOS VM**
   - NIC1: Custom → VMnet10.
   - NIC2: NAT (VMnet8) — **только** для CentOS.
3. **Каждая corp VM**
   - Одна NIC → VMnet10.
   - В госте: IP DHCP от CentOS или static /24, GW **`192.168.220.1`**, DNS **`192.168.220.1`** (если поднимаете dnsmasq на шлюзе).

## 2. CentOS: WireGuard

- Octet **5** (или из `config/PEERS.example.md`): адреса `10.200.1.5/32`, `10.200.2.5/32`.
- Регистрация ключей на VPS — с машины, где есть `root@` SSH (`Deploy-WireGuardClient.ps1` не обязателен; можно `wg genkey` + правка `wg0.conf` на серверах).

Два конфига (пример путей):

- `/etc/wireguard/wg-home1.conf` — peer VPN-1, **`AllowedIPs = 0.0.0.0/0`**, `Endpoint = 176.32.32.246:51820`
- `/etc/wireguard/wg-home3.conf` — peer VPN-2, **`AllowedIPs = 0.0.0.0/0`**, `Endpoint = 45.144.30.165:51820`

**Policy routing** (обязательно, иначе full tunnel отрежет UDP к Endpoint):

```bash
# /etc/wireguard/wg-vps-routes.sh — вызывать PostUp обоих профилей
VPS1=176.32.32.246
VPS2=45.144.30.165
DEV_NAT=eth1
ip rule add to ${VPS1}/32 table 100
ip rule add to ${VPS2}/32 table 100
ip route add default via $(ip -4 route show dev ${DEV_NAT} | awk '/default/ {print $3}') dev ${DEV_NAT} table 100
```

На **активном** профиле exit: `PostUp = ip route replace default dev wg0` (или `wg-home3` → `dev wg-home3`).

**Один активный exit:** не поднимать оба `0.0.0.0/0` одновременно без `ip rule`/`fwmark`. Рекомендация: unit `wg-quick@wg-home3` **или** `wg-home1` (переключатель для пользователя).

## 3. CentOS: firewall

```bash
# corp → tunnel only
iptables -A FORWARD -i eth0 -o eth1 -j DROP
iptables -A FORWARD -i eth0 -o wg+ -j ACCEPT
iptables -A FORWARD -i wg+ -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

Сохранить через `iptables-services` / nftables set.

## 4. CentOS: egress-check + Squid

1. Файл ожидаемых IP: `/etc/wireguard/expected-egress.conf` (из Home-1 / Home-3, см. `config/EGRESS-IPS.example.md`).
2. Timer `egress-check.service`:
   - `curl -4 -s --max-time 10 https://ifconfig.me/ip` (трафик пойдёт через default = WG).
   - если IP в списке → `systemctl start squid`; иначе → `systemctl stop squid`.
3. **Squid** `http_port 192.168.220.1:3128`, ACL `src 192.168.220.0/24`.

Corp Windows: параметры прокси → `192.168.220.1:3128`. Ubuntu guest: `HTTP_PROXY` / `auto-proxy`.

## 5. Проверки (агент выполняет и фиксирует в отчёте)

```bash
# на CentOS
curl -s ifconfig.me/ip          # домашний IP
curl -s --proxy http://127.0.0.1:3128 ifconfig.me/ip
ip rule list; ip route show table main
```

На corp VM без прокси — ошибка; с прокси — тот же IP.

## 6. Автозапуск

- `enable wg-quick@wg-home3` (или home1).
- `egress-check.timer`, `squid` (controlled by check).
- VMware: CentOS **Start with host** раньше corp VM (или dependency в `.vmx` / manual order).

## 7. Связь с репозиторием

| Действие | Путь |
|----------|------|
| Обновить octet | `config/PEERS.example.md` |
| Деплой WG Windows (если хост ноутбука Windows) | `wireguard-setup/Deploy-WireGuardClient.ps1` |
| Exit на домах | `docs/AGENT-HOME-1.md`, `docs/AGENT-HOME-3.md` |

## Не делать

- Bridged Wi‑Fi на corp VM.
- Split `/24` как основной режим маскировки.
- Полагаться только на PAC без блокировки direct egress с corp VM (firewall guest или только host-only).
