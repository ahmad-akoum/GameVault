import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/models/game.dart';
import 'package:gamevault/models/play_session.dart';
import 'package:gamevault/models/steam_playtime.dart';
import 'package:gamevault/services/local_store.dart';
import 'package:gamevault/services/steam_local_playtime.dart';
import 'package:gamevault/services/steam_playtime_service.dart';
import 'package:gamevault/services/steam_playtime_store.dart';

class Fixture {
  Fixture(this.dir);
  final Directory dir;
  late final root = Directory(p.join(dir.path, 'steam'));
  late final profile = Directory(p.join(dir.path, 'profile'));
  late final exe = File(p.join(root.path, 'steam.exe'));
  final first = SteamPlaytimeAccount(
    '${SteamPlaytimeAccount.individualBase + 101}',
  );
  final second = SteamPlaytimeAccount(
    '${SteamPlaytimeAccount.individualBase + 202}',
  );
  DateTime clock = DateTime.utc(2026, 11, 4, 12);
  SteamActiveProcess? active;
  bool failRead = false;
  Future<SteamCacheDocument> Function(String)? overrideRead;
  late final provider = SteamLocalPlaytimeProvider(
    installationRoots: () async => [root.path, root.path],
    activeProcess: () async => active,
    readDocument: (path) async {
      if (path.endsWith('localconfig.vdf') && failRead) {
        throw const SteamCacheFailure(SteamPlaytimeProblem.cacheUnreadable);
      }
      return overrideRead != null
          ? overrideRead!(path)
          : readSteamDocument(path);
    },
    now: () => clock,
  );
  late final store = SteamPlaytimeStore(profile);
  late final service = SteamPlaytimeService(provider, store);
  File cache(SteamPlaytimeAccount account) => File(
    p.join(
      root.path,
      'userdata',
      '${account.accountId}',
      'config',
      'localconfig.vdf',
    ),
  );
  Future<void> writeCache(
    String entries, {
    SteamPlaytimeAccount? account,
    DateTime? modified,
  }) async {
    final file = cache(account ?? first);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '"UserLocalConfigStore" { "Software" { "Valve" { "Steam" { "apps" { $entries } } } } }',
    );
    await file.setLastModified(
      modified ?? clock.subtract(const Duration(minutes: 2)),
    );
  }

  Future<void> initialize() async {
    await exe.parent.create(recursive: true);
    await exe.writeAsBytes([1]);
    final login = File(p.join(root.path, 'config', 'loginusers.vdf'));
    await login.parent.create(recursive: true);
    await login.writeAsString(
      '"users" { "${first.steamId64}" { "PersonaName" "Fixture A" "MostRecent" "0" } "${second.steamId64}" { "PersonaName" "Fixture B" "MostRecent" "1" } }',
    );
    active = SteamActiveProcess(101, 123, exe.path);
    await writeCache(
      '"11" { "Playtime" "123" "Playtime2wks" "15" "LastPlayed" "86400" }',
    );
    await writeCache('"11" { "Playtime" "9999" }', account: second);
  }

  Future<SteamAccountProposal> proposal() async =>
      (await service.proposeAccount()).proposal!;
  Future<void> confirm() async => service.confirmAccount(await proposal());
}

