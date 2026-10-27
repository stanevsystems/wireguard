#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Prepare travel laptop Windows host (no VMware changes).

.EXAMPLE
  .\Run-Prepare-LaptopHost-Logged.ps1 -RegisterOnServers -RetireHost3Tunnels
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string]$HostClientName = 'laptop',

    [ValidateRange(2, 254)]
    [int]$HostOctet = 4,

    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string]$GwClientName = 'laptop-gw',

    [ValidateRange(2, 254)]
    [int]$GwOctet = 5,

    [switch]$RegisterOnServers,

    [switch]$RetireHost3Tunnels,

    [switch]$SkipHostAdminTunnel
)

$ErrorActionPreference = 'Stop'
$DeployScript = Join-Path $PSScriptRoot 'Deploy-WireGuardClient.ps1'

function Write-Step([string]$Message) {
    Write-Host "`n== $Message ==" -ForegroundColor Cyan
}

function Ensure-SshKnownHosts {
    $known = Join-Path $env:USERPROFILE '.ssh\known_hosts'
    $sshDir = Split-Path $known -Parent
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
    }
    foreach ($h in @('176.32.32.246', '45.144.30.165')) {
        if (Select-String -Path $known -Pattern $h -Quiet -ErrorAction SilentlyContinue) { continue }
        Write-Host "ssh-keyscan $h -> known_hosts" -ForegroundColor DarkGray
        $lines = & ssh-keyscan -H $h 2>$null
        if ($lines) { $lines | Add-Content -Path $known -Encoding ascii }
    }
}

function New-GwCentOsTemplates {
    param(
        [string]$KeysDir,
        [int]$Octet
    )
    $vpn1 = "10.200.1.$Octet"
    $vpn2 = "10.200.2.$Octet"
    $hub1 = 'As40cjLtsqR9O1Skw4lYw/Pe9YfZBxCzn3rNpie8MTc='
    $hub2 = 'Tm27HQ9uS4TL0zCguamTTLadS8/MnczmCLOsVaJm6Vk='
    $centosDir = Join-Path $KeysDir 'centos'
    New-Item -ItemType Directory -Force -Path $centosDir | Out-Null

    @"
# Copy to CentOS: /etc/wireguard/wg-home1.conf
[Interface]
PrivateKey = <PASTE_FROM_scripts/clients/laptop-gw/private.key>
Address = $vpn1/32

[Peer]
PublicKey = $hub1
AllowedIPs = 0.0.0.0/0
Endpoint = 176.32.32.246:51820
PersistentKeepalive = 25
PostUp = /etc/wireguard/wg-vps-routes.sh
PostDown = ip rule del to 176.32.32.246/32 table 100 2>/dev/null; ip rule del to 45.144.30.165/32 table 100 2>/dev/null
"@ | Set-Content (Join-Path $centosDir 'wg-home1.conf.example') -Encoding ascii

    @"
# Copy to CentOS: /etc/wireguard/wg-home3.conf
[Interface]
PrivateKey = <PASTE_FROM_scripts/clients/laptop-gw/private.key>
Address = $vpn2/32

[Peer]
PublicKey = $hub2
AllowedIPs = 0.0.0.0/0
Endpoint = 45.144.30.165:51820
PersistentKeepalive = 25
PostUp = /etc/wireguard/wg-vps-routes.sh
PostDown = ip rule del to 176.32.32.246/32 table 100 2>/dev/null; ip rule del to 45.144.30.165/32 table 100 2>/dev/null
"@ | Set-Content (Join-Path $centosDir 'wg-home3.conf.example') -Encoding ascii

    @'
#!/bin/bash
set -euo pipefail
VPS1=176.32.32.246
VPS2=45.144.30.165
DEV_NAT="${WG_NAT_DEV:-eth1}"
GW=$(ip -4 route show dev "${DEV_NAT}" | awk '/default/ {print $3; exit}')
[[ -n "${GW}" ]] || { echo "No default via ${DEV_NAT}" >&2; exit 1; }
ip rule add to "${VPS1}/32" table 100 2>/dev/null || true
ip rule add to "${VPS2}/32" table 100 2>/dev/null || true
ip route replace default via "${GW}" dev "${DEV_NAT}" table 100
'@ | Set-Content (Join-Path $centosDir 'wg-vps-routes.sh') -Encoding ascii -NoNewline

    @"
REPLACE_HOME1=
77.242.105.103
"@ | Set-Content (Join-Path $centosDir 'expected-egress.conf.example') -Encoding ascii

    Write-Host "CentOS templates: $centosDir" -ForegroundColor Green
}

