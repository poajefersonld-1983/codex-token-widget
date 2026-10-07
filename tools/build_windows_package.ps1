$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
& node (Join-Path $PSScriptRoot 'check_public_tree.cjs') $root
if ($LASTEXITCODE -ne 0) { throw 'Verificação de publicação falhou.' }
# Explicit allowlist. Never copy the installed app, LOCALAPPDATA or a profile.
$files = @('LICENSE','windows\README.md','windows\install.ps1','windows\monitor.ps1','windows\backend.cjs','windows\backend.test.cjs')
$sources = @($files | ForEach-Object { Join-Path $root $_ })
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$target = Join-Path $dist 'Codex-Token-Monitor-Windows-1.1.0.zip'
Compress-Archive -LiteralPath $sources -DestinationPath $target -Force
Write-Output ('Pacote público criado: ' + $target)
