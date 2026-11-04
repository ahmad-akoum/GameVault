import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../models/steam_playtime.dart';
import 'steam_scanner.dart';

/// Verified running Steam process and registry account, not a last-login guess.
class SteamActiveProcess {
  const SteamActiveProcess(this.accountId, this.pid, this.executable);
  final int accountId, pid;
  final String executable;
}

class SteamAccountProposal {
  const SteamAccountProposal(
    this.account,
    this.root,
    this.pid,
    this.displayName,
  );
  final SteamPlaytimeAccount account;
  final String root, displayName;
  final int pid;
  bool sameProcess(SteamAccountProposal other) =>
      account.steamId64 == other.account.steamId64 &&
      pid == other.pid &&
      p.equals(root.toLowerCase(), other.root.toLowerCase());
}

class SteamAccountDetection {
  const SteamAccountDetection({this.proposal, this.problem});
  final SteamAccountProposal? proposal;
  final SteamPlaytimeProblem? problem;
}

class SteamCacheDocument {
  const SteamCacheDocument(this.values, this.modifiedAt);
  final Map<String, dynamic> values;
  final DateTime modifiedAt;
}

class SteamCacheFailure implements Exception {
  const SteamCacheFailure(this.problem);
  final SteamPlaytimeProblem problem;
}

class SteamPlaytimeRead {
  const SteamPlaytimeRead(this.snapshots, {this.problem});
  final List<SteamPlaytimeSnapshot> snapshots;
  final SteamPlaytimeProblem? problem;
}

/// Reads only Steam files. No API key, HTTP, Steam writes, or session dependency.
class SteamLocalPlaytimeProvider {
  SteamLocalPlaytimeProvider({
    Future<List<String>> Function()? installationRoots,
    Future<SteamActiveProcess?> Function()? activeProcess,
    Future<SteamCacheDocument> Function(String)? readDocument,
    DateTime Function()? now,
    this.maxCacheAge = const Duration(hours: 24),
  }) : installationRoots = installationRoots ?? SteamScanner.locateSteam,
       activeProcess = activeProcess ?? _windowsActiveProcess,
       readDocument = readDocument ?? readSteamDocument,
       now = now ?? DateTime.now;

  final Future<List<String>> Function() installationRoots;
  final Future<SteamActiveProcess?> Function() activeProcess;
  final Future<SteamCacheDocument> Function(String) readDocument;
  final DateTime Function() now;
  final Duration maxCacheAge;

  Future<SteamAccountDetection> detectAccount() async {
    try {
      final active = await activeProcess();
      if (active == null ||
          active.accountId <= 0 ||
          active.accountId > 0xffffffff ||
          active.pid <= 0 ||
          !p.isAbsolute(active.executable)) {
        return const SteamAccountDetection(
          problem: SteamPlaytimeProblem.accountUnavailable,
        );
      }
      final roots = <String>{};
      for (final root in await installationRoots()) {
        if (!p.isAbsolute(root)) continue;
        final executable = File(p.join(root, 'steam.exe'));
        if (!await executable.exists()) continue;
        final canonical = await executable.resolveSymbolicLinks();
        if (p.equals(
          canonical.toLowerCase(),
          (await File(active.executable).resolveSymbolicLinks()).toLowerCase(),
        )) {
          roots.add(p.dirname(canonical));
        }
      }
      if (roots.length != 1) {
        return const SteamAccountDetection(
          problem: SteamPlaytimeProblem.accountUnavailable,
        );
      }
      final root = roots.single;
      final document = await readDocument(
        p.join(root, 'config', 'loginusers.vdf'),
      );
      final users = document.values['users'];
      final expectedId =
          '${SteamPlaytimeAccount.individualBase + active.accountId}';
      if (users is! Map || users[expectedId] is! Map) {
        return const SteamAccountDetection(
          problem: SteamPlaytimeProblem.accountUnavailable,
        );
      }
      final repeated = await activeProcess();
      if (repeated == null ||
          repeated.accountId != active.accountId ||
          repeated.pid != active.pid ||
          !p.equals(
            repeated.executable.toLowerCase(),
            active.executable.toLowerCase(),
          )) {
        return const SteamAccountDetection(
          problem: SteamPlaytimeProblem.accountChanged,
        );
      }
      final name = (users[expectedId] as Map)['personaname'];
      final cleanName = name is String
          ? name.replaceAll(RegExp(r'[\r\n\x00-\x1f]'), '')
          : '';
      return SteamAccountDetection(
        proposal: SteamAccountProposal(
          SteamPlaytimeAccount(expectedId),
          root,
          active.pid,
          cleanName.substring(0, cleanName.length.clamp(0, 128)),
        ),
      );
    } catch (_) {
      // Never expose registry/login-file contents in an exception or log.
      return const SteamAccountDetection(
        problem: SteamPlaytimeProblem.accountUnavailable,
      );
    }
  }

