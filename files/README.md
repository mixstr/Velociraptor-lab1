# Лабораторная работа № 1 — Velociraptor

**Дисциплина:** Расследование инцидентов компьютерной безопасности  
**Студент:** Соколов Сергей Андреевич, КТ-23-04  
**Преподаватель:** Клинников Владимир Михайлович  
**Версия:** Velociraptor 0.77.3 · 29 октября 2026 г.

## Лабораторный стенд

| ВМ | Операционная система | Host-only адрес | Роль |
|---|---|---|---|
| VR-SERVER | Kali Linux (rolling) | 192.168.88.10 | Velociraptor сервер, TLS frontend :8000, Ansible controller |
| VR-WIN | Windows 11 Pro 26H2 | 192.168.88.20 | Windows-агент |
| vr-linux | Kali Linux (rolling) | 192.168.88.30 | Linux-агент, «C2-слушатель» `nc -lvnp 9001` |

Гипервизор VMware Workstation, изолированная сеть VMnet2 (host-only, `192.168.88.0/24`, без DHCP).
DNS-имя сервера: `velociraptor.lab`; административный интерфейс :8889 слушает только `127.0.0.1` и доступен через SSH-туннель (`ssh -L 8889:127.0.0.1:8889 kali@192.168.88.10`).

Для ВМ VR-SERVER и vr-linux назначен пользователь `kali` с паролем `kali` (права root через `sudo`), для ВМ VR-WIN — локальный пользователь `user`.

Пароль от зашифрованных архивов - `lab1-password`

## Состав репозитория

- `vql/` — три успешно проверенные VQL-детекции (`*.vql`) + YAML-описания артефактов `Custom.Lab.*`; `vql/results/` — экспорт результатов в JSON/CSV. Третья детекция использует WMI (`MSFT_NetTCPConnection`); исходная версия с ошибкой сравнения поля `State` в чистовую поставку не включена.
- `siem/` — серверный артефакт `Custom.Lab.AlertsToLog`, записывающий алерты в JSONL.
- `scripts/` — PowerShell, Ansible, inventory, скрипт манифеста и инструкция.
- `logs/ansible/{first-run,second-run}.log`, `logs/deploy-windows.log` — фактические журналы выполнения; `logs/lab-alerts.jsonl` — журнал алертов.
- `logs/evidence_manifest.csv` — проверочный реестр архивов с SHA-256.
- `docs/screenshots/` — иллюстрации проверок.
- `report/` — PDF-отчёт.
- `evidence/` — зашифрованные доказательства и дамп памяти.

## Результаты VQL

| Правило | Проверенный результат | Ограничение |
|---|---|---|
| `new-in-temp` | Обнаружены `lab-benign-update.exe` (подпись *trusted*, `Btime` 29.10 > `Mtime` 13.09 — файл скопирован) и `lab-beacon.ps1` в TEMP, по одной строке на файл, с SHA-256 | Окно 60 мин по `Btime`; только `%TEMP%` и `C:\Windows\Temp` |
| `persistence-delta` | `VelociraptorLabAutorun` добавлен в HKLM Run (`Diff=added`) | Run/RunOnce (HKLM, HKU) и папки Startup |
| `outbound-anomaly` (`WMI`) | TCP `192.168.88.20:56972 → 192.168.88.30:9001`, `State=5`, PID 1744 `powershell.exe -WindowStyle Hidden -File …\lab-beacon.ps1` | Однократная проверка; порты из allowlist не проверяются |

До атаки правила `new-in-temp` и `outbound-anomaly` вернули 0 строк.

После сбора копий тестовых файлов и дампа процесса PowerShell (PID 1744, 210 769 422 байт) процесс завершён, выполнена сетевая изоляция `Windows.Remediation.Quarantine`: доступ к `192.168.88.30:22` заблокирован (`False`), при этом доступ к Velociraptor по `192.168.88.10:8000` сохранился (`True`). Run-ключ и файлы удалены, после снятия политики связь восстановилась.

## Автоматизация и воспроизводимость

На сервере `VR-SERVER` (после настройки SSH-ключей) из каталога `scripts/`:

```bash
ansible -i inventory.ini linux_clients -m ping
ansible-playbook -i inventory.ini install-velociraptor-linux.yml -K | tee ../logs/ansible/first-run.log
ansible-playbook -i inventory.ini install-velociraptor-linux.yml -K | tee ../logs/ansible/second-run.log
```

Перед первым запуском агент был удалён (`dpkg -r velociraptor-client`).
Первый запуск: `ok=9 changed=2 unreachable=0 failed=0` — пакет установлен.
Второй запуск: `ok=7 changed=0 unreachable=0 failed=0 skipped=2`; служба `velociraptor_client` активна.

PowerShell администратора Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Temp\install-velociraptor-windows.ps1
```

Перед первым запуском агент был удалён (`Win32_Product.Uninstall`, ReturnValue 0).
Первый запуск: `INSTALL MSI`, `MSI exit code: 0`, `Changed=true`, `Service=Running`.
Второй запуск: `SKIP HOSTS`, `SKIP MSI`, `Changed=false`, `Service=Running`. **Идемпотентность подтверждена на установке агента «с нуля».**

## SIEM

Серверный артефакт `Custom.Lab.AlertsToLog` превращает каждую находку правил `Custom.Lab.*` в алерт и дописывает его в `/opt/velociraptor/logs/lab-alerts.jsonl`. Проверено: алерт `Custom.Lab.NewInTemp/NewExecutablesInTemp`, хост `VR-WIN`, `severity=high`.
