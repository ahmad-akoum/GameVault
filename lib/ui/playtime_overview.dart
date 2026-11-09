import 'package:flutter/material.dart';
import '../models/game.dart';
import '../models/playtime_reconciliation.dart';
import '../services/playtime_reconciliation_service.dart';
import '../state/vault_controller.dart';
import 'session_presentation.dart';

String playtimeIssue(PlaytimeReconciliationIssue issue) => switch (issue) {
  PlaytimeReconciliationIssue.accountNotConfirmed =>
    'Confirm your Steam account to set up historical playtime.',
  PlaytimeReconciliationIssue.accountUnavailable =>
    'Active Steam account could not be verified. Showing GameVault-only time.',
  PlaytimeReconciliationIssue.accountChanged =>
    'The active Steam account differs from the confirmed account. Review the account before using a baseline.',
  PlaytimeReconciliationIssue.steamUnavailable =>
    'Steam cached lifetime is unavailable. Missing data is not zero.',
  PlaytimeReconciliationIssue.staleSteamSnapshot =>
    'Steam data is stale. File freshness does not prove cloud synchronization.',
  PlaytimeReconciliationIssue.steamCounterDecreased =>
    'Steam lifetime decreased below the accepted baseline. Historical time has not changed.',
  PlaytimeReconciliationIssue.overlapRequired =>
    'Choose and acknowledge how much tracked runtime overlaps Steam.',
  PlaytimeReconciliationIssue.invalidOverlap =>
    'Overlap must not exceed either Steam lifetime or GameVault total runtime.',
  PlaytimeReconciliationIssue.invalidHistoricalValue =>
    'Enter a valid nonnegative historical duration.',
  PlaytimeReconciliationIssue.gameRunning =>
    'Close the game before setting or revising a baseline.',
  PlaytimeReconciliationIssue.invalidSessionData =>
    'Some session activity is incomplete. Reconciliation requires review.',
  PlaytimeReconciliationIssue.sessionHistoryChanged =>
    'Checkpointed sessions changed. Review and explicitly revise the baseline.',
  PlaytimeReconciliationIssue.proposalExpired =>
    'Inputs changed after the preview. Create a fresh preview.',
  PlaytimeReconciliationIssue.baselineMissing =>
    'No accepted historical baseline. Showing GameVault-only playtime.',
  PlaytimeReconciliationIssue.sidecarRecoveryRequired =>
    'Playtime storage needs deliberate recovery. Existing files were preserved.',
};

const profileEstimateExplanation =
    'Profile-based estimate: historical runtime may include AFK time. GameVault sessions are not Steam-account-stamped; play on another account cannot be separated automatically.';

