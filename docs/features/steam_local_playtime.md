# Steam local playtime — V2.4.1 Phase 1

This foundation reads Steam's cached lifetime **runtime in minutes** without an
API key or network requests. It does not infer active gameplay. Phase 2 adds a
separate [reconciliation foundation](playtime_reconciliation.md).
Phase 3 now connects it through main.dart and VaultController to the explicit
[Playtime Overview setup](playtime_overview.md). Discovery remains unbound until
the user confirms an account; development tests create only synthetic associations.

## Source and identity

`SteamLocalPlaytimeProvider` in `lib/services/steam_local_playtime.dart` reuses
`SteamScanner.locateSteam` and `ValveKeyValues.parse`. Its Windows adapter reads
ActiveUser/PID from HKCU and checks the running process name/path. Detection must
match a discovered Steam installation and an exact individual SteamID64 entry in
loginusers.vdf. MostRecent, profile-folder order and the largest cache are never
fallback identities. Unknown, stopped, mismatched or changing accounts fail closed.

Only the selected account's committed userdata/config/localconfig.vdf is read.
AppIDs are positive integer identifiers; titles and another account's cache are
never substitutes. Missing Playtime differs from an explicit zero. Recent-playtime
fields are not lifetime totals. LastPlayed's sentinel is not a genuine date.

Reads have a 16 MiB limit, compare two reads and modification/size metadata, and
parse in a worker isolate. Partial, malformed, missing or unreadable files produce
structured problems without logging source contents, account names or raw errors.
Steam's async temporary files are ignored. A changing file can be retried by the
future caller; Phase 1 installs no polling timer.

## Confirmation boundary

`SteamPlaytimeService.proposeAccount()` returns an unbound proposal. No sidecar
or association is created by discovery or an unconfirmed refresh.

The Phase 3 UI shows the proposal's display name and SteamID64, offers Confirm
and Cancel, and calls `confirmAccount(proposal)` only after an explicit Confirm.
This revalidates the proposal's account, installation and running PID before
saving. An expired proposal fails without changing the existing association.
Cancel does not accept a baseline. If account confirmation was explicitly completed
before Cancel, that association remains; confirming it is a separate user action.

Refresh requires the confirmed identity to remain active and rechecks identity
around cache reading. A different active account produces accountChanged, never
an automatic rebind. Explicitly confirming another account retains prior snapshots
under their original account/AppID namespace. A copied vault's association travels
with its sidecar, but refresh still requires that exact account to be verified.

## Separate persistence

`SteamPlaytimeSnapshot` in `lib/models/steam_playtime.dart` carries SteamID64,
derived account ID, AppID, source, integer lifetime minutes, retrieval timestamp,
file modification timestamp, optional last-played timestamp, state and problem.
`SteamPlaytimeStore` stores only `steam_playtime.json` beside the selected profile's
vault.json, plus its own backup and lock. It has no dependency on session tracking
and cannot choose vault.json as its output filename. There is no vault schema
migration and no new field on VaultGame, PlaySession or VaultSettings.

The Phase 1 version-1 sidecar holds a confirmed account, latest snapshots and separate
last-known valid snapshots. Failed/missing reads have null current minutes;
last-known values retain their original timestamps, including stale state. Repeated
refreshes replace snapshots by account/AppID rather than accumulating minutes.
Older out-of-order observations do not replace later persisted observations.
Phase 2 reads version 1 and writes version 2, retaining these fields and adding
accepted baseline revisions. Version-1-only readers reject version 2 instead of
silently discarding its baselines. Neither format changes vault.json.

Writes lock/reload the sidecar, serialize mutations, validate a complete JSON
round trip, flush a private staging file and rename it over the destination.
A previous-good backup supports read-only recovery from malformed JSON. After
Phase 2, recovered data is explicitly flagged and further writes are blocked until
deliberate restoration; this prevents a refresh from silently losing a baseline
accepted after the backup. Unreadable or newer
unsupported sidecars fail without reset/downgrade. Saving failures are explicit;
there is no silent in-memory association pretending to have been persisted.
Git ignore rules and the source/package privacy guard exclude sidecars, backups,
locks and staging files because account/playtime data is personal data.

## Freshness and limits

Available means a valid readable cache value, not a confirmed cloud total. A
configurable 24-hour file-age policy labels old values stale; a future file time
is also flagged. `staleAt` additionally ages saved retrieval timestamps. File
modification and LastPlayed do not prove the freshness of each game's counter.
LastPlayed age alone is not a reason to invalidate a game not played recently.
Steam's format is undocumented; offline/cross-device synchronization and missing
entries remain limitations. A lower counter is retained as source evidence, not
silently changed to a historical maximum. Baseline arithmetic is isolated in the reconciliation service.

## Verification

`test/steam_playtime_test.dart` uses newly created synthetic temporary Steam roots
and vaults. It covers confirmation gating, active identity vs MostRecent, wrong
paths/accounts, account-switch races, strict AppIDs, zero/missing/invalid values,
stale/future timestamps, malformed/unreadable/changing caches, restart persistence,
last-known retention, repeated refresh, failed writes and corrupt/newer schemas.
An existing LocalStore fixture with real PlaySession serialization remains
byte-identical after imports, as do the synthetic Steam files.

The opt-in `steam_playtime_live_test.dart` exercises only the default read-only
provider on Windows, using an explicitly supplied test AppID. It never calls
confirmAccount, instantiates a snapshot store or writes a personal association.
The offline suite skips this check. Real cache validation is separate from cloud
verification. The Phase 1/2 foundation checks did not require a Windows build;
Phase 3 adds isolated application verification. No API calls or physical input
tests are performed by this provider's automated tests.
