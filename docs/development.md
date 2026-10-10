# Development

## Layout

```
syncthing/
├── app/                          Flutter app: Android + Windows from one codebase
│   ├── lib/main.dart             entry: Windows → DesktopApp, Android → WorkManager + HomePage
│   ├── lib/src/sync/             pure-Dart sync engine (no Flutter imports)
│   │   ├── engine.dart           repo-folder ↔ local-folder roots, scan → plan → apply → commit
│   │   ├── plan.dart             three-way decision table, repo layout, conflict names, commit messages
│   │   ├── github.dart           GitHub Git Data API client (RemoteRepo interface)
│   │   └── ignore.dart           .gitignore subset
│   ├── lib/src/runner.dart       one phone sync with saved config: lock file, activity feed, countdown
│   ├── lib/src/shared_settings.dart  syncthing-config/settings.json (theme, app icon)
│   ├── lib/src/pairing.dart      QR pairing payload
│   ├── lib/src/ui/               phone screens, theme, theme picker, shared widgets
│   ├── lib/src/desktop/          Windows control panel and its LaptopSync service
│   ├── assets/sync/              sync.ps1 + install-startup.ps1 (the PC background sync)
│   ├── assets/icons/             Windows .ico files (default, mono)
│   ├── android/…/LauncherIcon.kt festival calendar, launcher-icon aliases, daily icon worker
│   ├── android/…/MainActivity.kt method channel: festival, QR scanner, auto-start screen
│   ├── windows/runner/           window size/title, `syncthing/window` channel for the taskbar icon
│   ├── tool/install_windows.ps1  per-user install of the Windows build
│   └── test/                     engine, planner and GitHub-client tests (fake GitHub)
└── docs/
```

## Toolchain (Windows)

| Tool | How it was installed | Notes |
| --- | --- | --- |
| Flutter (stable) | `git clone -b stable https://github.com/flutter/flutter.git %USERPROFILE%\dev\flutter` | `bin` on user `PATH` |
| Android Studio | `winget install Google.AndroidStudio` | its bundled JBR is the Gradle JDK: `flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"` |
| Android SDK | command-line tools zip → `%LOCALAPPDATA%\Android\Sdk`, `sdkmanager --licenses`, `platform-tools`, `ndk;28.2.13676358`, `platforms;android-37` | `ANDROID_HOME` set |
| VS Build Tools 2022 | Desktop development with C++ **plus the C++ ATL component** | ATL is needed by `flutter_secure_storage_windows` |
| Developer Mode | Settings → System → For developers | Flutter plugins on Windows need symlinks |

The Android project pins **AGP 9.4.1**, **Gradle 9.6.0**, **`compileSdk = 37`** and **`minSdk = 26`** (adaptive vector icons only). `sdkmanager.bat` splits arguments on `;`, so pass packages through `--package_file=<file>`.

When editing `*.gradle.kts` from Windows PowerShell 5.1, don't use `Set-Content -Encoding UTF8`. It adds a BOM that breaks the Kotlin script's `plugins {}` block. Likewise, Windows PowerShell 5.1 mangles quotes inside native-command arguments, which is why `sync.ps1` passes commit messages to git through a file.

## Build and test

```powershell
cd app
flutter test
flutter analyze
flutter build apk --release --split-per-abi --target-platform android-arm64
flutter build windows --release
powershell -ExecutionPolicy Bypass -File tool\install_windows.ps1
```

Release APKs are signed with the debug key, which is fine for sideloading onto your own phone.

Release builds shrink code with R8 in full mode, which strips the classes ML Kit's QR scanner finds by reflection (symptom: `getClass() on a null object reference` when scanning). `android/app/proguard-rules.pro` keeps them. To read an obfuscated stack trace, look the class names up in `build/app/outputs/mapping/release/mapping.txt`.

Test the background sync against a local bare repo, so you don't need GitHub:

```powershell
git init --bare -b main C:\tmp\remote.git
# config.json: { "repoPath": "C:\\tmp\\clone", "remoteUrl": "C:\\tmp\\remote.git" }
powershell -File app\assets\sync\sync.ps1 -ConfigPath config.json -Init
```

Launcher-icon vectors (`android/app/src/main/res/drawable/ic_launcher_*`) and the Windows `.ico` files were generated from the same 108-unit geometry (page, fold, two sync arcs). Keep them in step when changing the design.

## Design rules

- **Lightweight first.** Nothing resident on the phone; skip the remote tree fetch when the head hasn't moved; the Windows window is optional.
- **Never lose data.** Every ambiguous case keeps both versions. Edits beat deletes.
- **Same bytes everywhere.** No line-ending conversion on either side, so blob SHAs match.
- **Secrets stay off GitHub.** The phone token lives in Android/Windows secure storage and travels only by QR.
