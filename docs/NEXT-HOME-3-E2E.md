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
| CentOS SSH агента | `scripts/clients/centos-ssh/id_ed25519` |

**Симптом блокера:** с CentOS `curl ifconfig.me` → **`45.144.30.165`** (VPS), нужно **`77.242.105.103`**.

## Задачи агента на Home-3 (выполнить на машине Home-3)

- [ ] **1. WireGuard:** службы `WireGuardTunnel$host2-vpn1/vpn2` Running; `wg show` — handshake на **45.144.30.165** / **10.200.2.1**.
- [ ] **2. Exit NAT:** Admin PS: `scripts/Enable-WindowsWgExitNode.ps1 -VpnHub 2` (повторно, idempotent).
- [ ] **3. VPS-2 peer Home-3:** в `/etc/wireguard/wg0.conf` у **Home-3** (10.200.2.2): `AllowedIPs = 10.200.2.2/32, 0.0.0.0/0`. У **laptop-gw** (10.200.2.5): **только** `10.200.2.5/32` (без `0.0.0.0/0`). Один peer с `0.0.0.0/0` на hub.
- [ ] **4. VPS-2 forwarding:** `sysctl net.ipv4.ip_forward=1`; при необходимости iptables/nft forward (обычно wg уже маршрутизирует к exit peer).
- [ ] **5. WAN IP:** `(Invoke-RestMethod https://ifconfig.me/ip).Trim()` — сверить с **77.242.105.103**; если ISP сменился — сообщить, обновить `/etc/wireguard/expected-egress.conf` на CentOS.
- [ ] **6. E2E:** когда пункты 1–4 OK — с CentOS (SSH `root@192.168.181.182` с ноутбука или попросить агента на TECHO-1):
  ```bash
  systemctl restart wg-quick@wg-home3
  curl -4 -s https://ifconfig.me/ip
  /usr/local/sbin/egress-check.sh && systemctl is-active squid
  curl -4 -s --proxy http://192.168.72.128:3128 https://ifconfig.me/ip
  ```
  Ожидание: оба curl → **Home-3 WAN**, Squid **active**.

## Не в scope сейчас

- VPS-1 / Home-1 / laptop-vpn1
- VMware VMnet-gw / перенос corp VM на host-only (на ноутбуке VM пока через провайдера)

## После E2E

- Corp VM: системный прокси `http://192.168.72.128:3128` (когда подключат к host-only **ens192** / 72.0/24).
