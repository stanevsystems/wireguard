#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Разворачивает два split-tunnel WireGuard-клиента (VPN-1 + VPN-2) на Windows.

.PARAMETER ClientName
  Имя хоста (латиница), используется в именах туннелей: ClientName-vpn1, ClientName-vpn2.

.PARAMETER HostOctet
  Последний октет VPN-IP на обеих сетях (host2 = 2 → 10.200.1.2 и 10.200.2.2).

.PARAMETER RegisterOnServers
  Добавить peer на оба VPS по SSH (нужен ключ root@176.32.32.246 и root@45.144.30.165).

.EXAMPLE
  Set-ExecutionPolicy -Scope Process Bypass -Force; .\Deploy-WireGuardClient.ps1 -ClientName host3 -HostOctet 3 -RegisterOnServers

.EXAMPLE
  Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File "D:\Exchange\projects\wireguard-setup\Deploy-WireGuardClient.ps1" -ClientName laptop -HostOctet 4 -RegisterOnServers'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9_-]+$')]
    [string]$ClientName,

    [Parameter(Mandatory = $true)]
    [ValidateRange(2, 254)]
    [int]$HostOctet,

    [switch]$RegisterOnServers,

    [string]$Vpn1Server = '176.32.32.246',
    [string]$Vpn2Server = '45.144.30.165'
)

$ErrorActionPreference = 'Stop'

# --- общие параметры VPN (как на host2) ---
$VPN1_SUBNET = '10.200.1'
$VPN2_SUBNET = '10.200.2'
$VPN1_HUB_PUB = 'As40cjLtsqR9O1Skw4lYw/Pe9YfZBxCzn3rNpie8MTc='
$VPN2_HUB_PUB = 'Tm27HQ9uS4TL0zCguamTTLadS8/MnczmCLOsVaJm6Vk='
$LISTEN_PORT = 51820
$KEEPALIVE = 25

$ScriptDir = $PSScriptRoot
$StateDir = Join-Path $ScriptDir "clients\$ClientName"
$PrivFile = Join-Path $StateDir 'private.key'
$PubFile = Join-Path $StateDir 'public.key'
$WgDir = 'C:\Program Files\WireGuard'
$WgExe = Join-Path $WgDir 'wireguard.exe'
$WgCli = Join-Path $WgDir 'wg.exe'
$WgDest = Join-Path $WgDir 'Data\Configurations'

function Initialize-WireGuardPath {
    if (-not (Test-Path $WgCli)) {
        throw "Не найден $WgCli — переустановите WireGuard или перезапустите скрипт."
    }
    if ($env:Path -notlike "*$WgDir*") {
        $env:Path = "$WgDir;$env:Path"
    }
}

function Ensure-WireGuardInstalled {
    if ((Test-Path $WgExe) -and (Test-Path $WgCli)) {
        Initialize-WireGuardPath
        return
    }
    Write-Host 'WireGuard не найден, установка через winget...' -ForegroundColor Yellow
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw 'Установите WireGuard вручную: https://www.wireguard.com/install/ или winget install WireGuard.WireGuard'
    }
    & winget install --id WireGuard.WireGuard -e --accept-source-agreements --accept-package-agreements
    Start-Sleep -Seconds 2
    if (-not (Test-Path $WgExe) -or -not (Test-Path $WgCli)) {
        throw 'WireGuard не установился. Перезапустите скрипт после установки.'
    }
    Initialize-WireGuardPath
}

function Get-OrCreateKeyPair {
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    if ((Test-Path $PrivFile) -and (Test-Path $PubFile)) {
        Write-Host "Использую сохранённый ключ: $StateDir" -ForegroundColor DarkGray
        return @{
            Private = (Get-Content $PrivFile -Raw).Trim()
            Public  = (Get-Content $PubFile -Raw).Trim()
        }
    }
    $priv = (& $WgCli genkey | Out-String).Trim()
    $pub = ($priv | & $WgCli pubkey | Out-String).Trim()
    Set-Content -Path $PrivFile -Value $priv -NoNewline -Encoding ascii
    Set-Content -Path $PubFile -Value $pub -NoNewline -Encoding ascii
    icacls $PrivFile /inheritance:r /grant:r "${env:USERNAME}:R" /grant:r 'SYSTEM:F' | Out-Null
    Write-Host "Новый ключ: $PubFile" -ForegroundColor Green
    return @{ Private = $priv; Public = $pub }
}

function New-TunnelConf {
    param(
        [string]$PrivateKey,
        [string]$Address,
        [string]$HubPub,
        [string]$AllowedCidr,
        [string]$EndpointHost
    )
    @"
[Interface]
PrivateKey = $PrivateKey
Address = $Address/32

[Peer]
PublicKey = $HubPub
AllowedIPs = $AllowedCidr
Endpoint = ${EndpointHost}:${LISTEN_PORT}
PersistentKeepalive = $KEEPALIVE
"@
}

