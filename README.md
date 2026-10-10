# syncthing

Two-way sync for an [Obsidian](https://obsidian.md) vault between a Windows PC and an Android phone, using a **private GitHub repo** as the always-on hub. No server, no VM, no subscription.

```
 ┌──────────────┐     git (your SSH/HTTPS login)    ┌──────────────────────┐      GitHub REST API      ┌──────────────┐
 │ Windows app  │ ────────────────────────────────▶ │  private notes repo  │ ◀──────────────────────── │ Android app  │
 │ + background │ ◀──────────────────────────────── │  obsidian-notes/     │ ────────────────────────▶ │ (no git, no  │
 │   sync       │                                   │  syncthing-config/   │                           │  resident    │
 └──────────────┘                                   └──────────────────────┘                           │  process)    │
                                                                                                       └──────────────┘
```

One Flutter codebase (`app/`) builds both apps:

- **Windows**: a Material 3 control panel with status, a live countdown, Sync now, Auto sync, activity from both devices, Open in Obsidian, and a phone pairing QR code. The syncing runs in a tiny background process (bundled `sync.ps1` driving git) that starts at login and keeps running after you close the window.
- **Android**: syncs the phone's vault through the GitHub API. Android wakes it right after you edit a note and every 15 min to pull PC changes. Nothing stays resident in memory, and an idle check costs one API call or none.

Theme and app icon live in the repo (`syncthing-config/settings.json`), so changing them on one device changes them on the other. The Android launcher icon can also switch for Diwali, Holi, Christmas, New Year and national holidays.

Every sync makes one brief commit that says which device and what changed, e.g. `phone: 1 added, 2 modified`, with the GitHub account as author. Conflicts never lose data: both versions are kept.

## Quick start

1. Create a private notes repo (e.g. `obsidian-notes`), see [docs/notes-repo-setup.md](docs/notes-repo-setup.md).
2. **Windows**: build and install the app ([docs/windows-app.md](docs/windows-app.md)), then pick a sync folder and paste the repo URL. Open `<sync folder>\obsidian-notes` in Obsidian.
3. **Android**: install the APK, then Settings → **Scan pairing code** and scan the QR the Windows app shows. Pick your vault folder and Save ([docs/android-app.md](docs/android-app.md)).

## Docs

See [docs/README.md](docs/README.md).

## Not affiliated

A personal project, unrelated to the [Syncthing](https://syncthing.net) P2P file-sync tool.

## License

[MIT](LICENSE)
