#Requires -Version 5.1
<#
.SYNOPSIS
    Keeps an Obsidian vault in two-way sync with a private GitHub repo.

.DESCRIPTION
    Watches the vault for edits (debounced), commits them, merges remote changes and pushes.
    Also polls the remote periodically so edits made on the phone arrive without local activity.
    See docs/laptop-sync.md.

.PARAMETER Init
    One-time setup: turn the vault folder into a clone of the notes repo, then run one sync.

.PARAMETER Once
    Run a single sync and exit (useful for testing or for a scheduled job instead of the watcher).
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Init,
    [switch]$Once
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 leaves $PSScriptRoot empty inside param() defaults.
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'config.json' }
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$LogDir = Join-Path $PSScriptRoot 'logs'
$LogFile = Join-Path $LogDir 'sync.log'

function Write-Log([string]$Message) {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory $LogDir | Out-Null }
    if ((Test-Path $LogFile) -and (Get-Item $LogFile).Length -gt 1MB) { Move-Item $LogFile "$LogFile.1" -Force }
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Read-Config {
    if (-not (Test-Path $ConfigPath)) { throw "Config not found: $ConfigPath (copy config.example.json to config.json)" }
    $c = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $defaults = @{ branch = 'main'; deviceName = $env:COMPUTERNAME; debounceSeconds = 15; pollSeconds = 120 }
    foreach ($k in $defaults.Keys) {
        if (-not $c.PSObject.Properties[$k]) { $c | Add-Member -NotePropertyName $k -NotePropertyValue $defaults[$k] }
    }
    if (-not $c.vaultPath -or -not $c.remoteUrl) { throw 'config.json needs vaultPath and remoteUrl' }
    $c
}

