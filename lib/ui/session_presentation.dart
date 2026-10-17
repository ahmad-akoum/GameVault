import '../models/play_session.dart';

/// Exact whole seconds already recorded, without rounding or wrapping at 24h.
String sessionDuration(int seconds) {
  if (seconds < 0) return 'Unknown';
  if (seconds == 0) return '0s';
  return [
    if (seconds >= 3600) '${seconds ~/ 3600}h',
    if ((seconds % 3600) ~/ 60 != 0) '${(seconds % 3600) ~/ 60}m',
    if (seconds % 60 != 0) '${seconds % 60}s',
  ].join(' ');
}

/// Presentation only. Never infer missing activity from dates or total time.
class SessionBreakdown {
  SessionBreakdown(PlaySession session)
    : total = session.seconds,
      active = _hasActivity(session) ? session.activeSeconds : null;
  final int total;
  final int? active;
  int? get inactive => active == null ? null : total - active!;
  bool get known => active != null;
  static bool _hasActivity(PlaySession s) {
    if (s.seconds < 0 || s.activeSeconds < 0 || s.activeSeconds > s.seconds) {
      return false;
    }
    // Current persisted sessions carry matching day allocations. Incomplete
    // legacy/in-memory records must not turn absent activity into "inactive".
    return s.daily.values.every((n) => n >= 0) &&
        s.activeDaily.values.every((n) => n >= 0) &&
        s.daily.values.fold<int>(0, (a, b) => a + b) == s.seconds &&
        s.activeDaily.values.fold<int>(0, (a, b) => a + b) == s.activeSeconds &&
        s.activeDaily.entries.every((e) => e.value <= (s.daily[e.key] ?? 0));
  }
}

bool hasUnknownActivity(Iterable<PlaySession> sessions) =>
    sessions.any((s) => !SessionBreakdown(s).known);

String sessionRange(PlaySession s) {
  String clock(DateTime date) => [
    date.hour,
    date.minute,
    date.second,
  ].map((n) => n.toString().padLeft(2, '0')).join(':');
  final start = s.startedAt.toLocal(), end = s.endedAt?.toLocal();
  final first = '${dateKey(start)} ${clock(start)}';
  if (end == null) return 'Started $first · Local time';
  return '$first → ${dateKey(start) == dateKey(end) ? clock(end) : '${dateKey(end)} ${clock(end)}'} · Local time';
}
