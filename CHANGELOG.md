# Changelog

## 2.1.0 - 2026-10-16
- Fixed artwork blank frames during running-game tracker refreshes by preserving synchronous cached image resolution and stable provider identity; no tracking or inactivity changes.
- Artwork decoding now respects both physical display dimensions and cropping, preventing avoidable blur in library covers and Expanded banners. Decode sizes are cached in 64-pixel buckets; original cover/hero choices remain unchanged.
- Six appearance presets and independent accent/background/surface colors with live preview and mode-aware contrast.
- Persistent Compact, Comfortable and Expanded profile layouts.
- Artwork enlargement, zoom, pan, reset and keyboard/button closing.
- Additive settings compatibility; old preferences retain their values and default profile size is Comfortable.
- HLTB Explorer deferred because permissions and reliability are not established. Ratings remain V3 scope.

## 2.0.0 - 2026-10-16
Compared with V1: session and active-time tracking, launch/process integration, activity dashboard/history, collections and manual progress/executable import.
Stabilization: clean engine/window teardown before COM shutdown, package-derived Settings version, standard DualSense Raw Input activity alongside XInput and keyboard/mouse, no-op polling notification reduction and bounded asynchronous artwork loading.

## 2.0.0-rc.1
Existing V2 source preserved as a release candidate. Original owner acceptance was pending at that point; subsequent owner testing identified the stabilization issues above.

## 1.0.0 - historical source
Genuine pre-V2 source was recovered from Git history: selective Steam imports, metadata/artwork, HLTB matching, statuses, favorites, search/filter/sort and basic appearance. This entry does not invent an earlier public binary release.
