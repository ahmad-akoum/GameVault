enum AppearanceMode { dark, light, system }

enum GameStatus {
  playing('Playing'),
  backlog('Play Later'),
  onHold('On Hold'),
  completed('Completed'),
  completionist('100% Complete'),
  dropped('Dropped');

  const GameStatus(this.label);
  final String label;
}

enum HltbState {
  pending,
  loading,
  matched,
  noMatch,
  ambiguous,
  networkError,
  unavailable,
}

class HltbEntry {
  const HltbEntry({
    required this.id,
    required this.title,
    this.main = 0,
    this.extras = 0,
    this.complete = 0,
    this.year,
    this.steamId,
  });
  final int id;
  final String title;
  final double main, extras, complete;
  final int? year, steamId;
  String get url => 'https://howlongtobeat.com/game/$id';
  factory HltbEntry.fromJson(Map<String, dynamic> j) => HltbEntry(
    id: j['id'] as int,
    title: j['title'] as String,
    main: (j['main'] as num? ?? 0).toDouble(),
    extras: (j['extras'] as num? ?? 0).toDouble(),
    complete: (j['complete'] as num? ?? 0).toDouble(),
    year: j['year'] as int?,
    steamId: j['steamId'] as int?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'main': main,
    'extras': extras,
    'complete': complete,
    'year': year,
    'steamId': steamId,
  };
}

class SteamGame {
  const SteamGame({
    required this.appId,
    required this.name,
    required this.installPath,
    required this.libraryPath,
  });
  final int appId;
  final String name, installPath, libraryPath;
  String get coverUrl =>
      'https://cdn.akamai.steamstatic.com/steam/apps/$appId/library_600x900.jpg';
}

