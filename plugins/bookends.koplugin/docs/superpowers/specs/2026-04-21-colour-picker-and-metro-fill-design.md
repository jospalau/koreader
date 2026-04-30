# Colour picker for colour devices & metro fill — design

## Motivation

Two related but independent gaps in the colour system.

1. **Metro progress bar has no visible read portion.** Its trunk is painted in a single `metro_track` colour; progress is indicated only by the moving dot, and chapter ticks are painted uniformly regardless of whether the reader has already passed them. All other bar styles (bordered, wavy, thin) show a visible fill over the read portion. `bookends_overlay_widget.lua:961` reads `metro_fill` into a local and never paints with it — the hook for the feature already exists.
2. **No colour picker for colour devices.** Every colour setting today (`text_color`, `symbol_color`, `bar_colors.{fill,bg,track,tick,border,invert}` global & per-bar) is edited via a `% black` nudge that writes a greyscale byte. Users on Kindle Colorsoft / Kobo Libra Colour / Boox Go Color can't pick actual colours. Gating-capable Blitbuffer primitives (`ColorRGB32`, `Screen:isColorEnabled()`) already exist in KOReader — the plugin just doesn't use them.

The two ship independently: metro fill is device-agnostic and trivial; the colour picker is larger, colour-device-gated, and benefits from a community pre-release cycle.

