# Read-only Steam Update Center

## Data flow and evidence

`SteamUpdateService` reads configured libraries through `SteamScanner`, then one
AppID-specific appmanifest per imported game/library. It validates identity,
relative installation name, and an available game directory. Duplicates,
missing/unreadable manifests, unknown flags and corrupt/missing files produce
Unknown. It never writes a Steam file, starts a download, or reads account
credentials. Public build numbers, Steam news and screenshots are not used.

Steam stores a bitmask in StateFlags. The implemented flags include Update
Required (2), Fully Installed (4), Update Queued (8), Update Running (256), and
Update Paused (512). The client also records named state transitions in
`logs/content_log.txt`, with a separate update phase identifying Downloading.
The [Valve issue tracker example](https://github.com/ValveSoftware/steam-for-linux/issues/13433)
contains named download/queue/pause transitions and scheduler bitmask results.
These support the interpretation; the format remains internal and may change.
Current local read-only observations also contained these named transitions.

A positive installed build plus an explicit Update Required flag permits Update
Available. Queued or Paused is shown only with the corresponding explicit state,
not a nonzero ScheduledAutoUpdate value. A nonzero target build differing from
the installed build is insufficient by itself. This also avoids assuming a
beta installation should match the public branch. Same-build depot updates can
still be required, so build equality does not cancel an explicit required flag.

`WindowsGames.steamStarted` reads the Steam process creation time through the
native channel without interacting with Steam windows. A newer current-session
app-state log entry supersedes older saved manifest flags. Downloading requires
an explicit current-session Running Update / Downloading phase. Update Running
without an identified phase is Updating only with current-session confirmation.
Old running flags, contradictory flags, stopping phases and conflicting target
information fail safely. Initial installations with no installed build are not
presented as updates to an installed game.

The profile reports the source and recorded time. A saved manifest is Steam's
last persisted state, not a guarantee that its current UI has already flushed a
new transition. Age alone does not invalidate a pending flag: an update can sit
waiting for weeks. Newer conflicting log evidence does invalidate it. With Steam
closed/unverifiable, positive saved states are explicitly Last known, with no
live cover badge. No pending update recorded never means fully up to date.

## UI and refresh

`SteamUpdateBadge` sits at the cover's top left; favorite controls remain clear.
`SteamUpdateAction` replaces the Play button in `TrackingControls` only when
`evidence.badge` confirms a pending state. It is an amber OutlinedButton calling
the existing
`VaultController.openGameLocation(..., steam: true)` action. Clicking it opens
that AppID's Steam library page; it cannot launch a game or manage downloads.
Unknown, completed/no-pending and
Last known evidence retain Play. The normal controller notification rebuild
restores Play automatically after completion, without changing detection or
refresh intervals. Local games ignore Steam evidence.

`DetailsPage` always shows Open in Steam beside Open File Location for Steam
games. At narrow widths the actions wrap onto separate lines. Open in Steam
continues to work during any update state; the expanded evidence panel avoids
a duplicate Steam button.
`SteamUpdatePanel` shows evidence and a manual refresh in Game Settings. Queued,
Paused, Downloading and Updating use their own labels. Unknown has no badge.
All states are transient; they do not change game metadata or session records.

`VaultController.refreshSteamUpdates` serializes refresh work independently of
2-second activity polling. It runs at startup, every 30 seconds, on profile open,
after import/installation refresh, or manually. Changes notify the UI only when
evidence changes; no artwork cache is evicted. Configured libraries are read,
not whole drives. Small manifests are reread (same-size writes can share a
filesystem timestamp); the content log is stat-cached and limited to its last
1 MiB. Truncated/missing current-session evidence never fabricates a download.

## Validation and limitations

The read-only local probe observed required states in actual installed manifests
and paused states in two others; normal installed and beta records received no
update badge. Missing-file state was kept Unknown. The private probe output is
ignored, not distributed. No actual update was started, paused or reordered.

`steam_updates_test.dart` covers required, queued, paused, active download,
updating, completion/stopping, old-session logs, invalid/unknown flags, initial
installs, missing/corrupt/duplicate manifests, unavailable libraries, future
metadata, beta/target mismatches, closed Steam, changed files, cover placement,
profile controls and Open in Steam dispatch. Real active download transitions
and exact agreement with the user's Steam UI remain manual acceptance checks.

Queue position, precise schedule, workshop-only changes without an app update,
remote branch freshness, preload and unusual client states are not inferred.
A bounded log tail may lack evidence, and a client-format change may require an
adapter update. Current-session native detection is smoke-checked, but does not
use private Steam RPC or claim a supported official update-status API.

## Candidate 3 profile follow-up

Issue #12 follows owner testing of candidate 2. The earlier profile showed Play
and a separate pending status together, obscuring which action was available.
The replacement stays in the original launch slot, before the session summary.
Cover badges and independent artwork rendering are unchanged.

`profile_actions_test.dart` exercises every pending-state transition, completion,
Unknown/Last known fallback, non-interactive status, native Steam dispatch,
local-game exclusion and light/dark 360-pixel layouts. Existing service tests
continue to cover evidence classification; real Steam download transitions
still require owner acceptance and are not simulated by starting downloads.

## Candidate 4 interactive actions (Issue #14)

Candidate 3's non-interactive Chip was intentional but prevented the owner from
using the primary action to reach Steam. `SteamUpdateAction` now requires an
`onOpen` callback. `TrackingControls` wires every pending state to the same
existing navigation route. Available shows a persistent short instruction to
start the update manually in Steam; every status has a navigation tooltip.
The secondary Steam and file-location buttons stay independent and unchanged.

### Automatic update investigation

No reliable, supported update-only request for arbitrary installed retail games
was verified. Therefore no automatic update initiation is implemented or claimed.
The existing native `openSteam` path dispatches only
`steam://nav/games/details/<AppID>`; `rungameid` remains exclusive to Play.
Navigation success is not download success. No install/validate commands,
SteamCMD, private interfaces, manifest writes, or download UI automation are used.

[Valve's ISteamApps reference](https://partner.steamgames.com/doc/api/ISteamApps#MarkContentCorrupt)
documents MarkContentCorrupt as forcing verification on a subsequent launch,
not a launcher endpoint to start a pending update for a supplied game AppID.
It is not suitable here. Valve's
[Remote Downloads help](https://help.steampowered.com/en/faqs/view/1025-BD94-12FC-3409)
describes user-managed downloads via authenticated Steam pages/mobile, not a
verified update-only desktop URI contract. The Valve Developer Community
[protocol](https://developer.valvesoftware.com/wiki/Steam_browser_protocol) and
[SteamCMD](https://developer.valvesoftware.com/wiki/SteamCMD) pages returned HTTP
403 in this research session. Their unavailable contents were not treated as
verified documentation and no access restriction was bypassed. The conclusion
is deliberately limited to no supported method verified for this integration.

### Verification

`profile_actions_test.dart` asserts the exact single native openSteam call and
AppID for all five pending states, no Play callback/pending launch, correct
manual guidance, unchanged secondary action, completion/unknown/last-known
fallback, Play callback dispatch, unavailable-Steam error, and all three profile
sizes at 360 pixels in light/dark themes. The recording controller overrides
only Play in this UI fixture; existing installation tests separately verify
native Steam launch dispatch. Full Flutter, native, analysis and isolated
Windows build checks remain required. Actual Steam download transitions are
owner acceptance tests; navigation cannot guarantee Steam's independent
scheduler does not change state on its own.
