import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/models/steam_playtime.dart';
import 'package:gamevault/services/steam_local_playtime.dart';

void main() {
  final appId = int.tryParse(
    Platform.environment['GAMEVAULT_STEAM_TEST_APPID'] ?? '',
  );
  test(
    'opt-in read-only Windows Steam provider; no profile association',
    () async {
      final provider = SteamLocalPlaytimeProvider();
      final detection = await provider.detectAccount();
      expect(
        detection.proposal,
        isNotNull,
        reason: 'Steam must be running with a reliably identifiable account.',
      );
      final result = await provider.read(detection.proposal!, [appId!]);
      expect(result.snapshots.length, 1);
      final s = result.snapshots.single;
      expect(s.state, isNot(SteamPlaytimeState.unavailable));
      expect(s.lifetimeMinutes, greaterThanOrEqualTo(0));
      expect(s.cacheModifiedAt, isNotNull);
    },
    skip: !Platform.isWindows || appId == null,
  );
}
