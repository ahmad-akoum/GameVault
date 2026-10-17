# Temporarily paused HowLongToBeat lookup

## What users see

V2.2.0 keeps every locally saved HowLongToBeat estimate and saved match in the
vault and displays them on the game profile. New live searches and refreshes are
temporarily unavailable pending an authorized integration.

## How it works

`main.dart` supplies `DisabledHltbProvider` to `VaultController`. That provider
returns an unavailable result immediately and has no HTTP client, website
endpoint, or script-inspection code. `VaultController.importGames` no longer
starts an HLTB lookup after Steam metadata enrichment. The profile in
`ui/details_page.dart` shows a clear notice and renders saved estimates and saved
candidate matches from the existing `VaultGame` fields. Selecting a candidate
already stored in the vault is a local operation.

The model, JSON field names and migration behavior in `models/game.dart` remain
unchanged, so existing personal vault values are preserved. Metadata refreshes
copy the current game record and do not clear HLTB values.

## Why

The earlier provider relied on undocumented website endpoints and inspected
website scripts to discover endpoint changes. No authorized integration was
established. Removing the network adapter from the application and disabling
the profile controls prevents new automated retrieval. This limited change does
not claim to settle every licensing question about previously retrieved data.

## Verification

`test/services_test.dart` checks that the public provider fails closed and that
game import makes no HLTB request. `test/v2_widgets_test.dart` checks that saved
estimates and saved matches remain visible, the paused status is clear, and
search/refresh controls are absent. Existing vault round-trip tests continue to
cover saved HLTB fields.
