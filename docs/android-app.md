# Android app (`app/`)

## Install

Build the APK (see [development.md](development.md)) and install the one for your phone's CPU, which is almost always arm64:

```powershell
adb install app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

You can also copy the APK to the phone and open it (allow *Install unknown apps* for your file manager).

## Configure

Open the app → **Set up notes repo**:

| Field | Example |
| --- | --- |
| Notes repo | `you/obsidian-notes` (a full GitHub URL also works) |
| Branch | `main` |
| GitHub token | fine-grained token, see [notes-repo-setup.md](notes-repo-setup.md#3-phone-token) |
| Vault folder | the folder Obsidian mobile opens, e.g. `/storage/emulated/0/Documents/MyVault` (use the folder button) |
| Device name | `phone`; shown in commit messages and conflict copies |
| Background sync | every 15 / 30 / 60 min, or off |

Tap **Grant** next to *Storage access*. Android opens the *All files access* screen; enable it for Syncthing. Plain file access needs this, because Obsidian keeps vaults in shared storage. The app touches only the configured folder.

Tip: to start fresh on the phone, create an empty vault in Obsidian mobile, point the app at that folder, and tap **Sync now**.

## When does it sync?

- when you open the app
- when you tap **Sync now**
- in the background every N minutes (Android WorkManager, 15 min minimum), only on a network connection and when the battery isn't low

Android can't cheaply watch another app's files, so there's no instant push from the phone. For something you just wrote, open the app and tap **Sync now**. Doze mode and some vendors' battery savers stretch background intervals. If syncs are much rarer than configured, set the app's battery usage to *Unrestricted*.

## Sync log

The home screen shows the last 200 sync results (newest first), e.g. `3 down, 1 up` or `Up to date`.

## Changing settings

Changing the repo, branch or vault folder starts from a clean sync state. The next sync then compares both sides from scratch: identical files are left alone, and different ones become conflict copies, so nothing is overwritten.
