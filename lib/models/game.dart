enum AppearanceMode { dark, light, system }

enum GameSource { steam, local, epic }

/// Launcher identity, independent from the local vault/session integer ID.
class EpicIdentity {
  const EpicIdentity(this.namespace, this.catalogId, this.appName);
  final String namespace, catalogId, appName;
  bool get valid => [
    namespace,
    catalogId,
    appName,
  ].every((s) => RegExp(r'^[A-Za-z0-9_-]{1,160}$').hasMatch(s));
  String get key => '$namespace:$catalogId:$appName';
  String get launchUri {
    if (!valid) throw const FormatException('Invalid Epic identity');
    return 'com.epicgames.launcher://apps/${Uri.encodeComponent(key)}?action=launch&silent=true';
  }

  Map<String, dynamic> toJson() => {
    'namespace': namespace,
    'catalogId': catalogId,
    'appName': appName,
  };
  factory EpicIdentity.fromJson(Map<String, dynamic> j) => EpicIdentity(
    j['namespace'] as String,
    j['catalogId'] as String,
    j['appName'] as String,
  );
}

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

/// Shared discovery record; the historical name is retained for compatibility.
class SteamGame {
  const SteamGame({
    required this.appId,
    required this.name,
    required this.installPath,
    required this.libraryPath,
    this.source = GameSource.steam,
    this.epic,
  });
  final GameSource source;
  final EpicIdentity? epic;
  String get sourceLabel =>
      source == GameSource.epic ? 'Epic Games (experimental)' : 'Steam $appId';
  final int appId;
  final String name, installPath, libraryPath;
  String? get coverUrl => source == GameSource.steam
      ? 'https://cdn.akamai.steamstatic.com/steam/apps/$appId/library_600x900.jpg'
      : null;
}

