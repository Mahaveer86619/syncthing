# Architecture

## Why GitHub as the hub (and no VM)

Two-way sync needs a place both devices can reach whenever they're online. A private GitHub repo already is that place: always up, free, versioned, and reachable from a PC and a phone. Each device syncs *with GitHub*, never directly with the other, so it doesn't matter whether the other device is on.

A VM (or a peer-to-peer tool) only adds value if you need real-time sync between two devices that are both online, or want the data off GitHub. For notes, "within a few minutes" is enough, and every change also lands in git history as a free backup.

What you give up:

- **Latency.** PC → GitHub takes about 15 s after you stop typing. Phone → GitHub happens shortly after Obsidian saves. GitHub → phone takes up to 15 min (Android's minimum periodic interval), or is instant with *Sync now*. GitHub → PC takes up to 2 min by default.
- **Privacy.** Notes are stored on GitHub in a private repo. Client-side encryption is on the [roadmap](plan.md).

## Repo layout

```
obsidian-notes/          the Obsidian vault (with its own .gitignore)
syncthing-config/
    settings.json        settings shared by every device
README.md, ...           anything else at the root is never touched
```

`settings.json` holds `theme` (`dynamic` or `#RRGGBB`) and `appIcon` (`auto` or `mono`). It syncs like any note, so a theme or icon change on one device reaches the other on its next sync. Per-device things (sync folder, vault path, intervals, device name, tokens) stay on the device.

The Windows background sync creates this layout on a new repo. A repo from before the layout existed (vault at the root) is reorganised in one commit when the Windows app first connects, so history is kept as renames.

## Components

| Component | Where | How it talks to GitHub | Local state |
| --- | --- | --- | --- |
| Windows app (`app/`, `lib/src/desktop/`) | PC | Doesn't. It drives the background sync and reads its status and git history | `%LOCALAPPDATA%\Syncthing` |
| Background sync (`app/assets/sync/sync.ps1`) | PC, started at login | `git` over your SSH key or Git Credential Manager | The sync folder is a git clone |
| Android app (`app/`, `lib/src/sync/`) | Phone | GitHub REST *Git Data* API with a fine-grained token | `state.json` and its `syncthing-config/` copy in app-private storage; the vault stays plain files |

## PC flow

```
FileSystemWatcher event ──▶ 15 s of quiet ──▶ git add -A / commit
                                              └─▶ fetch ─▶ merge (keep both on conflict) ─▶ push
every 2 min, or "Sync now" in the app ──▶ the same, even with no local edits (pulls phone changes)
```

- A local-edit sync with nothing to push makes no network call.
- A rejected push (the phone pushed in between) is retried up to 3 times.
- Git does a real line-level merge, so edits to different parts of a note combine cleanly. Only overlapping edits become conflict copies.
- The app talks to the background process through files in `%LOCALAPPDATA%\Syncthing`: `logs\status.json` (last result), `logs\last_poll` (for the countdown), `logs\daemon.pid` (is it running) and a `sync-now` request file.

## Phone triggers

```
Obsidian saves a file ──▶ MediaStore change ──▶ WorkManager content trigger (one-shot, re-armed each run)
                                                 └─▶ stat-only local check ──changed?──▶ full sync
every 15 min ──▶ WorkManager periodic job ──▶ full sync (1 API call if remote unchanged)
```

No foreground service and no resident process. Some phone makers' battery managers delete these jobs when the app is swiped away; see [android-app.md](android-app.md#phones-that-kill-background-work).

## Phone sync engine

The phone does not run git. `lib/src/sync/engine.dart` mirrors repo folders to local folders (`obsidian-notes/` ↔ the vault, `syncthing-config/` ↔ app storage) and does a three-way comparison of `path → git blob SHA` maps:

- **base**: what both sides agreed on at the end of the last sync (`state.json`)
- **local**: the folders now (SHA cached by size + mtime, so unchanged files aren't re-read)
- **remote**: the branch's tree on GitHub (skipped entirely if the branch head hasn't moved)

| local vs base | remote vs base | Action |
| --- | --- | --- |
| same | changed | download (or delete locally) |
| changed | same | upload (or delete remotely) |
| deleted | changed | download: an edit beats a delete |
| changed | deleted | upload: an edit beats a delete |
| changed | changed, different | **conflict**: keep local, save remote as `name (conflict <time>).ext` on both sides |
| equal to remote | – | nothing |

Uploads become one commit: create blobs, a tree based on the remote tree (so files outside the mirrored folders are untouched), a commit, then a fast-forward-only ref update. If another device pushed in between, the update is rejected and the pass reruns.

On a first sync (empty base), files that exist on both sides with different content become conflicts rather than being overwritten.

## Commit messages

Both devices write the same brief format:

```
phone: 1 added, 2 modified

A Daily/2026-10-10.md
M Projects/syncthing.md
M Inbox.md
```

The subject names the device. The body lists up to 10 files, relative to the vault. The commit author is the GitHub account that pushed: your git identity on the PC, the token owner on the phone.

## What is not synced

`obsidian-notes/.gitignore` applies to both devices. By default it excludes:

- `.obsidian/workspace.json`, `.obsidian/workspace-mobile.json`: UI layout that changes constantly and differs per device
- `.obsidian/cache`, `.trash/`, OS junk files

The rest of `.obsidian/` (settings, plugins, themes) *is* synced. The phone supports `*`, `**`, `?`, trailing `/` and leading `/` patterns, but not `!` negation.

## Resource use

| | Idle | During a sync |
| --- | --- | --- |
| PC background sync | ~0% CPU (event-driven + 5 s wake-up), ~90 MB RAM (Windows PowerShell host), below-normal priority | `git` for a second or two |
| Windows app window | Only while open; refreshes small status files every 5 s | – |
| Android app | **Nothing resident.** WorkManager starts a short-lived background isolate after edits and every 15 min, only with a network connection | Edit check: stat walk, no network. Poll: 1 API call when nothing changed |

## Limits

- Files over 95 MB are skipped by the phone (GitHub's API limit is 100 MB).
- The GitHub API returns at most 100k entries for a recursive tree.
- The phone's first sync downloads each file with one API call (5,000 calls/hour), so seed big vaults from the PC.
