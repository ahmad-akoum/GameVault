# GameVault

A local-first Windows game library built with Flutter. Discover installed Steam
games, choose what to import, launch games and track new play sessions in one place.

**V2.0.0 stabilization is prepared locally; publication awaits owner approval.**
V2.1 visual customization and V3 ratings are separate future milestones in this snapshot.

## Supported platforms

Windows desktop is the implemented target. Android, macOS, Linux and web are not
supported application releases. An unrelated Android toolchain smoke build does not
establish Android support for GameVault.

## Implemented features

- Steam discovery across configured libraries, manifest validation and filtering of
  recognized tools, redistributables and Wallpaper Engine. Playable demos can appear.
- Selective import: detecting a game never automatically adds it to My Library.
- Steam metadata, cached artwork and best-effort HowLongToBeat matching.
- Search, filters, sorting, favorites, statuses, collections and manual progress.
- Steam launching and import/launch of local Windows executables.
- Observed runtime and activity-adjusted playtime, including imported games launched
  elsewhere while GameVault remains open.
- Configurable idle/focus thresholds: 60 seconds without input and 10 seconds unfocused.
  Keyboard/mouse and existing XInput activity are retained; standard DualSense Raw Input supplements them. Physical Bluetooth testing remains pending.
- Home activity summaries, recent games, statistics and session history.
- Dark/light/system appearance, accent customization and responsive desktop layouts.
- V1 data migration, previous-good backups, interrupted-session recovery, serialized
  saves and a data-folder lock against concurrent writers.

## Requirements and setup

Development was previously validated with Flutter **3.38.5**, Dart **3.10.4**, and
Visual Studio 2022 on Windows. Install Flutter with Dart on PATH and Visual Studio's
**Desktop development with C++** workload, including the Windows SDK.

After repository access is granted:

```powershell
git clone https://github.com/ahmad-akoum/GameVault.git
cd GameVault
flutter doctor -v
flutter pub get
.\scripts\prepare_windows.ps1
flutter analyze --no-pub
flutter test --no-pub
```

`prepare_windows.ps1` creates project-local plugin junctions when Windows symlink
privileges are unavailable. It does not change Windows security or the Flutter SDK.
If the first `flutter pub get` reports missing symlink support after resolving
dependencies, run the preparation script and then repeat `flutter pub get`.

Use an isolated data folder for development and acceptance testing:

```powershell
$env:GAMEVAULT_DATA_DIR = Join-Path (Get-Location) 'build\dev-vault'
flutter run -d windows
```

Build the regular Windows application:

```powershell
flutter build windows --release --no-pub -t lib/main.dart
```

The output is `build/windows/x64/runner/Release/`. Keep the executable, DLLs and
Flutter `data` directory together. A standalone EXE is not the complete application.
Other PCs may require Microsoft's Visual C++ runtime. Do not include `vault_data`
in an archive intended for other people.

## Storage and privacy

By default, GameVault keeps `vault_data` beside its executable. `GAMEVAULT_DATA_DIR`
overrides that location. Close the app before backing up the entire data folder.
Keep your real vault separate from development, tests and release packaging.

The first V2 save preserves a readable V1 document as `vault.json.v1-backup`.
Recoverable corruption can fall back to a valid backup; unrecoverable data blocks
startup rather than silently resetting the library.

Metadata/artwork and HLTB lookups contact external services. Local session tracking
does not record keystroke contents or inject code into games. No provider credentials
are required for the currently implemented local features.

## Limitations

- Historical Steam hours, past AFK reconstruction, achievements and critic/community
  rating integrations are not implemented.
- Tracking requires GameVault to remain open. Sampling is about every two seconds;
  session checkpoints are about every 15 seconds. Crashes can lose the last unsaved interval.
- Global input is an activity estimate. Reading and cutscenes may be classified idle;
  standard DualSense Raw Input is included, with physical acceptance testing pending.
- Protected processes and unusual launchers may require selecting the real executable.
  Ambiguous process matches are ignored; a process is not credited to multiple games.
- Steam metadata and HLTB are best-effort integrations that can change or become unavailable.
- Personal progress is manually entered, not calculated from achievements or HLTB.

## Screenshots

Public-safe screenshots are pending. Existing local screenshots contain a personal
game library and are deliberately excluded. Future images should use a separate
demonstration vault and accurately show the release candidate without invented metrics.

## Validation and releases

The retained V2 development report records 53 automated tests passing, clean analysis,
a successful Windows build and a native fixture smoke test. These historical checks
are not owner acceptance testing. See [validation](docs/VALIDATION.md) for current
publication checks and remaining manual tests.

- [Changelog](CHANGELOG.md)
- [Release candidate notes](docs/releases/v2.0.0-rc.1.md)
- [Source provenance](docs/SOURCE_PROVENANCE.md)
- [Development and release workflow](CONTRIBUTING.md)
- [Roadmap](docs/ROADMAP.md)

## Ownership and third-party services

No open-source license is granted by this repository. Dependencies retain their
respective licenses. GameVault is not affiliated with Valve, Steam, HowLongToBeat,
Metacritic, RAWG or IGDB. External services and their data remain subject to their terms.

## Stabilization

Settings uses actual Windows build metadata. Idle polls avoid redundant rebuilds; artwork decoding is bounded and file existence checks no longer block widget builds. No measured high-refresh FPS claim. See [V2.0 release notes](docs/releases/v2.0.0.md). HLTB website access is not cleared for public distribution; see [licensing](docs/LICENSING.md).
