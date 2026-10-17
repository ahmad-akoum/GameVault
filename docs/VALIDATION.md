# Validation — 6 October 2026

## Final tooling

- Flutter 3.38.5 / Dart 3.10.4; Windows 11 and Visual Studio 2022 detected by
  flutter doctor with no development-toolchain issues.
- dart format: all source, tests and diagnostic tools formatted.
- flutter analyze: no issues.
- flutter test: **32 tests passed**.
- flutter build windows --release: succeeded; full runtime output in
  build/windows/x64/runner/Release.

## Real integrations (no mocked production responses)

Read-only scan of the local Steam installation and libraryfolders.vdf discovered
four linked libraries and **33 installed app entries**, with one scan notice.
The manifest parser verified app identity, installation state and common folders.
Steam utilities/demos are presented as selectable entries rather than inferred games.
No Steam installation was modified.

WebsiteHltbProvider made real network lookups:

| Search | Results | Main / Extras / Completionist, hours |
| --- | ---: | --- |
| Elden Ring | 6 | 60.1 / 101.4 / 136.2 |
| Portal 2 | 6 | 8.6 / 13.8 / 22.9 |
| Red Dead Redemption 2 | 1 | 50.8 / 84.6 / 195.7 |
| Final Fantasy | 20 | Broad search; candidate titles returned |
| gamevault no such game qzxv9893 | 0 | No fabricated result |
| Black Myth: Wukong, actual UI import | 1 | 37.8 / 48.4 / 67.4 |

These are observed community averages at test time, not bundled application data
or guarantees of future values. Raw probe output is in integration_probe.txt.

The first older HLTB endpoint attempts (/api/find/init and /api/s/init) returned
404. The live homepage scripts exposed /api/search/site/init and /api/search/site.
The current initialization returned a token and the search POST accepted it.
GameVault's provider was changed to that tested protocol. The provider remains
replaceable because no official stable public API is assumed.

## Actual rendered Windows UI

Using the computer-use skill, launched the release in the isolated build/ui_qa
folder and inspected the rendered application, including:

- Empty Home and its scan action.
- Real scan results and artwork-loaded rows.
- Selecting only Black Myth: Wukong from 33 detected entries, then adding it.
- One saved GameVault game and the changed detected row showing In your vault;
  already-imported entry disabled, no automatic bulk import.
- Library cover grid and title/status/HLTB summary.
- Detailed hero artwork, real Steam metadata and all three HLTB values.
- Favorite toggle and Playing status edit; checked values saved to disk.
- Light theme and rose accent; primary surfaces stayed neutral.
- Custom RGB/hex color dialog.
- A live narrow-window resize showed the compact navigation rail and wrapped
  Settings copy. Automated tests cover exact 880x620, 1280x840 and 2560x1440 sizes.
- Closed and restarted the final release: saved game, cached artwork, Playing,
  favorite, light theme and rose accent all reappeared.

The first Windows automation typing/indexed-action attempts did not update the
search field reliably through the automation helper. Coordinate selection worked.
Title search itself was verified using Flutter widget text-input testing.
No claim is made that every native interaction was manually tested.

## Automated coverage

- KeyValues nested blocks, comments, Windows escaping and malformed syntax.
- Invalid libraries, empty libraries, multiple linked paths, duplicate manifests,
  missing installation folders and incomplete StateFlags.
- Selective imports and repeated-import prevention.
- Status/favorite edits during enrichment are retained.
- Removal removes the saved entry; production has no Steam file mutation path.
- Full data/settings/HLTB round trip, concurrent writes, corrupt-file recovery,
  schema-damaged primary preservation, write failure rollback and relative cache paths.
- HLTB response unit conversion, invalid schema, network failure, rate-limit cooldown,
  conservative title/AppID matching, ambiguous selection and failed-refresh cache retention.
- Home/Settings layouts at three sizes, populated small-window details, removal
  confirmation/cancel, small artwork fallback, theme persistence and library search.
- Finished filter includes both Completed and 100% Complete statuses.

Network-error and ambiguity cases use deliberate test doubles. The actual Windows
network was not disabled; physical controller input and V2 tracking were not tested
because V2 is not implemented. Native folder browsing is provided by file_selector;
its Windows plugin compiled, but a full manual browse-and-import cycle was not
completed (the real library path was supplied to the isolated QA configuration).

## Limits and handoff

HLTB and Steam public metadata/artwork endpoints can change, return missing data
or block requests. HLTB fallback discovery is bounded and best effort. A broad
search returns at most 20 candidates; an alternate title can narrow it. Unknown
playtime/story progress is omitted. Steam local manifests do not reliably distinguish
all games from utilities. JSON replacement can fall back to the prior good version
after a crash; this is recoverable local storage, not a database transaction.

Data is portable beside each executable. Debug and Release have separate default
vault_data folders; keep that in mind when switching launch methods. This V1 ships
as a release folder, not an installer. Other machines may require the standard
Microsoft Visual C++ runtime. Existing local development and release testing worked.

The user-facing release has no QA games or preconfigured Steam folders. All test
persistence was isolated within gamevault/build. GameVault is closed at handoff.
The only lasting new folder beside the existing Flutter projects is gamevault.

## Normal development launch

Also ran `flutter run -d windows` with only an isolated QA data-directory
dart-define added. Dependency resolution, the Windows Debug build and application
launch succeeded; Flutter exposed its normal hot-reload controls. Closed the
application afterward. Both Debug and Release executables were built.