  Future<SteamPlaytimeRead> read(
    SteamAccountProposal proposal,
    Iterable<int> appIds,
  ) async {
    final ids = appIds.toSet().toList()..sort();
    if (ids.any((id) => id <= 0 || id > 0xffffffff) || ids.length > 10000) {
      throw ArgumentError('Expected bounded, positive Steam AppIDs');
    }
    final before = await detectAccount();
    if (before.proposal == null || !proposal.sameProcess(before.proposal!)) {
      return SteamPlaytimeRead(
        const [],
        problem: before.problem ?? SteamPlaytimeProblem.accountChanged,
      );
    }
    SteamCacheDocument? document;
    SteamPlaytimeProblem? failure;
    try {
      document = await readDocument(
        p.join(
          proposal.root,
          'userdata',
          '${proposal.account.accountId}',
          'config',
          'localconfig.vdf',
        ),
      );
    } on SteamCacheFailure catch (e) {
      failure = e.problem;
    } catch (_) {
      failure = SteamPlaytimeProblem.cacheUnreadable;
    }
    final after = await detectAccount();
    if (after.proposal == null || !proposal.sameProcess(after.proposal!)) {
      return const SteamPlaytimeRead(
        [],
        problem: SteamPlaytimeProblem.accountChanged,
      );
    }
    final at = now().toUtc();
    Map<dynamic, dynamic>? apps;
    if (document != null) {
      dynamic value = document.values;
      for (final key in [
        'userlocalconfigstore',
        'software',
        'valve',
        'steam',
        'apps',
      ]) {
        value = value is Map ? value[key] : null;
      }
      if (value is Map) {
        apps = value;
      } else {
        failure = SteamPlaytimeProblem.cacheMalformed;
      }
    }
    final values = <SteamPlaytimeSnapshot>[];
    for (final id in ids) {
      final entry = apps?['$id'];
      final raw = entry is Map ? entry['playtime'] : null;
      final parsed = raw is String && RegExp(r'^\d+$').hasMatch(raw)
          ? int.tryParse(raw)
          : null;
      final minutes = parsed != null && parsed <= 0x7fffffff ? parsed : null;
      var problem =
          failure ??
          (raw == null
              ? SteamPlaytimeProblem.missingValue
              : minutes == null
              ? SteamPlaytimeProblem.invalidValue
              : null);
      var state = SteamPlaytimeState.unavailable;
      if (problem == null) {
        state = SteamPlaytimeState.available;
        if (document!.modifiedAt.isAfter(at)) {
          state = SteamPlaytimeState.stale;
          problem = SteamPlaytimeProblem.clockSkew;
        } else if (at.difference(document.modifiedAt) > maxCacheAge) {
          state = SteamPlaytimeState.stale;
          problem = SteamPlaytimeProblem.staleCache;
        }
      }
      final lastRaw = entry is Map ? entry['lastplayed'] : null;
      final last = lastRaw is String ? int.tryParse(lastRaw) : null;
      values.add(
        SteamPlaytimeSnapshot(
          account: proposal.account,
          appId: id,
          retrievedAt: at,
          state: state,
          lifetimeMinutes: state == SteamPlaytimeState.unavailable
              ? null
              : minutes,
          cacheModifiedAt: document?.modifiedAt,
          lastPlayedAt: last != null && last > 86400 && last <= 0xffffffff
              ? DateTime.fromMillisecondsSinceEpoch(last * 1000, isUtc: true)
              : null,
          problem: problem,
        ),
      );
    }
    return SteamPlaytimeRead(List.unmodifiable(values), problem: failure);
  }

  static Future<SteamActiveProcess?> _windowsActiveProcess() async {
    if (!Platform.isWindows) return null;
    try {
      // Constant read-only script: no file paths or user input are interpolated.
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"$ErrorActionPreference='Stop';try {$a=Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam\ActiveProcess';if([long]$a.ActiveUser -le 0 -or [int]$a.pid -le 0){exit 1};$p=Get-Process -Id $a.pid -ErrorAction Stop;if($p.ProcessName -ne 'steam' -or !$p.Path){exit 1};[pscustomobject]@{accountId=[long]$a.ActiveUser;pid=[int]$p.Id;executable=$p.Path}|ConvertTo-Json -Compress}catch{exit 1}",
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode != 0) return null;
      final j = jsonDecode(result.stdout.toString()) as Map;
      return SteamActiveProcess(
        j['accountId'] as int,
        j['pid'] as int,
        j['executable'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Read a complete committed file, reject in-progress replacements, bound memory,
/// and parse off the UI isolate. Never inspect async temporary Steam files.
Future<SteamCacheDocument> readSteamDocument(String path) =>
    Isolate.run(() async {
      const limit = 16 * 1024 * 1024;
      final file = File(path);
      try {
        final before = await file.stat();
        if (before.type != FileSystemEntityType.file) {
          throw const SteamCacheFailure(SteamPlaytimeProblem.cacheMissing);
        }
        if (before.size > limit) {
          throw const SteamCacheFailure(SteamPlaytimeProblem.cacheMalformed);
        }
        Future<Uint8List> boundedRead() async {
          final builder = BytesBuilder(copy: false);
          await for (final chunk in file.openRead(0, limit + 1)) {
            builder.add(chunk);
          }
          return builder.takeBytes();
        }

        final first = await boundedRead();
        final second = await boundedRead();
        final after = await file.stat();
        if (first.length > limit ||
            second.length > limit ||
            before.size != after.size ||
            before.modified != after.modified ||
            first.length != second.length ||
            Iterable<int>.generate(
              first.length,
            ).any((i) => first[i] != second[i])) {
          throw const SteamCacheFailure(SteamPlaytimeProblem.cacheChanging);
        }
        return SteamCacheDocument(
          ValveKeyValues.parse(utf8.decode(first)),
          after.modified.toUtc(),
        );
      } on SteamCacheFailure {
        rethrow;
      } on FormatException {
        throw const SteamCacheFailure(SteamPlaytimeProblem.cacheMalformed);
      } on FileSystemException {
        throw const SteamCacheFailure(SteamPlaytimeProblem.cacheUnreadable);
      }
    });
