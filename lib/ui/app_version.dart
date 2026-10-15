import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppVersionLabel extends StatelessWidget {
  const AppVersionLabel({super.key});
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
          : 'GameVault ${snapshot.data!.split('+').first}',
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );
}
