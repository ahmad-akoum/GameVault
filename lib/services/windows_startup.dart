import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// The sole fixed HKCU value belongs to GameVault. No reconciliation writes
/// happen on startup: changes require an explicit setting action in a stable app.
class WindowsStartup {
  WindowsStartup({
    bool? allowed,
    String? executable,
    Future<ProcessResult> Function(String, List<String>)? run,
  }) : executable = executable ?? Platform.resolvedExecutable,
       run = run ?? ((exe, args) => Process.run(exe, args)),
       allowed =
           allowed ??
           (Platform.isWindows &&
               kReleaseMode &&
               !const bool.fromEnvironment('GAMEVAULT_CANDIDATE') &&
               !(Platform.environment['GAMEVAULT_DATA_DIR']?.isNotEmpty ??
                   false) &&
               !Platform.resolvedExecutable.toLowerCase().contains(
                 'development_artifacts',
               ));
  final bool allowed;
  final String executable;
  final Future<ProcessResult> Function(String, List<String>) run;
  static const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  String get command => '"$executable"';
  Future<String?> read() async {
    if (!allowed) return null;
    final result = await run('reg.exe', ['query', key, '/v', 'GameVault']);
    if (result.exitCode != 0) return null;
    return RegExp(
      r'REG_SZ\s+([^\r\n]+)',
    ).firstMatch(result.stdout.toString())?.group(1)?.trim();
  }

  bool owns(String value) => RegExp(
    r'^"[^"\r\n]+[\\/]gamevault\.exe"$',
    caseSensitive: false,
  ).hasMatch(value);
  Future<void> restore(String? value) async {
    if (!allowed) {
      throw const FileSystemException(
        'Windows startup changes are disabled in development candidates.',
      );
    }
    if (value != null && (!owns(value) || value.length > 260)) {
      throw const FileSystemException(
        'Unexpected startup registration; no changes were made.',
      );
    }
    final current = await read();
    if (current != null && !owns(current)) {
      throw const FileSystemException(
        'Another startup registration uses this name.',
      );
    }
    if (current == value) return;
    final result = await run(
      'reg.exe',
      value == null
          ? ['delete', key, '/v', 'GameVault', '/f']
          : ['add', key, '/v', 'GameVault', '/t', 'REG_SZ', '/d', value, '/f'],
    );
    if (result.exitCode != 0) {
      throw const FileSystemException(
        'Windows could not save the startup preference.',
      );
    }
  }

  Future<void> setEnabled(bool value) async {
    if (value &&
        (!p.isAbsolute(executable) || !await File(executable).exists())) {
      throw const FileSystemException(
        'The installed executable is unavailable.',
      );
    }
    await restore(value ? command : null);
  }
}
