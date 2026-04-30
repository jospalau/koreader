# Font-family font picker — design

## Motivation

Bookends overlays currently store a specific TTF file as the font face. This is brittle across devices (different users have different font libraries) and actively hostile to the planned preset gallery — a shared preset pointing at `EB Garamond.ttf` renders as the fallback font on any user who doesn't have that file.

KOReader already solves this for document text via its **Settings › Font › Font-family fonts** mapping (`cre_font_family_fonts` setting), where users assign a specific font to each of the CSS generic families: serif, sans-serif, monospace, cursive, fantasy. Plus there's always a UI font in effect (`Font.fontmap.cfont`).

This feature adds that same abstraction to bookends: overlays can choose a font *family* (e.g. "serif"), and at render time the family resolves to the user's locally-mapped font. Presets become portable; users can still pick specific fonts when they want to.

## Scope

**In scope:**

1. Six selectable font-family entries in the bookends font picker: UI font, Serif, Sans-serif, Monospace, Cursive, Fantasy.
2. Sentinel storage format (`@family:<key>`) in the existing `font_face` field — no schema migration.
3. Render-time resolution to the current mapping via `G_reader_settings:readSetting("cre_font_family_fonts")` and `Font.fontmap.cfont`.
4. Graceful fallback: unmapped families render as UI font, matching KOReader's own family fallback semantics.
5. Label rendering everywhere the font name is shown (main menu, line editor, picker title, picker row).
6. One new README subsection explaining the feature and its relationship to KOReader's menu.

**Out of scope:**

- Per-book family mapping (KOReader supports per-document overrides; bookends sticks to the global map for v1).
- Emoji, math, fangsong families — unusual choices for overlay text.
- A bookends-specific family remap UI. Users configure families in KOReader's existing menu; bookends reads the result.
- Font bundling or download of missing fonts.
- Changes to the default `font_face` setting value (new installs still get the existing default TTF; users opt into families by picking one).

## Architecture

Additive. Four files touched. No new modules.

| File | Change |
|------|--------|
| `utils.lua` | Add `FONT_FAMILIES` constant, `FONT_FAMILY_ORDER` array, `resolveFontFace(face, fallback)`, `getFontFamilyLabel(face)`. |
| `main.lua` | One-line use of `utils.resolveFontFace` in `resolveLineConfig` before `Font:getFace`. Picker (`showFontPicker`) gains a "Font-family fonts" section at the top of page 1. Picker title row uses `getFontFamilyLabel` for family values. |
| `menu/main_menu.lua` | Font-setting menu label uses `utils.getFontFamilyLabel` for family values, falls back to existing logic otherwise. |
| `line_editor.lua` | Same label treatment for the per-line font button. |
| `README.md` | New subsection "Using KOReader's font families" under Settings. |

No changes to preset save/load, `overlay_widget.lua`, or any other menu file.

## Components

### Storage format

Family selections are stored in the existing `font_face` string field with an `@family:` prefix:

| Sentinel | Resolves to |
|---|---|
| `@family:ui` | `Font.fontmap.cfont` (picks up any UI-font patch) |
| `@family:serif` | `cre_font_family_fonts.serif` |
| `@family:sans-serif` | `cre_font_family_fonts["sans-serif"]` |
| `@family:monospace` | `cre_font_family_fonts.monospace` |
| `@family:cursive` | `cre_font_family_fonts.cursive` |
| `@family:fantasy` | `cre_font_family_fonts.fantasy` |

Unambiguous because no valid TTF path starts with `@`. Old presets and existing settings with TTF paths pass through unchanged.

### `utils.FONT_FAMILIES` constant

```lua
local FONT_FAMILIES = {
    ui             = _("UI font"),
    serif          = _("Serif"),
    ["sans-serif"] = _("Sans-serif"),
    monospace      = _("Monospace"),
    cursive        = _("Cursive"),
    fantasy        = _("Fantasy"),
}
local FONT_FAMILY_ORDER = { "ui", "serif", "sans-serif", "monospace", "cursive", "fantasy" }
```

