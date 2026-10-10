#Requires -Version 5.1
<#
.SYNOPSIS
    Installs the Windows build of Syncthing for the current user (no admin needed).
    Run `flutter build windows --release` in app/ first. Pass -Uninstall to remove it.
#>
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$dest = Join-Path $env:LOCALAPPDATA 'Programs\Syncthing'
$menu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Syncthing.lnk'
$desktop = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Syncthing.lnk'

Get-Process syncthing -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "$dest*" } | Stop-Process -Force

if ($Uninstall) {
    Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $menu, $desktop -ErrorAction SilentlyContinue
    Write-Host 'Removed the app. Background sync settings in %LOCALAPPDATA%\Syncthing were kept.'
    return
}

$build = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $build 'syncthing.exe'))) { throw "No build found at $build; run: flutter build windows --release" }

if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Copy-Item $build $dest -Recurse

$shell = New-Object -ComObject WScript.Shell
foreach ($path in $menu, $desktop) {
    $sc = $shell.CreateShortcut($path)
    $sc.TargetPath = Join-Path $dest 'syncthing.exe'
    $sc.WorkingDirectory = $dest
    $sc.Description = 'Sync your Obsidian vault with GitHub'
    $sc.Save()
}
Write-Host "Installed to $dest (Start menu and desktop shortcuts added)"
