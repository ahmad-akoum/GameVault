# Installation management and V2.3 profile

## Launching and relocation

`WindowsGames.launch` sends a Steam AppID to the existing native Steam URI
dispatcher. Before V2.3 it refused to do this if the saved installation folder
was missing. Moving a game between Steam libraries therefore caused GameVault
to reject an otherwise valid Steam launch. Selecting a tracking executable did
not fix this because that setting controls process observation, not Steam's
launch target. The stale-folder gate is removed for Steam games; local games
still require an existing absolute executable path. Bodycam itself was not
moved or launched during automated verification.

`SteamInstallation.inspect` follows configured libraryfolders.vdf paths and
reads only the requested AppID's appmanifest in each library. It validates the
AppID, a safe installation directory name, fully-installed flag, and an existing
folder. Duplicate valid installations are inconclusive. A missing manifest
alone does not mean missing files; inaccessible drives remain Unknown.

`VaultController.refreshInstallation` serializes the resulting vault update.
It changes installation/library paths only. Valid tracking overrides are
preserved, including external launchers. A missing override inside the old
installation is rebased only if the exact relative file exists under the new
root. Otherwise it is retained with guidance to select a path. Metadata,
artwork, matches, favorites, and sessions are not replaced. Launching attempts
this refresh automatically when the saved Steam directory no longer exists.

The profile provides Open File Location beside Open in Steam. Settings retain
Refresh Installation and the separate Open EXE Location action. The native `openLocation` handler uses Windows Shell folder APIs,
including file selection and parent-folder fallback; it does not build shell
commands from paths. No game files or Steam configuration are written.

## Update evidence

The V2.3 continuation reads actual saved StateFlags and current-session named
states/phases from Steam's content log. See `steam_updates.md` for classification,
refresh behavior, real observations, tests and limitations. Build IDs, update
schedules and timestamps remain useful context, not independent proof of a
pending update. Open in Steam delegates management; GameVault never downloads
or installs updates. Local metadata formats are not a stable public API, so
ambiguous and malformed evidence fails to Unknown.

## Profile and tests

`DetailsPage` puts the latest two sessions after playtime; View all sessions /
Show less toggles the full saved history. `TrackingControls` has separate
summary, progress/collections, and settings sections. The settings expansion
retains the executable picker. No time accounting changes are made.

`profileArtworkHeight` keeps the three desktop heights, but caps narrow banners
at a widescreen height. The existing Crop/Fit selection, source image and
artwork stream remain unchanged.

`installation_test.dart` covers configured C/D/G-style library relocations,
custom overrides, exact-path rebasing, persistence, duplicate/missing/corrupt
manifests, unavailable paths, Steam dispatch, and banner sizing.
`v23_profile_test.dart` verifies session expand/collapse without record changes
and reachable narrow settings. Existing responsive/theme/artwork and native
input suites remain required. Real relocated Bodycam launching and Explorer
selection still need user acceptance testing.

## Candidate 3 directory action

`VaultController.openGameLocation` now calls `SteamInstallation.directoryFor`
when opening a game directory. The earlier implementation passed the saved
path directly to Explorer, which could open an obsolete folder after a Steam
library move even when that folder still existed. `directoryFor` reuses
`inspect` on each click, preferring the sole manifest-verified installation in
configured/discovered libraries. It does not persist a metadata refresh or
modify games. Missing/ambiguous Steam evidence produces the existing friendly
error instead of guessing an old directory.

Local games use an existing absolute installation directory, then the parent
of an existing selected executable if their saved directory is unavailable.
The secondary Open EXE Location still selects a valid chosen executable using
the same native handler, with verified directory fallback when it is missing.
`installation_test.dart` covers moved libraries with a surviving old folder,
duplicate/missing manifests, unchanged saved metadata, local fallback, file
selection and failure without native dispatch. This reuses the established
Windows Shell APIs and does not write game files or Steam settings.
