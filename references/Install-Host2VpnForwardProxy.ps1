#Requires -RunAsAdministrator
<#
  Forward HTTP/HTTPS proxy on host2 (VPN + localhost -> VM upstream).
  Run: Set-ExecutionPolicy -Scope Process Bypass -Force; .\Install-Host2VpnForwardProxy.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\ProgramData\Host2VpnForwardProxy',
    [string]$SecretsFile = '',
    [switch]$SkipDownload
)

$ErrorActionPreference = 'Stop'
$ScriptDir = $PSScriptRoot
if (-not $SecretsFile) {
    $SecretsFile = Join-Path $ScriptDir 'proxy-secrets.local.ps1'
}
if (-not (Test-Path $SecretsFile)) {
    throw "Missing $SecretsFile. Copy proxy-secrets.example.ps1 to proxy-secrets.local.ps1"
}
. $SecretsFile

$DomainSuffixes = @(
    '*.inno.local'
    '*.cloud.vtb.ru'
    '*.region.vtb.ru'
    '*.dev.vtb.ru'
)
# 3proxy: allow user client dest — dest *.domain (NOT four-field form; 4th field = ports)
$DomainAclLines = 'allow * * ' + ($DomainSuffixes -join ',')

function Get-WgHostIps {
    $ips = @()
    foreach ($alias in @('host2-vpn1', 'host2-vpn2')) {
        $addr = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -match '^10\.200\.' } |
            Select-Object -ExpandProperty IPAddress -First 1
        if ($addr) { $ips += $addr }
    }
    if (-not $ips.Count) { $ips = @('10.200.1.2', '10.200.2.2') }
    return ($ips | Select-Object -Unique)
}

function Ensure-3ProxyBinary {
    param([string]$BinDir)
    $runExe = Join-Path $BinDir 'Host2VpnProxy.exe'
    $exe = Join-Path $BinDir '3proxy.exe'
    if ((Test-Path $runExe) -and $SkipDownload) { return $runExe }
    if (Test-Path $runExe) { return $runExe }

    New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
    $zipUrl = 'https://github.com/3proxy/3proxy/releases/download/0.9.4/3proxy-0.9.4-x64.zip'
    $zipPath = Join-Path $env:TEMP '3proxy-x64.zip'
    Write-Host 'Downloading 3proxy...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath (Join-Path $env:TEMP '3proxy-extract') -Force
    $found = Get-ChildItem -Path (Join-Path $env:TEMP '3proxy-extract') -Recurse -Filter '3proxy.exe' | Select-Object -First 1
    if (-not $found) { throw '3proxy.exe not found in zip' }
    $runExe = Join-Path $BinDir 'Host2VpnProxy.exe'
    Copy-Item $found.FullName $runExe -Force
    Copy-Item $runExe $exe -Force -ErrorAction SilentlyContinue
    return $runExe
}

function New-3ProxyConfig {
    param(
        [string]$CfgPath,
        [string[]]$ListenIps,
        [int]$Port,
        [string]$ParentHost,
        [int]$ParentPort,
        [string]$ParentUser,
        [string]$ParentPassword,
        [string]$DomainAclBlock
    )
    $listeners = @('127.0.0.1')
    $listeners += $ListenIps
    $listeners = $listeners | Select-Object -Unique

    $proxyLines = foreach ($ip in $listeners) {
        "proxy -p$Port -i$ip"
    }

    $passEsc = $ParentPassword -replace '\\', '\\' -replace '"', '\"'

    $content = @"
# Host2 VPN forward proxy - generated $(Get-Date -Format o)
nserver 8.8.8.8
nserver 1.1.1.1
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
auth none

$DomainAclBlock
parent 1000 http $ParentHost $ParentPort $ParentUser "$passEsc"
deny * * * *

$($proxyLines -join "`n")

log C:\ProgramData\Host2VpnForwardProxy\logs\3proxy.log D
logformat "- +_L%t.%. %N.%p %E %U %C:%c %R:%r %O %I %h %T"
rotate 30
"@
    New-Item -ItemType Directory -Force -Path (Join-Path $InstallRoot 'logs') | Out-Null
    Set-Content -Path $CfgPath -Value $content -Encoding ASCII
}

function Install-ProxyAutostart {
    param([string]$ExePath, [string]$CfgPath)
    $binDir = Split-Path $ExePath
    Copy-Item $CfgPath (Join-Path $binDir '3proxy.cfg') -Force
    $taskName = 'Host2VpnForwardProxy'

    Get-Process -Name '3proxy' -ErrorAction SilentlyContinue | Stop-Process -Force
    foreach ($old in @('Host2VpnForwardProxy', '3proxy', '3Proxy')) {
        $svc = Get-Service -Name $old -ErrorAction SilentlyContinue
        if ($svc) {
            Stop-Service $old -Force -ErrorAction SilentlyContinue
            & sc.exe delete $old | Out-Null
        }
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    $action = New-ScheduledTaskAction -Execute $ExePath -WorkingDirectory $binDir
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT30S'
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 999 `
        -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
        -User 'SYSTEM' -RunLevel Highest -Description '3proxy forward proxy for WireGuard clients' | Out-Null

    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 3
    $listen = Get-NetTCPConnection -LocalPort $ListenPort -State Listen -ErrorAction SilentlyContinue
    if (-not $listen) {
        Write-Warning 'Port not listening yet; task is registered for startup (+30s delay).'
    }
    Write-Host ('Scheduled task: ' + $taskName + ' (AtStartup, SYSTEM)') -ForegroundColor Green
}

function Ensure-Firewall {
    param([int]$Port)
    $name = 'Host2-VpnForwardProxy'
    $existing = Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue
    if ($existing) { Remove-NetFirewallRule -DisplayName $name }
    New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP `
        -LocalPort $Port -RemoteAddress '10.200.1.0/24', '10.200.2.0/24' | Out-Null
    Write-Host "Firewall: TCP $Port from 10.200.1.0/24 and 10.200.2.0/24" -ForegroundColor DarkGray
}

$binDir = Join-Path $InstallRoot 'bin'
$cfgPath = Join-Path $InstallRoot '3proxy.cfg'
$exe = Ensure-3ProxyBinary -BinDir $binDir
$vpnIps = Get-WgHostIps
Write-Host ('Listen VPN IPs: ' + ($vpnIps -join ', ')) -ForegroundColor Cyan

New-3ProxyConfig -CfgPath $cfgPath -ListenIps $vpnIps -Port $ListenPort `
    -ParentHost $UpstreamHost -ParentPort $UpstreamPort `
    -ParentUser $UpstreamUser -ParentPassword $UpstreamPassword -DomainAclBlock $DomainAclLines

if (-not (Test-Path $exe)) {
    throw ('Missing ' + $exe)
}
Install-ProxyAutostart -ExePath $exe -CfgPath $cfgPath
Ensure-Firewall -Port $ListenPort

Write-Host ''
Write-Host '=== Done ===' -ForegroundColor Green
Write-Host 'Proxy URLs (HTTP + HTTPS via CONNECT):'
foreach ($ip in $vpnIps) {
    Write-Host ('  http://' + $ip + ':' + $ListenPort)
}
Write-Host ('  http://127.0.0.1:' + $ListenPort + ' (local apps on host2)')
Write-Host ('Domains: ' + ($DomainSuffixes -join ', '))
Write-Host ('Upstream: http://' + $UpstreamHost + ':' + $UpstreamPort)
Write-Host ('VPN clients: set system proxy to host2 VPN IP, port ' + $ListenPort)