/// Minute-level presentation for estimates; exact recorded seconds stay in details.
String overviewDuration(int seconds) {
  final minutes = (seconds / 60).round();
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String overviewFooter({
  PlaytimeBaseline? baseline,
  required bool accepted,
  required bool provisional,
  required bool steam,
  required bool available,
}) {
  if (accepted && baseline != null) {
    if (baseline.source == HistoricalPlaytimeSource.manualHistorical) {
      return baseline.historicalSeconds == 0
          ? 'Manual · Zero history'
          : 'Manual · Historical-only time';
    }
    if (baseline.historicalSeconds == 0) return 'Steam · Zero history';
    final overlap = baseline.overlapSeconds == 0
        ? 'Zero'
        : baseline.overlapSeconds == baseline.tracked.total
        ? 'Full'
        : 'Partial';
    final evidence =
        baseline.overlapEvidence == SteamOverlapEvidence.userConfirmed
        ? 'confirmed'
        : 'assumed';
    return 'Steam · $overlap overlap $evidence';
  }
  if (provisional) return 'Steam · Full overlap assumed · Provisional';
  if (steam && !available) return 'Steam unavailable · GameVault measured time';
  return 'GameVault · Measured active time';
}

class PlaytimeOverview extends StatelessWidget {
  const PlaytimeOverview({
    super.key,
    required this.controller,
    required this.game,
  });
  final VaultController controller;
  final VaultGame game;

  @override
  Widget build(BuildContext context) {
    final c = controller, g = game, p = c.playtime;
    final active = c.tracker.total(g.appId, active: true),
        total = c.tracker.total(g.appId);
    final unknown = hasUnknownActivity(
      c.tracker.sessions.where((s) => s.gameId == g.appId),
    );
    final result = g.isSteam ? p?.estimate(g.appId, c.tracker.sessions) : null;
    final provisional = g.isSteam
        ? p?.provisional(g.appId, c.tracker.sessions)
        : null;
    final snapshot = g.isSteam ? p?.snapshotFor(g.appId) : null;
    final baseline = result?.baseline;
    final accepted = result?.combinedSeconds;
    final combined = accepted ?? provisional?.combined;
    final historical = baseline?.historicalSeconds ?? provisional?.historical;
    final footer = overviewFooter(
      baseline: baseline,
      accepted: accepted != null,
      provisional: provisional != null,
      steam: g.isSteam,
      available: snapshot?.lifetimeMinutes != null,
    );
    final warnings = <String>{
      if (result != null)
        ...result.issues
            .where(
              (i) =>
                  i != PlaytimeReconciliationIssue.baselineMissing &&
                  i != PlaytimeReconciliationIssue.accountNotConfirmed,
            )
            .map(playtimeIssue),
      if (g.isSteam &&
          snapshot != null &&
          snapshot.staleAt(
            p!.steam.provider.now(),
            p.steam.provider.maxCacheAge,
          ))
        playtimeIssue(PlaytimeReconciliationIssue.staleSteamSnapshot),
      if (g.isSteam &&
          p != null &&
          snapshot?.lifetimeMinutes == null &&
          !p.busy &&
          p.detection?.proposal != null &&
          (p.data.confirmedAccount == null || p.accountMatches))
        'Steam lifetime is unavailable. Adjust can use manual historical-only time.',
      if (p?.message != null && g.isSteam) p!.message!,
    };
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
    return Container(
      key: const ValueKey('playtimeOverview'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Playtime Overview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Playtime information',
                icon: const Icon(Icons.info_outline, size: 18),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => PlaytimeInformation(controller: c, game: g),
                ),
              ),
            ],
          ),
          if (combined == null)
            Text(
              'GameVault measured active time',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 4),
          Text(
            unknown
                ? 'Unknown'
                : '${accepted != null
                      ? 'Estimated '
                      : provisional != null
                      ? 'Provisional '
                      : ''}${overviewDuration(combined ?? active)}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          row(
            'Steam lifetime',
            !g.isSteam
                ? 'Not applicable'
                : snapshot?.lifetimeMinutes == null
                ? 'Unavailable'
                : overviewDuration(snapshot!.lifetimeMinutes! * 60),
          ),
          row(
            'GameVault active',
            unknown ? 'Unknown' : sessionDuration(active),
          ),
          row(
            'GameVault inactive',
            unknown ? 'Unknown' : sessionDuration(total - active),
          ),
          row(
            'Historical adjustment',
            historical == null ? 'Not set' : overviewDuration(historical),
          ),
          const SizedBox(height: 10),
          Text(footer, style: Theme.of(context).textTheme.bodySmall),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                warning,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
          if (g.isSteam && p != null)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.tune, size: 16),
                onPressed: c.storageBlocked
                    ? null
                    : () => showDialog<void>(
                        context: context,
                        builder: (_) =>
                            PlaytimeSetup(controller: c, appId: g.appId),
                      ),
                label: const Text('Adjust'),
              ),
            ),
        ],
      ),
    );
  }
}

