# ТЗ: corp CONNECT-прокси как External Tool / companion IntelliJ IDEA (VM)

Документ для передачи в новый диалог (генерация кода). Контекст проекта: **host2** → v2rayN → **VM (192.168.136.140)** → корп. сеть; **WireGuard и отдельные «VPN» на VM нельзя**; **3proxy.exe** на VM детектится Kaspersky как `HackTool.Win64.3Proxy.a`.

---

## 1. Цель

Получить **HTTP/HTTPS forward proxy (CONNECT + Basic auth)** на VM, который:

1. Работает как **штатный dev-инструмент рядом с IntelliJ** (External Tool, Run Configuration, или **плагин IDE**), а не как отдельный «подозрительный» `.exe` + Scheduled Task.
2. Принимает трафик с **host2** (`192.168.136.1`) и при необходимости с **WireGuard-подсетей** (`10.200.0.0/16`) через **VMnet8**.
3. Выдерживает **много параллельных HTTPS** (SPA Cloud/Sfera: сотни CONNECT).
4. Настраивается через **конфиг-файл** (порт, bind, логин/пароль, путь логов) без правки исходников.
5. **Стартует вместе с IntelliJ** (один клик / автозапуск при открытии проекта — на выбор реализации).

**Не цель:** обход корпоративной ИБ, скрытие от Sakura/Kaspersky обфускацией бинарников или маскировкой под легитимное ПО. Ложные срабатывания решаются **архитектурой (JVM-процесс IDE)**, **согласованием с ИБ** и **allowlist**, а не «невидимым» прокси.

---

## 2. Ограничения и риски (обязательно учесть при проектировании)

| Ограничение | Следствие для реализации |
|-------------|---------------------------|
| Kaspersky + Sakura на VM | Готовые бинарники **3proxy, squid, mitmproxy** — высокий риск детекта; не использовать как основу без согласования с ИБ |
| Политика ИБ | Любой **listening port** + **CONNECT relay** может попасть в EDR; нужен **минимальный** функционал, логирование, возможность показать ИБ назначение |
| Нет VPN на VM | Прокси только **forward** на VM; egress в корп — обычный маршрут гостя |
| IntelliJ «HTTP Proxy» в Settings | Это **исходящий** proxy клиента IDE; для host2 нужен **входящий** listener (отдельный компонент) |
| Общая папка host2↔VM | Конфиг/секреты могут лежать на `Z:\Exchange\...`; **не хранить пароль в git** |

---

## 3. Рекомендуемый класс решений (для генерации)

**Приоритет A — JVM/Kotlin companion (предпочтительно)**

- Отдельный модуль **Gradle** (`:corp-proxy`) или **IntelliJ Platform plugin** (optional).
- Запуск: External Tool → `java -jar corp-proxy.jar --config ...` **или** кнопка плагина «Start Corp Proxy».
- Процесс: **`java.exe`** с main-class проекта (как обычный dev tool), не переименованный `3proxy.exe`.
- Протокол: минимальный **HTTP proxy** (METHOD CONNECT, Basic auth, optional GET для health).
- Стек: Netty, Ktor CIO, или `com.sun.net.httpserver` + ручной CONNECT (Netty предпочтительнее для concurrency).

**Приоритет B — встроить в существующий probe только как dev (не prod)**

- PowerShell probe уже есть (`vm-probe/`); **медленный**, EDR смотрит на PowerShell listener — **не** соответствует «не палиться» и нагрузке.

**Не делать без явного согласования ИБ**

- Обфускация/упаковка исходников **ради** обхода сигнатур AV.
- Переименование известных hacktool-бинарников.
- Reverse tunnel, frp, WireGuard на VM.

---

## 4. Функциональные требования

### 4.1 Протокол

