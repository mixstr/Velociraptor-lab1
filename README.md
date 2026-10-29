# Лабораторная работа № 1 — Velociraptor

**Дисциплина:** Расследование инцидентов компьютерной безопасности  
**Студент:** Соколов Сергей Андреевич, КТ-23-04  
**Преподаватель:** Клинников Владимир Михайлович  
**Версия:** Velociraptor 0.77.3 · 29 октября 2026 г.

«Velociraptor: развёртывание, детектирование, автоматизация и имитация атак» —
полный цикл: сервер с TLS и systemd → агенты Windows/Linux → сбор артефактов →
3 VQL-детекции → безопасная имитация атаки → обнаружение и реагирование →
автоматизированная установка агентов → алерты в лог (SIEM) → зашифрованные доказательства.

## Лабораторный стенд (VMware Workstation, изолированная сеть VMnet2)

| ВМ | ОС | Адрес (VMnet2, host-only) | Роль |
|---|---|---|---|
| VR-SERVER | Kali Linux (rolling) | 192.168.88.10 | Velociraptor-сервер: TLS frontend :8000, GUI :8889 (только 127.0.0.1), Ansible controller |
| VR-WIN | Windows 11 Pro 26H2 | 192.168.88.20 | Windows-агент, объект имитации атаки |
| vr-linux | Kali Linux (rolling) | 192.168.88.30 | Linux-агент; «C2-слушатель» `nc -lvnp 9001` |

* DNS-имя сервера `velociraptor.lab` прописано в `hosts` всех ВМ.
* VMnet2: host-only, без DHCP, `192.168.88.0/24`. На время атаки NAT-адаптеры VR-WIN и vr-linux отключались.
* Веб-интерфейс доступен только через SSH-туннель: `ssh -L 8889:127.0.0.1:8889 kali@192.168.88.10`.
* Snapshot'ы: `00-clean-base`, `01-server-installed`, `02-agents-installed`, `03-before-attack`.

## Состав репозитория

| Каталог | Содержимое |
|---|---|
| `vql/` | 3 VQL-правила (`*.vql`) и их артефакты (`Custom.Lab.*.yaml`); `vql/results/` — экспорт результатов в JSON/CSV |
| `siem/` | `Custom.Lab.AlertsToLog.yaml` — серверный мониторинг, пишущий алерты в JSONL |
| `scripts/` | Ansible playbook + inventory (Linux), PowerShell-скрипт (Windows), скрипт манифеста |
| `logs/` | `ansible/first-run.log`, `ansible/second-run.log`, `deploy-windows.log`, `lab-alerts.jsonl`, `evidence_manifest.csv` |
| `evidence/` | Зашифрованные (`_locked.zip`) выгрузки Velociraptor: baseline и инцидент |
| `docs/screenshots/` | Скриншоты всех этапов |
| `report/` | PDF-отчёт |
| `files/` | Описание персональных установщиков агента (сами `.deb`/`.msi` в Git не хранятся) |

**Пароль зашифрованных архивов:** `lab1-password` (задан в Velociraptor как *Downloads Password*).

## Сервер

```bash
velociraptor config generate --merge '{"Frontend":{"hostname":"velociraptor.lab","bind_port":8000},
  "GUI":{"bind_address":"127.0.0.1","bind_port":8889},
  "Client":{"server_urls":["https://velociraptor.lab:8000/"]},
  "Datastore":{"location":"/opt/velociraptor","filestore_directory":"/opt/velociraptor"}}' > server.config.yaml
velociraptor debian server --config server.config.yaml && sudo dpkg -i velociraptor-server-*.deb
sudo systemctl enable --now velociraptor_server
```

TLS: сертификат `CN=VelociraptorServer`, издатель `O=Velociraptor CA` (собственный CA сервера), срок 1 год.
Служба `velociraptor_server.service` — `active (running)`, `enabled`.

## Результаты VQL

