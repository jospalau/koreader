# Colour Control System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add user-configurable colour control for text, icons, and progress bar sub-elements (borders, inversion), with a three-tier cascade: global settings → per-bar overrides → inline BBCode `[c=N]` tags.

**Architecture:** Extend the existing `resolveColor` / `bar_colors` system to handle new colour types (table `{grey=N}` alongside legacy integers). Add `text_color` and `icon_color` global settings. Extend the BBCode parser (`parseStyledSegments`) with `[c=N]` tags. Auto-wrap known icon tokens with colour tags during expansion. All changes are zero-cost when defaults are unchanged — same paint calls, different values.

**Tech Stack:** Lua, KOReader widget framework (Blitbuffer, TextWidget, Device), existing nudge dialog UI pattern.

**Spec:** `docs/superpowers/specs/2026-04-12-colour-opacity-controls-design.md`

---

### File Map

| File | Changes |
|---|---|
| `overlay_widget.lua` | Extend `textWidgetOpts` with optional `fgcolor`, extend `parseStyledSegments` with `[c=N]`/`[/c]`, pass `fgcolor` in `buildStyledLine` and plain-text paths, add `border`/`invert` to `paintProgressBar` |
| `main.lua` | New `resolveColor` (table-aware), read `text_color`/`icon_color` settings, pass `text_color` through to overlay widget, add `border`/`invert` to `resolveColors`, new `buildTextColourMenu()`, extend `_buildColorItems` with border/invert, extend preset build/load |
| `tokens.lua` | Auto-wrap `%B`/`%W` icon tokens with `[c=N]` when `icon_color` is set |

---

### Task 1: Extend `resolveColor` to handle table colour values

**Files:**
- Modify: `main.lua:992-1007` — `resolveColors` local function

The `resolveColors` function in `main.lua` converts stored settings to Blitbuffer colours. It needs to handle `{grey=N}` tables alongside legacy integers, and pass through the new `border`/`invert` fields. (The `resolveColor` inside `paintProgressBar` in `overlay_widget.lua` does NOT need changing — it receives already-resolved Color8 values.)

- [ ] **Step 1: Update `resolveColors` in `main.lua`**

In `main.lua`, the `resolveColors` function (inside `_paintToInner`, line 992) converts stored integer settings to `Blitbuffer.Color8`. Extend `colorOrTransparent` to also handle `{grey=N}` tables:

```lua
local function resolveColors(bc)
    local Blitbuffer = require("ffi/blitbuffer")
    local function colorOrTransparent(v)
        if not v then return nil end
        if type(v) == "table" then
            if v.grey then
                if v.grey >= 0xFF then return false end
                return Blitbuffer.Color8(v.grey)
            end
            return nil
        end
        if v >= 0xFF then return false end
        return Blitbuffer.Color8(v)
    end
    return {
        fill = colorOrTransparent(bc.fill),
        bg = colorOrTransparent(bc.bg),
        track = colorOrTransparent(bc.track),
        tick = colorOrTransparent(bc.tick),
        border = colorOrTransparent(bc.border),
        invert = colorOrTransparent(bc.invert),
        invert_read_ticks = bc.invert_read_ticks,
        tick_height_pct = bc.tick_height_pct,
    }
end
```

Note: `border` and `invert` are new fields — they pass through as `nil` for existing settings (no change in behaviour).

- [ ] **Step 2: Verify existing bar colours still work**

Push to Kindle, open a book with custom bar colours configured. Confirm bars render identically — the new `type(v) == "table"` check only triggers for tables, so all integer paths are unchanged.

- [ ] **Step 3: Commit**

```bash
git add main.lua
git commit -m "feat: extend resolveColors to handle {grey=N} table colour values"
```

---

### Task 2: Add `border` and `invert` colour fields to `paintProgressBar`

**Files:**
- Modify: `overlay_widget.lua:835-1207` — `paintProgressBar` function

Currently, border colour is hardcoded to `Blitbuffer.COLOR_BLACK` (lines 1159-1164) and tick inversion colour is hardcoded to `Blitbuffer.COLOR_WHITE` (lines 940, 1031, 1079). Extract these from the `colors` parameter.