- **HTTP/1.1 proxy**: `CONNECT host:443 HTTP/1.1`, ответ `200 Connection Established`, двусторонний relay байт.
- **Proxy-Authorization: Basic** — опционально отключаемо для теста; в prod **обязательно**.
- **ACL по доменам** (как на host2): разрешать только суффиксы  
  `*.inno.local`, `*.cloud.vtb.ru`, `*.region.vtb.ru`, `*.dev.vtb.ru`, `*.vtb.ru`; остальное **403/502**.
- **Health**: `GET /health` → `200 OK` (без auth или с auth — настраивается).

### 4.2 Производительность

- **≥ 256 одновременных CONNECT** (целевое **512**).
- **Async I/O** (Netty event loop или эквивалент); без блокировки thread-per-connection на PS.
- Таймауты: idle read/write configurable; connect timeout к upstream (corp) **≤ 30 s**.
- **TCP_NODELAY**, keep-alive на клиентском сокете.
- Опционально: лимит соединений с одного IP (host2 = один IP).

### 4.3 Конфигурация

Файл **YAML или properties** (путь через `--config` или env):

```yaml
listen:
  host: 192.168.136.140   # только VMnet, не 0.0.0.0 без необходимости
  port: 3332
auth:
  username: admin
  password: "<secret>"
acl:
  domain_suffixes:
    - inno.local
    - cloud.vtb.ru
    - region.vtb.ru
    - dev.vtb.ru
    - vtb.ru
logging:
  path: C:/Users/master/.cache/jetbrains/corp-proxy/access.log
  level: INFO
  rotate_mb: 50
limits:
  max_connections: 512
```

- Секреты: поддержать **override** из `%USERPROFILE%\.corp-proxy\secrets.local.yaml` (gitignore).
- **Синхронизация с host2**: те же значения дублировать в `host2-forward-proxy/proxy-secrets.local.ps1` (`UpstreamHost`, `UpstreamPort`, `UpstreamUser`, `UpstreamPassword`) + скрипт `sync-corp-vm-from-secrets.ps1`.

### 4.4 Интеграция с IntelliJ IDEA

1. **External Tool** (минимум):
   - Name: `Corp Proxy Start`
   - Program: `java`
   - Args: `-jar "$ProjectFileDir$/tools/corp-proxy/corp-proxy.jar" --config "$ProjectFileDir$/tools/corp-proxy/config.yaml"`
   - Working directory: `$ProjectFileDir$`
2. **Автозапуск с IDE** (один из вариантов, реализовать лучший):
   - **StartupActivity** в лёгком plugin; или
   - **External tool** + «Run on project open» через `.idea/workspace.xml` hook (хрупко); или
   - **Gradle task** `startCorpProxy` + compound Run Configuration «IDE + Proxy».
3. **Остановка**: External Tool `Stop` (kill by port/jpid file) или plugin dispose.
4. **UI (optional)**: Tool Window — статус listen, active connections, tail log.

Порт по умолчанию **3332** (совместимость с текущим IntelliJ-related портом в secrets); смена порта — только конфиг + `sync-corp-vm-from-secrets.ps1` на host2.

### 4.5 Сеть и firewall

- Bind только **`192.168.136.140`** (или auto-detect IP VMnet).
- Windows Firewall: inbound **TCP порт** только с `192.168.136.0/24`, `10.200.0.0/16`.
- **Не** создавать Scheduled Task SYSTEM без необходимости; процесс — **дочерний к сессии пользователя** (master), завершать при закрытии IDE (если plugin) или явной остановке.

---

## 5. Нефункциональные требования («не палиться» — корректная трактовка)

| Требование | Реализация |
|------------|------------|
| Нет сигнатуры HackTool.3Proxy | **Не** использовать 3proxy/squid бинарники; свой **JVM**-сервис |
| Похоже на dev workflow | Jar в каталоге проекта/`tools/`, запуск из IDE, логи в `%USERPROFILE%\.cache\jetbrains\...` |
| Прозрачность для ИБ | README для ИБ: назначение, порты, ACL, sample log line, нет tunnel/VPN |
| Минимальные права | Без admin для обычного запуска; firewall rule — один раз (documented script, optional) |
| Согласование | В ТЗ заложить шаг: **заявка в ИБ** на allowlist `java.exe` + command line + path |

