# Theme Studio

Settings opens a draft editor for appearance mode, accent, background, surface,
and an optional gradient. Quick swatches, a saturation/brightness field, hue
and shade sliders, and hex input all edit the same selected color. Select a
gradient stop to edit it with the same controls. Direction and intensity only
affect the backdrop. Reset and Surprise me edit the draft; Apply saves it and
Cancel discards it.

ThemeEditor owns the draft. VaultSettings persists a validated VaultGradient
with two to five opaque colors; older settings stay solid. vaultBackdrop
uses the same brightness-adapted colors in the preview and the main content
pane. Cards and controls keep their existing contrast-managed surfaces.

Theme editor tests cover legacy and malformed data, draft application,
three-stop serialization, and both brightness modes. Existing appearance and
responsive tests cover cancel behavior and opening the editor at narrow widths.

Apply clears the old custom appearance before applying the draft. This keeps
a reset Background or Surface at its default even when the other color was
edited afterward. Regression tests cover both directions, Cancel and reloading
the settings submitted by Apply.