/// Additive artwork preferences. Null on legacy records until first management.
class ArtworkPreferences {
  const ArtworkPreferences({
    this.originalCover,
    this.originalHero,
    this.covers = const [],
    this.heroes = const [],
    this.coverChosen = false,
    this.heroChosen = false,
    this.coverContained = false,
    this.heroContained = false,
  });
  final String? originalCover, originalHero;
  final List<String> covers, heroes;
  final bool coverContained, heroContained, coverChosen, heroChosen;
  Map<String, dynamic> toJson() => {
    'originalCover': originalCover,
    'originalHero': originalHero,
    'covers': covers,
    'heroes': heroes,
    'coverChosen': coverChosen,
    'heroChosen': heroChosen,
    'coverContained': coverContained,
    'heroContained': heroContained,
  };
  factory ArtworkPreferences.fromJson(Map<String, dynamic> j) =>
      ArtworkPreferences(
        originalCover: j['originalCover'] as String?,
        originalHero: j['originalHero'] as String?,
        covers: List<String>.from(j['covers'] ?? []),
        heroes: List<String>.from(j['heroes'] ?? []),
        coverChosen: j['coverChosen'] == true,
        heroChosen: j['heroChosen'] == true,
        coverContained: j['coverContained'] == true,
        heroContained: j['heroContained'] == true,
      );
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
    this.artwork,
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
    GameSource? source,
    this.epic,
  }) : source = source ?? (appId < 0 ? GameSource.local : GameSource.steam),
       addedAt = addedAt ?? DateTime.now();
  final GameSource source;
  final EpicIdentity? epic;
  bool get isSteam => source == GameSource.steam;
  bool get isEpic => source == GameSource.epic;
  String get sourceLabel => switch (source) {
    GameSource.steam => 'Steam',
    GameSource.local => 'Local game',
    GameSource.epic => 'Epic Games (experimental)',
  };
  final ArtworkPreferences? artwork;
  // Freeze the legacy cover-as-banner fallback when managing artwork, so a
  // cover change cannot silently change a game that had no separate banner.
  String? get profileArtworkPath =>
      heroPath ?? (artwork == null ? coverPath : artwork!.originalHero);
  final String? executablePath;
  final List<String> collections;
  final int? progressPercent;
  bool get isManual => source == GameSource.local;
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
    source: g.source,
    epic: g.epic,
  );
  VaultGame copy({
    String? title,
    String? installPath,
    String? libraryPath,
    GameStatus? status,
    bool? favorite,
    String? coverPath,
    ArtworkPreferences? artwork,
    bool clearCover = false,
    bool clearHero = false,
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
    source: source,
    epic: epic,
    title: title ?? this.title,
    installPath: installPath ?? this.installPath,
    libraryPath: libraryPath ?? this.libraryPath,
    addedAt: addedAt,
    status: status ?? this.status,
    favorite: favorite ?? this.favorite,
    artwork: artwork ?? this.artwork,
    coverPath: clearCover ? null : coverPath ?? this.coverPath,
    heroPath: clearHero ? null : heroPath ?? this.heroPath,
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
    'source': source.name,
    if (epic != null) 'epic': epic!.toJson(),
    'title': title,
    'installPath': installPath,
    'libraryPath': libraryPath,
    'addedAt': addedAt.toIso8601String(),
    'status': status.name,
    'favorite': favorite,
    'artwork': artwork?.toJson(),
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
    source: j['source'] == null
        ? null
        : GameSource.values.byName(j['source'] as String),
    epic: j['epic'] is Map
        ? EpicIdentity.fromJson(Map<String, dynamic>.from(j['epic']))
        : null,
    title: j['title'] as String,
    installPath: j['installPath'] as String,
    libraryPath: j['libraryPath'] as String,
    addedAt: DateTime.parse(j['addedAt'] as String),
    status: GameStatus.values.byName(j['status'] as String),
    favorite: j['favorite'] == true,
    artwork: j['artwork'] is Map
        ? ArtworkPreferences.fromJson(Map<String, dynamic>.from(j['artwork']))
        : null,
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

enum ProfileSize { compact, comfortable, expanded }

int? _color(dynamic value) => value is int && value >= 0 && value <= 0xffffffff
    ? value | 0xff000000
    : null;

class VaultSettings {
  const VaultSettings({
    this.theme = AppearanceMode.dark,
    this.accent = 0xffb8d96e,
    this.background,
    this.surface,
    this.profileSize = ProfileSize.comfortable,
    this.paths = const [],
    this.collections = const [],
    this.idleThreshold = 60,
    this.focusGrace = 10,
    this.activityAdjusted = true,
    this.trackingEnabled = true,
    this.sidebarCollapsed = false,
    this.startupEnabled = false,
  });
  final AppearanceMode theme;
  final int accent;
  final int? background, surface;
  final ProfileSize profileSize;
  final List<String> paths, collections;
  final int idleThreshold, focusGrace;
  final bool activityAdjusted, trackingEnabled;
  final bool sidebarCollapsed, startupEnabled;
  VaultSettings copy({
    AppearanceMode? theme,
    int? accent,
    int? background,
    int? surface,
    bool resetColors = false,
    ProfileSize? profileSize,
    List<String>? paths,
    List<String>? collections,
    int? idleThreshold,
    int? focusGrace,
    bool? activityAdjusted,
    bool? trackingEnabled,
    bool? sidebarCollapsed,
    bool? startupEnabled,
  }) => VaultSettings(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    background: resetColors ? null : background ?? this.background,
    surface: resetColors ? null : surface ?? this.surface,
    profileSize: profileSize ?? this.profileSize,
    paths: paths ?? this.paths,
    collections: collections ?? this.collections,
    idleThreshold: idleThreshold ?? this.idleThreshold,
    focusGrace: focusGrace ?? this.focusGrace,
    activityAdjusted: activityAdjusted ?? this.activityAdjusted,
    trackingEnabled: trackingEnabled ?? this.trackingEnabled,
    sidebarCollapsed: sidebarCollapsed ?? this.sidebarCollapsed,
    startupEnabled: startupEnabled ?? this.startupEnabled,
  );
  Map<String, dynamic> toJson() => {
    'theme': theme.name,
    'accent': accent,
    if (background != null) 'background': background,
    if (surface != null) 'surface': surface,
    'profileSize': profileSize.name,
    'paths': paths,
    'collections': collections,
    'idleThreshold': idleThreshold,
    'focusGrace': focusGrace,
    'activityAdjusted': activityAdjusted,
    'trackingEnabled': trackingEnabled,
    'sidebarCollapsed': sidebarCollapsed,
    'startupEnabled': startupEnabled,
  };
  factory VaultSettings.fromJson(Map<String, dynamic> j) => VaultSettings(
    theme: AppearanceMode.values.byName(j['theme'] as String? ?? 'dark'),
    accent: j['accent'] as int? ?? 0xffb8d96e,
    background: _color(j['background']),
    surface: _color(j['surface']),
    profileSize:
        ProfileSize.values
            .where((v) => v.name == j['profileSize'])
            .firstOrNull ??
        ProfileSize.comfortable,
    paths: List<String>.from(j['paths'] ?? []),
    collections: List<String>.from(j['collections'] ?? []),
    idleThreshold: ((j['idleThreshold'] as int?) ?? 60).clamp(15, 3600),
    focusGrace: ((j['focusGrace'] as int?) ?? 10).clamp(0, 300),
    activityAdjusted: j['activityAdjusted'] != false,
    trackingEnabled: j['trackingEnabled'] != false,
    sidebarCollapsed: j['sidebarCollapsed'] == true,
    startupEnabled: j['startupEnabled'] == true,
  );
}