- [ ] **Step 1: Read new colour fields from the `colors` parameter**

At the top of `paintProgressBar` (after line 844), add:

```lua
local custom_border = colors and colors.border
local custom_invert = colors and colors.invert
```

- [ ] **Step 2: Replace hardcoded border colour in bordered/rounded style**

In the bordered/rounded `else` branch, replace the four hardcoded `Blitbuffer.COLOR_BLACK` border references. At line 1159 (`paintBorder` call) and lines 1161-1164 (four `paintRect` calls for the border):

Replace:
```lua
bb:paintBorder(x, y, w, h, border, Blitbuffer.COLOR_BLACK, radius)
```
With:
```lua
local border_color = resolveColor(custom_border, Blitbuffer.COLOR_BLACK)
if border_color then
    bb:paintBorder(x, y, w, h, border, border_color, radius)
end
```

Replace the non-rounded border block (lines 1161-1164):
```lua
bb:paintRect(x, y, w, border, Blitbuffer.COLOR_BLACK)
bb:paintRect(x, y + h - border, w, border, Blitbuffer.COLOR_BLACK)
bb:paintRect(x, y, border, h, Blitbuffer.COLOR_BLACK)
bb:paintRect(x + w - border, y, border, h, Blitbuffer.COLOR_BLACK)
```
With:
```lua
local border_color = resolveColor(custom_border, Blitbuffer.COLOR_BLACK)
if border_color then
    bb:paintRect(x, y, w, border, border_color)
    bb:paintRect(x, y + h - border, w, border, border_color)
    bb:paintRect(x, y, border, h, border_color)
    bb:paintRect(x + w - border, y, border, h, border_color)
end
```

(Move the `border_color` resolution before the `if radius > 0` branch so both paths share it.)

- [ ] **Step 3: Replace hardcoded inversion colour**

Three locations where `Blitbuffer.COLOR_WHITE` is used for tick inversion:

**Solid style (line 1079):**
```lua
-- Before:
tick_color = Blitbuffer.COLOR_WHITE
-- After:
tick_color = resolveColor(custom_invert, Blitbuffer.COLOR_WHITE)
```

**Wavy style (line 1031):**
```lua
-- Before:
tick_color = Blitbuffer.COLOR_WHITE
-- After:
tick_color = resolveColor(custom_invert, Blitbuffer.COLOR_WHITE)
```

**Metro start ring inner fill (line 940):**
```lua
-- Before:
paintCircle(start_cx + ring_border, oy + ring_border, inner_r, Blitbuffer.COLOR_WHITE)
-- After:
paintCircle(start_cx + ring_border, oy + ring_border, inner_r, resolveColor(custom_invert, Blitbuffer.COLOR_WHITE))
```

**Bordered style tick inversion (line 1183):**
The bordered style uses `border_bg` (the unread background colour) for tick inversion, not a hardcoded white. This is already configurable via `bg` colour, so no change needed here.

- [ ] **Step 4: Test on Kindle**

Push to Kindle. Check all four bar styles (solid, bordered, rounded, metro, wavy) render correctly with default colours. Borders should still be black, tick inversion should still be white. No visual change expected.

- [ ] **Step 5: Commit**

```bash
git add overlay_widget.lua
git commit -m "feat: make bar border and tick inversion colours configurable"
```

---

### Task 3: Add border/invert to colour menus

**Files:**
- Modify: `main.lua:2279-2365` — `_buildColorItems` function
- Modify: `main.lua:2367-2377` — `buildBarColorsMenu` (saveColors cleanup check)

- [ ] **Step 1: Add border and invert items to `_buildColorItems`**

After the "Invert tick color on read portion" checkbox item (line 2363), add two new items before the closing `end`:

```lua
        {
            text_func = function()
                return _("Border color") .. ": " .. pctLabel("border", 100)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                colorNudge(_("Border color (% black)"), "border", 100, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                bc.border = nil; saveColors()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text_func = function()
                return _("Tick inversion color") .. ": " .. pctLabel("invert", 0)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                colorNudge(_("Tick inversion color (% black)"), "invert", 0, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                bc.invert = nil; saveColors()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
```

