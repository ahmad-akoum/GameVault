# Steam playtime reconciliation — V2.4.1 Phase 2

This service combines an **accepted unmeasured historical runtime estimate**
with GameVault's measured active seconds. It does not reconstruct historical AFK
time. It is separate from SessionTracker, VaultController.played, Activity charts,
rankings and streaks at the tracking layer. Phase 3 connects a separate UI projection
to lifetime summaries and rankings; see [Playtime Overview](playtime_overview.md).
No personal baseline is created automatically and no session migration is needed.

## Calculation and evidence

`lib/models/playtime_reconciliation.dart` contains immutable input checkpoints,
accepted baseline records and the pure `reconcilePlaytime` projection.

For a Steam-cache baseline:

```
S0 = reported Steam lifetime minutes × 60
T0 = GameVault observed total seconds at the checkpoint
A0 = GameVault active seconds at the checkpoint
O0 = explicitly accepted overlap of observed runtime already inside S0
H0 = S0 - O0
combined estimate now = H0 + current GameVault active seconds
```

T0 and A0 are both retained. Full overlap subtracts total runtime, including its
inactive component, once; subtracting only active time would leave overlapping
inactive time in H0. The ongoing inactive counter is not modified or subtracted
again. H0 is unmeasured runtime and can contain AFK time; it is not verified active
gameplay or necessarily all from before the first GameVault session.

For nonzero Steam and tracked runtime, overlap is required with either
userConfirmed or userAssumed evidence. Unknown evidence is rejected. An explicit
zero overlap is supported. Only the mathematical zero cases can supply overlap
automatically: no tracked runtime, or an actual reported Steam zero. Missing
Steam data is never a zero, and last-known snapshots are not silently substituted.
Overlap outside 0..min(S0,T0) is rejected, not clamped. Steam minute rounding or
sync delays can therefore require waiting or an explicit manual historical value.

For manual history, the user supplies H0 directly: **historical runtime not
already measured by GameVault**, not a current Steam lifetime total. Source is
manualHistorical; overlap is notApplicable. Any available Steam snapshot is kept
as reference evidence, without overriding the manual value. A manual zero is
an explicit no-historical-add-on choice, useful for games tracked from the start.
It preserves active time even when Steam reports rounded/excess runtime. It does
not turn an unavailable Steam lifetime field into a reported zero.

## Acceptance and revisions

`PlaytimeReconciliationService` reuses Phase 1's SteamPlaytimeService/provider and
store. Proposals and acceptance require the already confirmed account to be
identifiable and active. Account changes or unavailable identity fail closed.
Proposing requires all sessions for that game to be closed. It copies session IDs,
start times, total and active counts; the original sessions and day maps are never
changed. Existing session validation rejects incomplete activity and duplicate IDs.

`accept` is an explicit Phase 3 UI action. It rechecks the account, expected prior
revision, source snapshot, session checkpoint and freshness. Changed inputs expire
the preview rather than accepting a different calculation silently. Stale Steam
input requires explicit acknowledgement, retained with the accepted record.

Accepted baselines retain source, account/AppID, revision, snapshot, checkpoint,
overlap/evidence, H0, capture time and acceptance time. Explicit rebaselining appends
a new revision; it never adds H0 to an old combined result. Reaccepting an expired
preview fails. Account confirmation and Phase 1 refreshes preserve all revisions.

## Refresh, history and account boundaries

Steam increases, decreases, stale snapshots or unavailable cache reads never
change an accepted H0. Decreases, staleness and missing data are exposed as review
issues while the accepted projection remains stable. Extra Steam runtime played
without GameVault after the checkpoint is **not automatically added**. Doing so
would risk double-counting delayed synchronization. A deliberate new baseline is
required to incorporate such time.

Evaluation checks that the original checkpointed sessions are still present with
the same counts and start times. Edits/removal require review; they do not cause a
negative active delta or a silently changed historical adjustment. Additional
sessions, including a currently running new session, contribute only their active
seconds. Other games do not contribute. Existing unknown activity remains unknown.

Baselines are namespaced by confirmed SteamID64/AppID. A new confirmed account has
no inherited baseline; the earlier account's revisions remain preserved. GameVault
sessions themselves are profile-based and have no historical Steam-account stamp.
The baseline does not authenticate which account a past session used, or detect an
account switch that occurred while this disconnected service was not observing.
Future UI must retain that distinction and the accepted overlap assumptions.

## Persistence and compatibility

The existing separate steam_playtime.json now writes schema version 2 and reads
both 1 and 2. Version-1 snapshots and confirmation survive additive migration;
vault.json, PlaySession and VaultSettings schemas remain unchanged. Older Phase 1
readers fail closed on v2 instead of dropping its new fields. Snapshot writes keep
the baseline history; invalid revisions and inconsistent saved arithmetic fail
validation. Serialized writes retain locking, flushed staging/rename and backups,
with a 16 MiB output bound checked before replacing anything.

Backup recovery is now explicitly read-only. A backup can predate the latest
accepted revision, so automatic normalization could roll history back. The store
flags recoveredFromBackup, blocks mutations and reconciliation, and preserves the
primary/backup until deliberate restoration. Unsupported future schemas are never
downgraded. All sidecars and their backups/locks/staging files remain private.

## Verification

Shutdown previously drained cache refreshes but could miss direct account
confirmation or baseline-acceptance writes. `SteamPlaytimeStore.close()` now
seals the mutation queue synchronously and returns its pending completion.
`PlaytimeOverviewController.close()` seals the store before awaiting refreshes
and then drains admitted mutations. Reads remain available; later mutations
fail without writing. Existing staging, atomic replacement and recovery rules
are unchanged. Delayed confirmation/acceptance regression tests verify shutdown
waits, saved values survive reload, new writes are rejected, repeated close is
safe, and session records remain unchanged. This change is pending release.

`test/playtime_reconciliation_test.dart` covers full/partial/zero/assumed overlap,
missing and explicit zero Steam values, manual zero/nonzero values, stale-input
acknowledgement, refreshes and decreases, additional active time, open sessions,
changed/deleted/invalid sessions, duplicate acceptance, revision persistence,
account changes, legacy sidecars, rejected tampered arithmetic, failed writes and
read-only recovery. Phase 1 regressions remain required.

The full-overlap fixture is synthetic: Steam=2h, tracked runtime=1h1m1s,
active=30m27s. Subtracting overlapping total runtime leaves 58m59s of historical
runtime and a combined estimate of 1h29m26s. No personal baseline, account, cached
playtime or session history is included. Lifetime UI rounds/labels estimates
because Steam source precision is minutes.
