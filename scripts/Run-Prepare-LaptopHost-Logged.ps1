# Run Prepare-LaptopHost.ps1 in this elevated window with a log file.
# Usage (Admin PowerShell):
#   Set-Location D:\exchange\projects\_my_projects\wireguard\scripts
#   .\Run-Prepare-LaptopHost-Logged.ps1 -RegisterOnServers -RetireHost3Tunnels

param(
    [switch]$RegisterOnServers,
    [switch]$RetireHost3Tunnels
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Run PowerShell as Administrator, then retry (not the normal Cursor terminal).' -ForegroundColor Red
    exit 1
}

$log = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\prepare-laptop-host.log'
$prepareParams = @{}
if ($RegisterOnServers) { $prepareParams['RegisterOnServers'] = $true }
if ($RetireHost3Tunnels) { $prepareParams['RetireHost3Tunnels'] = $true }

& (Join-Path $PSScriptRoot 'Prepare-LaptopHost.ps1') @prepareParams *>&1 | Tee-Object -FilePath $log
Write-Host "Log: $log"