- [ ] **Step 2: Update saveColors cleanup check in `buildBarColorsMenu`**

The `saveColors` function in `buildBarColorsMenu` (line 2371) checks if all colour fields are nil to decide whether to delete the setting. Add `border` and `invert` to the check:

```lua
local function saveColors()
    if not bc.fill and not bc.bg and not bc.track and not bc.tick
       and bc.invert_read_ticks == nil and not bc.tick_height_pct
       and not bc.border and not bc.invert then
        self.settings:delSetting("bar_colors")
    else
        self.settings:saveSetting("bar_colors", bc)
    end
    self:markDirty()
end
```

- [ ] **Step 3: Test menu on Kindle**

Push to Kindle. Open Bookends → Settings → Progress bar colours and tick marks. Verify "Border color" and "Tick inversion color" items appear. Tap to nudge, hold to reset. Change border to 50%, confirm bordered bar border turns grey. Change inversion to 100% (black), confirm ticks on the read portion render in black instead of white.

- [ ] **Step 4: Commit**

```bash
git add main.lua
git commit -m "feat: add border and tick inversion colour to bar colour menus"
```

---

### Task 4: Extend `textWidgetOpts` to support explicit `fgcolor`

**Files:**
- Modify: `overlay_widget.lua:10-16` — `textWidgetOpts` function

- [ ] **Step 1: Make `textWidgetOpts` accept an optional colour parameter**

Replace the `textWidgetOpts` function:

```lua
-- Default TextWidget options for overlay text.
-- use_book_text_color ensures text matches the book's color scheme
-- (compatible with color theme patches like koreader-color-themes).
-- When fgcolor is provided, use it instead (disabling use_book_text_color).
local function textWidgetOpts(t, fgcolor)
    if fgcolor then
        t.fgcolor = fgcolor
    else
        t.use_book_text_color = true
    end
    return t
end
```

All existing callers pass no second argument, so they continue to get `use_book_text_color = true` — zero change in behaviour.

- [ ] **Step 2: Verify no visual change**

Push to Kindle. All text should render identically — the second parameter is nil everywhere.

- [ ] **Step 3: Commit**

```bash
git add overlay_widget.lua
git commit -m "feat: extend textWidgetOpts to accept explicit fgcolor"
```

---

### Task 5: Extend BBCode parser with `[c=N]` colour tags

**Files:**
- Modify: `overlay_widget.lua:523-602` — `parseStyledSegments` function

- [ ] **Step 1: Add colour tracking to the parser**

The existing parser uses a `stack` of tag letters (`"b"`, `"i"`, `"u"`) and derives style from the stack. For colour, we need a separate approach since colour tags carry a value. Add a `color_stack` alongside the existing `stack`:

In the locals section (after line 530):
```lua
local color_stack = {}  -- color stack: each entry is a {grey=N} table
```

In `currentStyle()`, add after the existing function (after line 549):
```lua
local function currentColor()
    if #color_stack == 0 then return nil end
    return color_stack[#color_stack]
end
```

In `flushPending()`, add the colour field to the segment (replace line 554):
```lua
local function flushPending()
    if pending == "" then return end
    local bold, italic, uppercase = currentStyle()
    local seg = { text = pending, bold = bold, italic = italic, uppercase = uppercase }
    local clr = currentColor()
    if clr then seg.color = clr end
    table.insert(segments, seg)
    pending = ""
end
```

- [ ] **Step 2: Add pattern matching for `[c=N]` and `[/c]`**

In the main `while` loop, add two new branches. Insert after the opening-tag check for `[biu]` (after line 583) and before the `else` fallback:

