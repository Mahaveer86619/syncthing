#Requires -Version 5.1
<#
.SYNOPSIS
    Starts sync.ps1 silently at every logon (Startup-folder shortcut, no admin needed).
    Pass -Uninstall to remove it.
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'syncthing-vault-sync.lnk'

if ($Uninstall) {
    if (Test-Path $lnk) { Remove-Item $lnk }
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like '*laptop-sync*sync.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId }
    Write-Host 'Removed startup entry and stopped the running sync.'
    return
}

$script = Join-Path $PSScriptRoot 'sync.ps1'
if (-not (Test-Path (Join-Path $PSScriptRoot 'config.json'))) { throw 'Create config.json first (see config.example.json).' }

# conhost --headless runs the console app with no window at all, not even a flash.
$shell = New-Object -ComObject WScript.Shell
$sc = $shell.CreateShortcut($lnk)
$sc.TargetPath = "$env:WINDIR\System32\conhost.exe"
$sc.Arguments = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`""
$sc.WorkingDirectory = $PSScriptRoot
$sc.Save()

Start-Process -FilePath $sc.TargetPath -ArgumentList $sc.Arguments -WorkingDirectory $PSScriptRoot
Write-Host "Installed: $lnk"
Write-Host "Sync is running now; log: $(Join-Path $PSScriptRoot 'logs\sync.log')"
