import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamevault/ui/app_version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'public version removes build metadata without hardcoding a version',
    () {
      expect(AppVersionLabel.publicVersion('2.4.0+16'), '2.4.0');
      expect(AppVersionLabel.publicVersion('2.5.1+42'), '2.5.1');
      expect(AppVersionLabel.publicVersion('3.0.0-rc.1+9'), '3.0.0-rc.1');
      expect(AppVersionLabel.publicVersion('2.4.0'), '2.4.0');
    },
  );
  testWidgets('Settings version label reads native version and hides build', (
    tester,
  ) async {
    const channel = MethodChannel('gamevault/windows');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'appVersion');
          return '2.4.0+16';
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await tester.pumpWidget(const MaterialApp(home: AppVersionLabel()));
    await tester.pumpAndSettle();
    expect(find.text('GameVault 2.4.0'), findsOneWidget);
    expect(find.textContaining('+16'), findsNothing);
  });
}
