import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/game.dart';
import '../models/play_session.dart';
import '../state/vault_controller.dart';
import 'components.dart';

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
    final values = [
      ('GAMEVAULT PLAYTIME', playtime(total), Icons.schedule),
      ('TODAY', playtime(todayTime), Icons.wb_twilight),
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
                    Text(
                      v.$2,
                      style: Theme.of(context).textTheme.headlineMedium,
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
              ? 'Activity-adjusted time • Measured by GameVault'
              : 'Full session time • Measured by GameVault',
        ),
        ActivitySummary(controller: c),
        const SizedBox(height: 28),
        SectionTitle(
          'Last seven days',
          action: Text(
            playtime(totals.fold(0, (a, b) => a + b)),
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
                height: 180,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(
                    7,
                    (i) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              playtime(totals[i]),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: math.max(3, 115 * totals[i] / peak),
                              width: 34,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary
                                    .withValues(
                                      alpha: totals[i] == 0 ? 0.15 : 0.85,
                                    ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (totals.every((n) => n == 0))
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('Your first tracked session will appear here.'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const SectionTitle('Most played'),
        if (ranked.isEmpty)
          const Text(
            'No recorded playtime yet. Keep GameVault open while playing.',
          ),
        ...ranked
            .take(5)
            .map(
              (g) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sports_esports_outlined),
                title: Text(
                  g.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(playtime(c.played(g.appId))),
                onTap: () => widget.onOpen(g),
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

class SessionRow extends StatelessWidget {
  const SessionRow({super.key, required this.session});
  final PlaySession session;
  @override
  Widget build(BuildContext context) {
    final s = session;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 12),
              Text(playtime(s.seconds)),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${s.startedAt.toLocal().toString().split('.').first}  →  ${s.open ? 'Running' : s.endedAt!.toLocal().toString().split('.').first}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Active ${playtime(s.activeSeconds)} • Inactive ${playtime(s.seconds - s.activeSeconds)}${s.reason == null ? '' : ' • ${s.reason}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
