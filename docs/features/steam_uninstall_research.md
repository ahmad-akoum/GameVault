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
