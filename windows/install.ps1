param([switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
[void](Get-Command node.exe -ErrorAction Stop)
$destination = Join-Path $env:LOCALAPPDATA 'CodexTokenMonitor'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$profile = Join-Path $destination 'profile'
New-Item -ItemType Directory -Path $profile -Force | Out-Null
# Private profile inherits no broad read/write access. Windows keyring stores auth.
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& "$env:SystemRoot\System32\icacls.exe" $profile /inheritance:r /grant:r "*${sid}:(OI)(CI)F" '*S-1-5-18:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível proteger a pasta do widget.' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'monitor.ps1'), (Join-Path $PSScriptRoot 'backend.cjs') -Destination $destination -Force
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Codex Token Monitor.lnk'))
$shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$shortcut.Arguments = '-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $destination 'monitor.ps1') + '"'
$shortcut.WorkingDirectory = $destination
$shortcut.Description = 'Monitor de limites do Codex na bandeja do Windows'
$shortcut.Save()
if (-not $NoLaunch) { Start-Process -FilePath $shortcut.TargetPath -ArgumentList $shortcut.Arguments -WindowStyle Hidden }
Write-Output ('Instalado em ' + $destination)