Обфускация **не** входит в scope MVP.

---

## 6. Интеграция с текущей инфраструктурой (host2)

```text
[host2 browser / v2rayN :10808]
        → outbound HTTP corp-vm (Basic auth)
        → VM listen 192.168.136.140:3332
        → CONNECT → corp targets
```

- v2rayN: профиль **corp-vm**, routing **corp_vm_domains** / `*.vtb.ru` и т.д.
- После смены порта/кредов на VM: **`sync-corp-vm-from-secrets.ps1`** на host2, Reload v2rayN.
- host2 **3128** (3proxy): upstream `UpstreamHost:UpstreamPort` из того же `proxy-secrets.local.ps1`.
- Документы: `IB-NO-3PROXY-ON-VM.md`, `PERFORMANCE.md`, `v2rayN-corp-routing.md`.

---

## 7. Критерии приёмки

1. С VM: `Get-NetTCPConnection -LocalPort 3332 -State Listen` → `LocalAddress` = `192.168.136.140`.
2. С host2: `Test-NetConnection 192.168.136.140 -Port 3332` → `True`.
3. С host2: `curl -k -x http://127.0.0.1:10808 https://sfera.inno.local/` → HTML (через v2rayN).
4. Cloud/Sfera в браузере host2: нет массовых timeout vs baseline «браузер в VM» (субъективно лучше PS probe).
5. 50+ параллельных `curl` через proxy — без исчерпания threads и без падения процесса.
6. Запуск/остановка из IntelliJ без ручного PowerShell.
7. Kaspersky: **нет** детекта `HackTool.Win64.3Proxy.a` (не гарантия «невидимости» — фиксируем отсутствие известного FP на 3proxy).

---

## 8. Поставка (deliverables)

1. Исходники: модуль `corp-proxy` (Kotlin/Java), README сборки.
2. `tools/corp-proxy/config.example.yaml` + инструкция secrets.
3. Скрипт **однократной** настройки firewall (optional, admin): `Set-CorpProxyFirewall.ps1`.
4. Инструкция IntelliJ: External Tool + (optional) plugin install from disk.
5. Обновление `proxy-secrets.example.ps1` и комментарий в `sync-corp-vm-from-secrets.ps1`.
6. Краткая **записка для ИБ** (1 стр.): назначение, ACL, порты, без VPN.

---

## 9. Prompt для нового диалога (скопировать)

```
Реализуй ТЗ из файла wireguard-setup/host2-forward-proxy/vm-corp-proxy/TZ-IDE-CORP-PROXY.md.

Стек: Kotlin + Netty, fat JAR, HTTP CONNECT proxy с Basic auth и ACL по domain suffix.
Конфиг YAML. Bind 192.168.136.140:3332. Max 512 conn. Логи в файл с ротацией.
IntelliJ: External Tool + опционально минимальный plugin (StartupActivity старт/стоп).
Не использовать 3proxy/squid. Без обфускации для обхода AV.
Добавь Gradle wrapper, тесты на CONNECT + ACL, README и config.example.yaml.
Секреты не коммитить. Совместимость с host2 v2rayN corp-vm и proxy-secrets.local.ps1.
```

---

## 10. Открытые вопросы (уточнить перед кодом)

1. Plugin vs только External Tool — нужен ли UI в IDE?
2. Фиксированный порт **3332** или configurable default **3333**?
3. Нужен ли **HTTPS** listener (обычно не нужен для corp-vm HTTP outbound).
4. Sakura: есть ли **whitelist** для кастомных jar, если приложить записку ИБ?
5. Завершать proxy при закрытии IDE **всегда** или оставлять в фоне?
