# Устаревшие планы (не развивать)

Зафиксировано, чтобы новый диалог не возвращался к отвергнутым веткам.

## Corp split + прокси на Home-3 для походного ноутбука

- **Было:** `AllowedIPs = /24`, corp VM → `10.200.x.2:3128` с ACL доменов.
- **Стало:** CentOS gw на ноутбуке, host-only corp VM, full tunnel exit Home-1/Home-3, gated proxy на CentOS — **`docs/LAPTOP-GW-ARCHITECTURE.md`**.

## Mac host1 как L3/L7 router

- **Идея:** пользователь за **macOS host1**; WireGuard на Mac; **policy routing** / PF отправляет выбранные IP/домены на **host2 WG IP:port**; host2 demux на три VM по Host header.
- **Статус:** заменено схемой **ноутбук Ubuntu + VMs**, egress через **host1/host2 в РФ**.
- **Полезное наследие:** split tunnel WG, HTTP forward proxy на hub-side Windows, VMnet host-only для прокси-слоя.

## «Проксировать всё через виртуалки на host1»

- **Статус:** отказ; corp-трафик VM на **ноутбуке** идёт через **RF proxy**, а не через промежуточный host1 за границей.
- **Исключение:** внутри **host2** цепочка v2rayN → **corp-proxy на VM** остаётся рабочим эталоном для Sfera/inno.

## Multi-VM L7 router только на host2

- Три VM → три upstream порта на одном host2 — обсуждалось в начале; текущий фокус **Basis/cvpn VM** + **corp-proxy :3332** на одной guest (`.140`), не полный demux на три сети.
- При необходимости второй/третьей corp-VM — расширять ACL/upstream в `Install-Host2VpnForwardProxy.ps1`, не возвращать Mac-router.

## USB Rutoken через прокси

- Изначально спрашивали проброс токена Mac → VM; решение: **отказ**, Rutoken на host2/VM + ручной USB passthrough.
