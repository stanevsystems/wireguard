#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Prepare Windows host (Home-1 / Home-3) as WireGuard exit node: forwarding + NAT for 10.200.0.0/16.

.PARAMETER VpnHub
  1 = primary documentation path for VPN-1; 2 = VPN-2. NAT covers both /24 either way.

.EXAMPLE
  Set-ExecutionPolicy -Scope Process Bypass -Force
  D:\Exchange\projects\_my_projects\wireguard\scripts\Enable-WindowsWgExitNode.ps1 -VpnHub 2
#>
[CmdletBinding()]
param(
    [ValidateSet(1, 2)]
    [int] $VpnHub = 2
)

$ErrorActionPreference = 'Stop'
$NatName = 'WgHomeExitNat'
$InternalPrefix = '10.200.0.0/16'

Write-Host "Enabling IPv4 forwarding on WireGuard interfaces..." -ForegroundColor Cyan
Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'WireGuard' -or $_.Name -match 'vpn' } | ForEach-Object {
    Set-NetIPInterface -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -Forwarding Enabled -ErrorAction SilentlyContinue
}

$existing = Get-NetNat -Name $NatName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "NetNat '$NatName' already exists (InternalPrefix $($existing.InternalIPInterfaceAddressPrefix))." -ForegroundColor Yellow
} else {
    Write-Host "Creating NetNat '$NatName' for $InternalPrefix ..." -ForegroundColor Cyan
    New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $InternalPrefix | Out-Null
}

# Allow forward: WireGuard -> physical LAN/WAN
$wgIf = Get-NetAdapter | Where-Object { $_.InterfaceDescription -match 'WireGuard' -or $_.Name -match 'host2-vpn' }
$upIf = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Name -notmatch 'vpn|Loopback|WSL|VirtualBox|VMware|vEthernet' }

foreach ($w in $wgIf) {
    foreach ($u in $upIf) {
        $ruleName = "WgExit-Forward-$($w.Name)-to-$($u.Name)"
        if (-not (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $ruleName -Direction Forward `
                -InterfaceAlias $w.Name -Action Allow | Out-Null
        }
    }
}

Write-Host ""
Write-Host "Done (VpnHub=$VpnHub). Next steps:" -ForegroundColor Green
Write-Host "  1. On VPS-$VpnHub set exit peer AllowedIPs = <wg-ip>/32, 0.0.0.0/0  (see scripts/vps-set-exit-peer.sh)"
Write-Host "  2. wg show  —  verify handshakes"
Write-Host "  3. From CentOS laptop client: curl ifconfig.me  —  must be this PC's ISP public IP"
Write-Host "  4. Record public IP in config/EGRESS-IPS.example.md for egress-check on CentOS"
