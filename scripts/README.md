# Автоматизация установки агентов

## Linux (Ansible, запуск на VR-SERVER)

1. Положите персональный пакет агента в `../files/velociraptor-linux-client.deb`
   (собирается командой `velociraptor debian client --config client.config.yaml`;
   в Git не хранится — содержит конфигурацию подключения).
2. Настройте SSH-ключ: `ssh-copy-id kali@192.168.88.30`.
3. Запуск:

```bash
ansible -i inventory.ini linux_clients -m ping
ansible-playbook -i inventory.ini install-velociraptor-linux.yml -K | tee ../logs/ansible/first-run.log
ansible-playbook -i inventory.ini install-velociraptor-linux.yml -K | tee ../logs/ansible/second-run.log
```

Идемпотентность (проверено): первый запуск после `dpkg -r velociraptor-client` —
`ok=9 changed=2 failed=0` (копирование и установка .deb); повторный —
`ok=7 changed=0 skipped=2 failed=0`.

## Windows (PowerShell)

Скопируйте MSI с вшитым конфигом (`velociraptor config repack --msi ...`) в
`C:\Temp\velociraptor-client-lab.msi` и выполните в PowerShell администратора:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Temp\install-velociraptor-windows.ps1
```

Журнал: `C:\Temp\Velociraptor-Lab\deploy-windows.log`. Проверено после удаления агента:
первый запуск — `INSTALL MSI ... MSI exit code: 0 ... Changed=true`,
повторный — `SKIP HOSTS`, `SKIP MSI`, `Changed=false Service=Running`.

## Манифест доказательств

`make-evidence-manifest.ps1` пересчитывает SHA-256 всех зашифрованных архивов
в `evidence/` и записывает `logs/evidence_manifest.csv`.