Reference implementation for the picker: [appearance.koplugin](https://github.com/Euphoriyy/appearance.koplugin) — an HSV colour wheel with separate brightness nudge, proven on colour e-ink devices. GPL-3.0, same license as Bookends. The Bookends port adapts it to a per-field picker across the plugin's colour surface.

## Scope

**In scope — v4.2.0 (metro fill):**

1. New optional field `bar_colors.metro_fill` (same shape as other `bar_colors.*` fields).
2. Metro render paints the read portion in `metro_fill` when distinct from `metro_track`; pixel-identical to today when unset.
3. Chapter ticks "caught up to" by progress paint in `metro_fill` instead of `metro_track`. Automatic, not toggleable.
4. New menu item "Metro read color" in `menu/colours_menu.lua`, grouped next to "Metro track color".
5. Added to `saveColors()` all-empty check so clearing every field removes the `bar_colors` blob.
6. Preset save/load requires no schema change — existing opaque-blob serialisation handles the new field.
7. One new translatable string; English .pot regeneration + placeholder entries in other locales.

**In scope — v4.3.0 (colour picker):**

1. New widget `bookends_colour_wheel.lua` — HSV wheel + brightness nudge + hex entry, ported from appearance.koplugin. GPL-3.0 preserved. Upstream-commit-SHA comment at file head.
2. Bookends-facing API `Bookends:showColourPicker(title, current_hex, default_hex, on_apply, on_default, touchmenu_instance)` mirroring the existing `showNudgeDialog` shape. Cancel/Default/Apply button row per plugin convention.
3. Hex-string storage: `{ hex = "#RRGGBB" }` alongside the existing `{ grey = 0xNN }`. Discriminated by field presence — no migration.
4. Central `parseColorValue(v)` helper in `bookends_overlay_widget.lua` with memoised parsing. Returns `ColorRGB32` on colour-enabled screens, `Color8` of luminance on greyscale screens (for cross-device preset portability).
5. Menu-side entry branch: `Screen:isColorEnabled()` at picker invocation time — picker on colour devices, existing `% black` nudge on greyscale. One branch point in a shared helper, picked up automatically by every call-site.
6. Cache flush on `onColorRenderingUpdate` event (KOReader broadcasts this when the user toggles colour rendering at runtime).
7. Preset gallery `🎨` flag: upload-side scan in the bookends-presets review tooling, install-side glyph in `preset_gallery.lua`.
8. README "Acknowledgements" section crediting appearance.koplugin, explicitly noting the port was done without colour-device hardware and leans on upstream's proven design.
9. Release notes for v4.3 include the same attribution + request for tester feedback.
10. Unit tests for `parseColorValue` (hex parse + luminance fallback) in the existing `_test_conditionals.lua`-style runner pattern.

**Out of scope:**

- **Inline `[c=N]` segment colour in format strings.** Requires syntax extension (`[c=#RRGGBB]` alongside greyscale `[c=N]`) and line-editor token-picker changes. Deferred to a later feature.
- **Greyscale-preview toggle inside the picker.** Lets preset authors catch luminance collisions at design time. Nice-to-have; deferred — ship v4.3 and revisit if community reports collision problems.
- **Per-field manual greyscale overrides** (author sets `{hex="#FF0000", grey=0x40}`). Adds UX complexity for a corner case; deferred.
- **Per-style independent fill/bg/tick fields.** metro_fill is a one-off exception (metro is deliberately visually distinct). No wavy-specific or bordered-specific colour fields added in this plan.
- **Colour management / ICC / gamut-awareness.** KOReader has no colour profile support on Kaleido; not addressable here.
- **HSL lightness alternative to HSV brightness.** Port upstream as-is for v4.3; HSL/lightness is a potential follow-up.

## Architecture

Two phases, two release branches, no dependencies between them.

| Phase | Files touched | Approximate LoC | Release | Risk |
|-------|---------------|------------------|---------|------|
| **1 — metro_fill** | `bookends_overlay_widget.lua`, `menu/colours_menu.lua`, `bookends_i18n.lua` (string tables), `locale/*.po` (placeholder entries) | ~40 | v4.2.0 | Low |
| **2 — picker** | new `bookends_colour_wheel.lua` (~500), `bookends_overlay_widget.lua` (storage-read extension), `menu/colours_menu.lua` (picker branch), `preset_gallery.lua` (🎨 flag), `preset_manager.lua` (has-colour detection), `README.md`, release notes, `main.lua` (event subscription for cache flush), `locale/*.po` | ~700 new + small edits | v4.3.0 | Medium (widget port, hardware untested by author) |

### Phase 1 — metro visible progress

**Render change** in `bookends_overlay_widget.lua` around `lines 941–989`:

```lua
local metro_track = resolveColor(custom_track, Blitbuffer.COLOR_DARK_GRAY)
local metro_fill  = resolveColor(custom_metro_fill, metro_track)  -- default = track

pr(line_ox, line_y, line_len, line_thick, metro_track)

if metro_fill ~= metro_track then
    pr(line_ox + line_fill_start, line_y, line_fill, line_thick, metro_fill)
end

-- tick loop gains an is_read check
for _, tick in ipairs(ticks or {}) do
    -- ... existing tick_frac, tick_pos, tick_above computation ...
    local is_read
    if reverse then
        is_read = tick_pos >= line_len - line_fill
    else
        is_read = tick_pos <= line_fill
    end
    local tick_color = (is_read and metro_fill ~= metro_track) and metro_fill or metro_track
    pr(line_ox + tick_pos, tick_above and line_y - metro_tick_h or line_y + line_thick,
       line_thick, metro_tick_h, tick_color)
end
```

The `metro_fill ~= metro_track` guard is load-bearing: when unset, we skip both the overlay paint and the tick recolouring, producing pixel-identical output to pre-change for all existing users.

**Tick-at-boundary rule:** ticks where `tick_pos == line_fill` count as read (using `<=`). Documented choice; low stakes visually.

**Menu item** in `menu/colours_menu.lua`, `_buildColorItems`, inserted after "Metro track color":

```lua
{
    text_func = function()
        return _("Metro read color") .. ": " .. pctLabel("metro_fill")
    end,
    keep_menu_open = true,
    callback = function(touchmenu_instance)
        colorNudge(_("Metro read color (% black)"), "metro_fill", 100, touchmenu_instance)
    end,
    hold_callback = function(touchmenu_instance)
        bc.metro_fill = nil; saveColors()
        if touchmenu_instance then touchmenu_instance:updateItems() end
    end,
},
```

Default = 100 (black) so a user who invokes the control and taps Apply-at-default sees clear progress; hold-to-reset reverts to track colour.

**`saveColors()` update:** add `and not bc.metro_fill` to the "all empty?" check so clearing every field drops the blob.

### Phase 2 — colour picker

#### Widget — `bookends_colour_wheel.lua`

Ported from appearance.koplugin. Structure preserved: HSV wheel (hue = angle, saturation = radius), brightness `-/+` nudge above, current-colour swatch + hex label below, Cancel/Apply button row. Bookends-specific additions:

- Default button between Cancel and Apply when `default_hex` is provided (matches plugin nudge convention).
- Hex field is a tap-to-edit `InputText` that writes back into the wheel (mirrors upstream's "Enter color" control visible in the reference screenshot).
- Dismissable = false (per saved user preference for dialogs).

Upstream-commit-SHA recorded in a comment at the file head; license preserved; adaptations called out.

#### Storage shape

```
-- greyscale device (or setting authored pre-v4.3):
bar_colors.fill = { grey = 0x40 }

-- colour device:
bar_colors.fill = { hex = "#7F08FF" }

-- both shapes coexist; readers branch on field presence
```

No migration. A preset authored pre-v4.3 keeps working forever. A preset authored on a colour device reads on a greyscale device via luminance conversion at paint time.

#### Render path — `parseColorValue` in `bookends_overlay_widget.lua`

```lua
local _hex_cache = {}

local function parseColorValue(v)
    if not v then return nil end
    if v.hex then
        local cached = _hex_cache[v.hex]
        if cached then return cached end
        local r = tonumber(v.hex:sub(2,3), 16) or 0
        local g = tonumber(v.hex:sub(4,5), 16) or 0
        local b = tonumber(v.hex:sub(6,7), 16) or 0
        if Screen:isColorEnabled() then
            cached = Blitbuffer.ColorRGB32(r, g, b, 0xFF)
        else
            local lum = math.floor(0.299*r + 0.587*g + 0.114*b + 0.5)
            cached = Blitbuffer.Color8(lum)
        end
        _hex_cache[v.hex] = cached
        return cached
    end
    if v.grey then return Blitbuffer.Color8(v.grey) end
    return nil
end
```

`resolveColor(value, default)` (the existing helper around line 920) is updated to delegate hex/grey parsing to this. Boolean `false` continues to mean "transparent/skip paint" unchanged; integer (legacy raw byte) path kept for ancient saved-settings compatibility per the 2026-04-12 spec.

#### Cache invalidation

In `main.lua`, subscribe to a KOReader event broadcast on colour-rendering toggle. **Event name unverified at spec time** — candidates include `onColorRenderingUpdate`, `onUpdateFooter`, or a more general refresh event. Implementation step: grep `koreader/frontend` for the broadcast site of `Screen:isColorEnabled()` changes and subscribe to whichever event fires. If none is reliably broadcast, fall back to checking `Screen:isColorEnabled()` at the top of `parseColorValue` and invalidating the cache on mismatch (slightly more expensive but self-healing).

```lua
function Bookends:onColorRenderingUpdate()
    -- flush the parseColorValue cache so subsequent paints reflect the new mode
    require("bookends_overlay_widget"):_flushColorCache()
    self:markDirty()
end
```

Expose `_flushColorCache` from `bookends_overlay_widget.lua` — a one-liner `_hex_cache = {}`. Without this flush, toggling colour rendering at runtime leaves `ColorRGB32` values cached that subsequent greyscale paints would handle via Blitbuffer's default converter rather than our luminance helper.

#### Device-gating branch — `menu/colours_menu.lua`

The shared `colorNudge(title, field, default_pct, touchmenu_instance)` helper gains a colour-device branch:

```lua
local function colorNudge(title, field, default_pct, touchmenu_instance)
    if Screen:isColorEnabled() then
        local current_hex = bc[field] and bc[field].hex
        -- convert grey (if present, e.g. migrated mid-session) to approximate hex
        if not current_hex and bc[field] and bc[field].grey then
            local g = string.format("%02X", bc[field].grey)
            current_hex = "#" .. g .. g .. g
        end
        local default_hex = defaultHexFor(field)  -- e.g. "#000000" for fill, nil for text
        self:showColourPicker(title, current_hex, default_hex,
            function(new_hex)
                bc[field] = { hex = new_hex }
                saveColors()
            end,
            function()
                bc[field] = nil
                saveColors()
            end,
            touchmenu_instance)
    else
        -- existing nudge code, unchanged
        local current_pct = bc[field] and math.floor((0xFF - bc[field].grey) * 100 / 0xFF + 0.5) or default_pct
        -- ...
    end
end
```

Call-site count: 10 — `text_color`, `symbol_color`, plus 8 `bar_colors` fields (fill, bg, track, tick, border, invert, metro_fill, border_thickness-excluded-because-numeric) × {global, per-bar}. `bar_colors` fields route through `colorNudge` in `_buildColorItems`, so a single branch in that helper covers all 16 `bar_colors` call-sites. `text_color` and `symbol_color` are today edited via inline `showNudgeDialog` calls in `buildTextColourMenu` — as part of this work, those two are refactored to route through a shared `textColorPickerOrNudge` helper that also branches on `Screen:isColorEnabled()`. Small refactor; keeps the branch logic in one place per setting family.

#### Preset gallery integration

**Install-side** (`preset_gallery.lua` when rendering a preset card):

```lua
local has_colour = preset.metadata and preset.metadata.has_colour
if has_colour then
    -- render a small 🎨 glyph next to the preset title
end
```

Optional tap-to-expand note: *"This preset uses colour. On greyscale devices, colour values render as their luminance equivalent; some elements may look flatter than intended."*

**Upload/review-side** (the bookends-presets repo's `review-preset-submission` tooling): scan submitted JSON for any table containing a `hex` field; if found, set `metadata.has_colour = true` on the preset record. Also update the plugin-side preset-serialiser so local presets get the flag on save.

#### Attribution

**README.md** (new "Acknowledgements" section near end):

> ### Acknowledgements
>
> The HSV colour-wheel picker used on colour e-ink devices is adapted from [appearance.koplugin](https://github.com/Euphoriyy/appearance.koplugin) by Euphoriyy (GPL-3.0). Since I don't have a colour e-ink device myself, I've leaned heavily on their proven design; if the picker feels off on your Kindle Colorsoft / Kobo Libra Colour / Boox Go Color, please open an issue on the Bookends repo — I can fix the bug, but I can't reproduce hardware-specific visual quirks without your help.

**Release notes (v4.3.0):** short credit line + tester request.

**`bookends_colour_wheel.lua` file header:**

```lua
--[[
Bookends colour wheel — HSV wheel + brightness picker widget.

Ported from appearance.koplugin (Euphoriyy, GPL-3.0):
  https://github.com/Euphoriyy/appearance.koplugin
  Source commit: <SHA at port time>

Adaptations for Bookends:
- Cancel/Default/Apply button row (plugin-wide dialog convention).
- Writes `{ hex = "#RRGGBB" }` into settings directly.
- dismissable = false (plugin-wide dialog convention).

Licence: GPL-3.0 (preserved from upstream). See LICENSE.
]]
```

## Testing strategy

Given the author has no colour e-ink hardware but has a Kindle (greyscale) and KOReader desktop (SDL2, full colour stack):

**Primary verification — KOReader desktop:**
- Widget rendering & interaction: does the wheel draw, does click/drag hit-test map to correct HSV coordinates, does the brightness nudge apply, does hex entry validate, does Cancel/Default/Apply fire correctly.
- End-to-end data flow: pick colour → hex in settings → read by overlay → paints as `ColorRGB32`.
- Luminance fallback: toggle KOReader's "Colour rendering" off mid-session → confirm cache flushes → confirm subsequent paints use `Color8(luminance)`.
- Cross-device preset portability: author preset on desktop (colour-enabled) → scp to Kindle → open a book → confirm luminance conversion; confirm 🎨 flag shows in gallery on desktop.

**Secondary verification — greyscale Kindle:**
- Pre-change regression: all existing bars paint identically.
- Metro_fill opt-in: set a value via nudge (phase 1) or picker-imported-preset (phase 2 only) — confirm read portion + ticks recolour.
- Picker doesn't appear — `Screen:isColorEnabled()` returns false, `% black` nudge behaves as before.
- Hex value in setting (imported from a colour preset) renders as luminance.

**Unit tests** in `_test_conditionals.lua`-style runner:
- `parseColorValue({hex="#000000"})` on colour screen → `ColorRGB32(0,0,0,255)`.
- `parseColorValue({hex="#FFFFFF"})` on greyscale → `Color8(255)`.
- `parseColorValue({hex="#FF0000"})` on greyscale → `Color8(76)` (lum = 0.299 × 255).
- Cache hit on repeated calls.
- Invalid hex → nil/default fallback (graceful, not crash).

**Tertiary — community pre-release (v4.3.0-rc1):**
- Tag a pre-release with attribution + explicit call for Kaleido-device testers.
- Request: screenshots of the picker, screenshots of applied colours on-book, feedback on dithering, wheel touch responsiveness, any visual oddities vs desktop.
- Hold the final v4.3.0 tag until at least one colour-device tester confirms the widget works and colours render sensibly.

## Release strategy

**v4.2.0 — metro fill (all devices):**
- Single feature branch, short review window (~1 day).
- One translatable string; refresh `.pot`, add placeholder entries in existing locales.
- Release notes: short bullet, no attribution needed.
- No pre-release — change is low-risk and pixel-identical for existing users.

**v4.3.0 — colour picker (colour-device feature; safe on greyscale):**
- Feature branch off post-v4.2 `master`.
- PR review via `code-review:code-review` — particular focus on the hex cache lifetime and event-subscription correctness.
- **v4.3.0-rc1 pre-release** with attribution + tester call.
- Translation refresh cycle after RC feedback settles (adds ~5–8 new strings: picker title variants, hex input label, "transparent"/"default" handling, gallery tooltip).
- Final v4.3.0 tag after at least one Kaleido-device confirmation.
- Upstream README update + release-notes credit — phrased as "leaning heavily on their design, please report issues".

## Risks & open questions

**Risks:**

- **Widget-upstream API drift.** appearance.koplugin targets some past KOReader version; touch event APIs, `Geom` / `Size` helpers, or widget base classes may have shifted. *Mitigation:* port against current KOReader master; wrap any upstream-API touch points so future version bumps localise.
- **Cache-flush completeness.** Missing `onColorRenderingUpdate` events (or other runtime-flips we don't know about) leave stale `ColorRGB32` cached values that subsequent paints route through Blitbuffer's default converter, which may produce visually different greyscale than our luminance helper. *Mitigation:* subscribe to the event; add a fallback `self:_flushColorCache()` call inside `markDirty()` if the event proves unreliable.
- **Two-sided gallery flag** (plugin preset_manager + bookends-presets review tool). Easy to ship the plugin side and forget the repo side. *Mitigation:* include both in the same v4.3 work; update the `review-preset-submission` skill.
- **Preset author accessibility pitfalls.** Nothing stops a user from picking red-green combinations that are unreadable to colour-vision-deficient readers. *Mitigation:* README Acknowledgements paragraph also notes "pick luminance-distinct colours for fill/bg" as a general preset-authoring tip.
- **Hardware-specific dithering behaviour.** Colours that look fine on desktop may look muddy on Kaleido. *Mitigation:* community pre-release with explicit feedback call.

**Open questions flagged for implementation-time decisions:**

- Brightness slider — HSV-V as upstream, or switch to HSL lightness to support pastel bg + saturated fg from the same hue? Recommendation: ship HSV for v4.3 to minimise widget changes; consider HSL for a follow-up if users request it.
- Default hex for `symbol_color` and `text_color` when Default button is tapped — we've been treating "unset" as the default for these (fall back to book text colour / symbol-inherits-text). Should the picker's Default button show a specific hex as a preview, or just grey-out the swatch? Lean toward just grey-out, and have Default clear the setting (matches the hold-to-reset semantics of the rest of the plugin).

## Future work (explicit non-commitments)

- **Inline `[c=#RRGGBB]` BBCode tag** in format strings — would complete colour parity with the global/per-bar settings but requires token-parser and line-editor changes.
- **Greyscale-preview toggle in picker** — preset authors catch luminance collisions at design time.
- **HSL lightness slider** — better for pastel/dark-variant authoring from a common hue.
- **Per-style colour fields** — wavy-specific fill, bordered-specific tick, etc. The metro_fill exception opens this pattern if future demand appears.
- **Palette suggestions** — pre-populated tiles for known-good e-ink colours at the top of the picker, short-circuiting the wheel for common choices.
