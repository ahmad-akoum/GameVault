import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/game.dart';
import '../models/play_session.dart';
import '../state/vault_controller.dart';
import 'components.dart';
import 'session_presentation.dart';

class ActivitySummary extends StatelessWidget {
  const ActivitySummary({super.key, required this.controller});
  final VaultController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final sessions = c.tracker.sessions;
    final total = sessions.fold<int>(
      0,
      (sum, s) =>
          sum + (c.settings.activityAdjusted ? s.activeSeconds : s.seconds),
    );
    final today = dateKey(DateTime.now());
    final todayTime = sessions.fold<int>(
      0,
      (sum, s) =>
          sum +
          ((c.settings.activityAdjusted ? s.activeDaily : s.daily)[today] ?? 0),
    );
    final unavailable =
        c.settings.activityAdjusted && hasUnknownActivity(sessions);
    final values = [
      (
        c.settings.activityAdjusted ? 'ACTIVE PLAYTIME' : 'TOTAL SESSION TIME',
        unavailable ? 'Unknown' : sessionDuration(total),
        Icons.schedule,
      ),
      (
        c.settings.activityAdjusted ? 'ACTIVE TODAY' : 'TOTAL TODAY',
        unavailable ? 'Unknown' : sessionDuration(todayTime),
        Icons.wb_twilight,
      ),
      ('SESSIONS', '${sessions.length}', Icons.sports_esports_outlined),
      (
        'RUNNING',
        '${sessions.where((s) => s.open).length}',
        Icons.play_circle_outline,
      ),
    ];
    return LayoutBuilder(
      builder: (context, size) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: values
            .map(
              (v) => Container(
                width:
                    (size.maxWidth - (size.maxWidth > 700 ? 36 : 12)) /
                    (size.maxWidth > 700 ? 4 : 2),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: .6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          v.$3,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            v.$1,
                            style: const TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        v.$2,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final VaultController controller;
  final ValueChanged<VaultGame> onOpen;
  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  int limit = 40;
  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final active = c.settings.activityAdjusted;
    final unknown = active && hasUnknownActivity(c.tracker.sessions);
    final sessions = c.tracker.sessions.reversed.toList();
    final days = List.generate(7, (i) {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day - 6 + i);
    });
    final totals = days
        .map(
          (day) => sessions.fold<int>(
            0,
            (sum, s) =>
                sum + ((active ? s.activeDaily : s.daily)[dateKey(day)] ?? 0),
          ),
        )
        .toList();
    final peak = math.max(1, totals.reduce(math.max));
    final ranked = c.games.where((g) => c.played(g.appId) > 0).toList()
      ..sort((a, b) => c.played(b.appId).compareTo(c.played(a.appId)));
    return ListView(
      children: [
        PageHeading(
          'Your activity',
          active
              ? 'Showing active playtime • Uses your idle threshold and focus grace'
              : 'Showing total session time • Includes active and inactive periods',
        ),
        ActivitySummary(controller: c),
        if (hasUnknownActivity(c.tracker.sessions))
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Some historical activity is unknown. Unknown breakdowns are not estimated; active summaries may be unavailable.',
            ),
          ),
        const SizedBox(height: 28),
        SectionTitle(
          'Last seven days',
          action: Text(
            unknown
                ? 'Unknown'
                : sessionDuration(totals.fold(0, (a, b) => a + b)),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              SizedBox(
                height: 200,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(
                    7,
                    (i) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: MediaQuery.sizeOf(context).width < 700
                              ? 2
                              : 8,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Tooltip(
                                  message: unknown
                                      ? 'Activity unknown'
                                      : sessionDuration(totals[i]),
                                  child: Text(
                                    unknown ? '—' : sessionDuration(totals[i]),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: unknown
                                  ? 3
                                  : math.max(3, 115 * totals[i] / peak),
                              width: 34,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary
                                    .withValues(
                                      alpha: unknown || totals[i] == 0
                                          ? 0.15
                                          : 0.85,
                                    ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 10),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                [
                                  'Mon',
                                  'Tue',
                                  'Wed',
                                  'Thu',
                                  'Fri',
                                  'Sat',
                                  'Sun',
                                ][days[i].weekday - 1],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (unknown)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'Activity for this range cannot be confirmed from incomplete historical records.',
                  ),
                ),
              if (!unknown && totals.every((n) => n == 0))
                Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    sessions.isEmpty
                        ? 'Your first tracked session will appear here.'
                        : active
                        ? 'No active playtime recorded in the last seven days.'
                        : 'No session time recorded in the last seven days.',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        SectionTitle(
          active ? 'Most played · Active time' : 'Most played · Total time',
        ),
        if (ranked.isEmpty)
          Text(
            unknown
                ? 'Active ranking is unavailable for sessions with unknown activity.'
                : sessions.isEmpty
                ? 'No recorded playtime yet. Keep GameVault open while playing.'
                : active
                ? 'No active playtime recorded for your library.'
                : 'No recorded session time for your current library.',
          ),
        ...ranked
            .take(5)
            .map(
              (g) => LayoutBuilder(
                builder: (context, constraints) {
                  final duration = Text(
                    active &&
                            hasUnknownActivity(
                              sessions.where((s) => s.gameId == g.appId),
                            )
                        ? 'Unknown'
                        : sessionDuration(c.played(g.appId)),
                  );
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sports_esports_outlined),
                    title: Text(
                      g.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: constraints.maxWidth < 600 ? duration : null,
                    trailing: constraints.maxWidth >= 600 ? duration : null,
                    onTap: () => widget.onOpen(g),
                  );
                },
              ),
            ),
        const SizedBox(height: 28),
        const SectionTitle('Library at a glance'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: GameStatus.values
              .map(
                (s) => Chip(
                  label: Text(
                    '${s.label}  ${c.games.where((g) => g.status == s).length}',
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 28),
        const SectionTitle('Session history'),
        if (sessions.isEmpty)
          const Text(
            'Nothing recorded yet. Historical Steam hours are not imported or estimated.',
          ),
        ...sessions.take(limit).map((s) => SessionRow(session: s)),
        if (sessions.length > limit)
          TextButton(
            onPressed: () => setState(() => limit += 40),
            child: const Text('Show more sessions'),
          ),
      ],
    );
  }
}

/// Shared by game-profile recent sessions and Activity history.
class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.session, this.showTitle = true});
  final PlaySession session;
  final bool showTitle;
  @override
  Widget build(BuildContext context) {
    final s = session, breakdown = SessionBreakdown(session);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                s.open ? Icons.play_arrow : Icons.history,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  showTitle ? s.title : sessionRange(s),
                  style: showTitle
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (showTitle) ...[
            const SizedBox(height: 6),
            Text(sessionRange(s), style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                'Total ${sessionDuration(breakdown.total)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Active ${breakdown.active == null ? 'Unknown' : sessionDuration(breakdown.active!)}',
              ),
              Text(
                'Inactive ${breakdown.inactive == null ? 'Unknown' : sessionDuration(breakdown.inactive!)}',
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.open ? 'Running' : s.reason ?? 'Ended',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (!breakdown.known)
            Text(
              'Activity breakdown unavailable for this historical record.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
