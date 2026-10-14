import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:gamevault/services/steam_app_info.dart';
import 'package:gamevault/services/steam_scanner.dart';
import 'services_test.dart' show fixtureDirectory, manifest;

Uint8List catalog(Map<int, String> types, int version) {
  final keys = ['appinfo', 'common', 'type'];
  final entries = BytesBuilder();
  List<int> u32(int n) =>
      (ByteData(4)..setUint32(0, n, Endian.little)).buffer.asUint8List();
  List<int> u64(int n) =>
      (ByteData(8)..setUint64(0, n, Endian.little)).buffer.asUint8List();
  List<int> key(int i) => version == 41 ? u32(i) : [...utf8.encode(keys[i]), 0];
  for (final entry in types.entries) {
    final tree = [
      0,
      ...key(0),
      0,
      ...key(1),
      1,
      ...key(2),
      ...utf8.encode(entry.value),
      0,
      8,
      8,
      8,
    ];
    final header = List<int>.filled(version >= 40 ? 60 : 40, 0);
    entries.add([
      ...u32(entry.key),
      ...u32(header.length + tree.length),
      ...header,
      ...tree,
    ]);
  }
  entries.add(u32(0));
  final data = entries.takeBytes();
  return Uint8List.fromList([
    ...u32(0x07564427 + version - 39),
    ...u32(1),
    if (version == 41) ...u64(16 + data.length),
    ...data,
    if (version == 41) ...[
      ...u32(keys.length),
      for (final key in keys) ...[...utf8.encode(key), 0],
    ],
  ]);
}

void main() {
  for (final version in [39, 40, 41]) {
    test('Steam appinfo v$version reads nested app types', () {
      expect(
        SteamAppInfo.types(
          catalog({10: 'Game', 20: 'Application', 30: 'Demo'}, version),
        ),
        {10: 'game', 20: 'application', 30: 'demo'},
      );
    });
  }
  test('truncated and unsupported catalogs fail safely', () {
    expect(() => SteamAppInfo.types(Uint8List(16)), throwsFormatException);
    final bytes = catalog({10: 'Game'}, 41);
    expect(
      () => SteamAppInfo.types(bytes.sublist(0, bytes.length - 5)),
      throwsFormatException,
    );
  });
  test(
    'secondary selection discovers central libraries and filters Steam types',
    () async {
      final dir = await fixtureDirectory();
      try {
        final main = Directory(p.join(dir.path, 'Steam'));
        final secondary = Directory(p.join(dir.path, 'other'));
        final third = Directory(p.join(dir.path, 'third'));
        await manifest(main, 10, 'Game');
        await manifest(secondary, 20, 'Software');
        await manifest(secondary, 480, 'Spacewar');
        await manifest(third, 30, 'Demo');
        await manifest(third, 40, 'Soundtrack', installed: false);
        await manifest(main, 228980, 'Redistributables');
        await Directory(p.join(main.path, 'appcache')).create();
        await File(p.join(main.path, 'appcache', 'appinfo.vdf')).writeAsBytes(
          catalog({
            10: 'Game',
            20: 'Application',
            30: 'Demo',
            40: 'Music',
            228980: 'Tool',
            480: 'Game',
          }, 41),
        );
        await File(
          p.join(main.path, 'steamapps', 'libraryfolders.vdf'),
        ).writeAsString(
          '"libraryfolders" { "1" { "path" "${secondary.path.replaceAll('\\', '\\\\')}" } "2" { "path" "${third.path.replaceAll('\\', '\\\\')}" } }',
        );
        final result = await SteamScanner(
          installationRoots: () async => [main.path, main.path.toUpperCase()],
        ).scan([secondary.path]);
        expect(result.games.map((g) => g.appId), [30, 10]);
        expect(result.paths.length, 3);
        expect(result.warnings, isEmpty);
        // Presence of a folder alone never creates a detected game.
        await Directory(
          p.join(third.path, 'steamapps', 'common', 'Leftover'),
        ).create();
        expect(
          (await SteamScanner(
            installationRoots: () async => [main.path],
          ).scan([secondary.path])).games.length,
          2,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('missing or corrupt type cache retains games with a notice', () async {
    final dir = await fixtureDirectory();
    try {
      await manifest(dir, 10, 'Unknown game', flags: '6');
      final scanner = SteamScanner(installationRoots: () async => []);
      expect((await scanner.scan([dir.path])).games.single.appId, 10);
      await Directory(p.join(dir.path, 'appcache')).create();
      await File(
        p.join(dir.path, 'appcache', 'appinfo.vdf'),
      ).writeAsBytes([1, 2, 3]);
      final result = await scanner.scan([dir.path]);
      expect(result.games.single.appId, 10);
      expect(result.warnings.length, 2);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
