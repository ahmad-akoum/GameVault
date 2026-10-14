# Publication validation

Publication preparation is separate from personal acceptance testing.

## Historical V2 evidence

The retained private development report records 53 automated tests passing, clean
static analysis, a successful Windows release build, and native fixture checks for
launch/process tracking, termination, persistence and duplicate association.
These checks used isolated data. They do not establish real-game/controller acceptance.

## Current preparation — 2026-10-14

- Genuine V1 and V2 source snapshots identified and imported without private reports.
- All original history inspected: 92 unique blobs; no matches for four stored research
  credentials, common credential signatures or suspicious literal secret assignments.
- Historical Steam inventories, machine diagnostics and personal-library screenshots
  excluded from every publishing commit. The original repository remains intact.
- Fresh `flutter analyze --no-pub`: passed with no issues.
- Fresh `flutter test --no-pub`: all 53 tests passed in the isolated publishing checkout.
  Expected negative-test diagnostics appeared for malformed HLTB data and denied writes.
- Dependency resolution retained the existing lockfile. The first attempt required
  the existing plugin-junction preparation script, then succeeded without system changes.
- No new Windows release build was necessary for source-only publication; the original
  binary and vault hashes remain unchanged. No binary asset is proposed.
- Publishing history and source identity are checked separately before upload.
- Owner acceptance testing: pending. No stable v2.0.0 release approved.

Pattern-based security checks reduce risk but cannot prove arbitrary secrets absent.
No application source or existing user data was changed for publication preparation.
