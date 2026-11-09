# Roadmap

V2.4.1 introduced local Steam lifetime estimates,
explicit historical reconciliation and cover/banner positioning. V2.3 restored
live HowLongToBeat search, selection and refresh; later versions retain it as
an unofficial integration. Service availability and authorization are not assumed.

## V2.5.0

Theme Studio, optional close to tray, read-only Storage Overview and profile
cleanup are included. Exit waits for Steam sidecar writes and offers a retry if the final session save fails.
GameVault reports Running while an observed game is open; exit remains with
the game itself.

## Later candidates

- Verified vault export and guided recovery, preserving artwork, sessions and
  Steam playtime data. Restore requires compatibility checks and explicit review.
- Retention of library entries when a game is uninstalled, with clear location
  and launch states. Library convenience changes can follow observed needs.
- Additional launchers, cloud sync, automatic update initiation and automatic
  story completion are out of scope for V2.5.
- V3 ratings remain research only. Verify provider access, platform matching,
  attribution and caching rights before implementation. Keep credentials out
  of distributed desktop binaries.

Measure real large-library or high-refresh bottlenecks before optimizing.
Later releases require their own scope, tests, source/build verification and
owner approval.
