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

# Read by the Windows app: the outcome of the latest sync attempt.
function Set-Status([string]$State, [string]$Message = '') {
    $json = @{ state = $State; message = $Message; time = (Get-Date).ToString('o') } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $LogDir 'status.json'), $json, (New-Object Text.UTF8Encoding($false)))
}

function Read-Config {
    if (-not (Test-Path $ConfigPath)) { throw "Config not found: $ConfigPath (copy config.example.json to config.json)" }
    $c = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $defaults = @{ branch = 'main'; deviceName = $env:COMPUTERNAME; debounceSeconds = 15; pollSeconds = 120 }
    foreach ($k in $defaults.Keys) {
        if (-not $c.PSObject.Properties[$k]) { $c | Add-Member -NotePropertyName $k -NotePropertyValue $defaults[$k] }
    }
    # Older configs called the sync folder vaultPath.
    if (-not $c.PSObject.Properties['repoPath'] -and $c.PSObject.Properties['vaultPath']) {
        $c | Add-Member -NotePropertyName repoPath -NotePropertyValue $c.vaultPath
    }
    if (-not $c.repoPath -or -not $c.remoteUrl) { throw 'config.json needs repoPath and remoteUrl' }
    $c
}

function Invoke-Git {
    param([string[]]$Arguments, [switch]$AllowFail)
    # Native stderr redirected under 'Stop' becomes a terminating error in Windows PowerShell 5.1.
    $ErrorActionPreference = 'Continue'
    $out = & git -C $script:Repo @Arguments 2>&1 | ForEach-Object {
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
function New-CommitMessage {
    $kinds = [ordered]@{ A = 'added'; M = 'modified'; R = 'renamed'; D = 'deleted' }
    $counts = @{}
    # name-status is tab-separated and, with core.quotepath=false, leaves spaces unquoted.
    $files = foreach ($line in Invoke-Git @('diff', '--cached', '--name-status', '-M')) {
        $fields = $line -split "`t"
        $code = $fields[0].Substring(0, 1)
        if (-not $kinds.Contains($code)) { $code = 'M' }
        $counts[$code] = 1 + [int]$counts[$code]
        '{0} {1}' -f $code, ($fields[-1] -replace '^obsidian-notes/', '')
    }
    $summary = ($kinds.Keys | Where-Object { $counts[$_] } | ForEach-Object { "$($counts[$_]) $($kinds[$_])" }) -join ', '
    $body = @($files | Sort-Object { $_.Substring(2) } | Select-Object -First 10)
    if ($files.Count -gt 10) { $body += "... and $($files.Count - 10) more" }
    "$($Config.deviceName): $summary`n`n$($body -join "`n")"
}

# The message goes through a file: Windows PowerShell 5.1 mangles quotes inside native arguments.
function Save-Commit([string]$Message) {
    $msgFile = Join-Path $env:TEMP 'syncthing-commit-msg.txt'
    [IO.File]::WriteAllText($msgFile, $Message, (New-Object Text.UTF8Encoding($false)))
    Invoke-Git @('commit', '-q', '-F', $msgFile) | Out-Null
}

function Initialize-Vault {
    if (-not (Test-Path $Repo)) { New-Item -ItemType Directory $Repo | Out-Null }
    if (-not (Test-Path (Join-Path $Repo '.git'))) { Invoke-Git @('init', '-q', '-b', $Branch) | Out-Null }
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

    # Interactive on purpose: lets Git Credential Manager store the login once.
    $env:GIT_TERMINAL_PROMPT = '1'
    Invoke-Git @('fetch', 'origin') -AllowFail | Out-Null
    $env:GIT_TERMINAL_PROMPT = '0'

    if ((Test-GitRef "refs/remotes/origin/$Branch") -and -not (Test-GitRef 'HEAD')) {
        Invoke-Git @('reset', '-q', '--mixed', "origin/$Branch") | Out-Null
        # Files that only exist remotely show up as "deleted"; restore them instead of pushing deletions.
        $missing = @(Invoke-Git @('ls-files', '--deleted'))
        if ($missing.Count -gt 0) { Invoke-Git (@('checkout', '--') + $missing) | Out-Null }
        Write-Log "attached to origin/$Branch ($($missing.Count) file(s) pulled down)"
    }
    Initialize-Layout
    Sync-Vault
}

# Only the vault and the shared settings sync. Whatever lands at the root (e.g. Obsidian opening
# the sync folder itself as a vault) stays local instead of being committed.
function Set-RootIgnore {
    $path = Join-Path $Repo '.gitignore'
    $content = "/*`n!/$NotesDir/`n!/$ConfigDir/`n!/.gitignore`n!/README.md`n!/LICENSE`n"
    if ((Test-Path $path) -and ([IO.File]::ReadAllText($path) -eq $content)) { return }
    [IO.File]::WriteAllText($path, $content, (New-Object Text.UTF8Encoding($false)))
    # Untrack root files committed before the rule existed; they stay on disk.
    $stray = @(Invoke-Git @('ls-files') | Where-Object { $_ -notmatch "^($NotesDir|$ConfigDir)/" -and $_ -notin '.gitignore', 'README.md', 'LICENSE' })
    if ($stray.Count -gt 0) { Invoke-Git (@('rm', '-q', '--cached', '--') + $stray) | Out-Null }
    Write-Log "root .gitignore set; untracked $($stray.Count) stray file(s)"
}

# Repo layout shared with the phone app: the vault in obsidian-notes/, app settings in
# syncthing-config/, anything else at the root left alone.
function Initialize-Layout {
    $notes = Join-Path $Repo $NotesDir
    $keep = @('.git', $NotesDir, $ConfigDir, 'README.md', 'LICENSE')
    if (-not (Test-Path $notes)) {
        New-Item -ItemType Directory $notes | Out-Null
        # An older single-folder repo: its notes move into obsidian-notes/ (git sees renames).
        $legacy = @(Get-ChildItem -LiteralPath $Repo -Force | Where-Object { $keep -notcontains $_.Name })
        foreach ($item in $legacy) { Move-Item -LiteralPath $item.FullName -Destination $notes }
        if ($legacy.Count -gt 0) { Write-Log "moved $($legacy.Count) item(s) into $NotesDir/" }
    }
    $ignore = Join-Path $notes '.gitignore'
    if (-not (Test-Path $ignore)) {
        Set-Content -Path $ignore -Encoding ASCII -Value @(
            '.obsidian/workspace.json', '.obsidian/workspace-mobile.json', '.obsidian/cache',
            '.trash/', '.DS_Store', 'Thumbs.db')
    }
    $settings = Join-Path (Join-Path $Repo $ConfigDir) 'settings.json'
    if (-not (Test-Path $settings)) {
        New-Item -ItemType Directory (Split-Path $settings) -Force | Out-Null
        [IO.File]::WriteAllText($settings, "{`n  ""theme"": ""dynamic"",`n  ""appIcon"": ""auto""`n}`n",
            (New-Object Text.UTF8Encoding($false)))
    }
    Set-RootIgnore
    Invoke-Git @('add', '-A') | Out-Null
    if (@(Invoke-Git @('status', '--porcelain')).Count -gt 0) {
        Save-Commit "$($Config.deviceName): set up $NotesDir/ and $ConfigDir/"
        Write-Log "organised the repo into $NotesDir/ and $ConfigDir/"
    }
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
            Copy-Item -LiteralPath (Join-Path $Repo $p) -Destination (Join-Path $Repo (Get-ConflictPath $p))
            Invoke-Git @('checkout', '--ours', '--', $p) | Out-Null
        } elseif ($hasTheirs) {
            # Deleted here, edited there: the edit wins.
            Invoke-Git @('checkout', '--theirs', '--', $p) | Out-Null
        }
    }
    Invoke-Git @('add', '-A') | Out-Null
    $n = $conflicts.Count
    Save-Commit "$($Config.deviceName): merge, $(if ($n -eq 1) { '1 conflict kept as a copy' } else { "$n conflicts kept as copies" })"
    Write-Log "merged remote changes; kept both versions of $($conflicts.Count) conflicting file(s)"
}

function Sync-Vault([switch]$LocalOnly) {
    Invoke-Git @('add', '-A') | Out-Null
    $changes = @(Invoke-Git @('status', '--porcelain'))
    if ($changes.Count -gt 0) {
        Save-Commit (New-CommitMessage)
        Write-Log "committed $($changes.Count) local change(s)"
    }
    if (-not (Test-GitRef 'HEAD')) { return }

    if ($LocalOnly -and (Test-GitRef "refs/remotes/origin/$Branch")) {
        $unpushed = [int](Invoke-Git @('rev-list', '--count', "origin/$Branch..HEAD"))
        if ($unpushed -eq 0) { return }
    }

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Invoke-Git @('fetch', '-q', 'origin') -AllowFail | Out-Null
        if ($script:LastGitExit -ne 0) {
            Write-Log 'fetch failed (offline?); will retry later'
            Set-Status 'offline' 'Could not reach GitHub'
            return
        }

        if (-not (Test-GitRef "refs/remotes/origin/$Branch")) {
            Invoke-Git @('push', '-q', '-u', 'origin', "HEAD:$Branch") | Out-Null
            Write-Log "pushed initial branch $Branch"
            Set-Status 'ok'
            return
        }
        $behind = [int](Invoke-Git @('rev-list', '--count', "HEAD..origin/$Branch"))
        if ($behind -gt 0) { Merge-Remote }

        $ahead = [int](Invoke-Git @('rev-list', '--count', "origin/$Branch..HEAD"))
        if ($ahead -eq 0) { Set-Status 'ok'; return }
        Invoke-Git @('push', '-q', 'origin', "HEAD:$Branch") -AllowFail | Out-Null
        if ($script:LastGitExit -eq 0) { Write-Log "pushed $ahead commit(s)"; Set-Status 'ok'; return }
        Write-Log "push rejected (attempt $attempt); refetching"
    }
}

function Test-VaultEvents {
    $relevant = $false
    foreach ($e in @(Get-Event -ErrorAction SilentlyContinue)) {
        if ($e.SourceIdentifier -like 'vault.*' -and $e.SourceEventArgs.FullPath) {
            $rel = $e.SourceEventArgs.FullPath.Substring($Repo.Length).TrimStart('\', '/')
            if ($rel -notmatch '^\.git([\\/]|$)') { $relevant = $true }
        }
        Remove-Event -EventIdentifier $e.EventIdentifier
    }
    $relevant
}

$NotesDir = 'obsidian-notes'
$ConfigDir = 'syncthing-config'
$Config = Read-Config
$Branch = $Config.branch
$Repo = [IO.Path]::GetFullPath($Config.repoPath).TrimEnd('\', '/')
$env:GIT_TERMINAL_PROMPT = '0'

if ($Init) { Initialize-Vault; exit 0 }
if (-not (Test-Path (Join-Path $Repo '.git'))) { throw "$Repo is not set up yet; run: .\sync.ps1 -Init" }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory $LogDir | Out-Null }
if ($Once) {
    try { Sync-Vault } catch { Write-Log "ERROR: $_"; Set-Status 'error' "$_"; exit 1 }
    exit 0
}

$mutex = New-Object System.Threading.Mutex($false, 'Local\syncthing-laptop-sync')
if (-not $mutex.WaitOne(0)) { Write-Log 'another instance is already running; exiting'; exit 0 }
(Get-Process -Id $PID).PriorityClass = 'BelowNormal'
try { Set-RootIgnore } catch { Write-Log "ERROR: $_" }
Set-Content -Path (Join-Path $LogDir 'daemon.pid') -Value $PID -Encoding ASCII
# The Windows app drops this file to ask for an immediate full sync.
$syncNowFile = Join-Path $PSScriptRoot 'sync-now'

$watcher = New-Object System.IO.FileSystemWatcher $Repo
$watcher.IncludeSubdirectories = $true
$watcher.InternalBufferSize = 65536
$watcher.NotifyFilter = [IO.NotifyFilters]'FileName, DirectoryName, LastWrite, Size'
foreach ($ev in 'Changed', 'Created', 'Deleted', 'Renamed') {
    Register-ObjectEvent -InputObject $watcher -EventName $ev -SourceIdentifier "vault.$ev" | Out-Null
}
$watcher.EnableRaisingEvents = $true
Write-Log "watching $Repo (branch $Branch, poll every $($Config.pollSeconds)s)"

$dirty = $false
$lastEvent = [datetime]::MinValue
$nextPoll = [datetime]::MinValue
while ($true) {
    $null = Wait-Event -Timeout 5
    if (Test-VaultEvents) { $dirty = $true; $lastEvent = Get-Date }
    $now = Get-Date
    try {
        if (Test-Path $syncNowFile) {
            Remove-Item $syncNowFile -Force
            $nextPoll = $now.AddSeconds($Config.pollSeconds)
            Set-Content -Path (Join-Path $LogDir 'last_poll') -Value $now.ToString('o') -Encoding ASCII
            Sync-Vault
        } elseif ($dirty -and ($now - $lastEvent).TotalSeconds -ge $Config.debounceSeconds) {
            $dirty = $false
            Sync-Vault -LocalOnly
        } elseif ($now -ge $nextPoll) {
            $nextPoll = $now.AddSeconds($Config.pollSeconds)
            Set-Content -Path (Join-Path $LogDir 'last_poll') -Value $now.ToString('o') -Encoding ASCII
            Sync-Vault
        }
    } catch {
        Write-Log "ERROR: $_"
        Set-Status 'error' "$_"
    }
}