```lua
        -- Check for closing colour tag [/c]
        elseif text:match("^%[/c%]", pos) then
            if #color_stack > 0 then
                flushPending()
                table.remove(color_stack)
                found_tags = true
                pos = pos + 4  -- [/c] = 4 chars
            else
                -- Mismatched close — render entire line as plain text
                return nil, false
            end
        -- Check for opening colour tag [c=N] where N is 0-100
        elseif text:match("^%[c=%d+%]", pos) then
            local val_str, end_pos = text:match("^%[c=(%d+)()%]", pos)
            if val_str then
                local pct = tonumber(val_str)
                if pct and pct >= 0 and pct <= 100 then
                    flushPending()
                    local grey = 0xFF - math.floor(pct * 0xFF / 100 + 0.5)
                    table.insert(color_stack, { grey = grey })
                    found_tags = true
                    pos = end_pos + 1  -- skip past the ']'
                else
                    pending = pending .. text:sub(pos, pos)
                    pos = pos + 1
                end
            else
                pending = pending .. text:sub(pos, pos)
                pos = pos + 1
            end
```

- [ ] **Step 3: Add unclosed colour stack check**

After the existing unclosed-tags check (line 593), add:
```lua
if #color_stack > 0 then
    return nil, false
end
```

- [ ] **Step 4: Verify existing BBCode tags still work**

Push to Kindle. Test a line with `[b]bold[/b]` and `[i]italic[/i]` — should render exactly as before. Test `[c=50]grey text[/c]` — should parse without error (rendering comes in next task).

- [ ] **Step 5: Commit**

```bash
git add overlay_widget.lua
git commit -m "feat: add [c=N] colour tags to BBCode parser"
```

---

### Task 6: Wire colour through `buildStyledLine` rendering

**Files:**
- Modify: `overlay_widget.lua:611-700` — `buildStyledLine` function

- [ ] **Step 1: Pass `fgcolor` from segment colour to TextWidget**

In the `buildStyledLine` loop where `TextWidget:new(textWidgetOpts{...})` is called (line 655), resolve the segment's colour and pass it:

Replace:
```lua
                local tw = TextWidget:new(textWidgetOpts{
                    text = display,
                    face = seg_face,
                    bold = seg_synthetic_bold,
                    max_width = seg_max_width,
                    truncate_with_ellipsis = seg_max_width ~= nil,
                })
```

With:
```lua
                -- Resolve segment colour: BBCode [c] tag → global text_color → nil (book colour)
                local seg_fgcolor = nil
                if seg.color then
                    seg_fgcolor = Blitbuffer.Color8(seg.color.grey)
                elseif cfg.text_color then
                    seg_fgcolor = Blitbuffer.Color8(cfg.text_color.grey)
                end

                local tw = TextWidget:new(textWidgetOpts({
                    text = display,
                    face = seg_face,
                    bold = seg_synthetic_bold,
                    max_width = seg_max_width,
                    truncate_with_ellipsis = seg_max_width ~= nil,
                }, seg_fgcolor))
```

- [ ] **Step 2: Test BBCode colour rendering on Kindle**

Push to Kindle. Configure a line with format `[c=50]dim text[/c] bright text`. The "dim text" should appear in mid-grey, "bright text" should use the book's text colour.

- [ ] **Step 3: Commit**

```bash
git add overlay_widget.lua
git commit -m "feat: render [c=N] BBCode colour tags via fgcolor"
```

---

### Task 7: Pass `text_color` through the plain-text rendering paths

**Files:**
- Modify: `overlay_widget.lua:330-410` — `buildTextWidget` function (plain text fast paths)
- Modify: `overlay_widget.lua:248-261` — `buildBarLine` text segments

The styled-line path (Task 6) handles BBCode lines. But lines without any tags take fast paths that also need `text_color`. The `cfg` table (per-line config) will carry a `text_color` field set by `main.lua`.

- [ ] **Step 1: Pass `text_color` in single-line plain text path**

In `buildTextWidget`, the single-line plain-text path (line 362):

Replace:
```lua
        local tw = TextWidget:new(textWidgetOpts{
            text = display_text,
            face = cfg.face,
            bold = cfg.bold,
            max_width = max_width,
            truncate_with_ellipsis = max_width ~= nil,
        })
```

