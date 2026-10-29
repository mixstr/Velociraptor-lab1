# Builds logs/evidence_manifest.csv: SHA-256 of every encrypted evidence archive.
# Run from the repository root on the host:
#   powershell -ExecutionPolicy Bypass -File .\scripts\make-evidence-manifest.ps1
$root = (Resolve-Path "$PSScriptRoot\..").Path
$out  = Join-Path $root 'logs\evidence_manifest.csv'
Get-ChildItem -Path (Join-Path $root 'evidence') -Recurse -File -Include *.zip, *.7z, *.7z.* |
  Sort-Object FullName |
  ForEach-Object {
    [pscustomobject]@{
      RelativePath = $_.FullName.Substring($root.Length + 1).Replace('\', '/')
      SizeBytes    = $_.Length
      SHA256       = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
      Encrypted    = 'Yes'
    }
  } | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8
Write-Host "Manifest written: $out"
Import-Csv $out | Format-Table -AutoSize
