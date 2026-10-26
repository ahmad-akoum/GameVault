import '../models/game.dart';
import '../services/steam_updates.dart';

enum LibrarySort {
  recentlyAdded('Recently added'),
  title('Title A–Z'),
  mainStory('Main story length'),
  recentlyPlayed('Recently Played'),
  leastRecentlyPlayed('Least Recently Played');

  const LibrarySort(this.label);
  final String label;
}

int compareLastPlayed(
  VaultGame a,
  VaultGame b,
  DateTime? Function(int) lastPlayed, {
  bool oldestFirst = false,
}) {
  final x = lastPlayed(a.appId), y = lastPlayed(b.appId);
  if (x == null && y != null) return 1;
  if (y == null && x != null) return -1;
  final order = x == null || y == null
      ? 0
      : oldestFirst
      ? x.compareTo(y)
      : y.compareTo(x);
  return order != 0
      ? order
      : a.title.toLowerCase().compareTo(b.title.toLowerCase());
}

List<VaultGame> queryLibrary(
  List<VaultGame> games, {
  String search = '',
  GameStatus? status,
  bool needsUpdate = false,
  bool favorites = false,
  LibrarySort sort = LibrarySort.recentlyAdded,
  required DateTime? Function(int) lastPlayed,
  Map<int, SteamUpdateEvidence> updates = const {},
}) {
  final result = games
      .where(
        (g) =>
            g.title.toLowerCase().contains(search.toLowerCase()) &&
            (!favorites || g.favorite) &&
            (!needsUpdate || (g.isSteam && updates[g.appId]?.badge != null)) &&
            (status == null ||
                g.status == status ||
                (status == GameStatus.completed &&
                    g.status == GameStatus.completionist)),
      )
      .toList();
  result.sort(
    (a, b) => switch (sort) {
      LibrarySort.recentlyPlayed => compareLastPlayed(a, b, lastPlayed),
      LibrarySort.leastRecentlyPlayed => compareLastPlayed(
        a,
        b,
        lastPlayed,
        oldestFirst: true,
      ),
      LibrarySort.title => a.title.toLowerCase().compareTo(
        b.title.toLowerCase(),
      ),
      LibrarySort.mainStory => (a.hltb?.main ?? double.infinity).compareTo(
        b.hltb?.main ?? double.infinity,
      ),
      LibrarySort.recentlyAdded => b.addedAt.compareTo(a.addedAt),
    },
  );
  return result;
}