class PlaytimeInformation extends StatelessWidget {
  const PlaytimeInformation({
    super.key,
    required this.controller,
    required this.game,
  });
  final VaultController controller;
  final VaultGame game;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.playtime ?? controller,
    builder: (context, _) {
      final c = controller, p = c.playtime, id = game.appId;
      final result = game.isSteam ? p?.estimate(id, c.tracker.sessions) : null;
      final b = result?.baseline, snapshot = p?.snapshotFor(id);
      Widget item(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text),
      );
      return AlertDialog(
        title: const Text('Playtime information'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                item(profileEstimateExplanation),
                if (p?.detection?.proposal case final account?)
                  item(
                    'Detected Steam account: ${account.displayName} • ${account.account.steamId64}',
                  ),
                if (p?.data.confirmedAccount != null)
                  item(
                    'Confirmed profile account: ${p!.data.confirmedAccount!.steamId64}',
                  ),
                item(
                  'Activity uses accepted estimates or measured active time only. Provisional estimates are never used in summaries or rankings.',
                ),
                item(
                  'GameVault total runtime: ${sessionDuration(c.tracker.total(id))}',
                ),
                item(
                  'GameVault active: ${sessionDuration(c.tracker.total(id, active: true))}',
                ),
                if (b != null) ...[
                  item(
                    'Accepted revision ${b.revision} • ${b.acceptedAt.toLocal().toString().split('.').first}',
                  ),
                  item(
                    'Historical adjustment: ${sessionDuration(b.historicalSeconds)}',
                  ),
                  if (b.overlapSeconds != null)
                    item(
                      'Accepted overlapping total runtime: ${sessionDuration(b.overlapSeconds!)}',
                    ),
                ] else
                  item(
                    'No accepted baseline. A provisional full-overlap estimate can change with cached Steam data; use Adjust to review and accept history.',
                  ),
                if (snapshot != null) ...[
                  if (b == null &&
                      snapshot.lifetimeMinutes != null &&
                      snapshot.lifetimeMinutes! * 60 < c.tracker.total(id))
                    item(
                      'Steam lifetime is below tracked runtime. Full overlap cannot be assumed; Adjust or refresh after Steam synchronizes.',
                    ),
                  item('Source: Steam local cache (minute precision)'),
                  item(
                    'Retrieved: ${snapshot.retrievedAt.toLocal().toString().split('.').first}',
                  ),
                  item(
                    'Cache file updated: ${snapshot.cacheModifiedAt?.toLocal().toString().split('.').first ?? 'Unknown'}',
                  ),
                  item(
                    'Cache freshness is not proof of cloud synchronization.',
                  ),
                ],
                if (p?.refreshedAt != null)
                  item(
                    'Last cache read: ${p!.refreshedAt!.toLocal().toString().split('.').first}',
                  ),
                item(
                  'Background identity checks run once a minute; opening a profile can recheck sooner. Automatic cache reads are limited to five minutes unless the account or game list changes. Refresh never changes accepted historical time.',
                ),
                if (result != null)
                  ...result.issues.map((i) => item(playtimeIssue(i))),
                if (p?.message != null) item(p!.message!),
                if (game.isSteam && p != null)
                  OutlinedButton.icon(
                    onPressed: p.busy
                        ? null
                        : () => c.refreshPlaytime(refresh: true),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text(
                      p.refreshing
                          ? 'Refreshing cache…'
                          : p.busy
                          ? 'Checking account…'
                          : 'Refresh Steam cache',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

enum HistoryChoice {
  fullOverlap,
  partialOverlap,
  noOverlap,
  zeroHistory,
  manualHistory,
}

class PlaytimeSetup extends StatefulWidget {
  const PlaytimeSetup({
    super.key,
    required this.controller,
    required this.appId,
  });
  final VaultController controller;
  final int appId;
  @override
  State<PlaytimeSetup> createState() => _PlaytimeSetupState();
}

class _PlaytimeSetupState extends State<PlaytimeSetup> {
  final hours = TextEditingController(),
      minutes = TextEditingController(),
      seconds = TextEditingController();
  HistoryChoice? choice;
  bool acknowledged = false, staleAccepted = false, working = false;
  String? error;
  PlaytimeBaselineProposal? preview;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.controller.refreshPlaytime(refresh: true, automatic: true),
    );
  }

  @override
  void dispose() {
    hours.dispose();
    minutes.dispose();
    seconds.dispose();
    super.dispose();
  }

  void reset() => setState(() {
    preview = null;
    error = null;
  });
  Future<void> run(Future<void> Function() action) async {
    setState(() {
      working = true;
      error = null;
    });
    try {
      await action();
    } on PlaytimeReconciliationFailure catch (e) {
      if (mounted) {
        setState(() {
          error = playtimeIssue(e.issue);
          preview = null;
        });
      }
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          preview = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error =
              'Could not complete this action. Check the account, duration and storage, then try again. Existing data was preserved.';
          preview = null;
        });
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  int enteredDuration() {
    int number(String s) {
      if (s.trim().isEmpty) return 0;
      if (!RegExp(r'^\d+$').hasMatch(s.trim())) {
        throw const FormatException(
          'Use nonnegative whole numbers for the duration.',
        );
      }
      return int.parse(s.trim());
    }

    if ([hours, minutes, seconds].every((c) => c.text.trim().isEmpty)) {
      throw const FormatException(
        'Enter a duration; enter 0 explicitly for zero historical time.',
      );
    }
    final h = number(hours.text),
        m = number(minutes.text),
        s = number(seconds.text);
    if (m > 59 || s > 59 || h > 10000000) {
      throw const FormatException(
        'Minutes and seconds must be between 0 and 59; check the hours value.',
      );
    }
    return h * 3600 + m * 60 + s;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller, p = c.playtime!;
    return ListenableBuilder(
      listenable: p,
      builder: (context, _) {
        final account = p.detection?.proposal;
        final blocked =
            working || p.busy || p.data.recoveredFromBackup || c.storageBlocked;
        final snapshot = p
            .data
            .latest['${p.data.confirmedAccount?.steamId64}:${widget.appId}'];
        final sourceStale =
            snapshot?.staleAt(
              p.steam.provider.now(),
              p.steam.provider.maxCacheAge,
            ) ??
            true;
        return AlertDialog(
          title: const Text('Set up / reconcile playtime'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(profileEstimateExplanation),
                  const SizedBox(height: 12),
                  Text(
                    'Confirmed account: ${p.data.confirmedAccount?.steamId64 ?? 'None'}',
                  ),
                  if (account == null)
                    const Text(
                      'Open Steam and sign in. No account is guessed from old logins.',
                    ),
                  if (account != null) ...[
                    Text(
                      'Detected active account: ${account.displayName} • ${account.account.steamId64}',
                    ),
                    if (!p.accountMatches)
                      FilledButton.tonal(
                        onPressed: blocked
                            ? null
                            : () => run(() async {
                                preview = null;
                                await p.confirm(account, c.steamAppIds);
                              }),
                        child: const Text('Confirm this Steam account'),
                      ),
                  ],
                  TextButton(
                    onPressed: blocked
                        ? null
                        : () => run(() async {
                            preview = null;
                            await c.refreshPlaytime(refresh: true);
                          }),
                    child: const Text('Recheck account and cache'),
                  ),
                  if (p.data.recoveredFromBackup)
                    Text(
                      playtimeIssue(
                        PlaytimeReconciliationIssue.sidecarRecoveryRequired,
                      ),
                    ),
                  if (p.message != null) Text(p.message!),
                  if (p.accountMatches && !p.data.recoveredFromBackup) ...[
                    Text(
                      'Steam lifetime total (read-only): ${snapshot?.lifetimeMinutes == null ? 'Unavailable' : sessionDuration(snapshot!.lifetimeMinutes! * 60)}',
                    ),
                    Text(
                      'GameVault total runtime: ${sessionDuration(c.tracker.total(widget.appId))}',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Overlap means tracked runtime already included in Steam. Subtract that total runtime once, then add GameVault active time. Never subtract only active time.',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<HistoryChoice>(
                      initialValue: choice,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Choose historical treatment',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: HistoryChoice.fullOverlap,
                          child: Text('Full tracked runtime overlaps Steam'),
                        ),
                        DropdownMenuItem(
                          value: HistoryChoice.partialOverlap,
                          child: Text('Partial overlap — enter runtime'),
                        ),
                        DropdownMenuItem(
                          value: HistoryChoice.noOverlap,
                          child: Text('Zero overlap with Steam'),
                        ),
                        DropdownMenuItem(
                          value: HistoryChoice.zeroHistory,
                          child: Text('Zero history — tracked from the start'),
                        ),
                        DropdownMenuItem(
                          value: HistoryChoice.manualHistory,
                          child: Text('Manual historical-only time'),
                        ),
                      ],
                      onChanged: blocked
                          ? null
                          : (v) => setState(() {
                              choice = v;
                              preview = null;
                              error = null;
                              acknowledged = false;
                            }),
                    ),
                    if (choice == HistoryChoice.partialOverlap ||
                        choice == HistoryChoice.manualHistory) ...[
                      const SizedBox(height: 12),
                      Text(
                        choice == HistoryChoice.manualHistory
                            ? 'Enter ONLY historical runtime not already measured by GameVault. Do not enter your full Steam lifetime total here.'
                            : 'Enter the portion of GameVault TOTAL runtime already counted by Steam.',
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (final field in [
                            (hours, 'Hours'),
                            (minutes, 'Minutes'),
                            (seconds, 'Seconds'),
                          ]) ...[
                            Expanded(
                              child: TextField(
                                controller: field.$1,
                                enabled: !blocked,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: field.$2,
                                ),
                                onChanged: (_) => reset(),
                              ),
                            ),
                            if (field.$2 != 'Seconds') const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ],
                    if (choice == HistoryChoice.zeroHistory)
                      const Text(
                        'Historical adjustment will be zero. Only measured GameVault active time contributes, even if Steam reports more runtime.',
                      ),
                    if (sourceStale &&
                        choice != HistoryChoice.manualHistory &&
                        choice != HistoryChoice.zeroHistory)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: staleAccepted,
                        title: const Text(
                          'I accept using stale Steam data for this baseline.',
                        ),
                        onChanged: blocked
                            ? null
                            : (v) => setState(() {
                                staleAccepted = v!;
                                preview = null;
                              }),
                      ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: acknowledged,
                      title: const Text(
                        'I understand this is an estimate and confirm the selected history / overlap assumption.',
                      ),
                      onChanged: blocked
                          ? null
                          : (v) => setState(() {
                              acknowledged = v!;
                              preview = null;
                            }),
                    ),
                    FilledButton.tonal(
                      onPressed: blocked || choice == null || !acknowledged
                          ? null
                          : () => run(() async {
                              final manual =
                                  choice == HistoryChoice.manualHistory ||
                                  choice == HistoryChoice.zeroHistory;
                              final value = switch (choice!) {
                                HistoryChoice.fullOverlap => c.tracker.total(
                                  widget.appId,
                                ),
                                HistoryChoice.noOverlap ||
                                HistoryChoice.zeroHistory => 0,
                                _ => enteredDuration(),
                              };
                              if (choice == HistoryChoice.partialOverlap &&
                                  (value <= 0 ||
                                      value >= c.tracker.total(widget.appId))) {
                                throw const FormatException(
                                  'Partial overlap must be greater than zero and less than GameVault total runtime. Use the full or zero overlap choices otherwise.',
                                );
                              }
                              preview = manual
                                  ? await p.reconciliation
                                        .proposeManualHistorical(
                                          widget.appId,
                                          c.tracker.sessions,
                                          historicalSeconds: value,
                                        )
                                  : await p.reconciliation.proposeSteam(
                                      widget.appId,
                                      c.tracker.sessions,
                                      overlapSeconds: value,
                                      evidence:
                                          SteamOverlapEvidence.userAssumed,
                                      allowStaleSnapshot: staleAccepted,
                                    );
                            }),
                      child: const Text('Preview calculation'),
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (preview case final proposal?) ...[
                    const Divider(),
                    Text(
                      'UNACCEPTED PREVIEW • revision ${proposal.draft.revision}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (proposal.draft.steamLifetimeAtBaselineSeconds
                        case final steam?)
                      Text('Steam lifetime: ${sessionDuration(steam)}'),
                    if (proposal.draft.overlapSeconds case final overlap?)
                      Text(
                        'Minus overlapping total runtime: ${sessionDuration(overlap)}',
                      ),
                    Text(
                      'Historical adjustment: ${sessionDuration(proposal.draft.historicalSeconds)}',
                    ),
                    Text(
                      'Plus GameVault active: ${sessionDuration(proposal.draft.tracked.active)}',
                    ),
                    Text(
                      'Estimated combined: ${sessionDuration(proposal.draft.historicalSeconds + proposal.draft.tracked.active)}',
                    ),
                    const Text(
                      'Nothing is saved until you accept. This revision preserves earlier baselines; future refreshes do not revise history.',
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: working ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: blocked || preview == null || !p.accountMatches
                  ? null
                  : () => run(() async {
                      await p.reconciliation.accept(
                        preview!,
                        c.tracker.sessions,
                      );
                      await c.refreshPlaytime();
                      if (context.mounted) Navigator.pop(context);
                    }),
              child: const Text('Accept baseline'),
            ),
          ],
        );
      },
    );
  }
}
