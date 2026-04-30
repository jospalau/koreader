# Per-Bar Colors & Tick Width Control — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow each standalone progress bar to have its own colors (overriding the global default), and let users control chapter tick width via a multiplier setting.

**Architecture:** Two independent additions to `main.lua` with a small touch to `tokens.lua`. Feature 1 extracts the color-resolution logic into a reusable helper, adds per-bar `colors` to bar config, and adds a per-bar color submenu. Feature 2 adds a scalar `tick_width_multiplier` setting threaded through both tick-computation sites.

**Tech Stack:** Lua (KOReader plugin), no external dependencies.

---

### Task 1: Extract `resolveColors` helper

**Files:**
- Modify: `main.lua:597-614` (extract inline color resolution into a reusable function)

- [ ] **Step 1: Add `resolveColors` helper above the paint loop**

Add this function near the top of `Bookends:paintTo` (before line 597), replacing the inline block:

```lua
local function resolveColors(bc)
    local Blitbuffer = require("ffi/blitbuffer")
    local function colorOrTransparent(v)
        if not v then return nil end
        if v >= 0xFF then return false end
        return Blitbuffer.Color8(v)
    end
    return {
        fill = colorOrTransparent(bc.fill),
        bg = colorOrTransparent(bc.bg),
        track = colorOrTransparent(bc.track),
        tick = colorOrTransparent(bc.tick),
        invert_read_ticks = bc.invert_read_ticks,
    }
end
```

Then replace lines 597-614 with:

```lua
-- Progress bar colors from settings
local bar_colors
local bc = self.settings:readSetting("bar_colors")
if bc then
    bar_colors = resolveColors(bc)
end
```

- [ ] **Step 2: Verify no visual change**

Push to Kindle via SCP, open a book with progress bars enabled. Confirm bars render identically to before.

- [ ] **Step 3: Commit**

```bash
git add main.lua
git commit -m "refactor: extract resolveColors helper for progress bar color resolution"
```

---

### Task 2: Per-bar color overrides in paint loop

**Files:**
- Modify: `main.lua:723-724` (per-bar color resolution before `paintProgressBar` call)

- [ ] **Step 1: Add per-bar color resolution before the paint call**

Replace line 723-724:

```lua
                OverlayWidget.paintProgressBar(bb, bar_x, bar_y, bar_w, bar_h, pct, ticks,
                    bar_cfg.style or "solid", paint_vertical and "vertical" or nil, paint_reverse, bar_colors)
```

With:

```lua
                local colors = bar_cfg.colors and resolveColors(bar_cfg.colors) or bar_colors
                OverlayWidget.paintProgressBar(bb, bar_x, bar_y, bar_w, bar_h, pct, ticks,
                    bar_cfg.style or "solid", paint_vertical and "vertical" or nil, paint_reverse, colors)
```

- [ ] **Step 2: Commit**

```bash
git add main.lua
git commit -m "feat: support per-bar color overrides on standalone progress bars"
```

---

### Task 3: Per-bar color submenu in `buildSingleBarMenu`

**Files:**
- Modify: `main.lua:1631-1743` (refactor `buildBarColorsMenu` to share item builders)
- Modify: `main.lua:1324-1410` (add submenu to `buildSingleBarMenu`)

- [ ] **Step 1: Extract shared color menu item builder**

Add a new private method that builds the 5+1 color menu items given a color table and save callback. Place it right before `buildBarColorsMenu` (before line 1631):