void main() {
  late Fixture f;
  setUp(() async {
    f = Fixture(
      await Directory.systemTemp.createTemp('gamevault_playtime_test_'),
    );
    await f.initialize();
  });
  tearDown(() async {
    // Only remove this test's freshly created temporary fixture.
    expect(p.isWithin(Directory.systemTemp.path, f.dir.path), true);
    await f.dir.delete(recursive: true);
  });

  test(
    'running account wins over MostRecent, largest cache and discovery order',
    () async {
      final proposal = await f.proposal();
      expect(proposal.account.steamId64, f.first.steamId64);
      expect(proposal.displayName, 'Fixture A');
      expect(await f.store.file.exists(), false);
      await f.confirm();
      final read = await f.service.refresh([11]);
      expect(read.snapshots.single.lifetimeMinutes, 123);
      expect(read.snapshots.single.account.steamId64, f.first.steamId64);
    },
  );

  test(
    'refresh before confirmation creates no association or snapshot file',
    () async {
      await f.service.proposeAccount();
      final read = await f.service.refresh([11]);
      expect(read.problem, SteamPlaytimeProblem.confirmationRequired);
      expect(read.snapshots, isEmpty);
      expect(await f.profile.exists(), false);
    },
  );

  test(
    'no active process never substitutes another locally cached account',
    () async {
      f.active = null;
      expect((await f.service.proposeAccount()).proposal, isNull);
      expect(
        (await f.service.proposeAccount()).problem,
        SteamPlaytimeProblem.accountUnavailable,
      );
    },
  );

  test(
    'unrecognized process path, account and missing login record are rejected',
    () async {
      final otherExe = await File(
        p.join(f.dir.path, 'other.exe'),
      ).writeAsBytes([1]);
      f.active = SteamActiveProcess(101, 123, otherExe.path);
      expect((await f.service.proposeAccount()).proposal, isNull);
      f.active = SteamActiveProcess(303, 123, f.exe.path);
      expect((await f.service.proposeAccount()).proposal, isNull);
      f.active = SteamActiveProcess(0, 123, f.exe.path);
      expect((await f.service.proposeAccount()).proposal, isNull);
    },
  );

  test(
    'expired confirmation preserves the previous association and snapshots',
    () async {
      await f.confirm();
      await f.service.refresh([11]);
      final before = await f.store.file.readAsBytes();
      final proposed = await f.proposal();
      f.active = SteamActiveProcess(202, 124, f.exe.path);
      await expectLater(
        f.service.confirmAccount(proposed),
        throwsA(isA<SteamAccountConfirmationExpired>()),
      );
      expect(await f.store.file.readAsBytes(), before);
      expect(
        (await f.service.refresh([11])).problem,
        SteamPlaytimeProblem.accountChanged,
      );
      expect(await f.store.file.readAsBytes(), before);
    },
  );

  test(
    'explicit account switching keeps snapshots in separate namespaces',
    () async {
      await f.confirm();
      await f.service.refresh([11]);
      f.active = SteamActiveProcess(202, 124, f.exe.path);
      final proposed = await f.proposal();
      await f.service.confirmAccount(proposed);
      await f.service.refresh([11]);
      final data = await SteamPlaytimeStore(f.profile).load();
      expect(data.confirmedAccount!.steamId64, f.second.steamId64);
      expect(data.latest['${f.first.steamId64}:11']!.lifetimeMinutes, 123);
      expect(data.latest['${f.second.steamId64}:11']!.lifetimeMinutes, 9999);
    },
  );

  test(
    'strict AppID matching, case-insensitive VDF, zero distinct from missing',
    () async {
      await f.writeCache('''// synthetic fixture
      "11" { "PLAYTIME" "0" "Playtime2wks" "900" }
      "12" { "LastPlayed" "1234567890" }
      "13" { "Playtime" "-1" }
      "14" { "Playtime" "1.5" }
      "15" { "Playtime" "9999999999999999999999" }
      "111" { "Playtime" "555" }
    ''');
      await f.confirm();
      final read = await f.service.refresh([11, 12, 13, 14, 15, 16, 11]);
      expect(read.snapshots.length, 6);
      expect(read.snapshots.first.lifetimeMinutes, 0);
      expect(read.snapshots.first.state, SteamPlaytimeState.available);
      expect(read.snapshots[1].problem, SteamPlaytimeProblem.missingValue);
      for (final snapshot in read.snapshots.skip(1)) {
        expect(snapshot.state, SteamPlaytimeState.unavailable);
        expect(snapshot.lifetimeMinutes, isNull);
      }
      expect(read.snapshots[2].problem, SteamPlaytimeProblem.invalidValue);
    },
  );

  test(
    'snapshots retain source, account, timestamps and minute precision on restart',
    () async {
      await f.confirm();
      await f.service.refresh([11]);
      final data = await SteamPlaytimeStore(f.profile).load();
      final s = data.latest.values.single;
      expect(s.account.accountId, 101);
      expect(s.toJson()['source'], 'steamLocalCache');
      expect(s.retrievedAt, f.clock);
      expect(s.cacheModifiedAt, f.clock.subtract(const Duration(minutes: 2)));
      expect(
        s.lastPlayedAt,
        isNull,
      ); // Sentinel is not a real last-played date.
      expect(s.lifetimeMinutes, 123);
    },
  );

  test(
    'stale cache retains a labeled value; old LastPlayed alone is not staleness',
    () async {
      await f.confirm();
      await f.writeCache(
        '"11" { "Playtime" "123" }',
        modified: f.clock.subtract(const Duration(days: 2)),
      );
      final s = (await f.service.refresh([11])).snapshots.single;
      expect(s.state, SteamPlaytimeState.stale);
      expect(s.problem, SteamPlaytimeProblem.staleCache);
      expect(s.lifetimeMinutes, 123);
      expect(s.staleAt(f.clock, const Duration(hours: 24)), true);
      await f.writeCache('"11" { "Playtime" "123" "LastPlayed" "1000000000" }');
      final fresh = (await f.service.refresh([11])).snapshots.single;
      expect(fresh.state, SteamPlaytimeState.available);
      expect(
        fresh.staleAt(
          f.clock.add(const Duration(days: 2)),
          const Duration(hours: 24),
        ),
        true,
      );
    },
  );

  test('future cache timestamp is stale, not proof of freshness', () async {
    await f.confirm();
    await f.writeCache(
      '"11" { "Playtime" "123" }',
      modified: f.clock.add(const Duration(days: 1)),
    );
    final s = (await f.service.refresh([11])).snapshots.single;
    expect(s.state, SteamPlaytimeState.stale);
    expect(s.problem, SteamPlaytimeProblem.clockSkew);
  });

  test(
    'missing cache returns Unavailable and retains separate last-known snapshot',
    () async {
      await f.confirm();
      await f.service.refresh([11]);
      await f.cache(f.first).delete();
      f.clock = f.clock.add(const Duration(minutes: 1));
      final s = (await f.service.refresh([11])).snapshots.single;
      expect(s.state, SteamPlaytimeState.unavailable);
      expect(s.problem, SteamPlaytimeProblem.cacheMissing);
      final data = await f.store.load();
      expect(data.latest[s.key]!.lifetimeMinutes, isNull);
      expect(data.lastKnown[s.key]!.lifetimeMinutes, 123);
      expect(
        data.lastKnown[s.key]!.retrievedAt,
        f.clock.subtract(const Duration(minutes: 1)),
      );
    },
  );

  test(
    'malformed and unreadable caches do not turn errors into zero',
    () async {
      await f.confirm();
      await f.cache(f.first).writeAsString('"UserLocalConfigStore" {');
      expect(
        (await f.service.refresh([11])).snapshots.single.problem,
        SteamPlaytimeProblem.cacheMalformed,
      );
      await f
          .cache(f.first)
          .writeAsString('"UserLocalConfigStore" { "Other" {} }');
      expect(
        (await f.service.refresh([11])).snapshots.single.problem,
        SteamPlaytimeProblem.cacheMalformed,
      );
      f.failRead = true;
      final s = (await f.service.refresh([11])).snapshots.single;
      expect(s.problem, SteamPlaytimeProblem.cacheUnreadable);
      expect(s.lifetimeMinutes, isNull);
    },
  );

  test(
    'account switch during a read discards the entire request without saving',
    () async {
      await f.confirm();
      final before = await f.store.file.readAsBytes();
      f.overrideRead = (path) async {
        final doc = await readSteamDocument(path);
        if (path.endsWith('localconfig.vdf')) {
          f.active = SteamActiveProcess(202, 124, f.exe.path);
        }
        return doc;
      };
      expect(
        (await f.service.refresh([11])).problem,
        SteamPlaytimeProblem.accountChanged,
      );
      expect(await f.store.file.readAsBytes(), before);
    },
  );

  test(
    'changing cache reports retryable unavailability and preserves last known',
    () async {
      await f.confirm();
      await f.service.refresh([11]);
      f.overrideRead = (path) async {
        if (path.endsWith('localconfig.vdf')) {
          throw const SteamCacheFailure(SteamPlaytimeProblem.cacheChanging);
        }
        return readSteamDocument(path);
      };
      final s = (await f.service.refresh([11])).snapshots.single;
      expect(s.problem, SteamPlaytimeProblem.cacheChanging);
      expect((await f.store.load()).lastKnown[s.key]!.lifetimeMinutes, 123);
    },
  );

  test(
    'repeated refresh upserts snapshots without accumulating minutes',
    () async {
      await f.confirm();
      await Future.wait([
        f.service.refresh([11]),
        f.service.refresh([11]),
      ]);
      final data = await f.store.load();
      expect(data.latest.length, 1);
      expect(data.lastKnown.length, 1);
      expect(data.latest.values.single.lifetimeMinutes, 123);
    },
  );

  test('older observations cannot replace newer persisted values', () async {
    await f.confirm();
    f.clock = f.clock.add(const Duration(minutes: 5));
    await f.service.refresh([11]);
    final laterTime = f.clock;
    f.clock = f.clock.subtract(const Duration(minutes: 1));
    await f.writeCache('"11" { "Playtime" "100" }');
    await f.service.refresh([11]);
    final latest = (await f.store.load()).latest.values.single;
    expect(latest.lifetimeMinutes, 123);
    expect(latest.retrievedAt, laterTime);
  });

  test(
    'cache reader rejects excessive size, invalid UTF8 and unclosed VDF',
    () async {
      final file = f.cache(f.first);
      await file.writeAsBytes([0xff]);
      await expectLater(
        readSteamDocument(file.path),
        throwsA(isA<SteamCacheFailure>()),
      );
      final handle = await file.open(mode: FileMode.write);
      await handle.truncate(16 * 1024 * 1024 + 1);
      await handle.close();
      await expectLater(
        readSteamDocument(file.path),
        throwsA(isA<SteamCacheFailure>()),
      );
      await file.writeAsString('"apps" { "11" "unterminated');
      await expectLater(
        readSteamDocument(file.path),
        throwsA(isA<SteamCacheFailure>()),
      );
    },
  );

  test(
    'two corrupt sidecar documents are preserved instead of reset',
    () async {
      await f.profile.create();
      await f.store.file.writeAsString('{');
      final backup = File('${f.store.file.path}.bak');
      await backup.writeAsString('{');
      await expectLater(
        f.confirm(),
        throwsA(isA<SteamPlaytimeStorageFailure>()),
      );
      expect(await f.store.file.readAsString(), '{');
      expect(await backup.readAsString(), '{');
    },
  );

  test('invalid AppIDs and forged identities are rejected', () async {
    await expectLater(f.service.refresh([-1]), throwsArgumentError);
    await expectLater(f.service.refresh([0]), throwsArgumentError);
    expect(() => SteamPlaytimeAccount('../other'), throwsFormatException);
    expect(
      () => SteamPlaytimeAccount('${SteamPlaytimeAccount.individualBase}'),
      throwsFormatException,
    );
    await f.confirm();
    await f.service.refresh([11]);
    final s = (await f.store.load()).latest.values.single.toJson();
    s['accountId'] = 202;
    expect(() => SteamPlaytimeSnapshot.fromJson(s), throwsFormatException);
  });

  test(
    'corrupt primary exposes read-only backup; unknown future schema is never downgraded',
    () async {
      await f.confirm();
      await f.service.refresh([11]);
      await f.service.refresh([
        11,
      ]); // Previous-good backup now includes the sample.
      await f.store.file.writeAsString('{');
      expect((await f.store.load()).latest.values.single.lifetimeMinutes, 123);
      expect((await f.store.load()).recoveredFromBackup, true);
      await expectLater(
        f.service.refresh([11]),
        throwsA(isA<SteamPlaytimeStorageFailure>()),
      );
      expect(await f.store.file.readAsString(), '{');
      expect((await f.store.load()).latest.values.single.lifetimeMinutes, 123);
      await f.store.file.writeAsString('{"version":999}');
      await expectLater(
        f.service.refresh([11]),
        throwsA(isA<SteamPlaytimeStorageFailure>()),
      );
      expect(await f.store.file.readAsString(), '{"version":999}');
    },
  );

  test(
    'failed persistence retains the previous sidecar and reports failure',
    () async {
      await f.confirm();
      final before = await f.store.file.readAsBytes();
      // A directory at the backup target is a deterministic synthetic write failure.
      await Directory('${f.store.file.path}.bak').create();
      await expectLater(
        f.service.refresh([11]),
        throwsA(isA<SteamPlaytimeStorageFailure>()),
      );
      expect(await f.store.file.readAsBytes(), before);
    },
  );

  test(
    'existing vault, sessions, settings and Steam files remain byte-identical',
    () async {
      final local = LocalStore(f.profile);
      final session = PlaySession(
        id: 'synthetic-session',
        gameId: 11,
        title: 'Fixture',
        startedAt: f.clock,
        lastObservedAt: f.clock.add(const Duration(seconds: 120)),
        endedAt: f.clock.add(const Duration(seconds: 120)),
        seconds: 120,
        activeSeconds: 80,
        daily: {'2026-11-04': 120},
        activeDaily: {'2026-11-04': 80},
      );
      await local.save(
        [
          VaultGame(
            appId: 11,
            title: 'Fixture',
            installPath: 'fixture',
            libraryPath: 'fixture',
          ),
        ],
        const VaultSettings(),
        sessions: [session.toJson()],
      );
      final original = await local.file.readAsBytes();
      final steamBefore = await f.cache(f.first).readAsBytes();
      await f.confirm();
      await f.service.refresh([11]);
      await f.service.refresh([11, 12]);
      expect(await local.file.readAsBytes(), original);
      expect(await f.cache(f.first).readAsBytes(), steamBefore);
      final reloaded = await local.load();
      expect(reloaded.sessions.single, session.toJson());
      expect(reloaded.games.single.title, 'Fixture');
      expect(
        jsonEncode(reloaded.settings.toJson()),
        jsonEncode(const VaultSettings().toJson()),
      );
    },
  );
}
