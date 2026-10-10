# Project plan

## Goal

Edit Obsidian notes on a Windows PC or an Android phone and have them appear on the other device without thinking about it. It should be cheap enough on CPU, RAM and battery to run all the time, and must never silently lose an edit.

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Hub | Private GitHub repo | Always on, free, versioned backup, no server. A VM isn't needed (see [architecture.md](architecture.md#why-github-as-the-hub-and-no-vm)). |
| Repo layout | `obsidian-notes/` + `syncthing-config/` | Notes and shared app settings side by side; anything else in the repo is left alone |
| PC client | Flutter Windows app + background `sync.ps1` (git) | GUI only when wanted; background sync with real git merges and nothing to install beyond git |
| Phone client | Flutter Android app + GitHub REST API | No git binary on Android; one API call per idle check |
| Phone background | WorkManager: MediaStore content trigger (edits) + 15-min periodic (remote) | Near-instant upload after edits and a guaranteed floor for pulls, with nothing resident |
| Conflicts | Keep both (conflict copy) | Simple, transparent, never destructive |
| Phone credentials | Fine-grained token, paired by QR from the Windows app | No typing, nothing secret in the repo; the PC uses its own git login |
| Shared settings | `syncthing-config/settings.json` (theme, app icon) | Rides the normal sync, no extra service |
| Look | Material 3 Expressive: dynamic colour (wallpaper / Windows accent) or a preset, bold type, shape-morphing status badge | Native on Android, consistent on Windows |
| Commit messages | `<device>: 1 added, 2 modified` + file list; author = pushing account | Brief, and shows who and where at a glance |

## Milestones

- [x] **M0: Toolchain.** Flutter, Android Studio + SDK, VS Build Tools with ATL, Developer Mode.
- [x] **M1: PC sync.** Watcher + debounce, poll, keep-both conflicts, retrying push, hidden autostart.
- [x] **M2: Sync engine.** Three-way planner, GitHub client, hash cache, ignore rules, race retry, repo-folder roots.
- [x] **M3: Android app.** Auto sync (edit trigger + 15-min poll), live countdown, activity feed, vault auto-detection, festival launcher icons.
- [x] **M4: Windows app.** Control panel over the background sync, activity from both devices, Open in Obsidian.
- [x] **M5: Cross-device.** Repo layout, shared theme/icon settings, QR pairing, OEM auto-start guidance.
- [ ] **M6: Real-world trial.** A week on the real notes repo; watch for conflicts, rate limits, battery, and XOS job kills.
- [ ] **M7: Polish.** Release signing, GitHub Actions building the APK and Windows zip on tags.

## Roadmap ideas

- Festival icons on Windows too (Android has them; Windows has Dynamic/Monochrome)
- Faster GitHub → phone: GitHub webhook → tiny relay → FCM push to wake the app
- Quick Settings tile / home-screen widget for one-tap sync
- First phone sync via a single zipball download instead of one call per file
- Native (compiled Dart) PC daemon to cut idle RAM from ~90 MB to ~15 MB, plus Linux/macOS
- Optional client-side encryption of notes before they reach GitHub
- Text-level three-way merge on the phone instead of conflict copies for non-overlapping edits
