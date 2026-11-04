# Playtime Overview - V2.4.1 Phases 3-4

The full-width profile banner stays above details/launch controls on the left and
Playtime Overview on the right (available content width at least 820px). Narrower
layouts stack them; Recent Sessions stays below. Theme colors come from ColorScheme.

## Compact panel and explicit setup

`ui/playtime_overview.dart` renders a minute-rounded prominent estimate (Estimated for accepted, Provisional for unaccepted), four rows
(Steam lifetime, GameVault active/inactive, historical adjustment), a source/overlap
footer and Adjust. The information button opens revision, timestamp, exact tracked
runtime, account, cache, refresh and limitation details. Actionable warnings remain
visible in the panel. Only presentation is rounded; calculations/storage keep seconds.
The main profile no longer repeats tracking explanations or the normal logical-size
measurement note; installation/storage errors remain visible.

`PlaytimeSetup` requires account confirmation, an explicit history treatment and
acknowledgment. Steam lifetime is read-only. Full/partial/zero overlap subtracts
TOTAL tracked runtime already counted by Steam; manual input instead means historical
runtime NOT already measured by GameVault. Zero history explicitly retains measured
active time. An unaccepted preview is followed by a separate Accept action. The
Phase 2 service revalidates identity, snapshot, revision and sessions. Cancel never
accepts history; separately confirmed accounts and previously applied revisions stay
confirmed. Stale input needs explicit acknowledgment. Games must be closed to accept
a baseline; later running sessions can contribute active seconds to an existing one.

## Automatic provisional estimates

`state/playtime_overview_controller.dart` reuses the local provider. When no account
is confirmed, it may read the VERIFIED active account into MEMORY ONLY: no association,
snapshot sidecar or baseline is written. Confirmed accounts continue through the
existing snapshot service. A different active account from the confirmed profile
blocks reuse until the user explicitly reviews the account; no old account snapshot
is substituted. Technical information identifies the detected and confirmed account.

For a game without any accepted baseline for that account, a recent available
snapshot can supply `Steam lifetime - current GV total + current GV active`.
The historical portion is `Steam lifetime - current GV total`. This is explicitly
PROVISIONAL, assuming full overlap, and can change with the cache. If Steam lifetime
is below tracked runtime, input is stale/missing, identity is unverified, recovery is
required, or session data is invalid, the provisional result is withheld. There is
no clamping, missing-to-zero conversion or fallback to another account. Existing
accepted/manual baselines always take precedence, including zero historical time.
Non-Steam games remain measured-only. Adjust can accept/revise a chosen assumption.

## Refresh lifecycle and root cause

Phase 3 requested cache refresh on profile entry and again on setup entry. Every
concurrent refresh queued another read, and identity checks shared the same busy
indicator as cache refresh. No unconditional refresh-on-widget-build loop was found, but
bursts could create redundant reads/writes and confusing busy text.

Phase 4 coalesces concurrent manual refreshes; a burst behind an identity read gets
ONE follow-up. Startup/profile/setup entry and the minute timer use an automatic
path: identity is checked once per timer minute; cache reads are limited to five
minutes unless account or game coverage changes. Automatic requests within five
seconds of a covered check are skipped. Manual Refresh bypasses the cache interval.
Unchanged background identity checks notify no listeners. Shutdown drains in-flight
reads and blocks queued follow-ups before releasing a vault; the full suite exposed
and now regression-tests this previous file-handle cleanup race. UI `refreshing` covers
actual cache work only; identity work is separate. Background checks are quiet.
Unconfirmed cache reads are memory-only. Confirmed snapshot persistence is bounded
to actual cache refreshes; these never alter accepted baseline revisions.

## Activity and data boundaries

`VaultController.lifetimePlayed` uses ACCEPTED combined estimates only when the
activity-adjusted setting is enabled and account/session checks pass; otherwise it
uses the selected tracked measure. Provisional estimates NEVER feed Activity.
`ui/activity_pages.dart` labels accepted estimates versus measured fallback in
lifetime summaries/rankings. Total-session mode remains measured-only. Today,
seven-day charts, streak inputs, session counts and Recent Sessions use real
sessions only. No artificial sessions, daily allocations or tracking changes exist.

Historical Steam runtime may include AFK time. Sessions are profile-based, not
Steam-account-stamped: an unobserved switch away and back cannot authenticate past
session ownership. Cache file freshness is not proof of cloud synchronization.
Later Steam-only play requires deliberate reconciliation for accepted totals.
Identity older than two minutes suppresses estimates until verified again. Unknown
legacy activity remains unknown. Separate sidecar recovery remains read-only.

## Verification

`test/playtime_overview_test.dart` covers explicit confirmation/preview/Cancel/accept,
full/partial/manual/zero history, unavailable/stale/decreased data, account switching,
identity expiry, Activity boundaries, narrow/light and wide/dark layouts, compact
information details, memory-only provisional results, refresh throttling/coalescing,
quiet unchanged background checks and actual-work indicators. Phase 1/2 regressions
remain required. Phase 4's focused playtime suite passed before artwork integration;
final full-suite/build results are reported with the development candidate.

Automated checks use isolated synthetic vaults. Physical gameplay, clean-machine
installation and final owner visual acceptance remain separate from these checks.
No personal accounts, baselines or session data are included in the repository
or release package. See the version-specific release notes for final verification.
