# host2: автоматическая маршрутизация VTB/inno через v2rayN

На host2 **не нужно** вручную ставить системный прокси `127.0.0.1:3128`, если уже работает **v2rayN** с системным прокси (у вас `SysProxyType: 1`).

Цепочка:

```text
Приложение -> v2rayN (Xray, правила) -> corp-vm (HTTP) -> 192.168.136.140:3332 (IntelliJ) -> корп. сеть
Остальное -> как сейчас (VLESS / direct)
```

Локальный **3proxy** на `10.200.x:3128` — только для **удалённых** VPN-клиентов (host3, Mac), не для host2.

---

## 0. Важно: версия Xray на host2

v2rayN **7.24.9** для профиля **HTTP** пишет outbound в формате `settings.address` / `user` / `pass`.
**Xray 25.x** (например 25.5.16 в `%LocalAppData%\v2rayN\bin\xray`) с этим **не стартует**:

`Failed to start: proxy/http: 0 target server` → ядро не поднимается, `127.0.0.1:10808` мёртв, интернет «пропал».

Нужен **Xray 26+** (как в `C:\Program Files\v2rayN-windows-64\bin\xray` после обновления v2rayN).

Быстрое восстановление на host2 (PowerShell):

```powershell
D:\Exchange\projects\wireguard-setup\host2-forward-proxy\fix-v2rayn-corp-xray-core.ps1
```

Либо в v2rayN: **Check update → Xray**, перезапуск.

---

## 1. Добавить HTTP upstream (один раз)

1. v2rayN → **Servers** → **Add [HTTP] server** (или Import custom).
2. Параметры:
   - **Address:** `192.168.136.140`
   - **Port:** `3332` (IntelliJ default; см. `proxy-secrets.local.ps1`)
   - **Username:** `admin`
   - **Password:** из `proxy-secrets.local.ps1`
   - **Remarks / alias:** `corp-vm` (важно для правила)
3. **Не** делайте его активным основным сервером — активным остаётся VLESS.

---

## 2. Правила маршрутизации (выше VLESS-списка)

**Settings → Routing setting → Add rule** (или «Правила маршрутизации»).

Добавьте **одно** правило **в начало списка** (выше правила с YouTube/Google → proxy):

| Поле | Значение |
|------|----------|
| Rule type | Domain / Домен |
| Domain | `inno.local`, `cloud.vtb.ru`, `region.vtb.ru`, `dev.vtb.ru` |
| Match mode | Subdomain / suffix (чтобы покрыть `*.…`) |
| Outbound / Server | **corp-vm** (HTTP-сервер из шага 1) |

Сохранить → **Reload** / переподключить v2rayN.

---

## 3. DNS для `*.inno.local`

Если внутренние имена не резолвятся:

- **Settings → DNS setting** → для `inno.local` укажите DNS, доступный через VM (или static **Hosts** в v2rayN / `C:\Windows\System32\drivers\etc\hosts`).
- Домены `*.vtb.ru` обычно резолвятся публично; при необходимости — корп. DNS через ту же VM.

---

## 4. Активный набор правил (v2rayN 7+)

В **`guiNConfig.json` поле `RoutingBasicItem.RoutingIndexId` всегда пустое** — это не баг. Начиная с v2rayN 7, выбранный набор хранится в SQLite: **`RoutingItem.IsActive = 1`** (у вас это **`mySet`**, id `4768167807311779449`). Скрипты `optimize-v2rayn-host2.ps1` / `patch-v2rayn-corp-routing.py` выставляют **IsActive**, а не RoutingIndexId.

Проверка:

```powershell
D:\Exchange\projects\wireguard-setup\host2-forward-proxy\verify-v2rayn-corp-routing.ps1
```

---

## 5. Проверка трафика

1. v2rayN → **Enable system proxy** (как обычно).
2. Браузер / `curl -x http://127.0.0.1:10808` — в сгенерированном `binConfigs\config.json` первое правило должно вести на outbound вида **`6123456789012345678-proxy-corp-vm`** (не на `proxy`/VLESS).
3. Лог **только через файлы** (в GUI v2rayN 7 нет всех переключателей): закрой v2rayN → `enable-v2rayn-corp-debug.ps1` → Reload → `curl -x http://127.0.0.1:10808 ...` → `%LocalAppData%\v2rayN\logs\corp-xray-error.log`. В логе должно быть `taking detour [6123456789012345678-proxy-corp-vm]` и `dialing TCP ... 192.168.136.140:3333`.
4. `Test-NetConnection 192.168.136.140 -Port 3332` — IntelliJ proxy доступен с host2.
5. Синхронизация порта/кредов с secrets: `sync-corp-vm-from-secrets.ps1` на host2.

---

## 6. Браузер vs `curl -x 10808`

| | `curl -x http://127.0.0.1:10808` | Браузер |
|---|-----------------------------------|---------|
| Прокси | явно | системный прокси Windows (WinINET) |
| `*.inno.local` | всегда через 10808 | может **обходить** прокси, если включено «не проксировать локальные адреса» (`NotProxyLocalAddress`) |

Если HTML через curl есть, а браузер висит:

```powershell
D:\Exchange\projects\wireguard-setup\host2-forward-proxy\fix-v2rayn-browser-corp.ps1
```

Reload v2rayN. В Windows: Параметры → Сеть → Прокси — **127.0.0.1:10808**, список обхода **без** `<local>` и без `10.*` для corp.

---

## 7. 3proxy для VPN-клиентов

После исправления ACL перезапустите установку (админ):

```powershell
D:\Exchange\projects\wireguard-setup\host2-forward-proxy\Install-Host2VpnForwardProxy.ps1 -SkipDownload
```

Проверка: `Get-NetTCPConnection -LocalPort 3128 -State Listen`.

На host3: системный прокси `http://10.200.1.2:3128` (или `.2.2`).
