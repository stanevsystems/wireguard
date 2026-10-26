# Ожидаемые публичные IP egress (для CentOS egress-check)

Заполнить после `Enable-WindowsWgExitNode.ps1` и настройки VPS. **Не** коммитить, если политика — только локально на CentOS; этот файл — шаблон.

| Узел | Hub | Команда снять IP | Значение |
|------|-----|------------------|----------|
| Home-1 | VPN-1 | `(Invoke-RestMethod https://ifconfig.me/ip).Trim()` на Home-1 | `REPLACE_ME` |
| Home-3 | VPN-2 | то же на Home-3 | `77.242.105.103` (снято 2026-10-26; перепроверять после смены ISP) |

На CentOS: `/etc/wireguard/expected-egress.conf` — по одному IP на строку или `HOME3=1.2.3.4`.
