# Agent context: WireGuard + laptop CentOS gateway

**Canonical handoff:** `d:\Exchange\projects\_my_projects\wireguard\`  
**Implementation tree:** `d:\Exchange\projects\wireguard-setup\` (legacy host2 corp proxy, v2rayN).

**Architecture:** `docs/LAPTOP-GW-ARCHITECTURE.md`

## Active phase (2026-10-27): VPN-2 / Home-3 only

Home-1 и VPS-1 **отложены**. Следующий агентский чат на **Home-3**: **`docs/NEXT-HOME-3-E2E.md`**.

## Status by machine

| Machine | Status |
|---------|--------|
| **TECHO-1 laptop** | `laptop-vpn2`, CentOS gw, `host3-*` removed — см. `docs/LAPTOP-HOST-STATUS.md`, `docs/CENTOS-ROUTER-STATUS.md` |
| **CentOS-Router** | wg-home3 + Squid + egress-check; **ждёт Home-3 exit** (egress сейчас IP VPS) |
| **Home-3** | **TODO E2E** — `docs/NEXT-HOME-3-E2E.md`, runbook `docs/AGENT-HOME-3.md` |
| **Home-1** | deferred |

## WG topology (VPN-2 path)

| Node | Public | WG | Role |
|------|--------|-----|------|
| VPS-2 | 45.144.30.165 | 10.200.2.1 | hub |
| Home-3 | — | 10.200.2.2 | **exit NAT** |
| laptop (Windows) | — | 10.200.2.4 | split admin |
| laptop-gw (CentOS) | — | 10.200.2.5 | full tunnel + proxy |

Port **51820/udp**. Exit peer on VPS-2: **only Home-3** with `0.0.0.0/0`.

## Open work

- [x] CentOS gw VM + wg-home3 + scripts on TECHO-1
- [x] laptop-gw + laptop peers on VPS-2
- [x] Prepare-LaptopHost (laptop-vpn*, retire host3)
- [ ] **Home-3 exit E2E** → CentOS egress **77.242.105.103** + Squid up
- [ ] Corp VM → host-only 72.x + proxy (later; VMware unchanged for now)
- [ ] Home-1 / VPS-1 (later)

## Agent runbooks

| Host | Doc |
|------|-----|
| **Home-3** (next) | `docs/NEXT-HOME-3-E2E.md`, `docs/AGENT-HOME-3.md` |
| Travel laptop | `docs/AGENT-LAPTOP.md` |
| Home-1 | `docs/AGENT-HOME-1.md` (deferred) |

## Scripts

| Script | Use |
|--------|-----|
| `scripts/Enable-WindowsWgExitNode.ps1` | Home-3 exit NAT |
| `scripts/vps-set-exit-peer.sh` | VPS exit peer |
| `scripts/register-laptop-gw-vpn2.sh` | Register CentOS peer from Git Bash |
