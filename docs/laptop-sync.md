# Laptop sync (`laptop-sync/`)

Windows, Windows PowerShell 5.1+ (built in) and git. No other dependencies.

## Configure

```powershell
cd laptop-sync
copy config.example.json config.json
```

| Key | Default | Meaning |
| --- | --- | --- |
| `vaultPath` | – | Your Obsidian vault folder |
| `remoteUrl` | – | Notes repo URL (SSH or HTTPS) |
| `branch` | `main` | Branch to sync |
| `deviceName` | computer name | Shown in commit messages; also the git author if you have no global git identity |
| `debounceSeconds` | `15` | Quiet time after the last edit before committing |
| `pollSeconds` | `120` | How often to pull remote changes when nothing happens locally |

`config.json` and `logs/` are git-ignored in this repo.

## First run

```powershell
.\sync.ps1 -Init
```

This:

1. runs `git init` in the vault if needed and sets `core.autocrlf=false`, so file bytes match what the phone hashes
2. adds `origin` and writes a default vault `.gitignore` (see [architecture.md](architecture.md#what-is-not-synced))
3. if the remote already has notes, attaches to them: files only on the remote are pulled down, and local files that differ are committed as local edits
4. runs one full sync

## Run always

```powershell
.\install-startup.ps1              # adds a Startup-folder shortcut and starts it now
.\install-startup.ps1 -Uninstall   # removes it and stops the running instance
```

The shortcut runs `conhost.exe --headless powershell.exe -File sync.ps1`, so no window appears. No admin rights are needed. Only one instance can run at a time (named mutex).

Other modes:

```powershell
.\sync.ps1          # foreground watcher (Ctrl+C to stop); useful to watch the log live
.\sync.ps1 -Once    # single sync, then exit
```

## Logs

`laptop-sync/logs/sync.log` (rotated at 1 MB), for example:

```
2026-10-10 21:03:14 committed 1 local change(s)
2026-10-10 21:03:18 merged remote changes; kept both versions of 1 conflicting file(s)
2026-10-10 21:03:18 pushed 2 commit(s)
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `fetch failed (offline?)` | Network or auth. Run `git -C <vault> fetch` by hand to see the real error. |
| Nothing syncs after a reboot | Check that `syncthing-vault-sync.lnk` exists in `shell:startup` and look at the log. |
| `... is not set up yet` | Run `.\sync.ps1 -Init` once. |
| Want to stop syncing temporarily | `.\install-startup.ps1 -Uninstall`, then run it again without `-Uninstall`. |
| Conflict copies piling up | Open both versions in Obsidian, merge by hand, delete the `(conflict …)` file. The deletion syncs too. |
