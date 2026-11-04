enum SteamPlaytimeState { available, stale, unavailable }

enum SteamPlaytimeProblem {
  accountUnavailable,
  accountChanged,
  confirmationRequired,
  cacheMissing,
  cacheUnreadable,
  cacheMalformed,
  cacheChanging,
  staleCache,
  clockSkew,
  missingValue,
  invalidValue,
}

class SteamAccountConfirmationExpired implements Exception {
  const SteamAccountConfirmationExpired();
  @override
  String toString() => 'Steam account changed; request a new confirmation.';
}

/// Public individual Steam account identity, never a credential.
class SteamPlaytimeAccount {
  SteamPlaytimeAccount(this.steamId64) {
    final id = int.tryParse(steamId64);
    if (!RegExp(r'^\d{17}$').hasMatch(steamId64) ||
        id == null ||
        id <= individualBase ||
        id > individualBase + 0xffffffff) {
      throw const FormatException('Invalid Steam account identity');
    }
  }
  static const individualBase = 76561197960265728;
  final String steamId64;
  int get accountId => int.parse(steamId64) - individualBase;
}

/// Minute precision supplied by Steam's local cache, not measured active time.
class SteamPlaytimeSnapshot {
  SteamPlaytimeSnapshot({
    required this.account,
    required this.appId,
    required this.retrievedAt,
    required this.state,
    this.lifetimeMinutes,
    this.cacheModifiedAt,
    this.lastPlayedAt,
    this.problem,
  }) {
    if (appId <= 0 ||
        appId > 0xffffffff ||
        lifetimeMinutes != null &&
            (lifetimeMinutes! < 0 || lifetimeMinutes! > 0x7fffffff) ||
        (state == SteamPlaytimeState.unavailable) !=
            (lifetimeMinutes == null)) {
      throw const FormatException('Invalid Steam playtime snapshot');
    }
  }
  static const source = 'steamLocalCache';
  final SteamPlaytimeAccount account;
  final int appId;
  final int? lifetimeMinutes;
  final DateTime retrievedAt;
  final DateTime? cacheModifiedAt, lastPlayedAt;
  final SteamPlaytimeState state;
  final SteamPlaytimeProblem? problem;
  String get key => '${account.steamId64}:$appId';

  /// File age is only a stale-data warning, never proof of cloud freshness.
  bool staleAt(DateTime now, Duration maxAge) =>
      state != SteamPlaytimeState.available ||
      cacheModifiedAt == null ||
      now.isBefore(cacheModifiedAt!) ||
      now.difference(cacheModifiedAt!) > maxAge ||
      now.isBefore(retrievedAt) ||
      now.difference(retrievedAt) > maxAge;

  Map<String, dynamic> toJson() => {
    'steamId64': account.steamId64,
    'accountId': account.accountId,
    'appId': appId,
    'source': source,
    'lifetimeMinutes': lifetimeMinutes,
    'retrievedAt': retrievedAt.toUtc().toIso8601String(),
    'cacheModifiedAt': cacheModifiedAt?.toUtc().toIso8601String(),
    'lastPlayedAt': lastPlayedAt?.toUtc().toIso8601String(),
    'state': state.name,
    'problem': problem?.name,
  };

  factory SteamPlaytimeSnapshot.fromJson(Map<String, dynamic> j) {
    final account = SteamPlaytimeAccount(j['steamId64'] as String);
    if (j['source'] != source || j['accountId'] != account.accountId) {
      throw const FormatException('Snapshot source or identity mismatch');
    }
    return SteamPlaytimeSnapshot(
      account: account,
      appId: j['appId'] as int,
      retrievedAt: DateTime.parse(j['retrievedAt'] as String),
      state: SteamPlaytimeState.values.byName(j['state'] as String),
      lifetimeMinutes: j['lifetimeMinutes'] as int?,
      cacheModifiedAt: j['cacheModifiedAt'] == null
          ? null
          : DateTime.parse(j['cacheModifiedAt'] as String),
      lastPlayedAt: j['lastPlayedAt'] == null
          ? null
          : DateTime.parse(j['lastPlayedAt'] as String),
      problem: j['problem'] == null
          ? null
          : SteamPlaytimeProblem.values.byName(j['problem'] as String),
    );
  }
}
