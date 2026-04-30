# Colour Control System

**Date:** 2026-04-12
**Status:** Draft — awaiting user review

## Problem

Bookends currently provides greyscale colour control only for progress bar elements (fill, background, track, tick) via a global/per-bar cascade. Text and icon colours are entirely delegated to KOReader's `use_book_text_color` flag — there is no user control. Several bar sub-elements (borders, inversion colour, metro ring inner) are hardcoded. Colour e-ink devices (Kobo Libra Colour, etc.) are not addressed.

## Goals

1. Allow user control over the **colour** of **text**, **icons**, and **progress bars** (including previously-hardcoded sub-elements).
2. Provide a **three-tier cascade**: global defaults → per-category settings → inline BBCode overrides.
3. Support both **greyscale and colour devices** with a single settings model.
4. Maintain **full backward compatibility** with existing `bar_colors` settings.
5. Keep the existing UX patterns (nudge dialogs, hold-to-reset) and zero-config defaults.
6. **Zero performance cost** when defaults are unchanged — same paint calls, different values.

## Non-Goals

- Opacity / alpha compositing (complexity outweighs benefit).
- Full theme/skin system with named colour slots.
- Android tablet colour profile integration.
- Per-line text colour settings in the line editor UI (inline BBCode tags cover this use case).

---

## Colour Representation

### Storage format

A colour value in settings is one of:

| Format | Example | Meaning |
|---|---|---|
| Integer (legacy) | `192` | Raw greyscale byte, 0=black, 255=white/transparent. Existing `bar_colors` format. |
| `{grey=N}` | `{grey=64}` | Greyscale, 0=black, 255=white. New canonical form. |
| `{r=N, g=N, b=N}` | `{r=255, g=0, b=0}` | Full RGB colour (phase 2). |

All integer fields are 0–255.

### Resolution to Blitbuffer types

A single `resolveColor(value, default)` function handles all formats:

```
integer         → Blitbuffer.Color8(value)    — legacy path
{grey=N}        → Blitbuffer.Color8(grey)
{r,g,b}         → ColorRGB32 on colour screen, Color8(luminance) on greyscale
nil             → default (pass-through)
false           → nil (transparent/skip paint)
```

Luminance conversion: `grey = floor(0.299*r + 0.587*g + 0.114*b)`.

### Device detection

`Device:hasColorScreen()` determines:
- Which Blitbuffer colour types to use at render time.
- Which picker UI to show (% black slider vs. hex/RGB input — colour picker is phase 2).

Settings are stored device-agnostically. A colour value saved on one device works on another via automatic conversion.

---

## Colour Categories & Cascade

### Hierarchy

```
Level 1: Global defaults (per category)
  │
  ├── text_color         → all overlay text
  ├── icon_color         → all icon glyphs (falls back to text_color)
  └── bar_colors         → all progress bars (existing + extended)
       ├── .fill, .bg, .track, .tick (existing)
       ├── .border       (NEW: bordered/rounded bar border)
       └── .invert       (NEW: tick inversion colour)
  │
Level 2: Per-element settings
  │
  ├── per-bar colors (existing)     → overrides bar_colors for one bar
  └── (no per-position text/icon colours — use BBCode instead)
  │
Level 3: Inline BBCode overrides    → highest priority
```

### Cascade rules

