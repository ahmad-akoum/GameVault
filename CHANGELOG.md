# Changelog

This history distinguishes preserved source from published releases. Import dates
are not original release dates; no historical public release is asserted.

## Unreleased

- V2.1 ratings remain research only; no API credentials or provider code are included.
- Stable V2 requires owner acceptance testing and explicit approval.

## 2.0.0-rc.1 — publication candidate prepared 2026-10-14

Existing V2 implementation recovered from the 2026-10-13 local development checkpoints.

### Added

- Steam/local executable launching and manual Windows game imports.
- Native process/focus/input observations and configurable active-time accounting.
- Separate elapsed/active session totals, activity summaries and session history.
- Collections and manual completion percentages.
- Additive V1 migration, checkpoints, interrupted-session recovery and data-folder locking.

### Improved

- Desktop Home, Activity, details and tracking controls with responsive layouts.
- Exact-executable priority and conservative handling of duplicate/ambiguous process matches.
- Session identity, reload state and malformed/duplicate session recovery validation.

### Preserved

- Selective Steam imports, multi-library discovery, recognized non-game exclusions,
  metadata/artwork, HLTB matching, favorites, statuses and appearance settings.

### Publication preparation

- Privacy-clean source imports, Flutter/user-data exclusions, documentation and release policy.
- Application code and dependency manifests are unchanged from the existing V2 checkpoint.
- Source-only candidate; no existing local executable is relabeled or uploaded.

## 1.0.0 — historical source checkpoint

Genuine pre-V2 source exists at original local commit `664de5f`, recorded 2026-10-13.
The original V1 release date is not established by that checkpoint.

- Selective Steam-library discovery/import, metadata and artwork.
- HowLongToBeat matching, favorites, statuses, search/filter/sort and appearance settings.
- Version-1 local JSON persistence and recovery support.
- Scanner already includes the multi-drive discovery and non-game filtering fixes.

The `v1.0.0` tag preserves this source. No downgraded V1 was manufactured, and no
V1 binary build or fresh acceptance test is claimed during publication preparation.
