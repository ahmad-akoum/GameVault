import '../models/game.dart';

/// Provider boundary for previously saved HowLongToBeat matching workflows.
///
/// The public release intentionally has no live website adapter while an
/// authorized integration is unavailable. Existing entries remain in the
/// vault and continue to be displayed locally.
abstract class HltbProvider {
  Future<List<HltbEntry>> search(String title);
}

class HltbFailure implements Exception {
  const HltbFailure(this.message, this.state);
  final String message;
  final HltbState state;
}

/// Fails closed without making a network request or inspecting website code.
class DisabledHltbProvider implements HltbProvider {
  const DisabledHltbProvider();

  static const message =
      'Live HowLongToBeat lookup is temporarily unavailable pending an authorized integration. Saved estimates remain available.';

  @override
  Future<List<HltbEntry>> search(String title) async {
    throw const HltbFailure(message, HltbState.unavailable);
  }
}

class HltbMatcher {
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp('[™®©]'), '')
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  static HltbEntry? confidentMatch(
    String title,
    int appId,
    List<HltbEntry> entries,
  ) {
    final byId = entries.where((e) => e.steamId == appId).toList();
    if (byId.length == 1) {
      return byId.single;
    }
    final exact = entries
        .where((e) => normalize(e.title) == normalize(title))
        .toList();
    return exact.length == 1 ? exact.single : null;
  }

  static List<HltbEntry> rank(String title, List<HltbEntry> entries) {
    final result = [...entries];
    final normalized = normalize(title);
    result.sort((a, b) {
      int score(HltbEntry entry) => normalize(entry.title) == normalized
          ? 2
          : normalize(entry.title).contains(normalized)
          ? 1
          : 0;
      return score(b).compareTo(score(a));
    });
    return result;
  }
}