function Invoke-Git {
    param([string[]]$Arguments, [switch]$AllowFail)
    # Native stderr redirected under 'Stop' becomes a terminating error in Windows PowerShell 5.1.
    $ErrorActionPreference = 'Continue'
    $out = & git -C $script:Vault @Arguments 2>&1 | ForEach-Object {
        if ($_ -is [Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" }
    } | Where-Object { $_ -and $_ -ne 'System.Management.Automation.RemoteException' }
    $script:LastGitExit = $LASTEXITCODE
    if ($LASTEXITCODE -ne 0 -and -not $AllowFail) {
        throw "git $($Arguments -join ' ') failed ($LASTEXITCODE): $($out -join ' | ')"
    }
    $out
}

function Test-GitRef([string]$Ref) {
    Invoke-Git @('rev-parse', '--verify', '--quiet', $Ref) -AllowFail | Out-Null
    $script:LastGitExit -eq 0
}

function Get-ConflictPath([string]$RelPath) {
    $dir = Split-Path $RelPath -Parent
    $name = [IO.Path]::GetFileNameWithoutExtension($RelPath)
    $ext = [IO.Path]::GetExtension($RelPath)
    $file = '{0} (conflict {1:yyyy-MM-dd HHmmss}){2}' -f $name, (Get-Date), $ext
    if ($dir) { Join-Path $dir $file } else { $file }
}

# Same format as the phone: "<device>: 2 added, 1 modified" and a short file list.
# Who pushed is the commit author (your git identity).
function New-CommitMessage([string[]]$Porcelain) {
    $kinds = [ordered]@{ A = 'added'; M = 'modified'; R = 'renamed'; D = 'deleted' }
    $counts = @{}
    $files = foreach ($line in $Porcelain) {
        $code = $line.Substring(0, 1)
        if (-not $kinds.Contains($code)) { $code = 'M' }
        $counts[$code] = 1 + [int]$counts[$code]
        '{0} {1}' -f $code, $line.Substring(3).Trim('"')
    }
    $summary = ($kinds.Keys | Where-Object { $counts[$_] } | ForEach-Object { "$($counts[$_]) $($kinds[$_])" }) -join ', '
    $body = @($files | Sort-Object { $_.Substring(2) } | Select-Object -First 10)
    if ($files.Count -gt 10) { $body += "... and $($files.Count - 10) more" }
    "$($Config.deviceName): $summary`n`n$($body -join "`n")"
}

function Initialize-Vault {
    if (-not (Test-Path $Vault)) { New-Item -ItemType Directory $Vault | Out-Null }
    if (-not (Test-Path (Join-Path $Vault '.git'))) { Invoke-Git @('init', '-q', '-b', $Branch) | Out-Null }
    # Byte-for-byte content keeps blob hashes identical to what the phone computes.
    Invoke-Git @('config', 'core.autocrlf', 'false') | Out-Null
    Invoke-Git @('config', 'core.quotepath', 'false') | Out-Null
    if (-not (Invoke-Git @('config', 'user.email') -AllowFail)) {
        Invoke-Git @('config', 'user.name', $Config.deviceName) | Out-Null
        Invoke-Git @('config', 'user.email', "$($Config.deviceName)@syncthing.local") | Out-Null
    }
    if ((Invoke-Git @('remote')) -contains 'origin') {
        Invoke-Git @('remote', 'set-url', 'origin', $Config.remoteUrl) | Out-Null
    } else {
        Invoke-Git @('remote', 'add', 'origin', $Config.remoteUrl) | Out-Null
    }

    $ignore = Join-Path $Vault '.gitignore'
    if (-not (Test-Path $ignore)) {
        Set-Content -Path $ignore -Encoding ASCII -Value @(
            '.obsidian/workspace.json', '.obsidian/workspace-mobile.json', '.obsidian/cache',
            '.trash/', '.DS_Store', 'Thumbs.db')
    }

    # Interactive on purpose: lets Git Credential Manager store the login once.
    $env:GIT_TERMINAL_PROMPT = '1'
    Invoke-Git @('fetch', 'origin') -AllowFail | Out-Null
    $env:GIT_TERMINAL_PROMPT = '0'

    if ((Test-GitRef "refs/remotes/origin/$Branch") -and -not (Test-GitRef 'HEAD')) {
        Invoke-Git @('reset', '-q', '--mixed', "origin/$Branch") | Out-Null
        # Files that only exist remotely show up as "deleted"; restore them instead of pushing deletions.
        $missing = @(Invoke-Git @('ls-files', '--deleted'))
        if ($missing.Count -gt 0) { Invoke-Git (@('checkout', '--') + $missing) | Out-Null }
        Write-Log "attached vault to origin/$Branch ($($missing.Count) file(s) pulled down)"
    }
    Sync-Vault
}

function Merge-Remote {
    Invoke-Git @('merge', '-q', '-m', "$($Config.deviceName): merge", "origin/$Branch") -AllowFail | Out-Null
    if ($script:LastGitExit -eq 0) { Write-Log 'merged remote changes'; return }

    $conflicts = @(Invoke-Git @('diff', '--name-only', '--diff-filter=U'))
    if ($conflicts.Count -eq 0) {
        Invoke-Git @('merge', '--abort') -AllowFail | Out-Null
        throw 'merge failed without conflicts; aborted'
    }
    foreach ($p in $conflicts) {
        Invoke-Git @('cat-file', '-e', ":2:$p") -AllowFail | Out-Null; $hasOurs = $script:LastGitExit -eq 0
        Invoke-Git @('cat-file', '-e', ":3:$p") -AllowFail | Out-Null; $hasTheirs = $script:LastGitExit -eq 0
        if ($hasOurs -and $hasTheirs) {
            Invoke-Git @('checkout', '--theirs', '--', $p) | Out-Null
            Copy-Item -LiteralPath (Join-Path $Vault $p) -Destination (Join-Path $Vault (Get-ConflictPath $p))
            Invoke-Git @('checkout', '--ours', '--', $p) | Out-Null
        } elseif ($hasTheirs) {
            # Deleted here, edited there: the edit wins.
            Invoke-Git @('checkout', '--theirs', '--', $p) | Out-Null
        }
    }
    Invoke-Git @('add', '-A') | Out-Null
    $n = $conflicts.Count
    Invoke-Git @('commit', '-q', '-m', "$($Config.deviceName): merge, $(if ($n -eq 1) { '1 conflict kept as a copy' } else { "$n conflicts kept as copies" })") | Out-Null
    Write-Log "merged remote changes; kept both versions of $($conflicts.Count) conflicting file(s)"
}

function Sync-Vault([switch]$LocalOnly) {
    Invoke-Git @('add', '-A') | Out-Null
    $changes = @(Invoke-Git @('status', '--porcelain'))
    if ($changes.Count -gt 0) {
        Invoke-Git @('commit', '-q', '-m', (New-CommitMessage $changes)) | Out-Null
        Write-Log "committed $($changes.Count) local change(s)"
    }
    if (-not (Test-GitRef 'HEAD')) { return }

    if ($LocalOnly -and (Test-GitRef "refs/remotes/origin/$Branch")) {
        $unpushed = [int](Invoke-Git @('rev-list', '--count', "origin/$Branch..HEAD"))
        if ($unpushed -eq 0) { return }
    }

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Invoke-Git @('fetch', '-q', 'origin') -AllowFail | Out-Null
        if ($script:LastGitExit -ne 0) { Write-Log 'fetch failed (offline?); will retry later'; return }

        if (-not (Test-GitRef "refs/remotes/origin/$Branch")) {
            Invoke-Git @('push', '-q', '-u', 'origin', "HEAD:$Branch") | Out-Null
            Write-Log "pushed initial branch $Branch"
            return
        }
        $behind = [int](Invoke-Git @('rev-list', '--count', "HEAD..origin/$Branch"))
        if ($behind -gt 0) { Merge-Remote }

        $ahead = [int](Invoke-Git @('rev-list', '--count', "origin/$Branch..HEAD"))
        if ($ahead -eq 0) { return }
        Invoke-Git @('push', '-q', 'origin', "HEAD:$Branch") -AllowFail | Out-Null
        if ($script:LastGitExit -eq 0) { Write-Log "pushed $ahead commit(s)"; return }
        Write-Log "push rejected (attempt $attempt); refetching"
    }
}

function Test-VaultEvents {
    $relevant = $false
    foreach ($e in @(Get-Event -ErrorAction SilentlyContinue)) {
        if ($e.SourceIdentifier -like 'vault.*' -and $e.SourceEventArgs.FullPath) {
            $rel = $e.SourceEventArgs.FullPath.Substring($Vault.Length).TrimStart('\', '/')
            if ($rel -notmatch '^\.git([\\/]|$)') { $relevant = $true }
        }
        Remove-Event -EventIdentifier $e.EventIdentifier
    }
    $relevant
}

$Config = Read-Config
$Branch = $Config.branch
$Vault = [IO.Path]::GetFullPath($Config.vaultPath).TrimEnd('\', '/')
$env:GIT_TERMINAL_PROMPT = '0'

if ($Init) { Initialize-Vault; exit 0 }
if (-not (Test-Path (Join-Path $Vault '.git'))) { throw "$Vault is not set up yet; run: .\sync.ps1 -Init" }
if ($Once) { Sync-Vault; exit 0 }

$mutex = New-Object System.Threading.Mutex($false, 'Local\syncthing-laptop-sync')
if (-not $mutex.WaitOne(0)) { Write-Log 'another instance is already running; exiting'; exit 0 }
(Get-Process -Id $PID).PriorityClass = 'BelowNormal'

$watcher = New-Object System.IO.FileSystemWatcher $Vault
$watcher.IncludeSubdirectories = $true
$watcher.InternalBufferSize = 65536
$watcher.NotifyFilter = [IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size'
foreach ($ev in 'Changed', 'Created', 'Deleted', 'Renamed') {
    Register-ObjectEvent -InputObject $watcher -EventName $ev -SourceIdentifier "vault.$ev" | Out-Null
}
$watcher.EnableRaisingEvents = $true
Write-Log "watching $Vault (branch $Branch, poll every $($Config.pollSeconds)s)"

$dirty = $false
$lastEvent = [datetime]::MinValue
$nextPoll = [datetime]::MinValue
while ($true) {
    $null = Wait-Event -Timeout 5
    if (Test-VaultEvents) { $dirty = $true; $lastEvent = Get-Date }
    $now = Get-Date
    try {
        if ($dirty -and ($now - $lastEvent).TotalSeconds -ge $Config.debounceSeconds) {
            $dirty = $false
            Sync-Vault -LocalOnly
        } elseif ($now -ge $nextPoll) {
            $nextPoll = $now.AddSeconds($Config.pollSeconds)
            Sync-Vault
        }
    } catch {
        Write-Log "ERROR: $_"
    }
}
