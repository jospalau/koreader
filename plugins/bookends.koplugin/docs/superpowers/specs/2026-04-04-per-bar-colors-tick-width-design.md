# Per-Bar Colors & Tick Width Control

**Date:** 2026-04-04
**Motivation:** Users want to combine transparent tick-only bars with visible filled bars (requires per-bar colors), and want thinner chapter ticks than the current hardcoded formula allows.

## Feature 1: Per-Bar Color Overrides

### Scope

- Applies to the 4 standalone progress bars only.
- Inline bars (in the 6 text regions) always use the global `bar_colors` setting.

### Settings Storage

Each `progress_bar_N` config gains an optional `colors` table with the same shape as the global `bar_colors`:

```lua
colors = {
    fill = <0x00–0xFF or nil>,   -- read portion
    bg = <0x00–0xFF or nil>,     -- unread portion
    track = <0x00–0xFF or nil>,  -- metro track line
    tick = <0x00–0xFF or nil>,   -- chapter tick marks
    invert_read_ticks = <bool or nil>,
}
```

When `colors` is absent (or nil), the bar uses the global colors — this is the default and preserves backward compatibility.

### Render Path

In the paint loop (`main.lua` ~line 616–724), replace the single global `bar_colors` pass with a per-bar resolution:

```lua
-- Before the paintProgressBar call for each bar:
local colors = bar_cfg.colors and resolveColors(bar_cfg.colors) or bar_colors
```

`resolveColors` is the same logic currently applied to the global `bc` table (lines 601–614) — convert raw byte values to Blitbuffer colors, treating 0xFF as transparent. Extract this into a small helper to avoid duplication.

### Menu

In `buildSingleBarMenu`, add a new submenu at the bottom of each bar's menu:

- **"Custom colors"** (submenu)
  - **"Use custom colors"** — toggle. When turned off, removes `bar_cfg.colors` and saves. When turned on, initializes `bar_cfg.colors = {}` (empty = all defaults).
  - When enabled, the same 5 items from `buildBarColorsMenu` appear, but scoped to `bar_cfg.colors` instead of the global setting:
    - Read color (spinner, 0–100% black)
    - Unread color (spinner)
    - Metro track color (spinner)
    - Tick color (spinner)
    - Invert tick color on read portion (checkbox)
    - Reset custom to defaults (clears `bar_cfg.colors` to `{}`)

Extract the color menu item builders from `buildBarColorsMenu` into a shared helper that takes `(color_table, save_callback)` so both the global menu and per-bar menus use the same code.

### Backward Compatibility

Existing configs have no `colors` key on any bar → global colors apply → no visible change.

## Feature 2: Tick Width Control

### Current Behavior

```lua
tick_w = math.max(1, (max_depth - depth + 1) * 2 - 1)
```

For a book with 3 TOC levels: top-level = 5px, level 2 = 3px, level 3 = 1px.

### New Setting

A global `tick_width_multiplier` setting (integer, range 0–5, default 2).

The formula becomes:

```lua
tick_w = math.max(1, (max_depth - depth + 1) * multiplier - 1)
```

| Multiplier | Level 1 | Level 2 | Level 3 | Effect |
|------------|---------|---------|---------|--------|
| 0 | 1 | 1 | 1 | All ticks 1px |
| 1 | 1 | 1 | 1 | All ticks 1px |
| 2 (default) | 5 | 3 | 1 | Current behavior |
| 3 | 7 | 5 | 3 | Chunky |
| 5 | 13 | 9 | 5 | Very bold |

### Storage

```lua
self.settings:readSetting("tick_width_multiplier", 2)
```

### Apply

Both tick-generation sites must use the setting:
- `main.lua:450` (standalone bar ticks)
- `tokens.lua:217` (inline bar ticks)

### Menu

Add a "Tick width" spinner to the existing global "Progress bar colors" submenu (below the existing color items, above "Reset all to defaults"):

- Label: `"Tick width: Nx"` where N is the current multiplier
- Spinner: range 0–5, default 2, step 1
- Long-press: reset to default (2)

## Files to Modify

1. **`main.lua`** — per-bar color resolution in paint loop, `buildSingleBarMenu` submenu, shared color menu helper, `buildBarColorsMenu` refactor, tick multiplier setting + menu item, tick formula update
2. **`overlay_widget.lua`** — no changes needed (already receives colors as a parameter)
3. **`tokens.lua`** — tick formula update (needs access to the multiplier setting)