class VaultGame {
  VaultGame({
    required this.appId,
    required this.title,
    required this.installPath,
    required this.libraryPath,
    DateTime? addedAt,
    this.status = GameStatus.backlog,
    this.favorite = false,
    this.coverPath,
    this.heroPath,
    this.release,
    this.developer,
    this.publisher,
    this.genres = const [],
    this.hltbState = HltbState.pending,
    this.hltb,
    this.candidates = const [],
    this.hltbUpdated,
    this.hltbMessage,
    this.metadataMessage,
    this.executablePath,
    this.collections = const [],
    this.progressPercent,
  }) : addedAt = addedAt ?? DateTime.now();
  final String? executablePath;
  final List<String> collections;
  final int? progressPercent;
  bool get isManual => appId < 0;
  final int appId;
  final String title, installPath, libraryPath;
  final DateTime addedAt;
  final GameStatus status;
  final bool favorite;
  final String? coverPath, heroPath, release, developer, publisher;
  final List<String> genres;
  final HltbState hltbState;
  final HltbEntry? hltb;
  final List<HltbEntry> candidates;
  final DateTime? hltbUpdated;
  final String? hltbMessage, metadataMessage;
  factory VaultGame.fromSteam(SteamGame g) => VaultGame(
    appId: g.appId,
    title: g.name,
    installPath: g.installPath,
    libraryPath: g.libraryPath,
  );
  VaultGame copy({
    String? title,
    GameStatus? status,
    bool? favorite,
    String? coverPath,
    String? heroPath,
    String? release,
    String? developer,
    String? publisher,
    List<String>? genres,
    HltbState? hltbState,
    HltbEntry? hltb,
    List<HltbEntry>? candidates,
    DateTime? hltbUpdated,
    String? hltbMessage,
    String? metadataMessage,
    String? executablePath,
    List<String>? collections,
    int? progressPercent,
    bool clearProgress = false,
    bool clearExecutable = false,
    bool clearMatch = false,
  }) => VaultGame(
    appId: appId,
    title: title ?? this.title,
    installPath: installPath,
    libraryPath: libraryPath,
    addedAt: addedAt,
    status: status ?? this.status,
    favorite: favorite ?? this.favorite,
    coverPath: coverPath ?? this.coverPath,
    heroPath: heroPath ?? this.heroPath,
    release: release ?? this.release,
    developer: developer ?? this.developer,
    publisher: publisher ?? this.publisher,
    genres: genres ?? this.genres,
    hltbState: hltbState ?? this.hltbState,
    hltb: clearMatch ? null : hltb ?? this.hltb,
    candidates: candidates ?? this.candidates,
    hltbUpdated: hltbUpdated ?? this.hltbUpdated,
    hltbMessage: hltbMessage ?? this.hltbMessage,
    metadataMessage: metadataMessage ?? this.metadataMessage,
    executablePath: clearExecutable
        ? null
        : executablePath ?? this.executablePath,
    collections: collections ?? this.collections,
    progressPercent: clearProgress
        ? null
        : progressPercent ?? this.progressPercent,
  );
  Map<String, dynamic> toJson() => {
    'appId': appId,
    'title': title,
    'installPath': installPath,
    'libraryPath': libraryPath,
    'addedAt': addedAt.toIso8601String(),
    'status': status.name,
    'favorite': favorite,
    'coverPath': coverPath,
    'heroPath': heroPath,
    'release': release,
    'developer': developer,
    'publisher': publisher,
    'genres': genres,
    'hltbState': hltbState == HltbState.loading
        ? HltbState.pending.name
        : hltbState.name,
    'hltb': hltb?.toJson(),
    'candidates': candidates.map((e) => e.toJson()).toList(),
    'hltbUpdated': hltbUpdated?.toIso8601String(),
    'hltbMessage': hltbMessage,
    'metadataMessage': metadataMessage,
    'executablePath': executablePath,
    'collections': collections,
    'progressPercent': progressPercent,
  };
  factory VaultGame.fromJson(Map<String, dynamic> j) => VaultGame(
    appId: j['appId'] as int,
    title: j['title'] as String,
    installPath: j['installPath'] as String,
    libraryPath: j['libraryPath'] as String,
    addedAt: DateTime.parse(j['addedAt'] as String),
    status: GameStatus.values.byName(j['status'] as String),
    favorite: j['favorite'] == true,
    coverPath: j['coverPath'] as String?,
    heroPath: j['heroPath'] as String?,
    release: j['release'] as String?,
    developer: j['developer'] as String?,
    publisher: j['publisher'] as String?,
    genres: List<String>.from(j['genres'] ?? []),
    hltbState: HltbState.values.byName(j['hltbState'] as String? ?? 'pending'),
    hltb: j['hltb'] == null
        ? null
        : HltbEntry.fromJson(Map<String, dynamic>.from(j['hltb'])),
    candidates: (j['candidates'] as List? ?? [])
        .map((e) => HltbEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    hltbUpdated: DateTime.tryParse(j['hltbUpdated'] as String? ?? ''),
    hltbMessage: j['hltbMessage'] as String?,
    metadataMessage: j['metadataMessage'] as String?,
    executablePath: j['executablePath'] as String?,
    collections: List<String>.from(j['collections'] ?? []),
    progressPercent: (j['progressPercent'] as int?)?.clamp(0, 100),
  );
}

class VaultSettings {
  const VaultSettings({
    this.theme = AppearanceMode.dark,
    this.accent = 0xffb8d96e,
    this.paths = const [],
    this.collections = const [],
    this.idleThreshold = 60,
    this.focusGrace = 10,
    this.activityAdjusted = true,
    this.trackingEnabled = true,
  });
  final AppearanceMode theme;
  final int accent;
  final List<String> paths, collections;
  final int idleThreshold, focusGrace;
  final bool activityAdjusted, trackingEnabled;
  VaultSettings copy({
    AppearanceMode? theme,
    int? accent,
    List<String>? paths,
    List<String>? collections,
    int? idleThreshold,
    int? focusGrace,
    bool? activityAdjusted,
    bool? trackingEnabled,
  }) => VaultSettings(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    paths: paths ?? this.paths,
    collections: collections ?? this.collections,
    idleThreshold: idleThreshold ?? this.idleThreshold,
    focusGrace: focusGrace ?? this.focusGrace,
    activityAdjusted: activityAdjusted ?? this.activityAdjusted,
    trackingEnabled: trackingEnabled ?? this.trackingEnabled,
  );
  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'accent': accent,
    'paths': paths,
    'collections': collections,
    'idleThreshold': idleThreshold,
    'focusGrace': focusGrace,
    'activityAdjusted': activityAdjusted,
    'trackingEnabled': trackingEnabled,
  };
  factory VaultSettings.fromJson(Map<String, dynamic> j) => VaultSettings(
    theme: AppearanceMode.values.byName(j['theme'] as String? ?? 'dark'),
    accent: j['accent'] as int? ?? 0xffb8d96e,
    paths: List<String>.from(j['paths'] ?? []),
    collections: List<String>.from(j['collections'] ?? []),
    idleThreshold: ((j['idleThreshold'] as int?) ?? 60).clamp(15, 3600),
    focusGrace: ((j['focusGrace'] as int?) ?? 10).clamp(0, 300),
    activityAdjusted: j['activityAdjusted'] != false,
    trackingEnabled: j['trackingEnabled'] != false,
  );
}
