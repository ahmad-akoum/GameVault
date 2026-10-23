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
`SteamUpdateSummary` presents an amber status and Open in Steam near Play.
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
