# Architecture

## Why GitHub as the hub (and no VM)

Two-way sync needs a place both devices can reach whenever they're online. A private GitHub repo already is that place: always up, free, versioned, and reachable from both a laptop and a phone. Each device syncs *with GitHub*, never directly with each other, so it doesn't matter whether the other device is on.

A VM (or a peer-to-peer tool) would only add value if you needed real-time sync between two devices that are both online, or wanted the data off GitHub. For notes, "within a few minutes" is enough, and every change also lands in git history as a free backup.

What you give up:

- **Latency.** Laptop → GitHub takes about 15 s after you stop typing. Phone → GitHub happens shortly after Obsidian saves (edit trigger). GitHub → phone takes up to 15 min (Android's minimum periodic interval), or is instant with *Sync now*.
- **Privacy.** Notes are stored on GitHub (private repo). Encrypting them is on the [roadmap](plan.md).

## Components

| Component | Where | How it talks to GitHub | Local state |
| --- | --- | --- | --- |
| `laptop-sync/sync.ps1` | Windows laptop | `git` CLI over SSH or HTTPS (your existing git credentials) | The vault folder *is* a git clone |
| `app/` (Flutter) | Android | GitHub REST *Git Data* API with a fine-grained token | `state.json` in app-private storage; the vault stays plain files |

Both write ordinary commits to the same branch in one brief format: `<device>: 1 added, 2 modified`, plus a body listing up to 10 files. The commit author is the GitHub account that pushed: your git identity on the laptop, the token owner on the phone.

## Laptop flow

```
FileSystemWatcher event ──▶ wait for 15 s of quiet ──▶ git add -A / commit
                                                        └─▶ fetch ─▶ merge (keep-both on conflict) ─▶ push
every 2 min ──▶ same, even with no local edits (pulls phone changes)
```

- A local-edit sync with nothing to push makes no network call.
- A rejected push (the phone pushed in between) is retried up to 3 times: fetch, merge, push.
- Git does a real line-level merge, so edits to different parts of the same note combine cleanly. Only overlapping edits become conflict copies.

## Phone triggers

```
Obsidian saves a file ──▶ MediaStore change ──▶ WorkManager content trigger (one-shot, re-armed each run)
                                                 └─▶ stat-only local check ──changed?──▶ full sync
every 15 min ──▶ WorkManager periodic job ──▶ full sync (1 API call if remote unchanged)
```

No foreground service and no resident process. See [android-app.md](android-app.md#auto-sync).

## Phone flow (sync engine)

The phone does not run git. `app/lib/src/sync/engine.dart` does a three-way comparison of `path → git blob SHA` maps:

- **base**: what both sides agreed on at the end of the last sync (saved in `state.json`)
- **local**: the vault folder now (SHA cached by size + mtime, so unchanged files aren't re-read)
- **remote**: the branch's tree on GitHub (skipped entirely if the branch head hasn't moved, so an idle poll costs **1 API call**)

| local vs base | remote vs base | Action |
| --- | --- | --- |
| same | changed | download (or delete locally) |
| changed | same | upload (or delete remotely) |
| deleted | changed | download: an edit beats a delete |
| changed | deleted | upload: an edit beats a delete |
| changed | changed, different | **conflict**: keep local, save remote as `name (conflict <time>).ext` on both sides |
| equal to remote | – | nothing |

Uploads become one commit: create blobs, a tree based on the remote tree, a commit, then a fast-forward-only ref update. If another device pushed in between, the ref update is rejected and the whole pass reruns (downloads already applied are idempotent).

On the first sync (empty base), files that exist on both sides with different content become conflicts rather than being overwritten.

## What is not synced

Both sides honour the vault's `.gitignore` (created by `sync.ps1 -Init`). By default it excludes:

- `.obsidian/workspace.json`, `.obsidian/workspace-mobile.json`: UI layout that changes constantly and differs per device
- `.obsidian/cache`, `.trash/`, OS junk files

The rest of `.obsidian/` (settings, plugins, themes) *is* synced. Add lines to `.gitignore` to keep per-device settings separate. The phone supports the usual `*`, `**`, `?`, trailing `/` and leading `/` patterns, but not `!` negation.

## Resource usage

| | Idle | During a sync |
| --- | --- | --- |
| Laptop script | ~0% CPU (event-driven + 5 s wake-up), ~90 MB RAM (Windows PowerShell host), below-normal priority | `git` for a second or two |
| Android app | **Nothing resident.** WorkManager starts a short-lived background isolate after edits and every 15 min, only with a network connection | Edit check: stat walk, no network. Poll: 1 API call when nothing changed |

## Limits

- Files over 95 MB are skipped by the phone (GitHub's API limit is 100 MB). Keep large attachments out of the vault or in `.gitignore`.
- The GitHub API returns at most 100k entries for a recursive tree, which is far beyond a normal vault.
- The phone's first sync downloads each file with one API call (5,000 calls/hour limit). For a very large vault, let the first sync run a couple of times.