With:
```lua
        local text_fgcolor = cfg.text_color and Blitbuffer.Color8(cfg.text_color.grey) or nil
        local tw = TextWidget:new(textWidgetOpts({
            text = display_text,
            face = cfg.face,
            bold = cfg.bold,
            max_width = max_width,
            truncate_with_ellipsis = max_width ~= nil,
        }, text_fgcolor))
```

- [ ] **Step 2: Pass `text_color` in multi-line plain text path**

Same change at line 395 (the multi-line plain-text path):

Replace:
```lua
            widget = TextWidget:new(textWidgetOpts{
                text = display_text,
                face = cfg.face,
                bold = cfg.bold,
                max_width = max_width,
                truncate_with_ellipsis = max_width ~= nil,
            })
```

With:
```lua
            local text_fgcolor = cfg.text_color and Blitbuffer.Color8(cfg.text_color.grey) or nil
            widget = TextWidget:new(textWidgetOpts({
                text = display_text,
                face = cfg.face,
                bold = cfg.bold,
                max_width = max_width,
                truncate_with_ellipsis = max_width ~= nil,
            }, text_fgcolor))
```

- [ ] **Step 3: Pass `text_color` in `buildBarLine` text segments**

In `buildBarLine`'s `addTextSegment` (line 251):

Replace:
```lua
        local tw = TextWidget:new(textWidgetOpts{
            text = display,
            face = cfg.face,
            bold = cfg.bold,
        })
```

With:
```lua
        local text_fgcolor = cfg.text_color and Blitbuffer.Color8(cfg.text_color.grey) or nil
        local tw = TextWidget:new(textWidgetOpts({
            text = display,
            face = cfg.face,
            bold = cfg.bold,
        }, text_fgcolor))
```

- [ ] **Step 4: Pass `text_color` in `buildStyledLine` reference height widget**

In `buildStyledLine` reference height TextWidget (line 673):

Replace:
```lua
        local ref_tw = TextWidget:new(textWidgetOpts{ text = " ", face = cfg.face, bold = cfg.bold })
```

With:
```lua
        local ref_tw = TextWidget:new(textWidgetOpts({ text = " ", face = cfg.face, bold = cfg.bold }))
```