```lua
function Bookends:_buildColorItems(bc, saveColors)
    local function colorSpinner(title, field, default_pct, touchmenu_instance)
        showSpinWidget({
            title_text = title,
            value = bc[field] and math.floor((0xFF - bc[field]) * 100 / 0xFF + 0.5) or default_pct,
            value_min = 0,
            value_max = 100,
            default_value = default_pct,
            unit = "% " .. _("black"),
            callback = function(spin)
                bc[field] = 0xFF - math.floor(spin.value * 0xFF / 100 + 0.5)
                saveColors()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        })
    end

    local function pctLabel(field, default_pct)
        if bc[field] then
            local pct = math.floor((0xFF - bc[field]) * 100 / 0xFF + 0.5)
            if pct == 0 then return _("transparent") end
            return pct .. "%"
        end
        return _("default") .. " (" .. default_pct .. "%)"
    end

    return {
        {
            text_func = function()
                return _("Read color") .. ": " .. pctLabel("fill", 75)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                colorSpinner(_("Read color (% black)"), "fill", 75, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                bc.fill = nil; saveColors()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text_func = function()
                return _("Unread color") .. ": " .. pctLabel("bg", 25)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                colorSpinner(_("Unread color (% black)"), "bg", 25, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                bc.bg = nil; saveColors()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text_func = function()
                return _("Metro track color") .. ": " .. pctLabel("track", 75)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                colorSpinner(_("Metro track color (% black)"), "track", 75, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                bc.track = nil; saveColors()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text_func = function()
                return _("Tick color") .. ": " .. pctLabel("tick", 100)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                colorSpinner(_("Tick color (% black)"), "tick", 100, touchmenu_instance)
            end,
            hold_callback = function(touchmenu_instance)
                bc.tick = nil; saveColors()
                if touchmenu_instance then touchmenu_instance:updateItems() end
            end,
        },
        {
            text = _("Invert tick color on read portion"),
            checked_func = function() return bc.invert_read_ticks ~= false end,
            callback = function()
                if bc.invert_read_ticks == false then
                    bc.invert_read_ticks = nil
                else
                    bc.invert_read_ticks = false
                end
                saveColors()
            end,
        },
    }
end
```

- [ ] **Step 2: Refactor `buildBarColorsMenu` to use the shared builder**

Replace the body of `buildBarColorsMenu` (lines 1631-1743) with:

```lua
function Bookends:buildBarColorsMenu()
    local bc = self.settings:readSetting("bar_colors") or {}

    local function saveColors()
        if not bc.fill and not bc.bg and not bc.track and not bc.tick and bc.invert_read_ticks == nil then
            self.settings:delSetting("bar_colors")
        else
            self.settings:saveSetting("bar_colors", bc)
        end
        self:markDirty()
    end

    local items = self:_buildColorItems(bc, saveColors)

    -- Tick width multiplier
    table.insert(items, {
        text_func = function()
            local m = self.settings:readSetting("tick_width_multiplier", 2)
            return _("Tick width") .. ": " .. m .. "x"
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            showSpinWidget({
                title_text = _("Tick width multiplier"),
                value = self.settings:readSetting("tick_width_multiplier", 2),
                value_min = 0,
                value_max = 5,
                default_value = 2,
                callback = function(spin)
                    self.settings:saveSetting("tick_width_multiplier", spin.value)
                    self._tick_cache = nil
                    self:markDirty()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            })
        end,
        hold_callback = function(touchmenu_instance)
            self.settings:delSetting("tick_width_multiplier")
            self._tick_cache = nil
            self:markDirty()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })

    -- Reset all
    table.insert(items, {
        text = _("Reset all to defaults"),
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            bc = {}
            self.settings:delSetting("bar_colors")
            self:markDirty()
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })

    return items
end
```

- [ ] **Step 3: Add per-bar color submenu to `buildSingleBarMenu`**

At the end of the return table in `buildSingleBarMenu` (before the closing `}`), add:

```lua
        {
            text_func = function()
                if bar_cfg.colors then
                    return _("Custom colors") .. " (\u{2713})"
                end
                return _("Custom colors")
            end,
            enabled_func = isEnabled,
            sub_item_table_func = function()
                local custom_items = {}

                -- Toggle
                table.insert(custom_items, {
                    text = _("Use custom colors"),
                    checked_func = function() return bar_cfg.colors ~= nil end,
                    callback = function()
                        if bar_cfg.colors then
                            bar_cfg.colors = nil
                        else
                            bar_cfg.colors = {}
                        end
                        saveBar()
                    end,
                    separator = true,
                })

                -- Color items (only functional when custom colors enabled)
                local bc = bar_cfg.colors or {}
                local color_items = self:_buildColorItems(bc, function()
                    bar_cfg.colors = bc
                    saveBar()
                end)
                for _, item in ipairs(color_items) do
                    local orig_enabled = item.enabled_func
                    item.enabled_func = function()
                        if not bar_cfg.colors then return false end
                        return orig_enabled == nil or orig_enabled()
                    end
                    table.insert(custom_items, item)
                end

                -- Reset custom to defaults
                table.insert(custom_items, {
                    text = _("Reset custom to defaults"),
                    enabled_func = function() return bar_cfg.colors ~= nil end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        bar_cfg.colors = {}
                        saveBar()
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })

                return custom_items
            end,
        },
```

- [ ] **Step 4: Verify menus on Kindle**

