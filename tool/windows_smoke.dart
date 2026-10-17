// Run in the Windows runner, never against the user's vault. Uses our fixture.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/windows_games.dart';
import 'package:gamevault/services/session_tracker.dart';
import 'package:gamevault/services/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Native integration checks'))),
    ),
  );
  final root = Platform.environment['GAMEVAULT_PROJECT_ROOT']!;
  final configuredBuild =
      Platform.environment['GAMEVAULT_BUILD_DIR'] ?? 'build';
  final buildRoot = p.isAbsolute(configuredBuild)
      ? configuredBuild
      : p.join(root, configuredBuild);
  const expectedVersion = String.fromEnvironment('GAMEVAULT_EXPECTED_VERSION');
  final output = File(p.join(buildRoot, 'native_smoke_result.json'));
  final store = LocalStore(Directory(p.join(buildRoot, 'native_smoke_data')));
  try {
    final version = await const MethodChannel(
      'gamevault/windows',
    ).invokeMethod<String>('appVersion', <String, Object>{});
    if (expectedVersion.isNotEmpty && version != expectedVersion) {
      throw StateError('Unexpected Windows build version');
    }
    final platform = WindowsGames();
    final executable = p.join(buildRoot, 'native_fixture.exe');
    final g = VaultGame(
      appId: -1,
      title: 'Native integration fixture',
      installPath: p.dirname(executable),
      libraryPath: p.dirname(executable),
      executablePath: executable,
    );
    final before = await platform.sample([g]);
    if (before.games.single.processes.isNotEmpty) {
      throw StateError('Fixture already running');
    }
    await platform.launch(g);
    await Future<void>.delayed(const Duration(seconds: 1));
    final first = await platform.sample([g]);
    if (first.games.single.processes.isEmpty) {
      throw StateError('Launched executable not detected');
    }
    final automatic = VaultGame(
      appId: 700,
      title: 'Automatic fixture',
      installPath: p.dirname(executable),
      libraryPath: p.dirname(executable),
    );
    final associated = await platform.sample([g, automatic]);
    if (associated.games[0].processes.isEmpty ||
        associated.games[1].processes.isNotEmpty) {
      throw StateError('One process was assigned to more than one game');
    }
    final tracker = SessionTracker();
    final clock = Stopwatch()..start();
    tracker.sample(
      now: DateTime.now(),
      monotonicSeconds: 0,
      games: first.games,
      idleSeconds: first.idleSeconds,
    );
    for (var i = 0; i < 7; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final sample = await platform.sample([g]);
      tracker.sample(
        now: DateTime.now(),
        monotonicSeconds: clock.elapsed.inSeconds,
        games: sample.games,
        idleSeconds: sample.idleSeconds,
      );
    }
    if (tracker.sessions.length != 1 ||
        tracker.sessions.single.open ||
        tracker.total(-1) < 6 ||
        tracker.total(-1) > 12) {
      throw StateError('Unexpected session result');
    }
    await store.acquireLock();
    await store.save([g], const VaultSettings(), sessions: tracker.toJson());
    final loaded = await store.load();
    if (loaded.sessions.length != 1) {
      throw StateError('Session persistence failed');
    }
    var missingRejected = false;
    try {
      await platform.launch(
        VaultGame(
          appId: -2,
          title: 'Missing',
          installPath: root,
          libraryPath: root,
          executablePath: p.join(buildRoot, 'missing.exe'),
        ),
      );
    } catch (_) {
      missingRejected = true;
    }
    if (!missingRejected) throw StateError('Missing executable accepted');
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'passed': true,
        'version': version,
        'launch': 'real ShellExecute .exe launch',
        'detected': true,
        'terminationDetected': true,
        'focusObserved': first.games.single.focused,
        'idleSeconds': first.idleSeconds,
        'trackedSeconds': tracker.total(-1),
        'persistenceRoundTrip': true,
        'missingExecutableRejected': true,
        'uniqueProcessAssociation': true,
        'limitations': [
          'No commercial game was launched',
          'No physical controller test',
          'Steam URI dispatch not exercised',
        ],
      }),
    );
  } catch (e, st) {
    await output.writeAsString(
      jsonEncode({'passed': false, 'error': '$e', 'stack': '$st'}),
    );
  } finally {
    await store.close();
    exit(0);
  }
}
