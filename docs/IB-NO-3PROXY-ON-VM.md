# VM: 3proxy нельзя (Kaspersky / ИБ)

Kaspersky Endpoint Security детектит бинарник как **HackTool.Win64.3Proxy.a** (`VmCorpProxy.exe` в `ProgramData`). Повторные установки усиливают внимание ИБ.

## Рабочая схема вместо 3proxy на VM

Settings → HTTP Proxy в IntelliJ — исходящий прокси клиента IDE. Входящий listener для host2 — JVM **corp-proxy** (`java -jar corp-proxy.jar`), порт **3332**. Сборка: **`corp-proxy/README.md`**. Текст для ИБ: **`IB-CORP-PROXY-JVM.md`**.

```text
host2 browser -> v2rayN:10808 -> corp-vm HTTP -> VM java corp-proxy :3332 -> corp
```

### На VM

1. **Не** запускать `Install-VmCorpForwardProxy.ps1` / `run_forwarder.ps1` снова.
2. Удалить следы (**нужен admin**, иначе `schtasks`: Access denied):
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass -Force
   Z:\Exchange\projects\wireguard-setup\host2-forward-proxy\vm-corp-proxy\Remove-VmCorpForwardProxy.ps1
   ```
   Либо: **PowerShell от имени администратора** → те же команды `schtasks /Delete /TN VmCorpForwardProxy /F` и удаление `C:\ProgramData\VmCorpForwardProxy`.
3. Собрать JAR, положить `tools/corp-proxy/corp-proxy.jar` и `config.yaml`, пароль — в `%USERPROFILE%\.corp-proxy\secrets.local.yaml`. Старт: External Tool **Corp Proxy Start** или плагин. Один раз: `Set-CorpProxyFirewall.ps1`.
4. Проверка **на VM**: `Get-NetTCPConnection -LocalPort 3332 -State Listen` → адрес `192.168.136.140`.

### На host2

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
D:\Exchange\projects\wireguard-setup\host2-forward-proxy\optimize-v2rayn-corp-lan.ps1
# fix-v2rayn-browser-corp.ps1 при необходимости
```

```powershell
D:\Exchange\projects\wireguard-setup\host2-forward-proxy\sync-corp-vm-from-secrets.ps1
```

Reload v2rayN. Порт/креды: **`host2-forward-proxy\proxy-secrets.local.ps1`** (corp-proxy **3332**, user **admin**). На VM тот же пароль в `%USERPROFILE%\.corp-proxy\secrets.local.yaml`.

```powershell
Test-NetConnection 192.168.136.140 -Port 3332
curl -k -x http://127.0.0.1:10808 https://sfera.inno.local/
```

### Где какой 3proxy

| Машина | 3proxy |
|--------|--------|
| **host2** (`Host2VpnForwardProxy`, :3128) | OK — для WireGuard-клиентов, не ставить на VM |
| **VM** | **Нет** — только JVM corp-proxy (`java -jar`), без VPN на госте |

`Prepare-Host2-3ProxyForVm.ps1` — только **на host2** (есть диск `D:\Exchange\...`). На VM этот скрипт не нужен, если 3proxy на госте не используем.

## Скорость

Цепочка host2 -> VM proxy остаётся; выигрыш даёт **corp-proxy.jar вместо PS probe** + **optimize-v2rayn-corp-lan.ps1** на host2. Тяжёлый Cloud/Sfera — браузер **внутри VM**.

## Дальнейшее развитие

ТЗ на JVM/companion-прокси (External Tool / plugin, без 3proxy): **`TZ-IDE-CORP-PROXY.md`**.
