# Development

## Layout

```
syncthing/
├── app/                      Flutter app (Android only)
│   ├── lib/main.dart         entry point + WorkManager background dispatcher
│   ├── lib/src/sync/         pure-Dart sync engine (no Flutter imports)
│   │   ├── engine.dart       scan → plan → apply → commit, state + hash cache
│   │   ├── plan.dart         three-way decision table, conflict naming
│   │   ├── github.dart       GitHub Git Data API client (RemoteRepo interface)
│   │   └── ignore.dart       .gitignore subset
│   ├── lib/src/runner.dart   one sync run with saved config, lock file, log
│   ├── lib/src/config.dart   settings (token in encrypted storage)
│   ├── lib/src/schedule.dart periodic WorkManager task
│   ├── lib/src/ui/           home + settings screens
│   └── test/                 engine tests against an in-memory fake GitHub
├── laptop-sync/              Windows watcher script
└── docs/
```

## Toolchain (Windows)

| Tool | How it was installed | Location |
| --- | --- | --- |
| Flutter (stable) | `git clone -b stable https://github.com/flutter/flutter.git` | `%USERPROFILE%\dev\flutter` (`bin` on user `PATH`) |
| Android Studio | `winget install Google.AndroidStudio` | `C:\Program Files\Android\Android Studio` |
| Android SDK | command-line tools zip → `sdkmanager --licenses`, `sdkmanager platform-tools` | `%LOCALAPPDATA%\Android\Sdk` (`ANDROID_HOME`) |
| JDK for Gradle | Android Studio's bundled JBR | `flutter config --jdk-dir "C:\Program Files\Android\Android Studio\jbr"` |

The project pins **AGP 9.4.1**, **Gradle 9.6.0** and **`compileSdk = 37`**. `permission_handler_android` compiles against API 37, and the Flutter template's AGP 9.1 can't resolve the SDK's `android-37.0` platform. If Gradle doesn't fetch the NDK itself, install it with `sdkmanager --package_file=<file>` containing `ndk;<version>` (the `.bat` wrapper splits arguments on `;`).

When editing `*.gradle.kts` from Windows PowerShell 5.1, don't use `Set-Content -Encoding UTF8`. It adds a BOM that breaks the Kotlin script's `plugins {}` block.

Gradle downloads the SDK platform, build-tools and NDK it needs on the first build. If your global `JAVA_HOME` is a very new JDK, keep the `--jdk-dir` setting, since Gradle often lags behind the newest Java.

Check everything with `flutter doctor`.

## Build and test

```powershell
cd app
flutter test                               # engine + planner tests
flutter analyze
flutter run                                # debug on a connected phone (USB debugging on)
flutter build apk --release --split-per-abi
```

Release builds are signed with the debug key, which is fine for sideloading onto your own phone. To publish, add a real signing config in `android/app/build.gradle.kts`.

Test the laptop script against a local bare repo, so you don't need GitHub:

```powershell
git init --bare -b main C:\tmp\remote.git
# config.json: "remoteUrl": "C:\\tmp\\remote.git"
.\sync.ps1 -Init
```

## Design rules

- **Lightweight first.** No resident service on the phone and no polling faster than needed. Skip the remote tree fetch when the head hasn't moved.
- **Never lose data.** Every ambiguous case keeps both versions. Edits beat deletes.
- **Same bytes everywhere.** No line-ending conversion on either side, so blob SHAs match.
