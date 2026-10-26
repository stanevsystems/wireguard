# Host2 VPN forward proxy

HTTP/HTTPS forward proxy on host2 for WireGuard peers and local apps.

## Routing

| Source | Listen | Allowed destinations |
|--------|--------|----------------------|
| `10.200.1.2`, `10.200.2.2`, `127.0.0.1` | TCP **3128** | `*.inno.local`, `*.cloud.vtb.ru`, `*.region.vtb.ru`, `*.dev.vtb.ru` |
| Other domains | — | **deny** |

Upstream chain: `192.168.136.140:3332` (JVM `corp-proxy.jar` on the VM; auth in `proxy-secrets.local.ps1` and `%USERPROFILE%\.corp-proxy\secrets.local.yaml`). Build: `vm-corp-proxy/corp-proxy/README.md`.

## host2 + v2rayN (automatic L7 on this PC)

Do **not** set manual system proxy to `:3128` on host2 if v2rayN is active. Add HTTP server **corp-vm** and routing rules — see **`v2rayN-corp-routing.md`**.

Port **3128** on host2 is for **remote VPN clients** (host3, Mac).

## Install (admin PowerShell)

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
D:\Exchange\projects\wireguard-setup\host2-forward-proxy\Install-Host2VpnForwardProxy.ps1
```

Autostart: Scheduled Task **Host2VpnForwardProxy** (SYSTEM, AtStartup + 30s delay).

If `3proxy.exe` is locked after a failed service install, reboot once and re-run the script, or run:

```powershell
schtasks /End /TN Host2VpnForwardProxy
Remove-Service Host2VpnForwardProxy -ErrorAction SilentlyContinue
```

## VPN clients (host3, Mac)

System proxy or PAC:

- VPN-1 hub side: `http://10.200.1.2:3128`
- VPN-2 hub side: `http://10.200.2.2:3128`

Use the IP of the VPN subnet you are on (host2 is `.2` in both).

## host2 local apps

`http://127.0.0.1:3128`

## Check

```powershell
Get-NetTCPConnection -LocalPort 3128 -State Listen
Get-ScheduledTask Host2VpnForwardProxy
Get-Content C:\ProgramData\Host2VpnForwardProxy\logs\3proxy.log -Tail 20
```

## Reconfigure

Edit `proxy-secrets.local.ps1` or domain list in `Install-Host2VpnForwardProxy.ps1`, re-run install script.

## VM diagnostics (corp upstream)

Temporary CONNECT proxy with logs on the VMware guest — **`vm-probe/README.md`**.

## VM corp entry (no WireGuard on guest)

**Kaspersky on VM blocks 3proxy** — use **`corp-proxy.jar` on :3332**, not `Install-VmCorpForwardProxy.ps1` and not Settings → HTTP Proxy. See **`vm-corp-proxy/IB-NO-3PROXY-ON-VM.md`**. Host2 tuning: **`optimize-v2rayn-corp-lan.ps1`**, details **`vm-corp-proxy/PERFORMANCE.md`**.
