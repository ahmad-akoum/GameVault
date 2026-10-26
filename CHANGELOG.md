# Changelog

## 2.4.0 — prepared (publication pending approval)

### Added
- Preview and reuse selected cover/banner artwork across the two independent slots.
- Needs Update filtering, Recently Played and Least Recently Played sorting.
- Persistent manual sidebar collapse alongside automatic narrow layouts.
- Cached local installed sizes and drive details with explicit refresh.
- Optional per-user Windows startup control, disabled in development candidates.
- Experimental Epic manifest discovery, selective import and launcher dispatch.

### Changed
- Manual Steam folders are an optional fallback; Scan again remains on Find games.
- Settings dynamically shows the public version without its internal build suffix;
  executable/package metadata retains the full version. Obsolete V2 label removed.

### Fixed
- Hide the sidebar arrow when responsive navigation cannot expand; retain its
  saved manual preference across width changes.
- Empty manual-folder settings no longer block automatic Steam registry/VDF discovery.

### Known limitations
- Epic update detection and online Epic artwork/metadata are deferred.
- Installed size is logical file bytes, excludes links, and may need manual refresh.
- Real game/launcher acceptance remains separate from automated dispatch checks.
- Candidate startup registration is intentionally unavailable. Existing narrow
  Expanded-banner cropping remains a future improvement.

## 2.3.0

### Added
- Refresh Installation across configured Steam libraries, installation status, and folder/executable location actions.
- Read-only Steam update-state detection and top-left cover badges with amber profile status and Open in Steam. Ambiguous states remain Unknown.
- Latest-two Recent Sessions with expand/collapse and collapsible Game Settings.

### Changed
- All verified pending Steam update stages use one Update Available action/badge; Play Game remains the safe fallback. Detailed evidence is expandable diagnostics, not a download-stage claim. Update buttons only open Steam.
- Automatic update initiation research is on hold and is not a V2.3 release blocker.
- Verified Steam pending states replace Play in its original profile position; completed, unknown and last-known states retain launch access. Status buttons open the corresponding game in Steam without launching or controlling downloads. Update Available explicitly asks users to start the update manually in Steam.
- Open in Steam and Open File Location are always accessible together on Steam profiles and wrap at narrow widths. Open EXE Location remains in Game Settings.
- Restored HLTB search, retrieved completion estimates, match selection, lookup after selected imports, and refresh. Saved estimates/matches remain intact; request failures are reported explicitly.
- Update-state refresh runs independently of activity tracking, with bounded log reads and no Steam writes.

### Fixed
- Open File Location resolves current Steam manifests when clicked, avoiding a surviving stale installation folder; local directories and executable-parent fallback are supported.
- Steam launching no longer rejects a valid AppID solely because its stored installation folder is stale.
- Narrow Expanded artwork uses a widescreen height cap, preserving desktop sizes and Crop/Fit.

### Known limitations
- HLTB live requests and isolated persistence tests pass, but its unofficial protocol and unresolved distribution permissions remain limitations. No access-control bypass is introduced.
- Steam state is saved local evidence, not a supported real-time client-button API. Unknown/closed/stale states never fabricate live badges or claim a game is fully up to date.
- Launcher-specific launch, relocation and update behavior depends on the local
  installation. V2.3 publication and its stable installation upgrade are complete.

## 2.2.0

### Added
- Independent library-cover and profile-banner management, local image imports, previews, default restoration and supported Steam alternatives.
- Clear Total/Active/Inactive session summaries with precise durations and responsive, compact session cards.
- Responsive layouts for narrow Windows 11 Snap Layout columns while retaining the normal-width design.

### Changed
- Keyboard/mouse and DualSense/XInput inactivity behavior reflects the approved Stage 1 fixes; the existing idle threshold and focus grace remain configurable.
- Existing HowLongToBeat estimates and saved choices remain visible, but live website lookup, refresh and website-script inspection are disabled pending an authorized integration.
- Source is published for viewing and testing without an open-source license; GameVault code remains all rights reserved.

