# Windows app

The Windows app is a control panel. The actual syncing is done by a small background process that it installs and manages. That process runs at login and keeps going when the window is closed.

## Install

```powershell
cd app
flutter build windows --release
powershell -ExecutionPolicy Bypass -File tool\install_windows.ps1   # -Uninstall to remove
```

It installs to `%LOCALAPPDATA%\Programs\Syncthing` with Start menu and desktop shortcuts. No admin is needed.

## First run

**Get started** → Settings:

| Field | Meaning |
| --- | --- |
| Sync folder | Where the notes repo is cloned, e.g. `C:\Users\you\Syncthing`. Your vault is its `obsidian-notes` folder; open that in Obsidian (or use **Open in Obsidian**). |
| Notes repo URL | SSH or HTTPS URL; uses your existing git login |
| Branch | usually `main` |
| Device name | Starts every commit from this PC, e.g. `laptop: 2 added` |
| Timing | Quiet time before uploading (default 15 s); how often to check for phone changes (default 2 min) |
| Pair your phone | Token for the phone + **Show pairing code** (see [notes-repo-setup.md](notes-repo-setup.md#4-pair-the-phone-no-typing)) |
| Theme / App icon | Shared with the phone through `syncthing-config/settings.json` |

Saving connects the folder to the repo (cloning, or reorganising an older repo into the [layout](architecture.md#repo-layout)) and turns on Auto sync.

## Dashboard

- **Status**: All synced / Offline / Needs attention (with the git error), plus note count and repo.
- **Next check for phone changes**: a live countdown to the next pull.
- **Sync now**: asks the background process for an immediate full sync, or runs one directly if Auto sync is off.
- **Auto sync**: on starts the background process now and at every login. Off stops it and removes it from login.
- **Activity**: the repo's recent commits from every device, with device, account and time. Click one to see its files.

## Files

`%LOCALAPPDATA%\Syncthing`:

| File | What |
| --- | --- |
| `config.json` | This PC's settings |
| `sync.ps1`, `install-startup.ps1` | The background sync, copied out of the app and updated with it |
| `logs\sync.log` | Background log, rotated at 1 MB |
| `logs\status.json`, `logs\last_poll`, `logs\daemon.pid` | How the app knows what the background process is doing |
| `icon.ico` | The current app icon (Dynamic or Monochrome) |

The background process can also run by hand: `powershell -File sync.ps1 -Once` (single sync) or `-Init` (connect/reorganise).

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Needs attention: `Repository not found` | Your git login can't see the private repo. See [several GitHub accounts](notes-repo-setup.md#2-pc-access). |
| Offline | Network or auth. Run `git -C <sync folder> fetch` to see the real error. |
| Nothing syncs after a reboot | Check that `syncthing-vault-sync.lnk` exists in `shell:startup`; toggle Auto sync off and on. |
| Conflict copies piling up | Open both versions in Obsidian, merge by hand, and delete the `(conflict …)` file. The deletion syncs too. |