function Ensure-GwKeyMaterial {
    param([string]$ClientName, [int]$Octet)
    $stateDir = Join-Path $PSScriptRoot "clients\$ClientName"
    $privFile = Join-Path $stateDir 'private.key'
    $pubFile = Join-Path $stateDir 'public.key'
    $WgCli = 'C:\Program Files\WireGuard\wg.exe'
    if (-not (Test-Path $WgCli)) { throw "WireGuard not found: $WgCli" }

    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    if (-not ((Test-Path $privFile) -and (Test-Path $pubFile))) {
        $priv = (& $WgCli genkey | Out-String).Trim()
        $pub = ($priv | & $WgCli pubkey | Out-String).Trim()
        Set-Content -Path $privFile -Value $priv -NoNewline -Encoding ascii
        Set-Content -Path $pubFile -Value $pub -NoNewline -Encoding ascii
        icacls $privFile /inheritance:r /grant:r "${env:USERNAME}:R" /grant:r 'SYSTEM:F' | Out-Null
        Write-Host "New key: $pubFile" -ForegroundColor Green
    }
    $pubKey = (Get-Content $pubFile -Raw).Trim()
    New-GwCentOsTemplates -KeysDir $stateDir -Octet $Octet

    if ($RegisterOnServers) {
        Ensure-SshKnownHosts
        & $DeployScript -ClientName $ClientName -HostOctet $Octet -RegisterOnServers -RegisterOnly -RegisterVpn2Only
    } else {
        Write-Warning 'laptop-gw not registered on VPS. PublicKey:'
        Write-Host $pubKey
        Write-Host "  VPN-2: 10.200.2.$Octet/32"
    }
}

function Remove-LegacyHost3Tunnels {
    $WgExe = 'C:\Program Files\WireGuard\wireguard.exe'
    $WgDest = 'C:\Program Files\WireGuard\Data\Configurations'
    foreach ($name in @('host3-vpn1', 'host3-vpn2')) {
        $svc = "WireGuardTunnel`$$name"
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s) {
            Stop-Service $svc -Force -ErrorAction SilentlyContinue
            & $WgExe /uninstalltunnelservice $name 2>$null
            Write-Host "Removed legacy service $svc" -ForegroundColor Yellow
        }
        $conf = Join-Path $WgDest "$name.conf"
        if (Test-Path $conf) { Remove-Item $conf -Force }
    }
}

Write-Step "CentOS key material (laptop-gw octet $GwOctet)"
Ensure-GwKeyMaterial -ClientName $GwClientName -Octet $GwOctet

if (-not $SkipHostAdminTunnel) {
    Write-Step "Host split-tunnel ($HostClientName octet $HostOctet)"
    if ($RegisterOnServers) {
        Ensure-SshKnownHosts
        & $DeployScript -ClientName $HostClientName -HostOctet $HostOctet `
            -RegisterOnServers -RegisterVpn2Only -RegisterOnly
    }
    & $DeployScript -ClientName $HostClientName -HostOctet $HostOctet
}

if ($RetireHost3Tunnels) {
    Write-Step 'Remove legacy host3-* tunnels'
    Remove-LegacyHost3Tunnels
}

Write-Step 'Hub ping test'
$WgCli = 'C:\Program Files\WireGuard\wg.exe'
& $WgCli show 2>$null
ping -n 2 10.200.1.1 | Out-Host
ping -n 2 10.200.2.1 | Out-Host

Write-Host "`nDone. VMware unchanged. See docs/AGENT-LAPTOP.md for CentOS." -ForegroundColor Green
Write-Host "Keys: $PSScriptRoot\clients\$GwClientName and $PSScriptRoot\clients\$HostClientName"
