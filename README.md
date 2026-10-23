# GameVault

Development follows [the contribution guide](CONTRIBUTING.md) and
[review/release instructions](docs/DEVELOPMENT.md). CI verifies PRs; it never
publishes a release automatically.

A local-first Flutter Windows game library: discover installed games, choose what to import, launch them, and track new play sessions.

**V2.2.0 - Session, artwork and responsive-layout update.**

This working tree contains the unpublished **V2.3.0 candidate 2 (2.3.0+10)**.
The features below describe this candidate; the approved stable release remains
V2.2.0. Candidate testing does not upgrade the owner's stable installation.

## Supported platform
Windows x64 desktop. Flutter 3.38.5, Dart 3.10.4 and Visual Studio 2022 with Desktop development with C++ were used for validation. Android is not a supported GameVault release; prior Android build success does not establish working desktop integrations on a phone.

## Implemented features
- Steam discovery across libraries and drives, manifest validation and non-game filtering, including Wallpaper Engine. Detection never automatically imports games.
- Cached artwork and metadata, HowLongToBeat search, saved-match selection and refresh (independent website integration; availability and distribution permissions are not guaranteed).
- Search, sorting, favorites, statuses, named collections and manual completion progress.
- Steam/local executable launching and conservative process matching.
- Installation refresh and folder actions across configured Steam libraries; conservative update-state badges and Open in Steam, with source/timestamp details and no automatic update downloads.
- Independent vertical cover and widescreen profile-banner selection, local image import, preview, restore and supported Steam alternatives.
- Total observed session time and activity-adjusted time; configurable 60-second idle and 10-second focus-loss defaults, session history and dashboard statistics.
- Keyboard/mouse and existing XInput activity; standard DualSense Raw Input observation with drift/noise thresholds. Owner gameplay acceptance covered DualSense Bluetooth with Steam Input both enabled and disabled.
- Dark, Light and System appearance; Cobalt, Crimson, Emerald, Amethyst, Obsidian and Midnight presets; separate accent/background/surface custom colors with preview. Surface hues adapt to mode for readable contrast.
- Compact, Comfortable and Expanded game profiles with a persistent size preference.
- Enlarged artwork viewer with zoom, pan, reset, Escape and a close button.
- Recent Sessions presents total, active and inactive time with seconds, timestamps and session-end status; narrow layouts retain access to all main screens.
- Local persistence, previous-good backup, V1 migration backup, interrupted-session recovery and a data-folder writer lock.

## Install or upgrade
Extract the entire versioned Windows ZIP to a writable folder. Keep gamevault.exe, all DLLs and the data directory together; run gamevault.exe after extraction. Microsoft Visual C++ runtime may be required on another PC.

Close GameVault and back up its entire vault_data folder before upgrading. Keep each historical vault separately. A new extracted release starts empty unless you explicitly provide a copy of your current vault. Never merge or replace a newer vault with an older one. See [user guide](docs/USER_GUIDE.md).

## Develop
Install the Windows Flutter toolchain and run:

```powershell
flutter pub get
.\scripts\prepare_windows.ps1
flutter analyze --no-pub
flutter test --no-pub
$env:GAMEVAULT_DATA_DIR = Join-Path (Get-Location) 'build\dev-vault'
flutter run -d windows
```

The preparation script creates local plugin junctions where symlink privileges are unavailable. If dependency resolution reports missing symlink support, run the script then repeat pub get. Do not upgrade dependencies just to build this release.

```powershell
$Build = Join-Path (Split-Path (Get-Location) -Qualifier) 'GameVaultBuilds\v2.2.0'
$Symbols = Join-Path $env:LOCALAPPDATA 'GameVaultPrivateSymbols\v2.2.0'
.\scripts\build_private_release.ps1 -Version 2.2.0 -BuildDirectory $Build -SymbolDirectory $Symbols
python tool/package_release.py 2.2.0 --build-dir $Build
```

The isolated build output is `$Build\windows\x64\runner\Release`. Packaging selects runtime files only and refuses to overwrite an existing versioned ZIP. Verify pubspec version and the executable's ProductVersion before packaging. See [developer guide](docs/DEVELOPMENT.md).

## Privacy and limitations
Data is stored in vault_data beside the executable, or the directory selected by GAMEVAULT_DATA_DIR. The application keeps no keystroke or controller-button history. Metadata services receive requests; local tracking is not an authenticated Steam account integration.

Historical Steam hours and historical AFK time cannot be reconstructed. Monitoring needs GameVault to remain open. Two-second process sampling and 15-second checkpoints are approximate; recent unsaved time may be lost after a crash. Global activity is an estimate, so reading or cutscenes can be classified inactive. Protected processes and unusual launchers may need an explicit executable selection.

Windows high-refresh frame measurements and clean-machine installation remain unverified. The scrolling changes do not establish a measured 120/180 FPS result.

Live HowLongToBeat website lookup, refresh and script inspection are disabled in this release pending an authorized integration. Previously saved estimates and saved matches remain available offline. This change does not by itself resolve every licensing question. Ratings remain reserved for V3.

## Screenshots
Screenshots of personal libraries are intentionally excluded. No private artwork cache or game/session database is distributed.

## Release documentation
- [Changelog](CHANGELOG.md)
- [V2.0 notes](docs/releases/v2.0.0.md)
- [V2.1 notes](docs/releases/v2.1.0.md)
- [Validation](docs/VALIDATION_2026-10.md)
- [Roadmap](docs/ROADMAP.md)
- [License and services](docs/LICENSING.md)

No open-source license is granted for original GameVault code. The public repository makes the source viewable for testing; all rights to GameVault code remain reserved, and no general reuse or redistribution permission is granted. Dependencies retain their own licenses. GameVault is independent of Valve, Sony, Microsoft and HowLongToBeat.

Release packages are prepared under release_artifacts/ready/<version>. Private debug symbols remain under release_artifacts/private-symbols and must not be uploaded. A package privacy guard rejects local project/home paths embedded in runtime files. Use separate debug-symbol directories for each version.

The private-release helper temporarily gives Flutter's generated plugin registrant a neutral package URI in generated package_config.json, compiles the same source, then restores that configuration byte-for-byte in a finally block. No dependency, SDK edit or source relocation is introduced. Debug splitting alone does not remove that URI. Do not run concurrent builds while the helper is running.