(No `fgcolor` needed for the reference-height widget — it's only measuring height, never displayed.)

- [ ] **Step 5: Commit**

```bash
git add overlay_widget.lua
git commit -m "feat: pass text_color through all plain-text rendering paths"
```

---

### Task 8: Read `text_color` and `icon_color` settings, pass to rendering

**Files:**
- Modify: `main.lua:979-1284` — `_paintToInner` function (settings read + line config assembly)

- [ ] **Step 1: Read global text_color and icon_color from settings**

Near the top of `_paintToInner`, after the `bar_colors` read (line 1011), add:

```lua
    -- Text/icon colours from settings
    local text_color = self.settings:readSetting("text_color")  -- {grey=N} or nil
    local icon_color = self.settings:readSetting("icon_color")  -- {grey=N} or nil
```

- [ ] **Step 2: Pass `text_color` into line configs**

In the line-config assembly loop (after line 1251, where `cfg.uppercase` is set), add:

```lua
            cfg.text_color = text_color
```

This makes `text_color` available to all `buildTextWidget` / `buildStyledLine` / `buildBarLine` calls via the `cfg` table.

- [ ] **Step 3: Test global text_color on Kindle**

Temporarily hardcode `text_color = {grey=128}` to verify text renders in mid-grey. Then remove the hardcode. Full settings UI comes in Task 10.

- [ ] **Step 4: Commit**

```bash
git add main.lua
git commit -m "feat: read text_color/icon_color settings and pass to rendering"
```

---

### Task 9: Icon auto-wrapping in token expansion

**Files:**
- Modify: `tokens.lua:758-774` — token replacement `gsub` callback

When `icon_color` is set, wrap known icon tokens (`%B`, `%W`) with `[c=N]` tags so they render in the icon colour. The icon_color is passed into `Tokens.expand` as an additional parameter.

- [ ] **Step 1: Add `icon_color` parameter to `Tokens.expand`**

In `tokens.lua`, the `Tokens.expand` function signature (find it near the top of the function). Add `icon_color` as a new parameter at the end:

```lua
function Tokens.expand(format_str, ui, session_elapsed, session_pages_read, is_preview, tick_width_multiplier, icon_color)
```

Also update `Tokens.expandPreview` (line 787) to pass it through:
```lua
function Tokens.expandPreview(format_str, ui, session_elapsed, session_pages_read, tick_width_multiplier, icon_color)
    return Tokens.expand(format_str, ui, session_elapsed, session_pages_read, true, tick_width_multiplier, icon_color)
end
```

- [ ] **Step 2: Wrap icon tokens in the replacement table**

After the `replace` table is built (after line 745), wrap `%B` and `%W` values if `icon_color` is set:

```lua
    -- Auto-wrap icon tokens with colour tags when icon_color is set.
    -- Note: if a user also manually wraps an icon token with [c=N] in their
    -- format string, the auto-wrap (inner) takes precedence due to parser
    -- nesting rules. Users who want per-icon control should unset icon_color
    -- and use [c=] tags directly.
    if icon_color and icon_color.grey then
        local pct = math.floor((0xFF - icon_color.grey) * 100 / 0xFF + 0.5)
        local wrap_open = "[c=" .. pct .. "]"
        local wrap_close = "[/c]"
        local icon_tokens = { "%B", "%W" }
        for _, tok in ipairs(icon_tokens) do
            local val = replace[tok]
            if val and val ~= "" then
                replace[tok] = wrap_open .. val .. wrap_close
            end
        end
    end
```

- [ ] **Step 3: Pass `icon_color` from `main.lua` into `Tokens.expand`**

In `main.lua`, find the `Tokens.expand` call inside `_paintToInner` (around line 1170-1174). Add `icon_color` as the last argument:

```lua
                    local result, is_empty, line_bar = Tokens.expand(
                        fmt, self.ui, session_elapsed, self.session_pages,
                        nil, self.settings:readSetting("tick_width_multiplier", self.DEFAULT_TICK_WIDTH_MULTIPLIER),
                        icon_color)
```

- [ ] **Step 4: Test icon colouring on Kindle**

Temporarily hardcode `icon_color = {grey=192}` (light grey) in `_paintToInner`. Add `%B` or `%W` to a format string. Verify the icon glyph appears lighter than surrounding text. Then remove the hardcode.

- [ ] **Step 5: Commit**

```bash
git add tokens.lua main.lua
git commit -m "feat: auto-wrap icon tokens with [c=N] when icon_color is set"
```

---

### Task 10: Add "Text & icon colours" settings menu

**Files:**
- Modify: `main.lua` — new `buildTextColourMenu()` method, add to settings menu

- [ ] **Step 1: Add `buildTextColourMenu` method**

Add this method near the existing `buildBarColorsMenu` (after line 2377):

```lua
function Bookends:buildTextColourMenu()
    local text_color = self.settings:readSetting("text_color")
    local icon_color = self.settings:readSetting("icon_color")

    local function textPctLabel()
        if text_color then
            local pct = math.floor((0xFF - text_color.grey) * 100 / 0xFF + 0.5)
            if pct == 0 then return _("transparent") end
            return pct .. "%"
        end
        return _("default") .. " (" .. _("book") .. ")"
    end

    local function iconPctLabel()
        if icon_color then
            local pct = math.floor((0xFF - icon_color.grey) * 100 / 0xFF + 0.5)
            if pct == 0 then return _("transparent") end
            return pct .. "%"
        end
        return _("default") .. " (" .. _("text") .. ")"
    end

    return {
        {
            text_func = function()
                return _("Text color") .. ": " .. textPctLabel()
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local current = text_color and math.floor((0xFF - text_color.grey) * 100 / 0xFF + 0.5) or 100
                self:showNudgeDialog(_("Text color (% black)"), current, 0, 100, 100, "%",
                    function(val)
                        text_color = { grey = 0xFF - math.floor(val * 0xFF / 100 + 0.5) }
                        self.settings:saveSetting("text_color", text_color)
                        self:markDirty()
                    end,
                    nil, nil, nil, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                text_color = nil
                self.settings:delSetting("text_color")
                self:markDirty()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text_func = function()
                return _("Icon color") .. ": " .. iconPctLabel()
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local current = icon_color and math.floor((0xFF - icon_color.grey) * 100 / 0xFF + 0.5) or 100
                self:showNudgeDialog(_("Icon color (% black)"), current, 0, 100, 100, "%",
                    function(val)
                        icon_color = { grey = 0xFF - math.floor(val * 0xFF / 100 + 0.5) }
                        self.settings:saveSetting("icon_color", icon_color)
                        self:markDirty()
                    end,
                    nil, nil, nil, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                icon_color = nil
                self.settings:delSetting("icon_color")
                self:markDirty()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
            separator = true,
        },
        {
            text = _("Reset all to defaults"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                text_color = nil
                icon_color = nil
                self.settings:delSetting("text_color")
                self.settings:delSetting("icon_color")
                self:markDirty()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
    }
end
```

- [ ] **Step 2: Add menu entry to settings**

Find where the "Progress bar colours and tick marks" menu item is added (line 1682). Insert a new item before it:

```lua
                {
                    text = _("Text & icon colours"),
                    sub_item_table_func = function()
                        return self:buildTextColourMenu()
                    end,
                },
```

- [ ] **Step 3: Test full UI flow on Kindle**

Push to Kindle. Open Bookends → Settings → Text & icon colours. Set text colour to 50% — all overlay text should turn mid-grey. Set icon colour to 25% — battery/wifi icons should be light grey while text stays at 50%. Hold to reset — text returns to book colour, icons inherit text colour. Reset all — everything back to defaults.

- [ ] **Step 4: Commit**

```bash
git add main.lua
git commit -m "feat: add Text & icon colours settings menu"
```

---

### Task 11: Extend preset system

**Files:**
- Modify: `main.lua:423-439` — `buildPreset`
- Modify: `main.lua:442-517` — `loadPreset`

- [ ] **Step 1: Capture text/icon colours in `buildPreset`**

After `preset.tick_height_pct` (line 438), add:

```lua
    preset.text_color = self.settings:readSetting("text_color")
    preset.icon_color = self.settings:readSetting("icon_color")
```

- [ ] **Step 2: Restore text/icon colours in `loadPreset`**

After the `tick_height_pct` restore block (after line 514), add:

```lua
    if preset.text_color then
        self.settings:saveSetting("text_color", preset.text_color)
    else
        self.settings:delSetting("text_color")
    end
    if preset.icon_color then
        self.settings:saveSetting("icon_color", preset.icon_color)
    else
        self.settings:delSetting("icon_color")
    end
```

- [ ] **Step 3: Test preset round-trip on Kindle**

Set text_color to 50%, icon_color to 25%. Save a preset. Reset colours to defaults. Load the preset. Verify text_color and icon_color are restored.

- [ ] **Step 4: Commit**

```bash
git add main.lua
git commit -m "feat: include text/icon colours in preset save/load"
```

---

### Task 12: Final integration test

**Files:** None (testing only)

- [ ] **Step 1: Test the full cascade**

On Kindle, configure:
1. Global text_color = 50% (mid-grey text)
2. Global icon_color = 75% (darker icons)
3. A format string with `[c=25]light text[/c] normal text %B`
4. Bar with custom border colour = 50%, inversion = 100%

Verify:
- "light text" renders in light grey (25% black)
- "normal text" renders in mid-grey (50% black from global)
- Battery icon renders in dark grey (75% black from icon_color)
- Bar border is grey, ticks on read portion invert to black

- [ ] **Step 2: Test backward compatibility**

Load an existing preset (saved before this feature). Verify:
- All colours are defaults (no change)
- No errors in crash log

- [ ] **Step 3: Test defaults (zero-config)**

Reset all text/icon colours, remove all `[c]` tags. Verify overlay looks identical to before the feature was implemented.

- [ ] **Step 4: Squash and commit**

Per dev workflow, squash intermediate commits before release if needed.
