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
| Device name | `phone`; the prefix of every commit this phone makes |

Then grant the two permissions on the same screen:

- **Storage access → Grant.** Android opens the *All files access* screen; enable it for Syncthing. Plain file access needs this, because Obsidian keeps vaults in shared storage. The app touches only the configured folder.
- **Battery: unrestricted → Allow.** Without it, Doze and vendor battery savers can postpone background syncs by hours.

Tip: to start fresh on the phone, create an empty vault in Obsidian mobile, point the app at that folder, and sync.

## Auto sync

The home screen has one main control, the **Auto sync** switch (on by default). **Sync now** next to it forces an immediate sync.

With auto sync on, nothing runs in the background between syncs. Android wakes the app only for these two jobs:

| Trigger | What runs | Cost when nothing changed |
| --- | --- | --- |
| **You edit a note.** Any file change in shared storage (MediaStore) fires a WorkManager content trigger within seconds of Obsidian saving. | A local-only check (file sizes and mtimes). It goes online only if the vault differs from the last sync, then pushes. | A directory stat walk, **no network** |
| **Every 15 min** (Android's minimum for periodic work) | A full sync, which brings in the laptop's changes | **1 API call** (branch head unchanged) |

Both jobs wait for a network connection. Both survive reboots, because WorkManager re-registers them. Opening the app re-registers them too, which heals schedules lost to *force stop* or an app update.

The edit trigger also fires for unrelated storage changes (a new photo or download). That's why it checks locally first: those wake-ups cost a few milliseconds and no data. Downloads the app writes itself also re-fire it, and they're recognised as already synced.

Expected latency: phone → GitHub within about a minute of saving. GitHub → phone within 15 min (or immediately with **Sync now**). Getting faster than 15 min would need a server to push notifications to the phone; see the [roadmap](plan.md).

## Activity

The home screen shows *Last checked …* and an activity list of syncs that actually moved something, e.g. `2 down, 1 up` (newest first, last 200). Idle checks only update *Last checked*, so the list doesn't fill with noise.

## Commit messages

Every sync that changes the repo makes one commit, for example:

```
phone: 1 added, 2 modified

A Daily/2026-10-10.md
M Projects/syncthing.md
M Inbox.md
```

The subject says which device and what changed. The body lists up to 10 files (A = added, M = modified, D = deleted, C = conflict). GitHub records the token's account as the commit author, so *who* pushed is in the commit too. The laptop uses the same format.

## Changing settings

Changing the repo, branch or vault folder starts from a clean sync state. The next sync then compares both sides from scratch: identical files are left alone, and different ones become conflict copies, so nothing is overwritten.
