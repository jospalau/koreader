# Progress Bars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add progress bar rendering to bookends.koplugin — full-width dedicated bars and inline bar tokens within text regions.

**Architecture:** Two independent systems: (1) full-width bars rendered as a dedicated layer in `paintTo` before text, using blitbuffer primitives; (2) inline `%bar_book`/`%bar_chapter` tokens that expand via a parallel data channel and render as `BarWidget` within a `HorizontalRowWidget`. Both share a common `BarWidget` painter.

**Tech Stack:** Lua, KOReader widget framework, Blitbuffer API

---

### Task 1: Add BarWidget to overlay_widget.lua

**Files:**
- Modify: `overlay_widget.lua:1-6` (add Blitbuffer require)
- Modify: `overlay_widget.lua:51` (insert BarWidget class before buildTextWidget)

- [ ] **Step 1: Add Blitbuffer require**

At the top of `overlay_widget.lua`, add the Blitbuffer require after the existing requires:

```lua
local Blitbuffer = require("ffi/blitbuffer")
```

Add it after line 4 (`local Screen = Device.screen`).

- [ ] **Step 2: Add BarWidget class**

Insert the following before the `buildTextWidget` function (before line 52's doc comment). This is a minimal paint-only widget that draws a progress bar using blitbuffer primitives. It supports two styles matching KOReader's ProgressWidget: thick (bordered, rounded) and thin (flat).

```lua
--- A progress bar widget that renders a filled rectangle with optional chapter ticks.
-- Supports "thick" (bordered, rounded) and "thin" (flat, minimal) styles.
local BarWidget = {}
BarWidget.__index = BarWidget

function BarWidget:new(o)
    o = o or {}
    setmetatable(o, self)
    o.width = o.width or 100
    o.height = o.height or 5
    o.fraction = math.max(0, math.min(1, o.fraction or 0))
    o.ticks = o.ticks or {}
    o.style = o.style or "thick"
    return o
end

function BarWidget:getSize()
    return { w = self.width, h = self.height }
end

function BarWidget:paintTo(bb, x, y)
    local w, h = self.width, self.height
    if w < 1 or h < 1 then return end

    if self.style == "thin" then
        -- Thin style: flat, no border, gray background + darker fill
        bb:paintRect(x, y, w, h, Blitbuffer.COLOR_GRAY)
        local fill_w = math.floor(w * self.fraction)
        if fill_w > 0 then
            bb:paintRect(x, y, fill_w, h, Blitbuffer.COLOR_GRAY_5)
        end
    else
        -- Thick style: bordered, rounded, white bg + dark gray fill
        local border = 1
        local radius = math.min(2, math.floor(h / 2))
        bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_WHITE, radius)
        bb:paintBorder(x, y, w, h, border, Blitbuffer.COLOR_BLACK, radius)
        local inner_x = x + border + 1
        local inner_y = y + border + 1
        local inner_w = w - 2 * (border + 1)
        local inner_h = h - 2 * (border + 1)
        if inner_w > 0 and inner_h > 0 then
            local fill_w = math.floor(inner_w * self.fraction)
            if fill_w > 0 then
                bb:paintRect(inner_x, inner_y, fill_w, inner_h, Blitbuffer.COLOR_DARK_GRAY)
            end
        end
        -- Chapter ticks
        for _, tick_frac in ipairs(self.ticks) do
            local tick_x = math.floor(inner_w * tick_frac)
            if tick_x > 0 and tick_x < inner_w then
                bb:paintRect(inner_x + tick_x, inner_y, 1, inner_h, Blitbuffer.COLOR_BLACK)
            end
        end
    end
end

function BarWidget:free()
    -- Nothing to free — pure blitbuffer painting
end
```

- [ ] **Step 3: Verify no syntax errors**

Open a Lua check on the file:

Run: `lua -e "loadfile('/home/andyhazz/projects/bookends.koplugin/overlay_widget.lua')()"`
Expected: No output (no syntax errors). Note: may fail on requires since we're outside KOReader, but a syntax error will say "syntax error".

Actually, use `luac -p` which only parses:

Run: `luac -p /home/andyhazz/projects/bookends.koplugin/overlay_widget.lua`
Expected: No output (no syntax errors)

- [ ] **Step 4: Commit**

```bash
git add overlay_widget.lua
git commit -m "feat: add BarWidget class for progress bar rendering

Supports thick (bordered, rounded) and thin (flat) styles matching
KOReader's ProgressWidget. Renders using blitbuffer primitives."
```

---

### Task 2: Add HorizontalRowWidget to overlay_widget.lua

**Files:**
- Modify: `overlay_widget.lua` (insert after BarWidget, before buildTextWidget)

- [ ] **Step 1: Add HorizontalRowWidget class**

Insert after BarWidget (before the `buildTextWidget` doc comment):

```lua
--- A horizontal row of widgets (text + bar segments) painted left-to-right.
-- Each segment is vertically centered within the row height.
local HorizontalRowWidget = {}
HorizontalRowWidget.__index = HorizontalRowWidget

function HorizontalRowWidget:new(o)
    o = o or {}
    setmetatable(o, self)
    o.segments = o.segments or {}
    o.width = o.width or 0
    o.height = o.height or 0
    return o
end

function HorizontalRowWidget:getSize()
    return { w = self.width, h = self.height }
end

function HorizontalRowWidget:paintTo(bb, x, y)
    local x_offset = 0
    for _, seg in ipairs(self.segments) do
        local seg_y = y + math.floor((self.height - seg.h) / 2)
        seg.widget:paintTo(bb, x + x_offset, seg_y)
        x_offset = x_offset + seg.w
    end
end

function HorizontalRowWidget:free()
    for _, seg in ipairs(self.segments) do
        if seg.widget and seg.widget.free then
            seg.widget:free()
        end
    end
    self.segments = {}
end
```

- [ ] **Step 2: Syntax check**

Run: `luac -p /home/andyhazz/projects/bookends.koplugin/overlay_widget.lua`
Expected: No output

- [ ] **Step 3: Commit**

```bash
git add overlay_widget.lua
git commit -m "feat: add HorizontalRowWidget for inline text+bar layout"
```

---

### Task 3: Add bar routing to buildTextWidget

**Files:**
- Modify: `overlay_widget.lua` — `buildTextWidget` function and add `buildBarLine` helper

This task adds the logic to detect `cfg.bar` in line_configs and route those lines through `HorizontalRowWidget` instead of plain `TextWidget`.

- [ ] **Step 1: Add buildBarLine helper function**

Insert just before `buildTextWidget` (after HorizontalRowWidget):

```lua
--- Build a HorizontalRowWidget for a line that contains a bar token.
-- @param text string: the text portion (bar token already stripped, may be empty)
-- @param cfg table: line config with .bar = {kind, pct, ticks}, .face, .bold, etc.
-- @param available_w number: total available width for this line
-- @param max_width number or nil: truncation limit
-- @return widget, width, height
local function buildBarLine(text, cfg, available_w, max_width)
    local bar_info = cfg.bar
    local bar_h = cfg.bar_height or 5
    local bar_style = cfg.bar_style or "thick"
    local effective_w = max_width or available_w

    -- Measure text portion
    local text_trimmed = text:match("^%s*(.-)%s*$") or ""
    local text_w = 0
    local text_widget = nil
    local text_h = 0

    if text_trimmed ~= "" then
        local display_text = cfg.uppercase and text_trimmed:upper() or text_trimmed
        text_widget = TextWidget:new(textWidgetOpts{
            text = display_text,
            face = cfg.face,
            bold = cfg.bold,
            max_width = max_width,
            truncate_with_ellipsis = max_width ~= nil,
        })
        local size = text_widget:getSize()
        text_w = size.w
        text_h = size.h
    end

    -- Bar width: fixed or auto-fill
    local bar_manual_w = cfg.bar_width or 0
    local bar_w
    if bar_manual_w > 0 then
        bar_w = math.min(bar_manual_w, math.max(0, effective_w - text_w))
    else
        bar_w = math.max(0, effective_w - text_w)
    end

    if bar_w < 1 then
        -- No room for bar, just return text
        if text_widget then
            return text_widget, text_w, text_h
        end
        return nil, 0, 0
    end

    local bar_widget = BarWidget:new{
        width = bar_w,
        height = bar_h,
        fraction = bar_info.pct or 0,
        ticks = bar_info.ticks or {},
        style = bar_style,
    }

    local segments = {}
    local total_w = 0
    local max_h = 0

    if text_widget then
        table.insert(segments, { widget = text_widget, w = text_w, h = text_h })
        total_w = total_w + text_w
        if text_h > max_h then max_h = text_h end
    end

    table.insert(segments, { widget = bar_widget, w = bar_w, h = bar_h })
    total_w = total_w + bar_w
    if bar_h > max_h then max_h = bar_h end

    local row = HorizontalRowWidget:new{
        segments = segments,
        width = total_w,
        height = max_h,
    }
    return row, total_w, max_h
end
```

- [ ] **Step 2: Modify buildTextWidget to accept available_w parameter**

Change the function signature and doc comment. Find:

```lua
--- Build a TextWidget or MultiLineWidget for a single line or multi-line string.
-- @param text string: the expanded text (may contain newlines)
-- @param line_configs table: array of {face=, bold=} per line
-- @param h_anchor string: "left", "center", or "right"
-- @param max_width number or nil: if set, truncate lines to this pixel width
-- @return widget, width, height
function OverlayWidget.buildTextWidget(text, line_configs, h_anchor, max_width)
```

Replace with:

```lua
--- Build a TextWidget, MultiLineWidget, or HorizontalRowWidget for a single or multi-line string.
-- @param text string: the expanded text (may contain newlines)
-- @param line_configs table: array of {face=, bold=, bar=} per line
-- @param h_anchor string: "left", "center", or "right"
-- @param max_width number or nil: if set, truncate lines to this pixel width
-- @param available_w number or nil: total available width (for bar auto-fill sizing)
-- @return widget, width, height
function OverlayWidget.buildTextWidget(text, line_configs, h_anchor, max_width, available_w)
```

- [ ] **Step 3: Add bar routing to the single-line path**

In `buildTextWidget`, replace the single-line block:

```lua
    if #lines == 1 then
        local cfg = getConfig(1)
        local display_text = cfg.uppercase and lines[1]:upper() or lines[1]
        local tw = TextWidget:new(textWidgetOpts{
            text = display_text,
            face = cfg.face,
            bold = cfg.bold,
            max_width = max_width,
            truncate_with_ellipsis = max_width ~= nil,
        })
        local size = tw:getSize()
        return tw, size.w, size.h
    end
```

With:

```lua
    if #lines == 1 then
        local cfg = getConfig(1)
        if cfg.bar then
            return buildBarLine(lines[1], cfg, available_w or Screen:getWidth(), max_width)
        end
        local display_text = cfg.uppercase and lines[1]:upper() or lines[1]
        local tw = TextWidget:new(textWidgetOpts{
            text = display_text,
            face = cfg.face,
            bold = cfg.bold,
            max_width = max_width,
            truncate_with_ellipsis = max_width ~= nil,
        })
        local size = tw:getSize()
        return tw, size.w, size.h
    end
```

- [ ] **Step 4: Add bar routing to the multi-line path**

In the multi-line loop, replace:

```lua
    for i, line in ipairs(lines) do
        local cfg = getConfig(i)
        local display_text = cfg.uppercase and line:upper() or line
        local tw = TextWidget:new(textWidgetOpts{
            text = display_text,
            face = cfg.face,
            bold = cfg.bold,
            max_width = max_width,
            truncate_with_ellipsis = max_width ~= nil,
        })
        local size = tw:getSize()
        table.insert(line_entries, {
            widget = tw, w = size.w, h = size.h,
            v_nudge = cfg.v_nudge or 0, h_nudge = cfg.h_nudge or 0,
        })
        if size.w > max_w then max_w = size.w end
        total_h = total_h + size.h
    end
```

With:

```lua
    for i, line in ipairs(lines) do
        local cfg = getConfig(i)
        local widget, w, h
        if cfg.bar then
            widget, w, h = buildBarLine(line, cfg, available_w or Screen:getWidth(), max_width)
        else
            local display_text = cfg.uppercase and line:upper() or line
            widget = TextWidget:new(textWidgetOpts{
                text = display_text,
                face = cfg.face,
                bold = cfg.bold,
                max_width = max_width,
                truncate_with_ellipsis = max_width ~= nil,
            })
            local size = widget:getSize()
            w, h = size.w, size.h
        end
        if widget then
            table.insert(line_entries, {
                widget = widget, w = w, h = h,
                v_nudge = cfg.v_nudge or 0, h_nudge = cfg.h_nudge or 0,
            })
            if w > max_w then max_w = w end
            total_h = total_h + h
        end
    end
```

- [ ] **Step 5: Add measureTextWidth function**

Add after `buildAndMeasure`:

```lua
--- Measure the text-only pixel width of a position's content (bar lines excluded).
-- Used for overlap prevention so bars don't inflate width calculations.
function OverlayWidget.measureTextWidth(text, line_configs)
    local max_w = 0
    local i = 0
    for line in text:gmatch("([^\n]+)") do
        i = i + 1
        local cfg = line_configs[i] or line_configs[#line_configs] or { face = nil, bold = false }
        if not cfg.bar then
            local display_text = cfg.uppercase and line:upper() or line
            local tw = TextWidget:new(textWidgetOpts{
                text = display_text, face = cfg.face, bold = cfg.bold,
            })
            local w = tw:getSize().w
            tw:free()
            if w > max_w then max_w = w end
        end
    end
    return max_w
end
```

- [ ] **Step 6: Syntax check**

Run: `luac -p /home/andyhazz/projects/bookends.koplugin/overlay_widget.lua`
Expected: No output

- [ ] **Step 7: Commit**

```bash
git add overlay_widget.lua
git commit -m "feat: add bar routing in buildTextWidget and measureTextWidth

buildTextWidget now detects cfg.bar in line configs and routes those
lines through buildBarLine/HorizontalRowWidget. measureTextWidth
excludes bar lines for accurate overlap prevention."
```

---

### Task 4: Add bar token expansion to tokens.lua

**Files:**
- Modify: `tokens.lua`

- [ ] **Step 1: Add bar tokens to preview mode**

In the preview table (around line 14-32), add before the closing `}`:

After `["%v"] = "[disk]",` add:

```lua
            ["%bar_book"] = "[book bar]",
            ["%bar_chapter"] = "[ch. bar]",
```

And change the preview gsub pattern from `(%%%a)` to handle multi-char tokens. Replace:

```lua
        return format_str:gsub("(%%%a)", preview)
```

With:

```lua
        local r = format_str:gsub("%%bar_book", preview["%bar_book"])
        r = r:gsub("%%bar_chapter", preview["%bar_chapter"])
        r = r:gsub("(%%%a)", preview)
        return r
```

- [ ] **Step 2: Add bar data computation**

After the fast path check (`if not format_str:find("%%") then`) and before the preview mode block, add a helper to check for bar tokens. Actually — bar computation should happen in the main expansion path, after the `needs()` helper is defined. Add after the `needs()` function (after line 44) and before `local pageno` (line 46):

Wait — `needs()` is a closure that checks single chars. We need to check for multi-char bar tokens separately. Add after the `needs()` function definition (after line 44):

```lua
    local has_bar_book = format_str:find("%%bar_book") ~= nil
    local has_bar_chapter = format_str:find("%%bar_chapter") ~= nil
```

Then after the chapter progress block (after line 96), add bar data computation:

```lua
    -- Bar token data (parallel channel — not embedded in text)
    local bar_info = nil
    if has_bar_book or has_bar_chapter then
        local bar_pageno = pageno or 0
        local bar_doc = doc

        if has_bar_book then
            local raw_total = bar_doc:getPageCount()
            if raw_total and raw_total > 0 then
                local pct
                if bar_doc:hasHiddenFlows() then
                    local flow = bar_doc:getPageFlow(bar_pageno)
                    local flow_total = bar_doc:getTotalPagesInFlow(flow)
                    local flow_page = bar_doc:getPageNumberInFlow(bar_pageno)
                    pct = flow_total > 0 and (flow_page / flow_total) or 0
                else
                    pct = bar_pageno / raw_total
                end
                pct = math.max(0, math.min(1, pct))

                -- Chapter tick positions as fractions
                local ticks = {}
                if ui.toc then
                    local toc = ui.toc:getFullToc() or {}
                    for _, entry in ipairs(toc) do
                        if entry.page and entry.page > 1 then
                            local tick_frac
                            if bar_doc:hasHiddenFlows() then
                                local flow = bar_doc:getPageFlow(entry.page)
                                if flow == bar_doc:getPageFlow(bar_pageno) then
                                    local flow_total = bar_doc:getTotalPagesInFlow(flow)
                                    tick_frac = flow_total > 0 and (bar_doc:getPageNumberInFlow(entry.page) / flow_total) or nil
                                end
                            else
                                tick_frac = entry.page / raw_total
                            end
                            if tick_frac and tick_frac > 0 and tick_frac < 1 then
                                table.insert(ticks, tick_frac)
                            end
                        end
                    end
                end

                bar_info = bar_info or {}
                bar_info.book = { kind = "book", pct = pct, ticks = ticks }
            end
        end

        if has_bar_chapter then
            local done = ui.toc and ui.toc:getChapterPagesDone(bar_pageno)
            local total = ui.toc and ui.toc:getChapterPageCount(bar_pageno)
            if done and total and total > 0 then
                local pct = math.max(0, math.min(1, (done + 1) / total))
                bar_info = bar_info or {}
                bar_info.chapter = { kind = "chapter", pct = pct, ticks = {} }
            else
                bar_info = bar_info or {}
                bar_info.chapter = { kind = "chapter", pct = 0, ticks = {} }
            end
        end
    end
```

- [ ] **Step 3: Strip bar tokens from text and build result**

Before the `replace` table (before line 313), add bar token stripping. The bar tokens must be removed before the single-char `gsub` to avoid `%b` collisions:

```lua
    -- Strip bar tokens from text (they're delivered via bar_info, not in the string)
    local result_str = format_str
    if has_bar_book then
        result_str = result_str:gsub("%%bar_book", "")
    end
    if has_bar_chapter then
        result_str = result_str:gsub("%%bar_chapter", "")
    end
```

Then change the main gsub to operate on `result_str` instead of `format_str`. Replace:

```lua
    local result = format_str:gsub("(%%%a)", function(token)
```

With:

```lua
    local result = result_str:gsub("(%%%a)", function(token)
```

- [ ] **Step 4: Update return to include bar_info**

Change the `is_empty` logic and return. Replace:

```lua
    local is_empty = has_token and all_empty
    return result, is_empty
```

With:

```lua
    -- A line with a bar token is never considered empty
    local is_empty = has_token and all_empty and not bar_info
    -- Determine which bar applies to this line (book takes precedence if both present)
    local line_bar = nil
    if bar_info then
        if has_bar_book then
            line_bar = bar_info.book
        elseif has_bar_chapter then
            line_bar = bar_info.chapter
        end
    end
    return result, is_empty, line_bar
```

- [ ] **Step 5: Syntax check**

Run: `luac -p /home/andyhazz/projects/bookends.koplugin/tokens.lua`
Expected: No output

- [ ] **Step 6: Commit**

```bash
git add tokens.lua
git commit -m "feat: add %bar_book and %bar_chapter token expansion

Bar tokens compute progress fraction and chapter tick positions,
returning data via a parallel channel (third return value) instead
of embedding sentinels in the text string. Avoids %b collision."
```

---

### Task 5: Wire bar_info through paintTo pipeline in main.lua

**Files:**
- Modify: `main.lua` — Phase 1, Phase 2, and cache logic in `paintTo`

- [ ] **Step 1: Collect bar_info in Phase 1**

In `paintTo`, Phase 1, add a `bar_data` table alongside `expanded` and `active_line_indices`. After line 466 (`local active_line_indices = {}`), add:

```lua
    local bar_data = {} -- key -> sparse table { [line_index] = bar_info }
```

Then in the per-line expansion loop, capture the third return value. Replace:

```lua
                for j, line in ipairs(visible_lines) do
                    local result, is_empty = Tokens.expand(line, self.ui, session_elapsed, session_pages)
                    if not is_empty then
                        table.insert(expanded_lines, result)
                        table.insert(final_indices, visible_indices[j])
                    end
                end
```

With:

```lua
                local position_bars = {}
                for j, line in ipairs(visible_lines) do
                    local result, is_empty, line_bar = Tokens.expand(line, self.ui, session_elapsed, session_pages)
                    if not is_empty then
                        table.insert(expanded_lines, result)
                        table.insert(final_indices, visible_indices[j])
                        if line_bar then
                            position_bars[#expanded_lines] = line_bar
                        end
                    end
                end
```

And after `active_line_indices[pos.key] = final_indices` add:

```lua
                    if next(position_bars) then
                        bar_data[pos.key] = position_bars
                    end
```

- [ ] **Step 2: Merge bar_info into line_configs in Phase 2**

In Phase 2, after the existing line config assembly (after `cfg.uppercase = ...`), add bar info. After line 548:

```lua
            cfg.uppercase = (pos_settings.line_uppercase and pos_settings.line_uppercase[i]) or false
```

Add:

```lua
            -- Bar info from token expansion
            local pos_bars = bar_data[key]
            local line_cfg_idx = #line_configs + 1  -- this will be the index after insert
```

Wait, that's not right — we need the expanded line index, not the original line index. The `line_configs` array is built in order of `indices`, and `bar_data[key]` is keyed by expanded line index (1-based within the expanded_lines array). Let me reconsider.

Actually, `bar_data[key]` is keyed by the expanded line index (position in `expanded_lines`), and `line_configs` is built in the same order as `indices` which matches the expanded lines. So the config index matches. Add after the `cfg.uppercase` line, before `table.insert(line_configs, cfg)`:

```lua
            -- Bar data (keyed by expanded line index, same order as line_configs)
            local expanded_idx = #line_configs + 1
            if bar_data[key] and bar_data[key][expanded_idx] then
                cfg.bar = bar_data[key][expanded_idx]
                cfg.bar_height = (pos_settings.line_bar_height and pos_settings.line_bar_height[i]) or nil
                cfg.bar_width = (pos_settings.line_bar_width and pos_settings.line_bar_width[i]) or nil
                cfg.bar_style = (pos_settings.line_bar_style and pos_settings.line_bar_style[i]) or nil
            end
```

- [ ] **Step 3: Pass available_w to buildTextWidget**

In Phase 2, change the `buildTextWidget` call to pass `screen_w`. Replace:

```lua
        local widget, w, h = OverlayWidget.buildTextWidget(text, line_configs, pos_def.h_anchor, nil)
```

With:

```lua
        local widget, w, h = OverlayWidget.buildTextWidget(text, line_configs, pos_def.h_anchor, nil, screen_w)
```

- [ ] **Step 4: Use text-only width for overlap prevention**

In Phase 3, when extracting widths for overlap calculation, use `measureTextWidth` for positions that have bars. Replace:

```lua
        local left_w = pre_built[left_key] and pre_built[left_key].w or nil
        local center_w = pre_built[center_key] and pre_built[center_key].w or nil
        local right_w = pre_built[right_key] and pre_built[right_key].w or nil
```

With:

```lua
        local function getOverlapWidth(key)
            local pb = pre_built[key]
            if not pb then return nil end
            if bar_data[key] then
                return OverlayWidget.measureTextWidth(expanded[key], pb.line_configs)
            end
            return pb.w
        end
        local left_w = getOverlapWidth(left_key)
        local center_w = getOverlapWidth(center_key)
        local right_w = getOverlapWidth(right_key)
```

- [ ] **Step 5: Pass available_w in Phase 4 rebuild**

In Phase 4, when rebuilding with truncation, pass `screen_w`. Replace:

```lua
                    widget, w, h = OverlayWidget.buildTextWidget(
                        expanded[key], pb.line_configs, pb.pos_def.h_anchor, max_width)
```

With:

```lua
                    widget, w, h = OverlayWidget.buildTextWidget(
                        expanded[key], pb.line_configs, pb.pos_def.h_anchor, max_width, screen_w)
```

- [ ] **Step 6: Skip cache for bar positions**

In the dirty check, skip cache for positions with bars. Replace:

```lua
    if not self.dirty then
        local changed = false
        for key, text in pairs(expanded) do
            if text ~= self.position_cache[key] then
                changed = true
                break
            end
        end
```

With:

```lua
    if not self.dirty then
        local changed = false
        for key, text in pairs(expanded) do
            if bar_data[key] or text ~= self.position_cache[key] then
                changed = true
                break
            end
        end
```

- [ ] **Step 7: Handle single-line nudge for HorizontalRowWidget**

The existing nudge code checks `not widget.lines` to detect non-MultiLineWidget. HorizontalRowWidget also lacks `.lines`, so the nudge applies correctly. No change needed.

- [ ] **Step 8: Syntax check**

Run: `luac -p /home/andyhazz/projects/bookends.koplugin/main.lua`
Expected: No output

- [ ] **Step 9: Commit**

```bash
git add main.lua
git commit -m "feat: wire bar_info through paintTo pipeline

Phase 1 collects bar data from Tokens.expand. Phase 2 merges it
into line_configs. Phase 3 uses text-only widths for overlap.
Cache skips positions with bars to ensure repaints on page turn."
```

---

### Task 6: Add per-line bar settings to editLineString and line management

**Files:**
- Modify: `main.lua` — `editLineString`, `removeLine`, `swapLines`, `moveToRegion`

- [ ] **Step 1: Initialize per-line bar tables in editLineString**

In `editLineString`, after the existing per-line table initializations (after line 1079 `pos_settings.line_page_filter = pos_settings.line_page_filter or {}`), add:

```lua
    pos_settings.line_bar_height = pos_settings.line_bar_height or {}
    pos_settings.line_bar_width = pos_settings.line_bar_width or {}
    pos_settings.line_bar_style = pos_settings.line_bar_style or {}
```

And after `local line_page_filter = ...` (line 1090), add:

```lua
    local line_bar_height = pos_settings.line_bar_height[line_idx] -- nil = use default (5)
    local line_bar_width = pos_settings.line_bar_width[line_idx] -- nil/0 = auto-fill
    local line_bar_style = pos_settings.line_bar_style[line_idx] -- nil = "thick"
```

- [ ] **Step 2: Add bar settings to applyLivePreview**

In `applyLivePreview`, after `pos_settings.line_page_filter[line_idx] = line_page_filter`, add:

```lua
        pos_settings.line_bar_height[line_idx] = line_bar_height
        pos_settings.line_bar_width[line_idx] = line_bar_width
        pos_settings.line_bar_style[line_idx] = line_bar_style
```

- [ ] **Step 3: Add conditional bar settings buttons**

Create the bar button definitions after `page_filter_button` and its callback (after line 1165). These buttons only appear in the dialog when the line contains a bar token:

```lua
    -- Bar setting buttons (only shown when line contains a bar token)
    local BAR_STYLE_LABELS = { thick = _("Thick"), thin = _("Thin") }
    local bar_height_button = {
        text_func = function()
            return _("Bar h") .. ": " .. (line_bar_height or 5)
        end,
        callback = function() end,
    }
    local bar_width_button = {
        text_func = function()
            local w = line_bar_width or 0
            return _("Bar w") .. ": " .. (w == 0 and _("auto") or w)
        end,
        callback = function() end,
    }
    local bar_style_button = {
        text_func = function()
            return BAR_STYLE_LABELS[line_bar_style or "thick"] or _("Thick")
        end,
        callback = function() end,
    }

    bar_height_button.callback = function()
        UIManager:show(SpinWidget:new{
            value = line_bar_height or 5,
            value_min = 1,
            value_max = 60,
            default_value = 5,
            title_text = _("Bar height (px)"),
            ok_text = _("Set"),
            callback = function(spin)
                line_bar_height = spin.value
                applyLivePreview()
                format_dialog:reinit()
            end,
        })
    end

    bar_width_button.callback = function()
        UIManager:show(SpinWidget:new{
            value = line_bar_width or 0,
            value_min = 0,
            value_max = 1200,
            default_value = 0,
            title_text = _("Bar width (px, 0 = auto-fill)"),
            ok_text = _("Set"),
            callback = function(spin)
                line_bar_width = spin.value == 0 and nil or spin.value
                applyLivePreview()
                format_dialog:reinit()
            end,
        })
    end

    bar_style_button.callback = function()
        if (line_bar_style or "thick") == "thick" then
            line_bar_style = "thin"
        else
            line_bar_style = nil -- nil = thick (default)
        end
        applyLivePreview()
        format_dialog:reinit()
    end
```

- [ ] **Step 4: Conditionally include bar row in dialog buttons**

Replace the `buttons` table in the `InputDialog:new` call. Find:

```lua
        buttons = {
            -- Row 1: style controls
            { style_button, size_button, font_button, case_button, page_filter_button },
            -- Row 2: position nudge (L/R on left, label center, U/D on right)
            { nudge_left, nudge_right, nudge_label, nudge_up, nudge_down },
            -- Row 3: main actions
```

Replace with:

```lua
        buttons = (function()
            local rows = {
                -- Row 1: style controls
                { style_button, size_button, font_button, case_button, page_filter_button },
            }
            -- Row 2 (conditional): bar settings — only when line has a bar token
            if current_text:find("%%bar_") then
                table.insert(rows, { bar_height_button, bar_width_button, bar_style_button })
            end
            -- Nudge row
            table.insert(rows, { nudge_left, nudge_right, nudge_label, nudge_up, nudge_down })
            -- Main actions row
            table.insert(rows,
```

Hmm, the `buttons` field is a nested table with specific structure. Let me approach this differently — build the rows table and use it:

Replace the entire `buttons = {` block in the `InputDialog:new`:

```lua
        buttons = (function()
            local rows = {
                { style_button, size_button, font_button, case_button, page_filter_button },
            }
            if current_text:find("%%bar_") then
                table.insert(rows, { bar_height_button, bar_width_button, bar_style_button })
            end
            table.insert(rows, { nudge_left, nudge_right, nudge_label, nudge_up, nudge_down })
            table.insert(rows, {
                {
                    text = _("Cancel"),
                    callback = function()
                        self.positions[pos.key] = util.tableDeepCopy(original_settings)
                        self:savePositionSetting(pos.key)
                        UIManager:close(format_dialog)
                        self:markDirty()
                    end,
                },
                {
                    text = _("Icons"),
                    callback = function()
                        format_dialog:onCloseKeyboard()
                        IconPicker:show(function(value)
                            format_dialog:addTextToInput(value)
                        end)
                    end,
                },
                {
                    text = _("Tokens"),
                    callback = function()
                        format_dialog:onCloseKeyboard()
                        self:showTokenPicker(function(token)
                            format_dialog:addTextToInput(token)
                        end)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local new_text = format_dialog:getInputText()
                        if new_text == "" then
                            table.remove(pos_settings.lines, line_idx)
                            sparseRemove(pos_settings.line_style, line_idx)
                            sparseRemove(pos_settings.line_font_size, line_idx)
                            sparseRemove(pos_settings.line_font_face, line_idx)
                            sparseRemove(pos_settings.line_v_nudge, line_idx)
                            sparseRemove(pos_settings.line_h_nudge, line_idx)
                            sparseRemove(pos_settings.line_uppercase, line_idx)
                            sparseRemove(pos_settings.line_page_filter, line_idx)
                            sparseRemove(pos_settings.line_bar_height, line_idx)
                            sparseRemove(pos_settings.line_bar_width, line_idx)
                            sparseRemove(pos_settings.line_bar_style, line_idx)
                        else
                            pos_settings.lines[line_idx] = new_text
                            applyLivePreview()
                        end
                        self:savePositionSetting(pos.key)
                        UIManager:close(format_dialog)
                        self:markDirty()
                    end,
                },
            })
            return rows
        end)(),
```

- [ ] **Step 5: Update removeLine in showLineManageDialog**

In `showLineManageDialog`, in the `removeLine` function, add after `sparseRemove(ps.line_page_filter, line_idx)`:

```lua
        sparseRemove(ps.line_bar_height, line_idx)
        sparseRemove(ps.line_bar_width, line_idx)
        sparseRemove(ps.line_bar_style, line_idx)
```

- [ ] **Step 6: Update swapLines in showLineManageDialog**

In `swapLines`, add after the `line_page_filter` swap block:

```lua
        if ps.line_bar_height then
            ps.line_bar_height[a], ps.line_bar_height[b] = ps.line_bar_height[b], ps.line_bar_height[a]
        end
        if ps.line_bar_width then
            ps.line_bar_width[a], ps.line_bar_width[b] = ps.line_bar_width[b], ps.line_bar_width[a]
        end
        if ps.line_bar_style then
            ps.line_bar_style[a], ps.line_bar_style[b] = ps.line_bar_style[b], ps.line_bar_style[a]
        end
```

- [ ] **Step 7: Update moveToRegion**

In `moveToRegion`, after the `line_uppercase` initialization, add:

```lua
        target.line_bar_height = target.line_bar_height or {}
        target.line_bar_width = target.line_bar_width or {}
        target.line_bar_style = target.line_bar_style or {}
```

And after the `target.line_uppercase[ti]` copy, add:

```lua
        target.line_bar_height[ti] = ps.line_bar_height and ps.line_bar_height[line_idx] or nil
        target.line_bar_width[ti] = ps.line_bar_width and ps.line_bar_width[line_idx] or nil
        target.line_bar_style[ti] = ps.line_bar_style and ps.line_bar_style[line_idx] or nil
```

- [ ] **Step 8: Syntax check**

Run: `luac -p /home/andyhazz/projects/bookends.koplugin/main.lua`
Expected: No output

- [ ] **Step 9: Commit**

```bash
git add main.lua
git commit -m "feat: add per-line bar settings to line editor and management

Bar height/width/style buttons appear conditionally when a bar token
is in the line. All line management operations (remove, swap, move)
handle the new per-line bar settings."
```

---

### Task 7: Add bar tokens to TOKEN_CATALOG

**Files:**
- Modify: `main.lua` — `TOKEN_CATALOG`

- [ ] **Step 1: Add bar tokens to the catalog**

In `TOKEN_CATALOG`, add a new category after "Page / Progress". Find:

```lua
    { _("Time / Date"), {
```

Insert before it:

```lua
    { _("Progress Bars"), {
        { "%bar_book", _("Book progress bar (with chapter ticks)") },
        { "%bar_chapter", _("Chapter progress bar") },
    }},
```

- [ ] **Step 2: Commit**

```bash
git add main.lua
git commit -m "feat: add bar tokens to token picker catalog"
```

---

### Task 8: Add full-width progress bars

**Files:**
- Modify: `main.lua` — `loadSettings`, `buildPreset`, `loadPreset`, `paintTo`, `buildMainMenu`

- [ ] **Step 1: Add full-width bar defaults to loadSettings**

In `loadSettings`, after loading `self.positions`, add:

```lua
    -- Full-width progress bars
    self.progress_bars = {
        self.settings:readSetting("progress_bar_1", {
            enabled = false,
            type = "book",
            style = "thin",
            height = 3,
            v_anchor = "bottom",
            margin_v = 0,
            margin_left = 0,
            margin_right = 0,
            show_chapter_ticks = true,
        }),
        self.settings:readSetting("progress_bar_2", {
            enabled = false,
            type = "chapter",
            style = "thin",
            height = 3,
            v_anchor = "bottom",
            margin_v = 0,
            margin_left = 0,
            margin_right = 0,
            show_chapter_ticks = false,
        }),
    }
```

- [ ] **Step 2: Add progress bar rendering to paintTo**

In `paintTo`, after the screen size calculation (after `local screen_h = screen_size.h`) and before Phase 1, add:

```lua
    -- Render full-width progress bars (behind text)
    for _, bar_cfg in ipairs(self.progress_bars or {}) do
        if bar_cfg.enabled then
            local bar_w = screen_w - (bar_cfg.margin_left or 0) - (bar_cfg.margin_right or 0)
            if bar_w > 0 then
                local bar_x = x + (bar_cfg.margin_left or 0)
                local bar_y
                if bar_cfg.v_anchor == "top" then
                    bar_y = y + (bar_cfg.margin_v or 0)
                else
                    bar_y = y + screen_h - (bar_cfg.height or 3) - (bar_cfg.margin_v or 0)
                end

                local pct = 0
                local ticks = {}
                local pageno_local = self.ui.view.state.page or 0
                local doc = self.ui.document

                if bar_cfg.type == "book" then
                    local raw_total = doc:getPageCount()
                    if raw_total and raw_total > 0 then
                        if doc:hasHiddenFlows() then
                            local flow = doc:getPageFlow(pageno_local)
                            local flow_total = doc:getTotalPagesInFlow(flow)
                            local flow_page = doc:getPageNumberInFlow(pageno_local)
                            pct = flow_total > 0 and (flow_page / flow_total) or 0
                        else
                            pct = pageno_local / raw_total
                        end
                        pct = math.max(0, math.min(1, pct))

                        if bar_cfg.show_chapter_ticks and self.ui.toc then
                            local toc = self.ui.toc:getFullToc() or {}
                            for _, entry in ipairs(toc) do
                                if entry.page and entry.page > 1 then
                                    local tick_frac
                                    if doc:hasHiddenFlows() then
                                        local flow = doc:getPageFlow(entry.page)
                                        if flow == doc:getPageFlow(pageno_local) then
                                            local flow_total = doc:getTotalPagesInFlow(flow)
                                            tick_frac = flow_total > 0 and (doc:getPageNumberInFlow(entry.page) / flow_total) or nil
                                        end
                                    else
                                        tick_frac = entry.page / raw_total
                                    end
                                    if tick_frac and tick_frac > 0 and tick_frac < 1 then
                                        table.insert(ticks, tick_frac)
                                    end
                                end
                            end
                        end
                    end
                elseif bar_cfg.type == "chapter" then
                    if self.ui.toc then
                        local done = self.ui.toc:getChapterPagesDone(pageno_local)
                        local total = self.ui.toc:getChapterPageCount(pageno_local)
                        if done and total and total > 0 then
                            pct = math.max(0, math.min(1, (done + 1) / total))
                        end
                    end
                end

                OverlayWidget.paintProgressBar(bb, bar_x, bar_y, bar_w, bar_cfg.height or 3, pct, ticks, bar_cfg.style or "thin")
            end
        end
    end
```

- [ ] **Step 3: Add paintProgressBar to overlay_widget.lua**

In `overlay_widget.lua`, add a standalone paint function after the `freeWidgets` function (before `return OverlayWidget`):

```lua
--- Paint a full-width progress bar directly to a blitbuffer.
-- Used for dedicated (non-inline) progress bars that don't need widget lifecycle.
function OverlayWidget.paintProgressBar(bb, x, y, w, h, fraction, ticks, style)
    if w < 1 or h < 1 then return end
    fraction = math.max(0, math.min(1, fraction or 0))

    if style == "thin" then
        bb:paintRect(x, y, w, h, Blitbuffer.COLOR_GRAY)
        local fill_w = math.floor(w * fraction)
        if fill_w > 0 then
            bb:paintRect(x, y, fill_w, h, Blitbuffer.COLOR_GRAY_5)
        end
    else
        local border = 1
        local radius = math.min(2, math.floor(h / 2))
        bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_WHITE, radius)
        bb:paintBorder(x, y, w, h, border, Blitbuffer.COLOR_BLACK, radius)
        local inner_x = x + border + 1
        local inner_y = y + border + 1
        local inner_w = w - 2 * (border + 1)
        local inner_h = h - 2 * (border + 1)
        if inner_w > 0 and inner_h > 0 then
            local fill_w = math.floor(inner_w * fraction)
            if fill_w > 0 then
                bb:paintRect(inner_x, inner_y, fill_w, inner_h, Blitbuffer.COLOR_DARK_GRAY)
            end
            for _, tick_frac in ipairs(ticks or {}) do
                local tick_x = math.floor(inner_w * tick_frac)
                if tick_x > 0 and tick_x < inner_w then
                    bb:paintRect(inner_x + tick_x, inner_y, 1, inner_h, Blitbuffer.COLOR_BLACK)
                end
            end
        end
    end
end
```

- [ ] **Step 4: Update buildPreset**

In `buildPreset`, after the positions loop, add:

```lua
    preset.progress_bars = util.tableDeepCopy(self.progress_bars)
```

- [ ] **Step 5: Update loadPreset**

In `loadPreset`, after the positions block, add:

```lua
    if preset.progress_bars then
        self.progress_bars = util.tableDeepCopy(preset.progress_bars)
        self.settings:saveSetting("progress_bar_1", self.progress_bars[1])
        self.settings:saveSetting("progress_bar_2", self.progress_bars[2])
    end
```

- [ ] **Step 6: Syntax check**

Run: `luac -p /home/andyhazz/projects/bookends.koplugin/main.lua && luac -p /home/andyhazz/projects/bookends.koplugin/overlay_widget.lua`
Expected: No output

- [ ] **Step 7: Commit**

```bash
git add main.lua overlay_widget.lua
git commit -m "feat: add full-width progress bar rendering

Two independent bar slots rendered behind text in paintTo. Each bar
has configurable type, style, height, anchor, and margins. Included
in preset save/load."
```

---

### Task 9: Add progress bar settings menu

**Files:**
- Modify: `main.lua` — `buildMainMenu`

- [ ] **Step 1: Add progress bars submenu**

In `buildMainMenu`, after the separator line (`menu[#menu].separator = true`) and before the Presets entry, add:

```lua
    -- Progress bars submenu
    table.insert(menu, {
        text = _("Progress bars"),
        enabled_func = function() return self.enabled end,
        sub_item_table_func = function()
            return self:buildProgressBarMenu()
        end,
    })
```

- [ ] **Step 2: Add buildProgressBarMenu method**

Add the new method after `buildMainMenu` ends:

```lua
function Bookends:buildProgressBarMenu()
    local items = {}
    for idx, bar_cfg in ipairs(self.progress_bars) do
        local label = idx == 1 and _("Bar 1") or _("Bar 2")
        table.insert(items, {
            text_func = function()
                if bar_cfg.enabled then
                    local type_label = bar_cfg.type == "chapter" and _("chapter") or _("book")
                    return label .. " (" .. type_label .. ", " .. bar_cfg.v_anchor .. ")"
                end
                return label
            end,
            checked_func = function() return bar_cfg.enabled end,
            sub_item_table_func = function()
                return self:buildSingleBarMenu(idx, bar_cfg)
            end,
        })
    end
    return items
end

function Bookends:buildSingleBarMenu(bar_idx, bar_cfg)
    local function saveBar()
        self.settings:saveSetting("progress_bar_" .. bar_idx, bar_cfg)
        self:markDirty()
    end

    return {
        {
            text = _("Enable"),
            checked_func = function() return bar_cfg.enabled end,
            callback = function()
                bar_cfg.enabled = not bar_cfg.enabled
                saveBar()
            end,
        },
        {
            text_func = function()
                return _("Type") .. ": " .. (bar_cfg.type == "chapter" and _("Chapter") or _("Book"))
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                bar_cfg.type = bar_cfg.type == "book" and "chapter" or "book"
                saveBar()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text_func = function()
                return _("Style") .. ": " .. (bar_cfg.style == "thin" and _("Thin") or _("Thick"))
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                bar_cfg.style = bar_cfg.style == "thin" and "thick" or "thin"
                saveBar()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text_func = function()
                return _("Height") .. ": " .. (bar_cfg.height or 3) .. "px"
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:showSpinner(_("Bar height (px)"), bar_cfg.height or 3, 1, 60, 3,
                    function(val)
                        bar_cfg.height = val
                        saveBar()
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end)
            end,
        },
        {
            text_func = function()
                return _("Anchor") .. ": " .. (bar_cfg.v_anchor == "top" and _("Top") or _("Bottom"))
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                bar_cfg.v_anchor = bar_cfg.v_anchor == "top" and "bottom" or "top"
                saveBar()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text_func = function()
                return _("Vertical margin") .. ": " .. (bar_cfg.margin_v or 0) .. "px"
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:showNudgeDialog(_("Vertical margin"), bar_cfg.margin_v or 0, function(val)
                    bar_cfg.margin_v = val
                    saveBar()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end)
            end,
        },
        {
            text_func = function()
                return _("Left margin") .. ": " .. (bar_cfg.margin_left or 0) .. "px"
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:showNudgeDialog(_("Left margin"), bar_cfg.margin_left or 0, function(val)
                    bar_cfg.margin_left = val
                    saveBar()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end)
            end,
        },
        {
            text_func = function()
                return _("Right margin") .. ": " .. (bar_cfg.margin_right or 0) .. "px"
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self:showNudgeDialog(_("Right margin"), bar_cfg.margin_right or 0, function(val)
                    bar_cfg.margin_right = val
                    saveBar()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end)
            end,
        },
        {
            text = _("Show chapter tick marks"),
            enabled_func = function() return bar_cfg.type == "book" end,
            checked_func = function() return bar_cfg.show_chapter_ticks end,
            callback = function()
                bar_cfg.show_chapter_ticks = not bar_cfg.show_chapter_ticks
                saveBar()
            end,
        },
    }
end
```

- [ ] **Step 3: Add showNudgeDialog helper**

Add after the menu methods:

```lua
function Bookends:showNudgeDialog(title, initial_value, on_change)
    local value = initial_value
    local dialog

    local function update(delta)
        value = math.max(0, value + delta)
        on_change(value)
        dialog:reinit()
    end

    dialog = require("ui/widget/inputdialog"):new{
        title = title .. ": " .. value .. "px",
        buttons = {
            {
                { text = "-10", callback = function() update(-10) end },
                { text = "-1",  callback = function() update(-1) end },
                { text = _("Reset"), callback = function() value = 0; on_change(0); dialog:reinit() end },
                { text = "+1",  callback = function() update(1) end },
                { text = "+10", callback = function() update(10) end },
            },
            {
                {
                    text = _("Close"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    -- Update the title dynamically on reinit
    local orig_reinit = dialog.reinit
    dialog.reinit = function(self_dialog)
        self_dialog.title = title .. ": " .. value .. "px"
        orig_reinit(self_dialog)
    end
    UIManager:show(dialog)
end
```

- [ ] **Step 4: Syntax check**

Run: `luac -p /home/andyhazz/projects/bookends.koplugin/main.lua`
Expected: No output

- [ ] **Step 5: Commit**

```bash
git add main.lua
git commit -m "feat: add progress bar settings menu with nudge controls

New 'Progress bars' submenu with per-bar settings: enable, type,
style, height, anchor, margins (with +1/+10 nudge buttons), and
chapter tick toggle."
```

---

### Task 10: Update version and final cleanup

**Files:**
- Modify: `_meta.lua`

- [ ] **Step 1: Bump version**

Read `_meta.lua` and bump the version to reflect this feature release (likely from 2.2.0 to 2.3.0).

- [ ] **Step 2: Final syntax check on all files**

Run: `luac -p /home/andyhazz/projects/bookends.koplugin/tokens.lua /home/andyhazz/projects/bookends.koplugin/overlay_widget.lua /home/andyhazz/projects/bookends.koplugin/main.lua`
Expected: No output

- [ ] **Step 3: Commit**

```bash
git add _meta.lua
git commit -m "feat(bookends): v2.3.0 — progress bars

Add full-width progress bars (two independent bar slots with
configurable type, style, height, anchor, and margins) and inline
bar tokens (%bar_book, %bar_chapter) for use within text regions.

Inspired by SH4DOWSIX's progress bar PR (#7)."
```
