# Следующий шаг: Home-3 (E2E VPN-2 only)

**Контекст:** 2026-10-27. Схема **без Home-1 / VPS-1**. Рабочая цепочка:

```text
corp VM (позже) → CentOS :3128 (192.168.72.128) → wg-home3 full tunnel
  → VPS-2 (45.144.30.165) → Home-3 exit NAT → ISP (77.242.105.103)
```

## Уже готово (ноутбук TECHO-1)

| Компонент | Статус |
|-----------|--------|
| Windows **laptop-vpn2** (10.200.2.4) | peer на VPS-2, hub ping OK |
| **laptop-vpn1** | без VPS-1 — handshake нет (ожидаемо) |
| Legacy **host3-*** | сняты |
| **CentOS** wg-home3 (10.200.2.5) | peer на VPS-2, handshake OK |
| CentOS Squid + egress-check | установлены; Squid **off** пока egress ≠ 77.242.105.103 |
| CentOS SSH агента | `scripts/clients/centos-ssh/id_ed25519` (на **TECHO-1**, не на Home-3) |

**Симптом блокера (был):** с CentOS `curl ifconfig.me` → **`45.144.30.165`** (VPS), нужно **`77.242.105.103`**.

**Исправление 2026-10-27 (Home-3):** на VPS-2 интерфейс **`wg0` не был в зоне firewalld** (`no zone` + `masquerade` на `public`) — hub не relay'ил трафик между peers, часть шла SNAT на VPS. Добавлено: `firewall-cmd --zone=trusted --add-interface=wg0` (+ PostUp в `/etc/wireguard/wg0.conf`). После этого **ping 10.200.2.5** с Home-3 и с VPS OK.

## Задачи агента на Home-3

- [x] **1. WireGuard:** службы `WireGuardTunnel$host2-vpn1/vpn2` Running; `wg show` — handshake на **45.144.30.165** / **10.200.2.1** (host2-vpn2).
- [x] **2. Exit NAT:** `Enable-WindowsWgExitNode.ps1 -VpnHub 2` (+ `IPEnableRouter`, forward rules).
- [x] **3. VPS-2 peer Home-3:** `10.200.2.2/32, 0.0.0.0/0`; laptop-gw **только** `10.200.2.5/32`.
- [x] **4. VPS-2 forwarding:** `ip_forward=1`; **wg0 → trusted** (`scripts/vps-fix-wg0-firewalld.sh`).
- [x] **5. WAN IP Home-3:** **77.242.105.103** (без изменений).
- [ ] **6. E2E curl + Squid:** выполнить **с TECHO-1** (есть ключ `centos-ssh`) или скопировать ключ на Home-3:

```bash
# Git Bash / TECHO-1 или Home-3 после scp ключа
ssh -i scripts/clients/centos-ssh/id_ed25519 root@10.200.2.5 'systemctl restart wg-quick@wg-home3; sleep 2; curl -4 -s https://ifconfig.me/ip; /usr/local/sbin/egress-check.sh; systemctl is-active squid; curl -4 -s --proxy http://192.168.72.128:3128 https://ifconfig.me/ip'
```

Ожидание: оба curl → **77.242.105.103**, Squid **active**.

Альтернатива с LAN ноутбука:

```bash
ssh -i scripts/clients/centos-ssh/id_ed25519 root@192.168.181.182 '... те же команды ...'
```

## Не в scope сейчас

- VPS-1 / Home-1 / laptop-vpn1
- VMware VMnet-gw / перенос corp VM на host-only (на ноутбуке VM пока через провайдера)

## После E2E

- Corp VM: системный прокси `http://192.168.72.128:3128` (когда подключат к host-only **ens192** / 72.0/24).
