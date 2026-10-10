# Project plan

## Goal

Edit Obsidian notes on a Windows laptop or an Android phone and have them appear on the other device without thinking about it. It should be cheap enough on CPU, RAM and battery to run all the time, and must never silently lose an edit.

## Decisions

| Question | Decision | Why |
| --- | --- | --- |
| Hub | Private GitHub repo | Always on, free, versioned backup, no server to maintain. A VM isn't needed (see [architecture.md](architecture.md#why-github-as-the-hub-and-no-vm)). |
| Laptop client | PowerShell + git CLI | Zero install on Windows, real git merges, the vault stays a normal repo (works with Obsidian Git too) |
| Phone client | Flutter app + GitHub REST API | No git binary on Android; one API call per idle check; small APK |
| Phone background | WorkManager periodic task | The OS-sanctioned way: survives reboots, respects Doze, nothing resident |
| Conflicts | Keep both (conflict copy) | Simple, transparent, never destructive |
| Token storage | Android encrypted storage | The token never touches the vault or the repo |

## Milestones

- [x] **M0: Toolchain.** Flutter stable, Android Studio, Android SDK + licenses, Gradle on a supported JDK.
- [x] **M1: Laptop sync.** Watcher + debounce, poll, keep-both conflicts, retrying push, hidden autostart, log rotation. Tested with two vaults against a bare repo.
- [x] **M2: Sync engine.** Three-way planner, GitHub client, hash cache, ignore rules, race retry. Unit tests with a fake remote.
- [x] **M3: Android app.** Settings, storage permission, Sync now, log view, periodic background sync.
- [ ] **M4: Real-world trial.** Laptop + phone on the real notes repo for a week; watch the logs for conflicts, rate limits and battery.
- [ ] **M5: Polish.** App icon, release signing, GitHub Actions to build the APK on tags.

## Roadmap ideas

- Quick Settings tile / home-screen widget for one-tap sync
- Sync when the app comes to the foreground and when charging starts
- First phone sync via a single zipball download instead of one call per file
- Inline small text files in the tree request to save blob calls
- Native (compiled Dart) laptop daemon to cut idle RAM from ~90 MB to ~15 MB, plus a Linux/macOS version
- Optional client-side encryption of notes before they reach GitHub
- Text-level 3-way merge on the phone (like git) instead of conflict copies for non-overlapping edits