Push to Kindle. Open Bookends settings:
1. Global "Progress bar colors" menu should work as before.
2. Each bar's sub-menu should show "Custom colors" at the bottom.
3. Enable custom colors on Bar 1, set Read and Unread to 0% (transparent). Confirm Bar 1 disappears (only ticks visible if ticks enabled). Confirm other bars still use global colors.
4. Disable custom colors on Bar 1. Confirm it reverts to global colors.

- [ ] **Step 5: Commit**

```bash
git add main.lua
git commit -m "feat: per-bar color overrides with shared menu builder"
```

---

### Task 4: Tick width multiplier in tick computation

**Files:**
- Modify: `main.lua:440-461` (`_computeTickCache` — use multiplier)
- Modify: `tokens.lua:37,214-217` (`Tokens.expand` — accept and use multiplier)

- [ ] **Step 1: Update `_computeTickCache` to use tick_width_multiplier**

In `main.lua`, replace line 450:

```lua
        local tick_w = math.max(1, (max_depth - depth + 1) * 2 - 1)
```

With:

```lua
        local tick_m = self.settings:readSetting("tick_width_multiplier", 2)
        local tick_w = math.max(1, (max_depth - depth + 1) * tick_m - 1)
```

- [ ] **Step 2: Thread tick_width_multiplier into `Tokens.expand`**

In `tokens.lua`, update the function signature at line 37:

```lua
function Tokens.expand(format_str, ui, session_elapsed, session_pages_read, preview_mode, tick_width_multiplier)
```

Replace line 217:

```lua
                local tick_w = math.max(1, (max_depth - depth + 1) * 2 - 1)
```

With:

```lua
                local tick_m = tick_width_multiplier or 2
                local tick_w = math.max(1, (max_depth - depth + 1) * tick_m - 1)
```

Update `expandPreview` at line 586-587 to pass it through:

```lua
function Tokens.expandPreview(format_str, ui, session_elapsed, session_pages_read, tick_width_multiplier)
    return Tokens.expand(format_str, ui, session_elapsed, session_pages_read, true, tick_width_multiplier)
end
```

- [ ] **Step 3: Pass multiplier from call sites in `main.lua`**

Find both call sites in `main.lua` that invoke `Tokens.expand` and `Tokens.expandPreview`, and pass the multiplier.

At line 757:

```lua
                    local result, is_empty, line_bar = Tokens.expand(line, self.ui, session_elapsed, session_pages,
                        nil, self.settings:readSetting("tick_width_multiplier", 2))
```

At line 2982 (preview call site), check whether it calls `expand` or `expandPreview` and pass accordingly:

```lua
                local expanded = Tokens.expand(token, self.ui, session_elapsed, session_pages,
                    nil, self.settings:readSetting("tick_width_multiplier", 2))
```

- [ ] **Step 4: Verify on Kindle**

Push to Kindle. Set tick width multiplier to 0 in the global bar colors menu. Confirm all chapter ticks render at 1px. Set to 3, confirm ticks are chunkier. Reset (long-press), confirm default (2x) behavior restored. Check both standalone bars and inline bars.

- [ ] **Step 5: Commit**

```bash
git add main.lua tokens.lua
git commit -m "feat: configurable tick width multiplier for chapter ticks"
```

---

### Task 5: Final integration test

**Files:** None (testing only)

- [ ] **Step 1: Full scenario test on Kindle**

Push final code. Test this exact scenario from the Reddit user:
1. Bar 1: bottom anchor, book type, all-level ticks, custom colors with Read=0% (transparent) and Unread=0% (transparent), thickness 16px
2. Bar 2: bottom anchor, book type, all-level ticks, custom colors with Read=0% and Unread=0%, thickness 14px, margin_v offset to stack above Bar 1
3. Tick width multiplier set to 1 (all ticks 1px)
4. Confirm: only ticks visible, no fill, thin ticks
5. Toggle Bookends overlay off/on — bars should disappear/reappear with the overlay
6. Add a Bar 3 with default global colors (visible fill) — confirm it uses global colors while 1 and 2 use transparent custom

- [ ] **Step 2: Verify backward compatibility**

Remove any per-bar `colors` keys from settings (or test on a fresh book). Confirm all bars use global colors as before.

- [ ] **Step 3: Squash and final commit**

```bash
git rebase -i HEAD~4
# squash all into one commit
```

Final message:

```
feat(bookends): per-bar color overrides and tick width multiplier

Standalone progress bars can now have individual colors (read, unread,
track, tick, invert) overriding the global defaults. Adds a tick width
multiplier setting (0-5x) controlling chapter tick thickness.

Closes motivation from user combining Bookends with external patches
for transparent tick-only bars.
```
