# V2.5 profile and installation changes

The profile shows Running while the existing tracker observes the game. On
process exit, the tracker closes the session and the same profile rebuild
restores the appropriate Play or Steam update action. Playtime Overview shows
measured active and inactive durations in seconds. The lifetime headline
continues to round to minutes. A cache value below tracked runtime still
prevents provisional full overlap; the explanation is in Playtime information.

TrackingControls and DetailsPage remove manual percentage editing and display,
retain status and collections, and show Last played beside Recent sessions.
VaultGame retains the legacy progressPercent field in serialized data so an
upgrade does not discard a value previously saved by an older version.

No supported Steam or Epic launcher command was identified for stopping an
arbitrary running game. Windows WM_CLOSE lets an application prompt, defer, or
reject closing, but current observations identify processes, not a verified
game-owned window and save behavior. This applies to Steam, Epic and manual
games. GameVault displays Running and leaves normal exit to the game.

- [Steamworks API overview](https://partner.steamgames.com/doc/sdk/api)
- [Epic launcher activation](https://assets-unreal2-epic-prod-us2.s3.amazonaws.com/original/4X/f/c/4/fc4342c50e1a0abf34943e019ee90bacccc62950.pdf)
- [Windows WM_CLOSE](https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-close)

Profile tests cover the running-to-exited transition and exact active/inactive
seconds. Reconciliation tests continue to cover baseline immutability on
refresh, including counter decreases and missing snapshots.

V2.5.1 removes the separate Collections section from game profiles. To
change membership, select a collection in the sidebar's Collections page and
choose Manage games. The dialog saves only changed memberships in one vault
write through VaultController.updateCollectionMembership. Cancel leaves
memberships unchanged. Widget coverage checks Cancel, add and remove, plus
preservation of unrelated memberships and favorite state.
