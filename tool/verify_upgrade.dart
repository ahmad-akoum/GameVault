// Explicitly copies an existing vault to a fresh private destination before testing.
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:gamevault/models/game.dart';
import 'package:gamevault/services/local_store.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Provide source vault and a NEW private destination');
  }
  final source = Directory(p.canonicalize(args[0]));
  final target = Directory(p.canonicalize(args[1]));
  if (await target.exists() ||
      p.equals(source.path, target.path) ||
      p.isWithin(source.path, target.path)) {
    throw StateError('Destination must be new and outside the source vault');
  }
  await target.create(recursive: true);
  await for (final item in source.list(recursive: true, followLinks: false)) {
    if (item is File && p.basename(item.path) != 'vault.lock') {
      final copy = File(
        p.join(target.path, p.relative(item.path, from: source.path)),
      );
      await copy.parent.create(recursive: true);
      await item.copy(copy.path);
    }
  }
  final store = LocalStore(target);
  await store.acquireLock();
  try {
    final before = await store.load();
    final settings = before.settings.copy(
      background: 0xff101725,
      surface: 0xff192840,
      profileSize: ProfileSize.expanded,
    );
    final games = jsonEncode(before.games.map((g) => g.toJson()).toList());
    final sessions = jsonEncode(before.sessions);
    await store.save(
      before.games,
      settings,
      sessions: before.sessions
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
    await store.close();
    await store.acquireLock();
    final after = await store.load();
    if (games != jsonEncode(after.games.map((g) => g.toJson()).toList()) ||
        sessions != jsonEncode(after.sessions) ||
        jsonEncode(settings.toJson()) != jsonEncode(after.settings.toJson())) {
      throw StateError('Upgrade round trip differs');
    }
    stdout.writeln(
      'Private-copy upgrade and settings restart passed; games and complete historical session records unchanged.',
    );
  } finally {
    await store.close();
  }
}
