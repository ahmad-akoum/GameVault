# Steam uninstall investigation

Steam Support documents Library > Manage > Uninstall. On Windows, Steam
registers per-game uninstall entries whose command can point to steam.exe
with steam://uninstall/<AppID>. Inspection confirmed this form exists in
Steam-created registrations. A registry entry can be stale and is neither
proof of installation nor proof that the current client will show the
normal confirmation or handle rejection consistently. Steamworks documents
installation queries, but no supported third-party uninstall API or
completion callback was verified. No uninstall command was executed.

Steam delivers game files in depots and can run developer-provided
game-specific uninstall scripts. Valve tells developers to leave common
redistributables installed because other games may use them. Those sources
do not promise which extra files, mods, settings or local saves survive.
Steam Cloud only covers configured, successfully synchronized data. Some
cloud paths are in the install directory and some are elsewhere. Uploaded
Steam achievements are account data. This is separate from local save
files, unsynchronized data and the per-account userdata cache.

GameVault already verifies Steam installation evidence with a matching
AppID manifest, the installed flag and a valid folder in a known library.
It stores profiles, sessions and Steam playtime independently of those
folders. Missing or inconsistent evidence remains distinct from a verified
installation. Storage Overview resolves the installation before using a
cached size on refresh. An old folder alone cannot prove installation.
Existing refresh can reconnect the same AppID when it finds a valid new
manifest; no uninstall-specific status or retention migration is added here.

Before implementing an uninstall action, validate the command on a
disposable Windows Steam setup with a sacrificial title. Check the Steam
confirmation, cancellation, completion and the manifest/leftover files
before and after. Check closed, offline, updating, unavailable and
game-running states. If verified, delegate only a freshly verified Steam
AppID to Steam, then refresh evidence independently. An accepted launch
request would not prove that the uninstall completed.

- [Steam's documented client workflow](https://help.steampowered.com/en/faqs/view/4566-6D94-3A46-953A)
- [Steamworks installation queries](https://partner.steamgames.com/doc/api/ISteamApps)
- [Steam depots](https://partner.steamgames.com/doc/store/application/depots)
- [InstallScripts and uninstall hooks](https://partner.steamgames.com/doc/sdk/installscripts)
- [Steam Cloud](https://partner.steamgames.com/doc/features/cloud)
- [Steam stats and achievements](https://partner.steamgames.com/doc/features/achievements)

## Candidate 2 implementation

The profile action confirms the named game before sending the fixed native
Steam uninstall URI through the Windows runner. The controller validates
the Steam source and numeric AppID, checks current installation evidence,
and checks for a running game. The runner checks the numeric AppID again.
An accepted Windows handoff does not establish success in Steam.

The profile checks Steam again when reopened or focused. A handoff starts
up to eight additional checks, four seconds apart, while the profile is
open. Steam cancellation or an unchanged manifest leaves the game installed.
An unreadable library, damaged record, or library index that still lists
the AppID without its manifest leaves the result inconclusive. The user
can refresh manually when Steam finishes. Not Installed requires readable
libraries without an installation record or an indexed AppID. Leftover
folders are ignored for that decision and left on disk.

Install via Steam uses the fixed Steam install URI. A verified manifest
for the same AppID reconnects the existing profile, including when Steam
reinstalls it to a different path. Storage Overview revalidates a game
before counting cached bytes. Steam manages game files while the GameVault
profile and its history remain in the vault.

Tests mock the Windows handoff and change only temporary Steam manifests.
They cover invalid IDs, unsupported launchers, running games, cancellation,
unavailable Steam, leftover files, storage, history and reinstall. The
actual Steam dialog and file removal still require owner acceptance with
a specifically approved sacrificial game.

- [Valve's documented native install link](https://partner.steamgames.com/doc/steamhardware/steamdeck/devkits)

## Candidate 3 detection correction

Steam can remove a game manifest and leave its libraryfolders.vdf entry
and unmanaged files behind. An older index no longer blocks Not Installed
when every known library is readable, no matching manifest remains, and
Steam's bounded content log has a newer Uninstalled transition for the
same AppID. A newer contradictory transition or a newer index leaves
the result Unknown. Positive installed manifests still take precedence.

The profile hides executable and storage actions plus Game Update Center
for verified uninstalled Steam games. Unknown disables Play and suppresses
stale update claims. The update center keeps its Steam action and refresh
control. Up to Date is reserved for live Steam evidence of a matching
recorded target build; other inconclusive evidence displays Unknown.

Candidate 4 presents verified absence as a neutral installation notice.
Storage Overview rechecks the installation and groups verified uninstalled
games separately from unavailable locations. Those games have no measured
size and do not count as failed measurements. Refreshing after reinstall
returns the game to its drive group. Fixture coverage checks both states.

Candidate 5 checks the open Steam profile on focus return and at most once
every 12 seconds while the profile is visible, even when Steam has focus. Those checks read Steam
metadata, with storage recalculated on a verified reinstall. A one-time
metadata pass seeds cover badges on startup. The shared game cards show
verified Not Installed in the existing badge slot and preserve personal
statuses. Unfinished installs remain inconclusive, and the old timeout
message has been removed. Fixture tests cover focus return, an open-window
transition, incomplete manifests and shared card badge precedence.
