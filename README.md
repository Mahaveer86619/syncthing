# syncthing

Two-way sync for an [Obsidian](https://obsidian.md) vault between a Windows laptop and an Android phone, using a **private GitHub repo** as the always-on hub. No server, no VM, no subscription.

```
 ┌──────────────┐        git push/pull        ┌─────────────────────┐      GitHub REST API      ┌──────────────┐
 │ Laptop vault │ ──────────────────────────▶ │ private notes repo  │ ◀──────────────────────── │ Android vault│
 │ (git clone)  │ ◀────────────────────────── │  (GitHub = the hub) │ ────────────────────────▶ │ (plain files)│
 └──────────────┘   laptop-sync/sync.ps1      └─────────────────────┘     app/ (Flutter)         └──────────────┘
```

- **`laptop-sync/`**: a PowerShell script that watches the vault, commits edits about 15 s after you stop typing, pulls remote changes every 2 min, and pushes. It runs hidden at logon with no window and idles at ~0% CPU.
- **`app/`**: a small Flutter Android app. It syncs the phone's vault folder with the same repo through the GitHub API (no git needed on the phone). It runs as a WorkManager job every 15 min (or when you tap **Sync now**) and is not resident in memory between runs.

Conflicts never lose data: if both sides edited the same note, your local version stays and the other one is saved beside it as `note (conflict 2026-10-10 153012).md`.

## Quick start

1. **Notes repo**: create a private repo (e.g. `obsidian-notes`) with a README, and a fine-grained token for the phone. See [docs/notes-repo-setup.md](docs/notes-repo-setup.md).
2. **Laptop**:
   ```powershell
   cd laptop-sync
   copy config.example.json config.json   # set vaultPath + remoteUrl
   .\sync.ps1 -Init                        # one-time: attach vault to the repo
   .\install-startup.ps1                   # run silently at every logon
   ```
   Details: [docs/laptop-sync.md](docs/laptop-sync.md).
3. **Phone**: build/install the APK, then fill in repo, token and vault folder in Settings. See [docs/android-app.md](docs/android-app.md).

## Docs

See [docs/README.md](docs/README.md) for architecture, the sync algorithm, development setup and the roadmap.

## Not affiliated

This is a personal project and is unrelated to the [Syncthing](https://syncthing.net) P2P file-sync tool.

## License

[MIT](LICENSE)