### `utils.resolveFontFace(face, fallback)`

```lua
function utils.resolveFontFace(face, fallback)
    if type(face) ~= "string" then return fallback end
    local family = face:match("^@family:(.+)$")
    if not family then return face end
    if family == "ui" then
        return Font.fontmap and Font.fontmap.cfont or fallback
    end
    local map = G_reader_settings:readSetting("cre_font_family_fonts") or {}
    local mapped = map[family]
    if mapped and mapped ~= "" then return mapped end
    -- Unmapped family → UI font (matches KOReader's family fallback)
    return Font.fontmap and Font.fontmap.cfont or fallback
end
```

Called once per rendering site. `face` is passed through unchanged when it isn't a sentinel, so non-family callers see zero behaviour change.

### `utils.getFontFamilyLabel(face)`

Returns a table describing how to display the selection, or `nil` when the face is not a family sentinel:

```lua
function utils.getFontFamilyLabel(face)
    if type(face) ~= "string" then return nil end
    local family = face:match("^@family:(.+)$")
    if not family then return nil end
    local human = FONT_FAMILIES[family] or family
    local resolved = utils.resolveFontFace(face, nil)
    local FontList = require("fontlist")
    local display
    if resolved then
        display = FontList:getLocalizedFontName(resolved, 0)
               or resolved:match("([^/]+)%.[tT][tT][fF]$")
               or resolved
    end
    local is_mapped = false
    if family == "ui" then
        is_mapped = true
    else
        local map = G_reader_settings:readSetting("cre_font_family_fonts") or {}
        is_mapped = map[family] and map[family] ~= ""
    end
    return {
        label     = human .. " (" .. (is_mapped and display or _("UI font")) .. ")",
        is_family = true,
        is_mapped = is_mapped,
        resolved  = resolved,
    }
end
```

Three consumers:
- Picker row text
- Picker title row
- Main menu + line editor labels

### Picker UI changes

Layout (page 1 only):

```
Select font: <current label in its own typeface>
──────────────────────────────────────────
── Font-family fonts ──                     ← dim header
✓ UI font       (FS Me)                     ← each row rendered in its own resolved face
  Serif        (EB Garamond)
  Sans-serif   (Noto Sans)
  Monospace    (JetBrains Mono)
  Cursive      (UI font)                    ← renders in UI font
  Fantasy      (UI font)                    ← renders in UI font
── Fonts ──                                 ← dim header
  Atkinson Hyperlegible
  ...
```

Mechanics:
- Family rows are inserted at the top of page 1 only. Pages 2+ are unchanged.
- `on_select(face)` receives `"@family:<key>"` when a family row is tapped; callers treat the string identically to how they treat a TTF path today.
- Each row's label is rendered in its resolved face at the picker's row font size — so the user previews exactly what they're picking.
- `✓` selected-indicator logic compares against the full `font_face` string (TTF path or sentinel) unchanged.
- Scroll-to-current stays as-is: if the current face is a family sentinel, the picker opens on page 1 (where families live).

### Menu and line-editor labels

At both call sites, check for a family value first:

```lua
local fam = utils.getFontFamilyLabel(face)
if fam then
    name = fam.label
else
    name = FontChooser.getFontNameText(face)    -- existing path
end
```

Produces labels like `"Serif (EB Garamond)"` or `"Cursive (UI font)"` in the overview menus. Users always see what will actually render.

## Data flow

Unchanged — only the face-string domain widens.

1. User opens font picker from menu or line editor.
2. Picker shows 6 family rows plus specific-font list.
3. User taps a row; callback receives either a TTF path (existing behaviour) or `@family:<key>` (new).
4. Caller saves string to its settings slot.
5. On paint, `main.lua` reads the stored face and calls `resolveLineConfig(face, ...)`.
6. `resolveLineConfig` calls `utils.resolveFontFace(face, defaults.font_face)` to get a TTF path.
7. `Font:getFace(resolved_face, scaled_size)` as today.

