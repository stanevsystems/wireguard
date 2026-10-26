# Клиент WireGuard (Windows / macOS / Linux)

## Windows (новый хост)

1. PowerShell **от администратора**.
2. Уникальный **`-HostOctet`** (см. `config/PEERS.example.md`).
3. SSH-ключ к обоим VPS **или** `ssh-keyscan` + ручная регистрация pubkey.

```powershell
ssh-keyscan -H 176.32.32.246 45.144.30.165 | Out-File -Append $env:USERPROFILE\.ssh\known_hosts -Encoding ascii
Set-ExecutionPolicy -Scope Process Bypass -Force
D:\Exchange\projects\wireguard-setup\Deploy-WireGuardClient.ps1 -ClientName laptop -HostOctet 4 -RegisterOnServers
```

Скрипт: UTF-8 **с BOM**; после winget использует `C:\Program Files\WireGuard\wg.exe`.

**host2 (фиксированные conf):** `install-host2-tunnels.ps1` + `host2-vpn1.conf` / `host2-vpn2.conf`.

## macOS

```bash
cd /path/to/wireguard-setup
chmod +x deploy-wireguard-client-macos.sh
sudo ./deploy-wireguard-client-macos.sh --name macbook --octet 5 --register
```

## Ubuntu (ноутбук) — TODO в новом диалоге

Варианты:

- `wireguard` + `wg-quick@wg1` / `@wg2` по аналогии с macOS LaunchDaemon;
- или NetworkManager plugin;
- два конфига с теми же `[Peer]` Endpoint и `AllowedIPs = 10.200.1.0/24` / `10.200.2.0/24`.

Ключи: `wg genkey` | `wg pubkey`; регистрация peer на VPS как выше.

## После подключения

```bash
ping 10.200.1.1
ping 10.200.2.1
```

**Прокси для corp-доменов:**

```bash
export HTTP_PROXY=http://10.200.1.2:3128
export HTTPS_PROXY=http://10.200.1.2:3128
curl -I https://…  # corp URL из ACL
```

Windows VM: системный прокси или GPO/user env → тот же URL.

## Автозапуск

- Windows: службы `WireGuardTunnel$…` (Automatic) — создаёт Deploy-скрипт.
- host2 forward proxy: Scheduled Task **Host2VpnForwardProxy** — см. `docs/HOST2-FORWARD-PROXY.md`.
