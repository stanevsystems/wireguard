# Agent context: WireGuard + laptop CentOS gateway

Bootstrap a **new chat** for: **CentOS gw VM** on travel laptop, corp VMs **host-only**, egress **only** via **Home-1 / Home-3 exit NAT**, gated HTTP proxy on CentOS.

**Canonical handoff:** `d:\Exchange\projects\_my_projects\wireguard\`  
**Implementation tree:** `d:\Exchange\projects\wireguard-setup\` (legacy host2 corp proxy, v2rayN, corp-proxy JVM).

## Pivot (2026-10-26)

| Deprecated for travel laptop | Current |
|------------------------------|---------|
| Split WG `/24` + corp proxy on Home-3 `:3128` ACL | Full tunnel to **one** home exit; corp VM → **CentOS :3128** on host-only |
| Ubuntu host as WG client | **CentOS** minimal VM = only router/proxy for corp guests |
| Mac host1 router abroad | **Home-1** + **Home-3** in RF as symmetric exit nodes |

**Architecture:** `docs/LAPTOP-GW-ARCHITECTURE.md`

## Agent runbooks (by machine)

| Host | Doc |
|------|-----|
| **Home-3** (now) | `docs/AGENT-HOME-3.md` |
| **Home-1** | `docs/AGENT-HOME-1.md` |
| **Travel laptop** | `docs/AGENT-LAPTOP.md` |

## WG topology

| Node | Public | Role |
|------|--------|------|
| VPN-1 | 176.32.32.246 | hub `10.200.1.1/24`; exit → **Home-1** |
| VPN-2 | 45.144.30.165 | hub `10.200.2.1/24`; exit → **Home-3** (`10.200.2.2`) |
| Home-3 / host2 | — | `.1.2`, `.2.2`; `Enable-WindowsWgExitNode.ps1` |
| laptop-gw CentOS | — | octet **5** → `.1.5`, `.2.5` (see `config/PEERS.example.md`) |

Port **51820/udp**. Hubs: `ip_forward=1`. **No** site-to-site between VPS-1 and VPS-2.

Exit on hub: peer `AllowedIPs = <home-wg-ip>/32, 0.0.0.0/0` — **one exit per VPS** (`scripts/vps-set-exit-peer.sh`).

## Home-3 legacy (still on disk, not travel path)

- `Host2VpnForwardProxy` :3128 corp ACL — local/legacy; see `docs/HOST2-FORWARD-PROXY.md`
- v2rayN → corp-proxy `.140:3332` on VMware VM

## Scripts (this repo)

| Script | Use |
|--------|-----|
| `scripts/Enable-WindowsWgExitNode.ps1` | Home-1 / Home-3 NAT |
| `scripts/vps-set-exit-peer.sh` | VPS exit peer |
| `scripts/Deploy-WireGuardClient.ps1` | copy/symlink from `wireguard-setup` |

## Open work

- [ ] Run exit prep on **Home-3** (admin PS + VPS VPN-2 peer)
- [ ] Deploy **Home-1** WG + exit VPN-1
- [ ] Build **CentOS gw** VM + VMware VMnet-gw on laptop
- [ ] Squid + egress-check timer on CentOS
- [ ] Fill `config/EGRESS-IPS.example.md` with real WAN IPs

## Related

- Corp VPN in VM: `_my_projects/cvpn/`
- Transcript history: `60160116-7105-47b1-a5b1-33dfdab7c646`
