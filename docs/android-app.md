# Android app

## Install

Build the APK (see [development.md](development.md)) and install the one for your phone's CPU, which is almost always arm64:

```powershell
adb install app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

You can also copy the APK to the phone and open it (allow *Install unknown apps* for your file manager).

## Set up

Open the app → **Get started** → Settings:

1. **Scan pairing code**: scan the QR from the Windows app (Settings → Pair your phone). Repo, branch and token are filled in. The scanner comes from Google Play Services, so the app needs no camera permission. You can also type them in yourself.
2. **Vault**: vaults found on the phone appear as chips (e.g. *Mahaveer's vault*); tap one. Picking a parent folder like `Obsidian/` steps into the vault inside, and a folder without `.obsidian` is refused.
3. **Device name**: starts every commit from this phone, e.g. `phone: 2 added`.
4. **Keep syncing reliably**: allow *Storage access* (Obsidian keeps vaults in shared storage), *Unrestricted battery*, and *Auto-start* (see below).
5. **Theme** and **App icon**: shared with the Windows app.
6. **Save**. The first sync starts right away.

## Auto sync

The home screen's **Auto sync** switch (on by default) keeps syncing without the app open. **Sync now** forces an immediate sync.

Nothing runs in the background between syncs. Android wakes the app in two cases:

| Trigger | What runs | Cost when nothing changed |
| --- | --- | --- |
| **You edit a note**: any file change in shared storage fires a WorkManager content trigger within seconds | Local-only check (sizes and mtimes); goes online only if the vault changed, then pushes | A directory stat walk, **no network** |
| **Every 15 min** (Android's minimum) | Full sync, which brings in PC changes | **1 API call** |

The dashboard shows a live **Next check for laptop changes** countdown. It is an estimate: Android picks the exact moment and may batch or defer jobs in deep sleep, so an overdue check reads "Any moment now".

Opening the app re-registers both jobs and syncs, which heals schedules lost to *force stop* or an app update.

## Phones that kill background work

Some phone makers' battery managers do more than stock Android when you swipe an app from Recents: they **delete its scheduled jobs**. On Infinix/Tecno/itel (XOS "Hiber") this shows in `adb logcat` as `removeTask … cleanType:SwipeUpClean` followed by `Job didn't exist in JobStore`. Xiaomi, Oppo/Realme, Vivo and Huawei behave similarly.

To keep auto sync alive:

1. Settings → **Auto-start** → **Open**, and allow Syncthing. This opens the maker's auto-start manager.
2. **Lock Syncthing in Recents** (long-press its card or pull it down, then tap the lock). On XOS this was the step that mattered: locked apps survive "clear all", and the jobs kept running.
3. Allow **Unrestricted battery**.

If a phone still loses the jobs, opening the app once restores them.

## Activity

The home screen lists syncs that moved something, grouped by day, e.g. `3 notes synced · 2 received · 1 removed`. Tap one to see the notes. Idle checks only update *Last checked*, and repeated errors (like being offline) collapse into one entry.

## App icon and theme

- **App icon: Dynamic**: colourful, and switches itself for Diwali, Holi, Christmas, New Year and national holidays (a daily background check plus whenever you leave the app). **Monochrome**: a quiet grey icon.
- **Theme: Dynamic** follows your wallpaper (Material You); presets pin an accent colour.

Both are stored in `syncthing-config/settings.json`, so they follow you to the Windows app and back. Lunar-calendar festival dates are listed per year in `LauncherIcon.kt` (through 2028) and need extending yearly.

## Changing repo or vault

Changing the repo, branch or vault starts from a clean sync state. The next sync compares both sides from scratch: identical files are left alone and different ones become conflict copies, so nothing is overwritten.