| Правило | Артефакт | Проверенный результат | Ограничение |
|---|---|---|---|
| `new-in-temp` | `Custom.Lab.NewInTemp` | 2 находки в `C:\Users\user\AppData\Local\Temp`: `lab-benign-update.exe` (SHA-256 `468ffe12…b684577e`, подпись *trusted*, `Btime` 29.10 21:57 > `Mtime` 13.09 — файл скопирован) и `lab-beacon.ps1` (`31b1ea48…2b0aa58f`, без подписи) | Окно 60 мин по `Btime`; только %TEMP% и `C:\Windows\Temp` |
| `persistence-delta` | `Custom.Lab.PersistenceDelta` | `HKLM\…\CurrentVersion\Run\VelociraptorLabAutorun` → `"…\Temp\lab-benign-update.exe"`, `Diff=added` (через 5 с после изменения) | Run/RunOnce (HKLM, HKU) и папки Startup; службы, задачи, WMI не охвачены |
| `outbound-anomaly` | `Custom.Lab.OutboundAnomaly` | `192.168.88.20:56972 → 192.168.88.30:9001`, `State=5`, PID 1744 `powershell.exe -WindowStyle Hidden -File …\Temp\lab-beacon.ps1` | Точечная проверка (WMI `MSFT_NetTCPConnection`); allowlist портов |

До атаки («чистый» хост) правила `new-in-temp` и `outbound-anomaly` вернули 0 строк.

## Имитация атаки и реагирование

1. Доставка: копия `notepad.exe` → `%TEMP%\lab-benign-update.exe`; скрипт `%TEMP%\lab-beacon.ps1`.
2. Закрепление: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\VelociraptorLabAutorun`.
3. «C2»: скрытый PowerShell (PID 1744) каждые 10 с отправляет строку `lab-beacon` на `vr-linux:9001`.

Реакция (порядок: доказательства → остановка → изоляция → очистка → восстановление):

| Действие | Средство | Результат |
|---|---|---|
| Дамп памяти | `Windows.Memory.ProcessDump` (PID 1744) | `1744_powershell.exe.dmp`, 210 769 422 байт |
| Копии файлов | `Windows.Search.FileFinder` (`lab-*`, Upload+Hash) | 2 файла (255 и 360 448 байт) |
| Kill | `Stop-Process -Id 1744 -Force` | Соединение закрыто, `nc` на vr-linux завершился |
| Soft containment | `Windows.Remediation.Quarantine` (IPsec) | vr-linux:22 — **False**, velociraptor.lab:8000 — **True** |
| Очистка | удаление Run-ключа и файлов `lab-*` | Проверено повторным запросом |
| Снятие изоляции | Quarantine с `RemovePolicy` | Связь восстановлена |

## Автоматизация и идемпотентность

На VR-SERVER из `scripts/` (SSH-ключ на vr-linux, sudo-пароль через `-K`):

```bash
ansible -i inventory.ini linux_clients -m ping
ansible-playbook -i inventory.ini install-velociraptor-linux.yml -K | tee ../logs/ansible/first-run.log
ansible-playbook -i inventory.ini install-velociraptor-linux.yml -K | tee ../logs/ansible/second-run.log
```

| Запуск (агент предварительно удалён `dpkg -r`) | PLAY RECAP |
|---|---|
| первый | `ok=9 changed=2 unreachable=0 failed=0` — `installed in this run, service=active` |
| второй | `ok=7 changed=0 unreachable=0 failed=0 skipped=2` — `already installed, service=active` |

Windows (агент предварительно удалён через `Win32_Product.Uninstall`, ReturnValue 0):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Temp\install-velociraptor-windows.ps1
```

| Запуск | Результат |
|---|---|
| первый | `INSTALL MSI … SHA256=94405EDB…568C8`, `MSI exit code: 0`, `Changed=true Service=Running Frontend8000=True` |
| второй | `SKIP HOSTS`, `SKIP MSI`, `Changed=false Service=Running Frontend8000=True` |

**Идемпотентность подтверждена на установке «с нуля» для обеих платформ.**

## SIEM (упрощённо)

Серверный артефакт `siem/Custom.Lab.AlertsToLog.yaml` превращает каждую находку правил
`Custom.Lab.*` в алерт: строка JSON в `/opt/velociraptor/logs/lab-alerts.jsonl`
и событие сервера (просмотр в Notebook/Server Events). Проверено: алерт
`Custom.Lab.NewInTemp/NewExecutablesInTemp`, `VR-WIN`, `severity=high`, 29.10.2026 23:40:37.

## Шифрование доказательств

Все выгрузки коллекций сделаны с паролем (*Downloads Password*), Velociraptor
формирует защищённые паролем архивы `*_locked.zip`. Контрольные суммы — `logs/evidence_manifest.csv`
(`scripts/make-evidence-manifest.ps1`). Незашифрованные `.dmp`, `.exe`, `.ps1`,
а также конфиги и установщики с ключами исключены `.gitignore`.
