# Запуск ТОЛЬКО из PowerShell от имени администратора.
# Важно: между командами — точка с запятой (;), не одиночный & (иначе уйдёт в фоновую Job).
#
#   Set-ExecutionPolicy -Scope Process Bypass -Force; D:\Exchange\projects\wireguard-setup\install-host2-tunnels.ps1
#
# Или одной строкой с UAC из обычной консоли:
#   Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "D:\Exchange\projects\wireguard-setup\install-host2-tunnels.ps1"'

$ErrorActionPreference = 'Stop'
$src = 'D:\Exchange\projects\wireguard-setup'
$dest = 'C:\Program Files\WireGuard\Data\Configurations'
$wg = 'C:\Program Files\WireGuard\wireguard.exe'

foreach ($name in @('host2-vpn1', 'host2-vpn2')) {
    Copy-Item (Join-Path $src "$name.conf") (Join-Path $dest "$name.conf") -Force
    & $wg /installtunnelservice (Join-Path $dest "$name.conf")
}

Start-Sleep -Seconds 2
Write-Host "`n=== wg show ===" -ForegroundColor Cyan
wg show
Write-Host "`nPing VPN1 hub:" -ForegroundColor Cyan
ping -n 2 10.200.1.1
Write-Host "`nPing VPN2 hub:" -ForegroundColor Cyan
ping -n 2 10.200.2.1
