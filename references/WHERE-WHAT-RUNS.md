# host2 vs VM — что где запускать

| Действие | Где | Команда |
|----------|-----|---------|
| v2rayN, браузер, `curl -x 127.0.0.1:10808` | **host2** (HOME-3, `D:\Exchange\...`) | обычная работа |
| Системный прокси для браузера | **host2** | один раз: `fix-v2rayn-browser-corp.ps1`, потом Reload v2rayN |
| Слушалка probe :3334 | **только VM**, только отладка | `Run-VmHttpProbeListener.ps1` |
| corp-proxy :3332 | **только VM** | External Tool / `java -jar tools/corp-proxy/corp-proxy.jar` — см. `vm-corp-proxy/corp-proxy/README.md` |
| Лог probe | общий диск | `...\vm-probe\logs\probe.log` |

**Не запускай** `Start-VmHttpProbeListener.ps1` на host2 без `-AllowOnHost2` — v2rayN ходит на **192.168.136.140:3334** (VM), не на host2.

Цепочка для Sfera:

```text
браузер (host2) -> системный прокси 127.0.0.1:10808 -> v2rayN -> corp-vm -> VM:3332 (corp-proxy.jar) -> sfera.inno.local
```

Probe `:3334` — только отладка, в бою его быть не должно.
