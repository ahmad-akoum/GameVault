# Artwork positioning and display modes - V2.4.1 Phase 4

Manage Artwork keeps independent cover/banner choices and now offers three modes:

| Mode | Rendering |
| --- | --- |
| Crop to fill | Fills the slot; normalized horizontal/vertical position and 1-3x zoom select the visible region. |
| Fit entire image | Centers the complete image, preserving its aspect ratio. |
| Fit with blurred background | Centers the complete image over an edge-to-edge blurred copy of the same source. |

The preview updates while moving sliders. Reset Position and Zoom recenters crop
at 1x; Restore Default previews the original file with centered default cropping.
Apply persists only the selected slot. Cancel discards pending changes; earlier
Apply actions remain saved. Switching slots reloads that slot's saved preferences.
Position controls affect axes with actual cropping. Zoom only applies to Crop to
Fill; switching fit modes retains the draft crop values for switching back.
The enlarged viewer still shows the full original for inspection, not a baked crop.

## Files and decisions

- `models/artwork_presentation.dart`: immutable ArtworkPresentation/ArtworkFit,
  normalized positions (-1 to 1), zoom and additive JSON. Invalid persisted numbers
  are bounded; unknown modes fall back to crop.
- `models/game.dart`: ArtworkPreferences stores optional coverLayout/heroLayout.
  Older coverContained/heroContained values supply defaults when new fields are
  absent, preserving existing vault appearance without a bulk migration.
- `state/vault_controller.dart`: applyArtwork saves the selected slot through the
  existing serialized mutation queue, retaining the other slot, source paths,
  default choices, metadata and latest sessions. Metadata refresh preserves layouts.
- `ui/artwork_manager.dart`: mode chips, labeled position/zoom sliders, reset,
  live preview, independent Apply/Cancel/default behavior.
- `ui/components.dart`: GameArtwork applies the presentation in library cards,
  profiles and previews. The outer clip plus aligned zoomed box and aligned image
  compose the desired crop without stretching or rewriting source files.
- `ui/artwork_image.dart`: existing synchronous image-provider keys and intrinsic
  decode sizing remain in use. Crop zoom requests proportionally more physical
  pixels; the decoder never invents resolution beyond the source.

Blur uses ImageFiltered on a bounded 256px background decode with a reused blur
filter and a repaint boundary. The full foreground uses a display-sized contain
decode. This avoids reprocessing or saving image files, huge background decodes,
global cache increases and unnecessary repeated decoding. Repeated tracking-style
rebuilds retain synchronous cache resolution and visible frames. Corrupt/missing
images use existing placeholders/fallbacks. Themes use existing ColorScheme colors.

Legacy rendering stays unchanged until the user chooses a new mode/position.
No artwork source, personal image, cover/hero distinction or Steam installation is
modified. Settings are per game/slot, not per alternative image. The viewport's
aspect ratio still affects the visible crop; the manager uses a representative
slot shape. Fit Entire or Blurred mode can preserve the entire artwork at any size.
Low-resolution sources and large zoom cannot recover missing original detail.

## Tests and acceptance

`test/artwork_presentation_test.dart` verifies legacy defaults, bounded malformed
values, JSON/save/reload, independent slots, metadata refresh, unchanged source
bytes/sessions, portrait/landscape/square sources in all modes, decode budgets,
crop pixels at opposite positions, zoomed geometry, cached visible frames and
narrow manager preview/Cancel. Existing artwork import/default/refresh, overlay,
image-quality, responsive and flicker regressions remain required.

These are automated synthetic-image checks. Owner visual acceptance should compare
portrait banners and landscape/square images at all profile sizes, try both slots,
Apply/restart, Cancel/default restore, and verify normal scrolling/game launches.
No new real-game hardware or GPU transition testing is claimed by this feature.

The focused artwork suites passed 32 tests independently of the focused playtime
checks. Final combined verification passed 237 Flutter tests (two live checks
skipped), clean analysis, both native suites and an isolated x64 Release build
with graceful startup/shutdown. Owner visual acceptance is still required.
