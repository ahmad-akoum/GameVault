class PlaySession {
  PlaySession({
    required this.id,
    required this.gameId,
    required this.title,
    required this.startedAt,
    required this.lastObservedAt,
    this.endedAt,
    this.seconds = 0,
    this.activeSeconds = 0,
    this.reason,
    Map<String, int>? daily,
    Map<String, int>? activeDaily,
  }) : daily = daily ?? {},
       activeDaily = activeDaily ?? {};
  final String id, title;
  final int gameId;
  final DateTime startedAt;
  DateTime lastObservedAt;
  DateTime? endedAt;
  int seconds, activeSeconds;
  String? reason;
  final Map<String, int> daily, activeDaily;
  bool get open => endedAt == null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'gameId': gameId,
    'title': title,
    'startedAt': startedAt.toIso8601String(),
    'lastObservedAt': lastObservedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'seconds': seconds,
    'activeSeconds': activeSeconds,
    'reason': reason,
    'daily': daily,
    'activeDaily': activeDaily,
  };
  factory PlaySession.fromJson(Map<String, dynamic> j) {
    final seconds = j['seconds'] as int;
    final active = j['activeSeconds'] as int;
    if (seconds < 0 || active < 0 || active > seconds) {
      throw const FormatException('Invalid session duration');
    }
    final daily = Map<String, int>.from(j['daily'] ?? {});
    final activeDaily = Map<String, int>.from(j['activeDaily'] ?? {});
    if (daily.values.any((n) => n < 0) ||
        activeDaily.values.any((n) => n < 0) ||
        daily.values.fold<int>(0, (a, b) => a + b) != seconds ||
        activeDaily.values.fold<int>(0, (a, b) => a + b) != active ||
        activeDaily.entries.any((e) => e.value > (daily[e.key] ?? 0))) {
      throw const FormatException('Invalid session day totals');
    }
    return PlaySession(
      id: j['id'] as String,
      gameId: j['gameId'] as int,
      title: j['title'] as String,
      startedAt: DateTime.parse(j['startedAt']),
      lastObservedAt: DateTime.parse(j['lastObservedAt']),
      endedAt: j['endedAt'] == null ? null : DateTime.parse(j['endedAt']),
      seconds: seconds,
      activeSeconds: active,
      reason: j['reason'] as String?,
      daily: daily,
      activeDaily: activeDaily,
    );
  }
}

String playtime(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${seconds ~/ 60}m';
  return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
}

String dateKey(DateTime value) {
  final d = value.toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
