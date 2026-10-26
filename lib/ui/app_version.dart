import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({super.key});
  // Settings shows the public version; native/package metadata retains +build.
  static String publicVersion(String version) => version.split('+').first;
  static final Future<String?> _version = _read();
  static Future<String?> _read() async {
    try {
      return await const MethodChannel(
        'gamevault/windows',
      ).invokeMethod<String>('appVersion', <String, Object>{});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _version,
    builder: (context, snapshot) => Text(
      snapshot.data == null
          ? 'GameVault'
          : 'GameVault ${publicVersion(snapshot.data!)}',
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );
}
