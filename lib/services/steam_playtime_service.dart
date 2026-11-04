import '../models/steam_playtime.dart';
import 'steam_local_playtime.dart';
import 'steam_playtime_store.dart';

/// Phase 1 integration boundary. Not wired to app startup or any current UI.
/// A later confirmation dialog must call confirmAccount only after user approval.
class SteamPlaytimeService {
  SteamPlaytimeService(this.provider, this.store);
  final SteamLocalPlaytimeProvider provider;
  final SteamPlaytimeStore store;

  Future<SteamAccountDetection> proposeAccount() => provider.detectAccount();

  /// Explicit user action: discovery and refresh never invoke this themselves.
  /// Revalidate the exact proposal so stale dialogs cannot bind another account.
  Future<bool> confirmAccount(SteamAccountProposal proposal) => store.update((
    data,
  ) async {
    final current = await provider.detectAccount();
    if (current.proposal == null || !proposal.sameProcess(current.proposal!)) {
      // Throw before writing, preserving the prior profile association.
      throw const SteamAccountConfirmationExpired();
    }
    return (
      SteamPlaytimeData(
        confirmedAccount: proposal.account,
        latest: data.latest,
        lastKnown: data.lastKnown,
        baselines: data.baselines,
      ),
      true,
    );
  });

  Future<SteamPlaytimeRead> refresh(Iterable<int> appIds) async {
    final ids = List<int>.of(appIds);
    if (ids.any((id) => id <= 0 || id > 0xffffffff) || ids.length > 10000) {
      throw ArgumentError('Expected bounded, positive Steam AppIDs');
    }
    final initial = await store.load();
    if (initial.confirmedAccount == null) {
      return const SteamPlaytimeRead(
        [],
        problem: SteamPlaytimeProblem.confirmationRequired,
      );
    }
    final detected = await provider.detectAccount();
    if (detected.proposal == null) {
      return SteamPlaytimeRead(const [], problem: detected.problem);
    }
    if (detected.proposal!.account.steamId64 !=
        initial.confirmedAccount!.steamId64) {
      return const SteamPlaytimeRead(
        [],
        problem: SteamPlaytimeProblem.accountChanged,
      );
    }
    final read = await provider.read(detected.proposal!, ids);
    if (read.snapshots.isEmpty) return read;
    return store.update((latestData) async {
      if (latestData.confirmedAccount?.steamId64 !=
          initial.confirmedAccount!.steamId64) {
        throw const SteamAccountConfirmationExpired();
      }
      final latest = {...latestData.latest},
          lastKnown = {...latestData.lastKnown};
      for (final snapshot in read.snapshots) {
        // Concurrent/out-of-order requests cannot replace a later observation.
        final existing = latest[snapshot.key];
        if (existing != null &&
            existing.retrievedAt.isAfter(snapshot.retrievedAt)) {
          continue;
        }
        latest[snapshot.key] = snapshot;
        if (snapshot.lifetimeMinutes != null) {
          lastKnown[snapshot.key] = snapshot;
        }
      }
      return (
        SteamPlaytimeData(
          confirmedAccount: latestData.confirmedAccount,
          latest: latest,
          lastKnown: lastKnown,
          baselines: latestData.baselines,
        ),
        read,
      );
    });
  }
}
