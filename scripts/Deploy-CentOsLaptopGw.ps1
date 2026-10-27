#Requires -Version 5.1
<#
.SYNOPSIS
  Копирует ключ WG и setup-laptop-gw.sh на CentOS и запускает настройку по SSH.

.EXAMPLE
  .\Deploy-CentOsLaptopGw.ps1 -CentOsHost 192.168.181.182 -RegisterOnServers
#>
[CmdletBinding()]
param(
    [string]$CentOsHost = '192.168.181.182',
    [string]$SshUser = 'root',
    [string]$IdentityFile = (Join-Path $PSScriptRoot 'clients\centos-ssh\id_ed25519'),
    [switch]$RegisterOnServers
)

$ErrorActionPreference = 'Stop'
$PrivKey = Join-Path $PSScriptRoot 'clients\laptop-gw\private.key'
$SetupSh = Join-Path $PSScriptRoot 'centos\setup-laptop-gw.sh'
$DeployWg = Join-Path $PSScriptRoot 'Deploy-WireGuardClient.ps1'

if (-not (Test-Path $PrivKey)) { throw "Нет $PrivKey — сначала Prepare-LaptopHost.ps1" }
if (-not (Test-Path $SetupSh)) { throw "Нет $SetupSh" }

$ssh = @('-o', 'StrictHostKeyChecking=accept-new', '-i', $IdentityFile, "${SshUser}@${CentOsHost}")

Write-Host "Проверка SSH..." -ForegroundColor Cyan
& ssh @ssh 'echo SSH_OK'
if ($LASTEXITCODE -ne 0) { throw 'SSH не удался. Проверьте ключ в /root/.ssh/authorized_keys на CentOS.' }

Write-Host "Копирование файлов..." -ForegroundColor Cyan
& scp @ssh $PrivKey "${SshUser}@${CentOsHost}:/root/wg-laptop-gw.private.key"
& scp @ssh $SetupSh "${SshUser}@${CentOsHost}:/root/setup-laptop-gw.sh"
if ($LASTEXITCODE -ne 0) { throw 'scp failed' }

Write-Host "Запуск setup-laptop-gw.sh на CentOS..." -ForegroundColor Cyan
& ssh @ssh 'chmod 600 /root/wg-laptop-gw.private.key; sed -i "s/\r$//" /root/setup-laptop-gw.sh; bash /root/setup-laptop-gw.sh'
if ($LASTEXITCODE -ne 0) { throw 'setup script failed' }

if ($RegisterOnServers) {
    Write-Host "Регистрация laptop-gw на VPS..." -ForegroundColor Cyan
    & $DeployWg -ClientName laptop-gw -HostOctet 5 -RegisterOnServers
    foreach ($suffix in @('vpn1', 'vpn2')) {
        $svc = "WireGuardTunnel`$laptop-gw-$suffix"
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Manual -ErrorAction SilentlyContinue
    }
}

Write-Host "Проверки на CentOS..." -ForegroundColor Cyan
& ssh @ssh @'
set -e
wg show 2>/dev/null || true
curl -4 -s --max-time 15 https://ifconfig.me/ip || echo "curl-direct-fail"
systemctl is-active egress-check.timer
curl -4 -s --max-time 15 --proxy http://127.0.0.1:3128 https://ifconfig.me/ip || echo "squid-not-up-yet"
'@

Write-Host "Готово." -ForegroundColor Green
