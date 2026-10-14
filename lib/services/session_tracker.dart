import '../models/play_session.dart';

class GameObservation {
  const GameObservation(this.id, this.title, this.processes, this.focused);
  final int id;
  final String title;
  final Set<String> processes;
  final bool focused;
}

/// Monotonic, observation-based accounting. Wall time is only used for labels.
/// No credit for time while GameVault is closed, suspended or unable to sample.
class SessionTracker {
  final List<PlaySession> sessions = [];
  final Map<int, GameObservation> _previous = {};
  final Map<int, int> _unfocusedSince = {};
  int? _lastTick;
  int _serial = 0;

  void load(List<dynamic> json) {
    sessions.clear();
    for (final item in json) {
      final session = PlaySession.fromJson(Map<String, dynamic>.from(item));
      if (session.open) {
        session.endedAt = session.lastObservedAt;
        session.reason = 'Recovered after interruption';
      }
      sessions.add(session);
    }
    _previous.clear();
    _unfocusedSince.clear();
    _lastTick = null;
  }

  List<Map<String, dynamic>> toJson() =>
      sessions.map((s) => s.toJson()).toList();
  PlaySession? current(int id) =>
      sessions.where((s) => s.gameId == id && s.open).firstOrNull;
  int total(int id, {bool active = false}) => sessions
      .where((s) => s.gameId == id)
      .fold(0, (sum, s) => sum + (active ? s.activeSeconds : s.seconds));
  DateTime? lastPlayed(int id) => sessions
      .where((s) => s.gameId == id)
      .map((s) => s.lastObservedAt)
      .fold<DateTime?>(
        null,
        (last, d) => last == null || d.isAfter(last) ? d : last,
      );

  void sample({
    required DateTime now,
    required int monotonicSeconds,
    required List<GameObservation> games,
    required int idleSeconds,
    int idleThreshold = 60,
    int focusGrace = 10,
  }) {
    final previousTick = _lastTick;
    if (previousTick != null && monotonicSeconds <= previousTick) return;
    final delta = previousTick == null ? 0 : monotonicSeconds - previousTick;
    _lastTick = monotonicSeconds;
    final live = {
      for (final g in games.where((g) => g.processes.isNotEmpty)) g.id: g,
    };
    for (final session in sessions.where((s) => s.open).toList()) {
      final g = live[session.gameId];
      final previous = _previous[session.gameId];
      final continuous =
          g != null &&
          previous != null &&
          g.processes.intersection(previous.processes).isNotEmpty;
      if (!continuous || delta > 10) {
        session.endedAt = session.lastObservedAt;
        session.reason = delta > 10
            ? 'Monitoring gap'
            : g == null
            ? 'Process ended'
            : 'Process restarted';
        _unfocusedSince.remove(session.gameId);
      }
    }
    for (final g in live.values) {
      var session = current(g.id);
      if (session == null) {
        session = PlaySession(
          id: '${now.toUtc().microsecondsSinceEpoch}-${g.id}-${_serial++}',
          gameId: g.id,
          title: g.title,
          startedAt: now.toUtc(),
          lastObservedAt: now.toUtc(),
        );
        sessions.add(session);
        if (!g.focused) _unfocusedSince[g.id] = monotonicSeconds;
        continue;
      }
      if (g.focused) {
        _unfocusedSince.remove(g.id);
      } else {
        _unfocusedSince.putIfAbsent(g.id, () => monotonicSeconds - delta);
      }
      final unfocused = _unfocusedSince[g.id];
      // Count only the part of this interval before each inactivity threshold.
      var active = delta;
      if (unfocused != null) {
        active = active.clamp(
          0,
          (focusGrace - (monotonicSeconds - delta - unfocused)).clamp(0, delta),
        );
      }
      active = active.clamp(
        0,
        (idleThreshold - (idleSeconds - delta)).clamp(0, delta),
      );
      session.seconds += delta;
      session.activeSeconds += active;
      // Allocate bounded observed intervals across local midnight, not all to start day.
      for (var i = 0; i < delta; i++) {
        final day = dateKey(now.subtract(Duration(seconds: delta - i)));
        session.daily[day] = (session.daily[day] ?? 0) + 1;
        if (i < active) {
          session.activeDaily[day] = (session.activeDaily[day] ?? 0) + 1;
        }
      }
      if (!now.isBefore(session.lastObservedAt)) {
        session.lastObservedAt = now.toUtc();
      }
    }
    _previous
      ..clear()
      ..addAll(live);
  }

  void closeAll(String reason) {
    for (final s in sessions.where((s) => s.open)) {
      s.endedAt = s.lastObservedAt;
      s.reason = reason;
    }
    _previous.clear();
    _unfocusedSince.clear();
    _lastTick = null;
  }
}