## Error handling

All edge cases resolve to a readable font rather than crashing:

| Case | Behaviour |
|---|---|
| `face` is a sentinel for an unmapped family | Resolves to UI font (via `Font.fontmap.cfont`). |
| `face` is a sentinel with an unknown key (e.g. `@family:unknown`) | Falls through to UI font. Label reads `"unknown (UI font)"`. |
| `Font.fontmap.cfont` is nil (deeply pathological) | Returns caller's `fallback`; `Font:getFace(nil)` itself falls back. |
| `cre_font_family_fonts` setting is absent | Treated as empty map; all families render as UI font. |
| Default bookends font (`defaults.font_face`) is itself set to `@family:ui` | No recursion — `resolveFontFace` handles `@family:ui` directly. |

## State invalidation

KOReader's family map and UI font are read via live lookups (`G_reader_settings`, `Font.fontmap`) at render time. No cache inside bookends, so changes in the KOReader Font-family fonts menu propagate on the next repaint.

No new event subscriptions needed — KOReader's font-settings dialogue closes with a re-render that already repaints the reader. Bookends' existing dirty-on-reader-refresh plumbing covers it.

## Testing

Manual validation on Kindle per standard workflow:

| Check | Method | Expected |
|---|---|---|
| UI font family selectable | Pick "UI font" in picker | Overlay renders in `Font.fontmap.cfont` (e.g. "FS Me" if patched, else "NotoSans-Regular") |
| Serif maps correctly | Pick "Serif" in picker; verify `cre_font_family_fonts.serif` is set to a known font | Overlay renders in that font |
| Unmapped family falls back to UI | Clear the fantasy mapping in KOReader; pick "Fantasy" | Overlay renders in UI font; label shows "Fantasy (UI font)" |
| Live re-mapping | With "Serif" selected, change the serif mapping in KOReader settings | Next page turn → overlay uses new font |
| Specific-font selection unchanged | Pick a TTF from the existing list | Behaves exactly as before |
| Label in main menu | Set global default to `@family:serif` via picker | Menu shows `"Serif (<actual serif>)"` |
| Label in line editor | Set per-line font to `@family:cursive` | Line editor button shows `"Cursive (...)"` |
| Preset portability | Save preset with `@family:serif`; reload on a device with a different serif mapping | Overlay renders with the new device's serif font |
| No stale caches | Zero-cost verify — confirm `resolveFontFace` reads `G_reader_settings` fresh each call |

## README

New subsection under **Settings** (`<details>` block), titled *"Using KOReader's font families"*. Two paragraphs:

> Bookends' font picker includes KOReader's font-family slots: UI font, Serif, Sans-serif, Monospace, Cursive, and Fantasy. Pick a family instead of a specific font, and overlays will use whichever font you have mapped to that slot in **Settings › Font › Font-family fonts**. This keeps overlay appearance consistent with the document font and makes presets portable across devices — someone sharing a preset that picks "Serif" will have it rendered in your serif, not theirs.

> If a family slot isn't mapped, the overlay falls back to your KOReader UI font. That's the same behaviour KOReader itself uses — if you see overlay text rendering in the UI font when you expected something else, check your KOReader **Font-family fonts** menu.

## Release notes line

> Font picker now includes KOReader's font-family fonts — pick "Serif", "Sans-serif", "Monospace", "Cursive", "Fantasy" or "UI font" instead of a specific typeface, so overlays follow your KOReader font settings. Presets that use a family will render with the destination device's fonts.

## Commit plan

Feature branch: `feature/font-family-picker` cut from `master`. Iterative commits during development; squash before tagging — no tag until further user-facing work accumulates (see project release cadence).

Final squashed commit message:
> `feat: add font-family font choices to the font picker`