function Register-PeerOnServer {
    param(
        [string]$SshHost,
        [string]$PublicKey,
        [string]$AllowedIp32,
        [string]$Comment
    )
    $bash = @'
set -euo pipefail
CONF=/etc/wireguard/wg0.conf
PUB='__PUB__'
IP='__IP__'
COMMENT='__COMMENT__'
if grep -q "$PUB" "$CONF" 2>/dev/null; then
  wg set wg0 peer "$PUB" allowed-ips "$IP" 2>/dev/null || true
  exit 0
fi
wg set wg0 peer "$PUB" allowed-ips "$IP"
printf '\n[Peer]\n# %s\nPublicKey = %s\nAllowedIPs = %s\n' "$COMMENT" "$PUB" "$IP" >> "$CONF"
'@
    $bash = $bash.Replace('__PUB__', $PublicKey.Replace("'", "'\''"))
    $bash = $bash.Replace('__IP__', $AllowedIp32)
    $bash = $bash.Replace('__COMMENT__', $Comment.Replace("'", "'\''"))
    $bash = $bash -replace "`r`n", "`n"
    $sshArgs = @(
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=15',
        '-o', 'StrictHostKeyChecking=accept-new'
    )
    $bash | & ssh @sshArgs "root@$SshHost" 'bash -s'
    if ($LASTEXITCODE -ne 0) {
        throw "SSH/register failed on ${SshHost} (exit $LASTEXITCODE). Run: ssh-keyscan -H ${SshHost} >> `$env:USERPROFILE\.ssh\known_hosts"
    }
    Write-Host "Peer registered on ${SshHost}: ${AllowedIp32}" -ForegroundColor Green
}

function Install-TunnelService {
    param([string]$ConfPath)
    if (-not (Test-Path $ConfPath)) {
        throw "Config not found: $ConfPath"
    }
    $ConfPath = (Resolve-Path -LiteralPath $ConfPath).Path
    $name = [System.IO.Path]::GetFileNameWithoutExtension($ConfPath)
    $svcName = "WireGuardTunnel`$$name"
    $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($svc) {
        Restart-Service -Name $svcName -Force
        Start-Sleep -Seconds 2
    } else {
        & $WgExe /installtunnelservice $ConfPath
        if ($LASTEXITCODE -ne 0) {
            throw "installtunnelservice failed for $name (exit $LASTEXITCODE)"
        }
        Start-Sleep -Seconds 1
        $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
        if (-not $svc) { throw "Служба $svcName не создана" }
    }
    Set-Service -Name $svcName -StartupType Automatic
    if ((Get-Service $svcName).Status -ne 'Running') {
        Start-Service -Name $svcName
    }
}

# --- main ---
if ($HostOctet -eq 2 -and $ClientName -ne 'host2') {
    Write-Warning 'Октет 2 занят host2; убедитесь, что это переустановка того же хоста.'
}

Ensure-WireGuardInstalled
$keys = Get-OrCreateKeyPair

$ip1 = "$VPN1_SUBNET.$HostOctet"
$ip2 = "$VPN2_SUBNET.$HostOctet"

if ($RegisterOnServers) {
    Register-PeerOnServer -SshHost $Vpn1Server -PublicKey $keys.Public -AllowedIp32 "${ip1}/32" -Comment "$ClientName (Windows)"
    Register-PeerOnServer -SshHost $Vpn2Server -PublicKey $keys.Public -AllowedIp32 "${ip2}/32" -Comment "$ClientName (Windows)"
} else {
    Write-Warning 'Peer на серверах НЕ добавлены. Запустите с -RegisterOnServers или добавьте вручную:'
    Write-Host "  PublicKey: $($keys.Public)"
    Write-Host "  VPN-1 AllowedIPs: ${ip1}/32"
    Write-Host "  VPN-2 AllowedIPs: ${ip2}/32"
}

$conf1Name = "$ClientName-vpn1.conf"
$conf2Name = "$ClientName-vpn2.conf"
$conf1Local = Join-Path $StateDir $conf1Name
$conf2Local = Join-Path $StateDir $conf2Name

New-TunnelConf -PrivateKey $keys.Private -Address $ip1 -HubPub $VPN1_HUB_PUB `
    -AllowedCidr "$VPN1_SUBNET.0/24" -EndpointHost $Vpn1Server | Set-Content $conf1Local -Encoding ascii
New-TunnelConf -PrivateKey $keys.Private -Address $ip2 -HubPub $VPN2_HUB_PUB `
    -AllowedCidr "$VPN2_SUBNET.0/24" -EndpointHost $Vpn2Server | Set-Content $conf2Local -Encoding ascii

New-Item -ItemType Directory -Force -Path $WgDest | Out-Null
Copy-Item $conf1Local (Join-Path $WgDest $conf1Name) -Force
Copy-Item $conf2Local (Join-Path $WgDest $conf2Name) -Force

Install-TunnelService (Join-Path $WgDest $conf1Name)
Install-TunnelService (Join-Path $WgDest $conf2Name)

Start-Sleep -Seconds 2
Write-Host "`n=== wg show ===" -ForegroundColor Cyan
& $WgCli show
Write-Host "`nPing ${VPN1_SUBNET}.1:" -ForegroundColor Cyan
ping -n 2 "${VPN1_SUBNET}.1"
Write-Host "`nPing ${VPN2_SUBNET}.1:" -ForegroundColor Cyan
ping -n 2 "${VPN2_SUBNET}.1"

Write-Host "`nГотово. Автозапуск: службы WireGuardTunnel`$$ClientName-vpn1/vpn2 (Automatic)." -ForegroundColor Green
Write-Host "Ключи и копии конфигов: $StateDir"
