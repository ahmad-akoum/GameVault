# Narrow Windows layout — V2.2 development polish

## Behavior and cause
GameVault can request a minimum window size of 360 × 620 logical pixels, down
from 880 × 620. The previous width was an explicit `WindowOptions.minimumSize`
restriction, rather than a game-library or database limitation. The existing
Windows `window_manager` plugin applies it to `WM_GETMINMAXINFO.ptMinTrackSize`
after multiplying by the display scale. No native runner or plugin was changed.
Windows decides which Snap layouts are offered; a slot narrower than the scaled
minimum still cannot fit the app. This change does not add a custom Snap menu.

Below 600 logical pixels, a menu button opens the full navigation drawer so a
permanent sidebar does not consume the content width. At larger widths the
existing compact/full sidebars remain. Navigation itself scrolls if needed.
The titlebar caption stays on one line without displacing window buttons.

## Main files and decisions
- `lib/main.dart`: native minimum size and safe titlebar caption truncation.
- `lib/ui/vault_shell.dart`: drawer breakpoint, reduced narrow page margins and
  scrollable navigation. Closing the drawer preserves the existing destinations.
- `lib/ui/responsive.dart`: `AdaptiveRow` stacks controls according to the local
  available width, including inside dialogs. Wide rows retain their alignments.
  Flexible row children lose their horizontal flex when stacked. `ResponsivePage`
  gives narrow filter/result pages one vertical scroll so controls cannot crowd
  results out of a fixed-height viewport.
- `components.dart`: headings stack their actions; grids can use one column and
  accommodate enlarged text. Grids inside a page scroll shrink to their content;
  bounded library grids retain lazy scrolling. Empty-library prompts can scroll.
- Library, collections and detected-game pages adapt their filters/results;
  profiles stack completion-time panels, metadata and action rows. Activity keeps
  its existing seven-day chart with tighter narrow column spacing and wraps long
  ranking durations under titles. Wide ranking rows retain trailing durations.
- Settings retains its existing controls; idle/focus dropdowns now constrain
  their selected text rather than overflowing with enlarged fonts. No values,
  tracking decisions or persistence rules changed.
- `artwork_manager.dart` uses wrapping cover/banner choices and footer actions;
  current-banner previews respect the narrow dialog width. Its content scrolls
  while Apply/Cancel remain outside the scroll. `artwork_viewer.dart` stacks its
  title and wrapping zoom/close toolbar on narrow windows. Image providers,
  caching, cover/hero choices and stable image-stream behavior are unchanged.

Recent-session polish is documented in `session_statistics.md`. No model,
tracker, input, accounting or storage implementation changed for this work.

## Verification and manual acceptance
`test/responsive_layout_test.dart` exercises Home, library, collections,
detected games, all profile sizes, sessions, Activity, Settings, color dialogs,
artwork management and the viewer at 360/400/480/600/880/1280 logical pixels.
It checks bottom controls can be reached by scrolling, long game titles and
durations, enlarged text in Light mode, Dark mode, drawer destinations and the
desktop titlebar's overlay ancestry. Session serialization is compared before
and after rendering. Existing tests cover presets/custom colors and stable
artwork during periodic refreshes. Existing navigation tests explicitly select
the page scroll rather than the newly scrollable navigation or selectable text.

Native Snap interaction is a manual acceptance check, not simulated by widget
tests. On the owner's Windows display/scaling, snap GameVault into both narrow
side slots, visit every destination, scroll to bottom actions, open/import and
cancel artwork, enlarge artwork and check zoom/close. Repeat at normal width,
with preferred themes and profile sizes. Inspect Recent sessions for readable
timestamps, exact durations and end status without horizontal activity bars.

Known limitation: at narrow widths, the Expanded profile banner can crop more
aggressively than the Comfortable layout. The selected artwork is preserved;
this is a presentation issue reserved for a future update.

Automated result for 2.2.0-dev.4+7: all 119 Flutter tests pass, static analysis
is clean, both existing native input suites pass, and Windows Debug builds.
A native window query confirms 360 × 620 logical minimum pixels at 96 DPI.
Startup and normal shutdown exit 0 with a separately verified disposable copy
of the current development vault; its vault document is unchanged afterward.
No interactive Snap or new hardware gameplay testing is claimed. Both original
vaults match their independent private backups, and existing V2.0/V2.1 ZIPs
and the preserved V2.1 runtime remain unchanged. No publication or tag created.