### Fixed
- Avoided blurred artwork caused by undersized image decoding and unstable image-provider identity during tracking refreshes.
- Improved inactivity classification for focused idle periods and meaningful DualSense input while ignoring unchanged controller state and stick drift.
- Improved Windows shutdown and narrow-window access to navigation, settings, artwork controls and session details.

### Known Limitations
- At narrow widths, the Expanded profile banner can crop more aggressively than Comfortable; recorded for a future update.
- Live HowLongToBeat retrieval is unavailable until an authorized integration is established. This does not assert that every third-party data-rights question is resolved.
- GameVault's source code has no general reuse license. Existing third-party dependencies keep their own licenses.

## 2.2.0-dev.4 - UI polish development, not approved for release
- Reduced Recent sessions padding/gaps and removed horizontal activity bars; exact Total/Active/Inactive durations, timestamps and end status remain.
- Reduced the Windows minimum width from 880 to 360 logical pixels; added narrow navigation drawer, responsive filters/grids, stacked profile and Settings controls, and wrapping artwork controls. Existing wide layouts retained.
- Added narrow-layout regression coverage including enlarged text. Tracking, input, accounting and stored data remain unchanged. Actual Windows Snap arrangement requires owner acceptance.

## 2.2.0-dev.3 - Stage 3 development, not approved for release
- Clear Total/Active/Inactive session cards with exact stored-second formatting, local date ranges, existing status and a static accessible activity bar.
- Explicit active-versus-total labels on profile, Home and Activity summaries; conservative Unknown display for incomplete activity evidence.
- Presentation only: tracking, thresholds, session accounting/storage and approved artwork behavior remain unchanged. Final V2.2 QA/release preparation has not started.

## 2.2.0-dev.2 - Stage 2 development, not approved for release
- Independent cover/banner selection, managed local imports, previews, fill/fit choices, saved alternatives and per-role default restoration.
- Optional explicit checks for distinct artwork through existing Steam CDN routes; no new provider or invented variants.
- Metadata refresh preserves selected/original artwork, including concurrent edits. Fixed desktop title-bar Tooltip Overlay ancestry.
- Stage 1 passed owner gameplay acceptance. Stage 2 UI/gameplay acceptance remains pending; Stage 3 has not started.

## 2.2.0-dev.1 - Stage 1 development, not approved for release
- Inactivity tracking: device-backed keyboard/mouse observations replace the Windows last-input timestamp; unchanged controller states and small analog noise no longer refresh idle time.
- Existing idle choices, focus grace, session totals and persistence remain unchanged. Hardware acceptance is pending.
- Artwork management and statistics presentation are not implemented in this stage.

## 2.1.0 - prepared, not published
- Fixed artwork blank frames during running-game tracker refreshes by preserving synchronous cached image resolution and stable provider identity; no tracking or inactivity changes.
- Artwork decoding now respects both physical display dimensions and cropping, preventing avoidable blur in library covers and Expanded banners. Decode sizes are cached in 64-pixel buckets; original cover/hero choices remain unchanged.
- Six appearance presets and independent accent/background/surface colors with live preview and mode-aware contrast.
- Persistent Compact, Comfortable and Expanded profile layouts.
- Artwork enlargement, zoom, pan, reset and keyboard/button closing.
- Additive settings compatibility; old preferences retain their values and default profile size is Comfortable.
- HLTB Explorer deferred because permissions and reliability are not established. Ratings remain V3 scope.

## 2.0.0 - stabilized, prepared, not published
Compared with V1: session and active-time tracking, launch/process integration, activity dashboard/history, collections and manual progress/executable import.
Stabilization: clean engine/window teardown before COM shutdown, package-derived Settings version, standard DualSense Raw Input activity alongside XInput and keyboard/mouse, no-op polling notification reduction and bounded asynchronous artwork loading.

## 2.0.0-rc.1
Existing V2 source preserved as a release candidate. Original owner acceptance was pending at that point; subsequent owner testing identified the stabilization issues above.

## 1.0.0 - historical source
Genuine pre-V2 source was recovered from Git history: selective Steam imports, metadata/artwork, HLTB matching, statuses, favorites, search/filter/sort and basic appearance. This entry does not invent an earlier public binary release.
