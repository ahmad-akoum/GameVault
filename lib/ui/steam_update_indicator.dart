import 'package:flutter/material.dart';
import '../services/steam_updates.dart';

/// Pending updates navigate to Steam; they never launch or manage downloads.
class SteamUpdateAction extends StatelessWidget {
  const SteamUpdateAction({
    super.key,
    required this.evidence,
    required this.onOpen,
  });
  final SteamUpdateEvidence evidence;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    final amber = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xffffb74d)
        : const Color(0xff8a4700);
    return Tooltip(
      message:
          '${evidence.source}\n${evidence.message}\n'
          'Open this game in Steam. Manage updates there manually.',
      child: OutlinedButton.icon(
        onPressed: onOpen,
        icon: const Icon(Icons.system_update_alt, size: 18),
        label: Text(evidence.state.label),
        style: OutlinedButton.styleFrom(
          foregroundColor: amber,
          backgroundColor: amber.withValues(alpha: .10),
          side: BorderSide(color: amber),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class SteamUpdateBadge extends StatelessWidget {
  const SteamUpdateBadge({super.key, required this.evidence});
  final SteamUpdateEvidence evidence;
  @override
  Widget build(BuildContext context) {
    if (evidence.badge == null) return const SizedBox.shrink();
    return Tooltip(
      message:
          '${evidence.source}\n${evidence.message}${evidence.recordedAt == null ? '' : '\nRecorded ${evidence.recordedAt!.toLocal()}'}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xff8a4700),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Text(
            evidence.badge!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class SteamUpdatePanel extends StatelessWidget {
  const SteamUpdatePanel({
    super.key,
    required this.evidence,
    required this.onOpen,
    this.onRefresh,
    this.showOpen = true,
  });
  final SteamUpdateEvidence evidence;
  final VoidCallback onOpen;
  final VoidCallback? onRefresh;
  final bool showOpen;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        evidence.summary,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: evidence.pending && !evidence.lastKnown
              ? (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xffffb74d)
                    : const Color(0xff8a4700))
              : null,
        ),
      ),
      const SizedBox(height: 6),
      Text(evidence.message),
      if (evidence.recordedAt != null)
        Text(
          '${evidence.source} • ${evidence.recordedAt!.toLocal()}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      if (evidence.lastKnown)
        const Text(
          'Steam is closed or its current session could not be verified. No live update badge is shown.',
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (showOpen)
            OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open in Steam'),
            ),
          TextButton(
            onPressed: onRefresh,
            child: const Text('Refresh update status'),
          ),
        ],
      ),
    ],
  );
}
