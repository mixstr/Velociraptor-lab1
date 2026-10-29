# Lab 1: idempotent Velociraptor Windows client deployment.
# Run from an elevated PowerShell session:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Temp\install-velociraptor-windows.ps1
# A repeated run changes nothing if the agent is already installed and running.
param(
    [string]$MsiPath = 'C:\Temp\velociraptor-client-lab.msi',
    [string]$ServerIp = '192.168.88.10',
    [string]$ServerName = 'velociraptor.lab',
    [string]$LogDir = 'C:\Temp\Velociraptor-Lab'
)

$ErrorActionPreference = 'Stop'

$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated PowerShell session.'
}

New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
$runLog = Join-Path $LogDir 'deploy-windows.log'
$msiLog = Join-Path $LogDir 'velociraptor-msi.log'

function Write-LabLog([string]$Message) {
    $entry = '{0} {1}' -f (Get-Date).ToString('o'), $Message
    Add-Content -LiteralPath $runLog -Value $entry -Encoding UTF8
    Write-Host $entry
}

Write-LabLog "BEGIN Windows Velociraptor client deployment on $env:COMPUTERNAME"
$changed = $false

# 1. Server name in hosts (added only if missing)
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
if (-not (Select-String -Path $hostsFile -Pattern "\s$([regex]::Escape($ServerName))(\s|$)" -Quiet)) {
    Add-Content -Path $hostsFile -Value "`r`n$ServerIp $ServerName" -Encoding ASCII
    Write-LabLog "HOSTS: added $ServerIp $ServerName"
    $changed = $true
} else {
    Write-LabLog "SKIP HOSTS: $ServerName already present"
}

# 2. Install MSI only if the service is absent
$service = Get-Service -Name 'Velociraptor' -ErrorAction SilentlyContinue
if ($null -eq $service) {
    if (-not (Test-Path -LiteralPath $MsiPath -PathType Leaf)) {
        throw "Velociraptor service not found and MSI missing: $MsiPath"
    }
    $hash = (Get-FileHash -LiteralPath $MsiPath -Algorithm SHA256).Hash
    Write-LabLog "INSTALL MSI: $MsiPath SHA256=$hash"
    $msiArgs = '/i "{0}" /qn /norestart /L*v "{1}"' -f $MsiPath, $msiLog
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -PassThru -Wait
    Write-LabLog "MSI exit code: $($proc.ExitCode)"
    if ($proc.ExitCode -notin @(0, 3010)) { throw "MSI failed with exit code $($proc.ExitCode), see $msiLog" }
    $changed = $true
    $service = Get-Service -Name 'Velociraptor'
} else {
    Write-LabLog 'SKIP MSI: Velociraptor service already installed'
}

# 3. Service: automatic start and Running state
if ($service.StartType -ne 'Automatic') {
    Set-Service -Name 'Velociraptor' -StartupType Automatic
    Write-LabLog 'SET StartupType=Automatic'
    $changed = $true
}
$service.Refresh()
if ($service.Status -ne 'Running') {
    Write-LabLog "START SERVICE: previous status=$($service.Status)"
    Start-Service -Name 'Velociraptor'
    $changed = $true
}

# 4. Verification
$service = Get-Service -Name 'Velociraptor'
$tcp = Test-NetConnection -ComputerName $ServerName -Port 8000 -InformationLevel Quiet -WarningAction SilentlyContinue
if ($service.Status -ne 'Running') { throw "Velociraptor service is not running: $($service.Status)" }
Write-LabLog "RESULT Changed=$($changed.ToString().ToLower()) Service=$($service.Status) Frontend8000=$tcp"
Write-LabLog 'END Windows Velociraptor client deployment'
