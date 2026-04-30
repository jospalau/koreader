# Progress Bars Feature Design

## Overview

Add progress bar rendering to bookends.koplugin via two complementary systems:

1. **Full-width progress bars** — up to two independently configured bars rendered as dedicated layers, separate from the 6 text regions.
2. **Inline bar tokens** — `%bar_book` and `%bar_chapter` tokens usable within region lines, mixable with text.

Text always renders on top of full-width bars. The two systems are independent — users can use either or both.

Attribution: This feature was inspired by and builds on the work of SH4DOWSIX (PR #7).

---

## 1. Full-Width Progress Bars

### Concept

Two generic bar slots (Bar 1, Bar 2), each independently configured. Not tied to top/bottom — each bar has its own anchor and margins, allowing flexible layouts like:

- Single book bar at the top edge
- Two bars stacked at the bottom (book + chapter)
- Left/right split at the bottom (book left half, chapter right half)

### Settings per bar

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `enabled` | boolean | false | On/off toggle |
| `type` | `"book"` or `"chapter"` | `"book"` | What progress to show |
| `style` | `"thick"` or `"thin"` | `"thin"` | Visual style (see below) |
| `height` | number (px) | 7 (thick) / 3 (thin) | Bar height |
| `v_anchor` | `"top"` or `"bottom"` | `"bottom"` | Which screen edge to pin to |
| `margin_v` | number (px) | 0 | Distance from anchored edge |
| `margin_left` | number (px) | 0 | Left inset |
| `margin_right` | number (px) | 0 | Right inset |
| `show_chapter_ticks` | boolean | true | Chapter boundary tick marks (book type only) |

### Visual styles (matching KOReader's ProgressWidget)

**Thick:** Bordered bar with rounded corners. White background, dark gray fill, black border. Tick marks as thin vertical lines.

**Thin:** Flat, no border, no rounding. Gray background, darker gray fill. No tick marks (ticks disabled in thin style, matching KOReader behaviour).

### Rendering

- Painted first in `paintTo`, before text regions, so text overlays on top.
- Uses blitbuffer primitives directly: `paintRoundedRect` / `paintRect` for background, `paintRect` for fill and ticks.
- Bar position: `x = margin_left`, `y` computed from `v_anchor` + `margin_v`, `width = screen_width - margin_left - margin_right`.
- Data source: reads `pageno`, page count, and TOC directly in `paintTo` — no token system involvement.

### Settings storage

Stored as `"progress_bar_1"` and `"progress_bar_2"` in bookends.lua. Included in presets via `buildPreset()` / `loadPreset()`.

### Settings menu

New "Progress bars" submenu in the main Bookends menu:

- Bar 1: enable/disable, type, style, height, anchor, margins (with nudge buttons for live preview), chapter ticks toggle
- Bar 2: same

Margin adjustment uses the existing nudge button pattern (+1/+10 steps with real-time preview updates).

---

## 2. Inline Bar Tokens

### Tokens

- `%bar_book` — book progress bar with optional chapter ticks
- `%bar_chapter` — chapter progress bar

Usable in any line of any region, mixable with text: `"p.%p %bar_book"`, `"%bar_chapter %P"`, or standalone `"%bar_book"`.

### Token Expansion (Parallel Data Channel — Approach 3)

`Tokens.expand` is modified to:

1. Strip `%bar_book` / `%bar_chapter` from the returned text string (surrounding text preserved).
2. Return a third value: `bar_info` — a table describing the bar on this line, or `nil` if no bar token was present.

```lua
-- Example return for a line "p.%p %bar_book":
text = "p.42 ",  -- bar token stripped, text preserved
is_empty = false,
bar_info = { kind = "book", pct = 0.75, ticks = {0.25, 0.5, 0.75} }

-- Example return for a line with no bar token:
text = "p.42",
is_empty = false,
bar_info = nil
```

In Phase 1 of `paintTo`, `bar_info` is collected per-line into a sparse table keyed by line index for that position.

**`needs()` collision fix:** Bar tokens are checked via dedicated multi-character patterns (`format_str:find("%%bar_book")`) before single-letter token substitution runs. This avoids the `%%b` substring collision with battery tokens.

**`is_empty` logic:** A line containing only a bar token (text is empty/whitespace after stripping) is never considered empty — the bar always renders.

**Preview mode:** `%bar_book` → `[book bar]`, `%bar_chapter` → `[ch. bar]`.

### Data flow through the pipeline

1. **Phase 1 (token expansion):** `bar_info` collected alongside `expanded[key]`.
2. **Phase 2 (build for measurement):** `bar_info` entries merged into `line_configs` as `cfg.bar = {kind, pct, ticks}`.
3. **Phase 2/3 (widget build):** `buildTextWidget` checks `cfg.bar` and routes to horizontal row layout when present.

### Per-line settings

| Setting | Type | Default | Min | Description |
|---------|------|---------|-----|-------------|
| `line_bar_height` | number (px) | 5 | 1 | Bar height |
| `line_bar_width` | number (px) | 0 | 0 | Fixed width, 0 = auto-fill |
| `line_bar_style` | `"thick"` or `"thin"` | `"thick"` | — | Visual style |

Stored as sparse tables in position settings, same pattern as `line_font_size`, `line_v_nudge`, etc.

**Conditional UI:** Bar settings buttons (height, width, style) only appear in `editLineString` when the line's format string contains `%bar_book` or `%bar_chapter`. This avoids cluttering the dialog for non-bar lines.

**Line management:** `removeLine`, `swapLines`, and `moveToRegion` all copy/shift `line_bar_height`, `line_bar_width`, and `line_bar_style`.

---

## 3. Inline Bar Rendering

### New widgets in overlay_widget.lua

**`BarWidget`** — renders a single progress bar rectangle.

- Properties: `width`, `height`, `fraction`, `ticks`, `style`
- Paints with blitbuffer primitives (same approach as full-width bars)
- Respects book text color (reads foreground/background from context, not hardcoded)

**`HorizontalRowWidget`** — renders an ordered array of segments (text + bar) left-to-right.

- Each segment is a widget with `{widget, w, h}`
- `paintTo` renders left-to-right, vertically centering each segment
- `getSize` returns `{w = total, h = max}`
- `free` iterates and frees all child widgets

### Routing in buildTextWidget

- Single line, no bar → existing `TextWidget` fast path (unchanged)
- Single line with bar → `HorizontalRowWidget` with text segments + bar
- Multi-line, some with bars → `MultiLineWidget` where each line is either `TextWidget` or `HorizontalRowWidget`

### Auto-fill width

When `line_bar_width` is 0 (default), the bar takes remaining horizontal space:
`bar_width = available_width - text_width`

Text segments are measured first, then the bar fills whatever remains. `available_width` comes from the position's allocated space (after overlap prevention).

### Overlap prevention

`measureTextWidth` returns width of **text portions only**, excluding bars. This prevents a full-width center bar from squeezing side text to zero. Bars are clamped to whatever space remains after overlap limits are applied.

### Color theme support

`BarWidget` uses book text color awareness (via the same mechanism as `textWidgetOpts` uses `use_book_text_color = true`) rather than hardcoding white/black/gray.

---

## 4. Cache and Dirty Tracking

**Text cache:** Since bar tokens are stripped from the text string, the text portion of the cache comparison is unaffected by progress changes. However, positions containing bar tokens must always re-render on page turn (the fraction changes even if the text doesn't).

**Approach:** The existing `position_cache` comparison already misses whenever any token in the line changes (e.g. `%p` changes page number). For bar-only lines (no other tokens), the stripped text is empty/static, so the cache would falsely hit. Fix: if a position has any `bar_info`, skip the cache for that position — always rebuild. This is simple and correct; bars are cheap to render.

**Full-width bars:** Always re-render on every `paintTo` call. They have no cache — they just read the current page number and paint.

---

## 5. Preset Integration

Full-width bar settings (`progress_bar_1`, `progress_bar_2`) are included in `buildPreset()` and `loadPreset()`.

Inline bar per-line settings are part of position data, so they're captured in presets automatically.

Built-in presets remain unchanged (no bars). A new built-in preset could optionally demonstrate bars.

---

## Files Modified

| File | Changes |
|------|---------|
| `tokens.lua` | New `%bar_book` / `%bar_chapter` expansion, `bar_info` return value, `needs()` patterns |
| `overlay_widget.lua` | New `BarWidget`, `HorizontalRowWidget`, bar routing in `buildTextWidget`, `measureTextWidth` update |
| `main.lua` | Full-width bar rendering in `paintTo`, bar settings menu, per-line bar settings in `editLineString` (conditional), `moveToRegion`/`removeLine`/`swapLines` updates, preset integration |
