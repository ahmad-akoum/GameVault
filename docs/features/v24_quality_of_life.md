# V2.4 quality of life

## Library and navigation

`ui/library_query.dart` filters on the existing live Steam badge evidence. Queued,
paused and active update evidence still have one visible name: Update Available.
Unknown and old evidence never enter Needs Update. The controller's normal
notification rebuilds the filtered list when an update finishes.

The two play-history sort directions use `SessionTracker.lastPlayed`, the same
timestamps used by Home. Unplayed games go last in both directions, with title
ordering for ties. `library_pages.dart` owns the dropdowns; `vault_shell.dart`
owns navigation. `VaultSettings.sidebarCollapsed` remembers manual collapse;
small windows still use the automatic compact navigation/drawer. Settings uses
the native executable version with build metadata hidden in the label. The EXE
and package retain the full version; `AppVersionLabel.publicVersion` removes
only the `+build` suffix, covered by unit and native-channel widget tests. The obsolete V2
sidebar label is gone.

The manual toggle is rendered only at widths of at least 1050 pixels, where
expansion is supported. Previously it remained visible but disabled below that
boundary. Resizing does not change the stored preference. The sidebar regression
covers the 1049/1050 boundary, forced compact mode, drawer mode and both saved
manual states; the existing responsive thresholds are unchanged.

## Sharing selected artwork

`ArtworkManager.reuseOther` validates and previews the selected cover or banner
in the opposite tab. It reuses the managed file path, without copying pixels or
creating another image. Apply uses the existing `VaultController.applyArtwork`;
Cancel changes nothing. The original/default path and fitting preference remain
independent for each slot. A missing file produces the existing validation
message. Steam lookup and local imports keep their existing behavior.

## Installed storage

`InstalledStorageService` measures file lengths in a worker isolate. It visits
only a verified installation folder, does not follow links, and does not read or
modify game contents. The result is logical file size, not allocated disk space
for compressed/sparse files. Inaccessible files produce an unavailable result
rather than a misleading partial total.

Results live in a separate optional `vault_data/storage_cache.json`, keyed by
installation path, for 24 hours. Concurrent requests are deduplicated and scans
are serialized. Profiles request storage on opening; Refresh storage bypasses
the cache. Refresh Installation also refreshes it. A moved installation resolves
through its launcher metadata first, so the old folder does not supply the new
size. Session polling never scans directories. A game changed while the profile
stays open may need a refresh; filesystem watchers are deliberately out of scope.

## Windows startup

`WindowsStartup` uses the per-user `HKCU` Run key's single GameVault value,
following [Microsoft's documented mechanism](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys).
It quotes the installed EXE path, checks existing ownership, avoids duplicate
registrations and removes only its own value when disabled. Registry changes
require an explicit toggle; reading settings never enables startup. The
controller persists the preference and restores the previous registration if
saving fails. A stale registration is reported and can be updated explicitly.

Debug, candidate builds and data-override environments disable these writes.
The isolated build helper's `-Candidate` define is included in both compilation
passes; the development_artifacts path is an additional guard. A stable release
must be rebuilt without that switch after owner approval. No real startup
registration is created during candidate tests; tests inject a fake registry.

## Steam automatic discovery audit

The existing scanner reads installation registry entries, standard Steam roots,
and linked `libraryfolders.vdf` records, then verifies AppID manifests. Its
classification and linked-library traversal are preserved. Two entry conditions
previously prevented fresh users with no manually saved folders from reaching
that working code: `SteamScanner.scan` rejected an empty list and `VaultShell`
redirected Add games to Settings. These guards are removed. Manual folders are
still an optional fallback; Find games retains the single Scan again control.

## Experimental Epic installations

`EpicScanner` reads local Epic `Data/Manifests/*.item` installation records.
It requires a complete application entry, a valid launcher identity, a real
installation directory and the declared executable inside it. Malformed,
missing and conflicting records are skipped with notices. No whole-drive search,
account token, Epic web API or download-state inference is used.

`GameSource` and `EpicIdentity` are additive model fields. Legacy negative IDs
remain local games; legacy positive IDs remain Steam games. Epic games receive
unused negative vault IDs while retaining the namespace/catalog/artifact tuple
as their launcher identity. Rescanning reuses that identity and does not add a
game automatically. Session IDs and historical records are unchanged.

`WindowsGames.launch` dispatches Epic identities through the native `openEpic`
method. The native handler validates each identifier, checks Windows protocol
registration, and asks the installed launcher to open Epic's documented launch
URI. See [Epic Games Protocol Activation](https://assets-unreal2-epic-prod-us2.s3.dualstack.us-east-1.amazonaws.com/original/4X/f/c/4/fc4342c50e1a0abf34943e019ee90bacccc62950.pdf).
The game process is still detected by the existing installation-root tracking;
launcher helper processes are excluded. Users can select an exact tracking EXE
if a title needs it. Epic library and file-location actions are separate.

Epic entries do not call Steam metadata, artwork or update services. Local
artwork imports and title-based HLTB matching are available. Epic update detection
and automatic online Epic artwork/metadata are deferred. A successful protocol
dispatch is not proof that a game reached its menu: launcher login, updates and
title-specific launch requirements remain external conditions.

## Verification

`v24_services_test.dart` covers source migration, Steam discovery without manual
paths, Epic validation/import/deduplication/relocation, launch dispatch, storage
measurement/caching, and fake-registry startup behavior. `v24_widgets_test.dart`
covers artwork preview/apply/default independence, sidebar persistence/drawer,
live filter changes, sort menus and candidate startup controls at narrow widths.
The complete existing Flutter suite and both native inactivity suites remain
required. Live local discovery evidence stays private; hardware/gameplay and
service availability are reported separately from automated checks.

The first rendered candidate check exposed an old Steam-only discovery-row
label despite the correct Epic model identity. The row now reads its launcher
label from the discovery model, and a widget regression rejects negative Steam
labels for Epic. The candidate build helper also preserves its single compiler
define as a typed PowerShell argument array in both compilation passes.