**For text:**
1. `[c=...]` BBCode tag → use specified colour, `use_book_text_color = false`
2. No tag + `text_color` set → use `text_color`, `use_book_text_color = false`
3. No tag + `text_color` is nil → `use_book_text_color = true` (today's behaviour)

**For icons (expanded from tokens):**
1. `[c=...]` tag manually placed around icon → use specified colour
2. No manual tag + `icon_color` set → auto-wrap during token expansion
3. No manual tag + `icon_color` nil + `text_color` set → inherit text_color
4. All nil → `use_book_text_color = true`

**For bars:** Existing cascade preserved:
1. Per-bar `colors` table → overrides for that bar
2. Global `bar_colors` → overrides for all bars
3. Hardcoded defaults per style (solid/bordered/metro/wavy)

New `border` and `invert` fields added to both levels.

---

## BBCode Colour Tags

### Syntax

Extend the existing `[b]`/`[i]`/`[u]` parser in `parseStyledSegments`:

```
[c=N]text[/c]              N = 0–100, percentage black (greyscale shorthand)
[c=#RRGGBB]text[/c]        hex colour (colour screens; greyscale-converted on e-ink)
```

### Nesting

Colour tags nest with style tags using the existing stack mechanism:

```
[b][c=50]bold grey[/c][/b]         ✓ valid
[c=50][i]grey italic[/i][/c]       ✓ valid
[c=50][c=80]override[/c]outer[/c]  ✓ valid (inner overrides outer)
[c=50]unclosed text                 → renders as plain text (existing safety)
```

### Segment data

Each segment produced by `parseStyledSegments` gains an optional `color` field:

```lua
{ text = "hello", bold = false, italic = false, uppercase = false,
  color = {grey=128},   -- nil if no [c] tag active
}
```

### Rendering

In `buildStyledLine`, when creating a TextWidget for a segment:
- If `segment.color` or global text_color is set → resolve to Blitbuffer colour, pass as `fgcolor`, set `use_book_text_color = false`
- If neither is set → keep `use_book_text_color = true` (zero overhead, identical to today)

---

## Icon Auto-Wrapping

When `icon_color` is set globally, icon tokens are automatically wrapped with colour tags during token expansion.

### Which characters are "icons"?

Only **known icon-producing tokens** defined in `tokens.lua` are auto-wrapped: `%B` (battery), `%W` (wifi), and any future icon tokens. These are the only characters the plugin can reliably identify as icons.

Characters inserted manually via the icon picker are treated as regular text — they inherit `text_color` like any other character. Users can override individual icon-picker characters with `[c=...]` tags in their format strings if they want different colouring.

This avoids fragile Unicode-range detection and keeps the behaviour predictable.

### Implementation

During text assembly in `main.lua` (~line 1250), after token expansion:
- If `icon_color` is set and a token expansion produced a known icon character, wrap it: `[c=XX]icon[/c]`
- If the icon is already inside a user-placed `[c=...]` tag, skip auto-wrapping (manual override wins)
- This is invisible to the user — format strings don't change, only the expanded text fed to the renderer

---

## New Settings

### Settings keys

| Key | Type | Default | Description |
|---|---|---|---|
| `text_color` | colour value or nil | nil | Global text foreground colour |
| `icon_color` | colour value or nil | nil (inherit text_color) | Global icon colour |
| `bar_colors.border` | colour value or nil | nil (black) | Border colour for bordered/rounded bars |
| `bar_colors.invert` | colour value or nil | nil (white) | Tick inversion colour |

### Menu structure

```
Bookends →
  ...
  Text & icon colours →
    Text color: default (book)        — nudge 0–100% black, or "use book colour"
    Icon color: default (text)        — nudge, or "same as text"
    Reset all to defaults

  Progress bar colours and tick marks →  (existing menu, extended)
    Read color: 75%                      (existing)
    Unread color: 25%                    (existing)
    Metro track color: 75%              (existing)
    Tick color: 100%                     (existing)
    Invert tick color on read portion    (existing)
    ─────────────────────
    Border color: default (100%)         (NEW)
    Tick inversion color: default (0%)   (NEW)
    ─────────────────────
    Tick width: 2x                       (existing)
    Tick height: 100%                    (existing)
    Reset all to defaults                (existing)
```

All new items follow the existing pattern: nudge dialog on tap, reset on hold, `text_func` shows current value.

---

## Rendering Pipeline Changes

All colour changes are **zero-cost** — they pass different values through the same existing paint calls. No new buffers, no new compositing, no new code paths at paint time.

### `overlay_widget.lua`

1. **`textWidgetOpts(t, color)`**: Becomes context-aware. When `color` is provided, sets `t.fgcolor` and omits `use_book_text_color`. When not provided, preserves existing `use_book_text_color = true`. Same constructor call, different value.

2. **`resolveColor(value, default)`**: Enhanced to handle integer, table, and nil/false inputs. Returns the appropriate Blitbuffer colour type for the current device. Same type-check logic as today, extended with one `type(value) == "table"` branch.

3. **`paintProgressBar` colours parameter**: Add `border` and `invert` colour fields. Replace four hardcoded `COLOR_BLACK` references at lines 1159-1164 and three hardcoded `COLOR_WHITE` references at lines 940, 1031, 1079 with `resolveColor(custom_border, ...)` and `resolveColor(custom_invert, ...)`. Same `paintRect` calls, different colour argument.

4. **`parseStyledSegments`**: Extend pattern matching to recognise `[c=...]` and `[/c]` tags. Store colour on segment data. The parser already runs for `[b]`/`[i]`/`[u]` — adding `[c]` is one extra pattern match in the existing loop.

5. **`buildStyledLine`**: When creating TextWidget for each segment, pass resolved `fgcolor` from segment colour → global text_color → nil cascade.

### `main.lua`

1. **Token expansion**: When `icon_color` is set, wrap icon characters in `[c=...]` tags during text assembly. Only during dirty rebuild.

2. **New `buildTextColourMenu()`**: Builds the "Text & icon colours" submenu using the existing `showNudgeDialog` pattern.

3. **Extend `_buildColorItems`**: Add "Border color" and "Tick inversion color" items to both global and per-bar colour menus.

4. **Preset system**: `buildPreset` captures new settings; `loadPreset` restores them with nil defaults for missing fields.

### Performance guarantee

| Feature used | Extra cost vs. today |
|---|---|
| Nothing (all defaults) | Zero — identical code paths |
| Text/icon colour (global or BBCode) | Zero — same paint calls, different `fgcolor` value |
| Bar border/invert colour | Zero — same `paintRect`, different colour arg |
| BBCode `[c=...]` tags | Zero — parser already runs for `[b]`/`[i]`/`[u]` |

---

## Backward Compatibility

| Scenario | Behaviour |
|---|---|
| Existing `bar_colors` with integers | Works unchanged — `resolveColor` handles raw integers |
| No `text_color` set | `use_book_text_color = true` — identical to today |
| Old preset loaded (no text/icon fields) | Missing fields default to nil — no change in appearance |
| Format string with no `[c]` tags | Parsed identically to today — `parseStyledSegments` returns nil for no-tag lines |
| New preset loaded on old plugin version | Unknown fields silently ignored by old code |

---

## Phases

### Phase 1 (this implementation)

- New `resolveColor` supporting integer + `{grey}` formats
- Global `text_color`, `icon_color` settings + menu
- BBCode `[c=N]` tags (greyscale percentage)
- Bar `border` and `invert` colour fields
- Icon auto-wrapping
- Preset integration

### Phase 2 (follow-up)

- `[c=#RRGGBB]` hex colour tag support
- `{r,g,b}` colour storage
- Colour picker UI for `Device:hasColorScreen()` devices
- Potential per-position text colour in line editor (if BBCode proves insufficient)
