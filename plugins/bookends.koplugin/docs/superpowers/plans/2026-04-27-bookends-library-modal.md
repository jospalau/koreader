# Bookends Library Modal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the three pickers (presets, icons, tokens-with-conditionals) onto a shared `BookendsLibraryModal` widget with submit-then-show name search, lifted from the existing custom preset modal's chrome.

**Architecture:** Single shared widget (`menu/library_modal.lua`) provides chrome (header, optional tabs, search input above chip strip, two-row chip wrap, paginated list-or-grid result area, footer). Three sibling domain modules (`menu/preset_manager_modal.lua` refactored, `menu/icons_library.lua` new, `menu/tokens_library.lua` new) consume the shared widget with domain-specific config (data sources, chip lists, row/cell renderers, footer actions). The legacy `IconPicker.showPickerMenu` wrapper is deleted; the line editor's call sites swap to the new modals. A build script (`tools/build_nerdfont_names.py`) generates a 3,700-entry Nerd Font name → codepoint data file for icon search.

**Tech Stack:** Lua 5.1 + KOReader widget toolkit (Menu, FocusManager, InputDialog, FrameContainer, etc); Python 3 + fontTools for the build script; Kindle Paperwhite 5 (1248×1648, framebuffer SSH access via `ssh kindle`) for visual verification.

**Reference spec:** `docs/superpowers/specs/2026-04-27-bookends-library-modal-design.md`

---

## Pre-flight

### Task 0: Set up the feature branch

**Files:**
- None modified yet

- [ ] **Step 1: Create the feature branch from master**

```bash
git checkout master
git pull
git checkout -b feature/library-modal
```

- [ ] **Step 2: Verify clean working tree and Kindle SSH connectivity**

```bash
git status                # expect: "nothing to commit, working tree clean"
ssh kindle 'echo ok'      # expect: "ok"
```

If Kindle SSH fails, ask the user to wake the device and verify Wi-Fi.

- [ ] **Step 3: Verify Lua syntax-check tool is available**

```bash
luac -v                   # expect: "Lua 5.1.<n>"
```

If `luac` is missing, install it via the system package manager (`sudo pacman -S lua51` or similar). The `luac -p` syntax-check is the project's first line of defense before any tar-pipe to Kindle.

---

## Phase 1 — Library Modal substrate + preset modal refactor

The highest-risk phase: it changes the most code with no new user-visible functionality. Aim is byte-for-byte preserved behaviour for the preset modal at the end of Phase 1.

### Task 1: Skeleton `menu/library_modal.lua`

**Files:**
- Create: `menu/library_modal.lua`

- [ ] **Step 1: Create the skeleton module**

```lua
--- BookendsLibraryModal — shared chrome widget for the preset, icons, and
--- tokens libraries. Renders header, optional tabs, search input, chip strip
--- (with two-row wrap), paginated list-or-grid result area, and footer.
--- Domain-specific data and per-row rendering are supplied by the caller via
--- a config table. See docs/superpowers/specs/2026-04-27-bookends-library-modal-design.md
--- for the full config shape.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("bookends_i18n").gettext

local LibraryModal = WidgetContainer:extend{
    name = "library_modal",
    config = nil,           -- domain config table (see spec)
    -- runtime state
    active_tab = nil,       -- key of active tab, or nil if no tabs
    active_chip = nil,      -- key of active chip, or nil
    page = 1,
    search_query = nil,     -- current submitted query, or nil
}

function LibraryModal:init()
    assert(self.config, "LibraryModal requires a config table")
    -- Pre-populate runtime state from config defaults
    if self.config.tabs and #self.config.tabs > 0 then
        self.active_tab = self.config.tabs[1].key
    end
    -- Default chip is "all" if present in the chip strip
    local chips = self.config.chip_strip and self.config.chip_strip(self.active_tab) or {}
    for _, chip in ipairs(chips) do
        if chip.is_active then self.active_chip = chip.key; break end
    end
    if not self.active_chip and chips[1] then
        self.active_chip = chips[1].key
    end
    -- Build the modal frame on init; populated lazily via :refresh()
    self:_buildFrame()
end

function LibraryModal:_buildFrame()
    -- Frame-level dimensions match the existing preset modal's modal dimensions
    -- (90% of screen width, content-driven height up to 85% screen height).
    -- Implementation populates self[1] via :refresh().
end

function LibraryModal:refresh()
    -- Rebuild the inner content. Called on tab change, chip tap, search submit,
    -- page change. Avoids rebuilding the modal frame itself (which would
    -- re-trigger :init in some paint cycles).
end

return LibraryModal
```

- [ ] **Step 2: Run `luac -p` to verify syntax**

```bash
luac -p menu/library_modal.lua
```
Expected: no output (success).

- [ ] **Step 3: Commit the skeleton**

```bash
git add menu/library_modal.lua
git commit -m "feat(library-modal): add skeleton module"
```

### Task 2: Extract the title bar + tab bar from preset modal

**Files:**
- Modify: `menu/library_modal.lua`
- Reference: `menu/preset_manager_modal.lua` (read its title-bar and tab-bar render code; do not modify yet)

- [ ] **Step 1: Read the preset modal's title-bar code to understand layout**

```bash
grep -nE 'title|tabs|setTab' menu/preset_manager_modal.lua | head -30
```

Identify the title widget construction (typically a TextWidget + segmented tab buttons in a horizontal group with a separator below). Note the exact size, padding, and font face used so the extracted version preserves visual parity.

- [ ] **Step 2: Add the title/tab rendering helper to `menu/library_modal.lua`**

Insert into `LibraryModal` (paste after `_buildFrame`):

```lua
function LibraryModal:_renderTitleBar(content_width)
    local Font = require("ui/font")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local LineWidget = require("ui/widget/linewidget")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen

    local title_w = TextWidget:new{
        text = self.config.title,
        face = Font:getFace("cfont", 22),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local right_widget
    if self.config.tabs then
        -- Build segmented [Tab1 | Tab2] pill row; active tab is filled black,
        -- inactive is outlined. Tap on an inactive tab fires on_tab_change.
        right_widget = self:_renderTabSegments()
    else
        right_widget = HorizontalSpan:new{ width = 0 }
    end

    -- Title left, tab segments right, with the gap absorbed by a flexible spacer.
    local row = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = content_width - right_widget:getSize().w, h = title_w:getSize().h },
            title_w,
        },
        right_widget,
    }

    return VerticalGroup:new{
        row,
        VerticalSpan:new{ width = Size.span.vertical_default },
        LineWidget:new{
            background = Blitbuffer.COLOR_BLACK,
            dimen = Geom:new{ w = content_width, h = Size.line.thin },
        },
    }
end

function LibraryModal:_renderTabSegments()
    -- Returns a HorizontalGroup of tap-able segment widgets. Active segment
    -- has black bg + white text; inactive has white bg + black text. On tap,
    -- :_onTabSelect(key) is called, which updates active_tab + invokes
    -- self.config.on_tab_change + self:refresh().
    local Font = require("ui/font")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    local seg_pad_h = Screen:scaleBySize(12)
    local seg_pad_v = Screen:scaleBySize(6)

    local function seg(label, is_active, on_tap)
        local fg = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local bg = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local tw = TextWidget:new{
            text = label, face = Font:getFace("cfont", 14), bold = is_active, fgcolor = fg,
        }
        local fc = FrameContainer:new{
            bordersize = 0, padding = 0,
            padding_left = seg_pad_h, padding_right = seg_pad_h,
            padding_top = seg_pad_v, padding_bottom = seg_pad_v,
            margin = 0, background = bg, tw,
        }
        local ic = InputContainer:new{ dimen = Geom:new{ w = fc:getSize().w, h = fc:getSize().h }, fc }
        ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = ic.dimen } } }
        ic.onTapSelect = function() on_tap(); return true end
        return ic
    end

    local hg = HorizontalGroup:new{ align = "center" }
    for i, tab in ipairs(self.config.tabs) do
        if i > 1 then table.insert(hg, HorizontalSpan:new{ width = Screen:scaleBySize(8) }) end
        local is_active = tab.key == self.active_tab
        table.insert(hg, seg(tab.label, is_active, function() self:_onTabSelect(tab.key) end))
    end
    return hg
end

function LibraryModal:_onTabSelect(tab_key)
    if self.active_tab == tab_key then return end
    self.active_tab = tab_key
    self.search_query = nil
    self.page = 1
    -- Default chip on the new tab is its first chip (or "all")
    local chips = self.config.chip_strip and self.config.chip_strip(self.active_tab) or {}
    self.active_chip = chips[1] and chips[1].key or nil
    if self.config.on_tab_change then self.config.on_tab_change(tab_key) end
    self:refresh()
end
```

- [ ] **Step 3: Verify syntax**

```bash
luac -p menu/library_modal.lua
```

- [ ] **Step 4: Commit**

```bash
git add menu/library_modal.lua
git commit -m "feat(library-modal): add title bar + tab segment rendering"
```

### Task 3: Search input widget (above the chip strip)

**Files:**
- Modify: `menu/library_modal.lua`

- [ ] **Step 1: Add the search input render method**

Append to `LibraryModal`:

```lua
function LibraryModal:_renderSearchInput(content_width)
    local Font = require("ui/font")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen
    local placeholder = self.config.search_placeholder
        and self.config.search_placeholder(self.active_tab)
        or _("Search…")
    -- The visible "input" is a tappable framed box. Tapping opens a
    -- single-purpose InputDialog with keyboard-on-open. On submit, we set
    -- self.search_query, reset self.page = 1, and refresh.
    local label_text = self.search_query and (self.search_query) or placeholder
    local label_color = self.search_query and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    local label = TextWidget:new{
        text = label_text,
        face = Font:getFace("cfont", 16),
        fgcolor = label_color,
    }

    local pad_h = Screen:scaleBySize(12)
    local pad_v = Screen:scaleBySize(8)
    local inner_h = label:getSize().h + 2 * pad_v
    local frame = FrameContainer:new{
        bordersize = Size.border.thin,
        padding = 0,
        padding_left = pad_h, padding_right = pad_h,
        padding_top = pad_v, padding_bottom = pad_v,
        margin = 0,
        radius = Screen:scaleBySize(4),
        background = Blitbuffer.COLOR_WHITE,
        dimen = Geom:new{ w = content_width, h = inner_h },
        label,
    }

    local ic = InputContainer:new{
        dimen = Geom:new{ w = content_width, h = inner_h },
        frame,
    }
    local GestureRange = require("ui/gesturerange")
    ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = ic.dimen } } }
    ic.onTapSelect = function() self:_openSearchDialog(); return true end
    return ic
end

function LibraryModal:_openSearchDialog()
    local InputDialog = require("ui/widget/inputdialog")
    local placeholder = self.config.search_placeholder
        and self.config.search_placeholder(self.active_tab) or _("Search…")
    local dlg
    dlg = InputDialog:new{
        title = placeholder,
        input = self.search_query or "",
        input_type = "text",
        buttons = {{
            { text = _("Cancel"), id = "cancel", callback = function() UIManager:close(dlg) end },
            { text = _("Search"), id = "search", is_enter_default = true, callback = function()
                local q = dlg:getInputText()
                UIManager:close(dlg)
                self:_onSearchSubmit(q)
            end },
        }},
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()  -- keyboard-on-open per spec; single-purpose intent
end

function LibraryModal:_onSearchSubmit(q)
    if not q or #q < 2 then
        -- Empty/short input clears the search rather than submitting noise
        self.search_query = nil
    else
        self.search_query = q
    end
    self.page = 1
    if self.config.on_search_submit then self.config.on_search_submit(self.search_query) end
    self:refresh()
end
```

- [ ] **Step 2: Verify syntax**

```bash
luac -p menu/library_modal.lua
```

- [ ] **Step 3: Commit**

```bash
git add menu/library_modal.lua
git commit -m "feat(library-modal): add search input + dialog with keyboard-on-open"
```

### Task 4: Chip strip with two-row wrap

**Files:**
- Modify: `menu/library_modal.lua`

- [ ] **Step 1: Add the chip strip render method with width-aware wrapping**

Append:

```lua
function LibraryModal:_renderChipStrip(content_width)
    local Font = require("ui/font")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local TextWidget = require("ui/widget/textwidget")
    local Screen = Device.screen

    if not self.config.chip_strip then return nil end
    local chips = self.config.chip_strip(self.active_tab)
    if not chips or #chips == 0 then return nil end

    local pad_h = Screen:scaleBySize(10)
    local pad_v = Screen:scaleBySize(4)
    local chip_gap = Screen:scaleBySize(6)
    local row_gap = Screen:scaleBySize(6)

    local function buildChip(chip)
        local is_active = chip.key == self.active_chip
        local fg = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local bg = is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local tw = TextWidget:new{
            text = chip.label, face = Font:getFace("cfont", 13), bold = is_active, fgcolor = fg,
        }
        local fc = FrameContainer:new{
            bordersize = is_active and 0 or Size.border.thin,
            padding = 0,
            padding_left = pad_h, padding_right = pad_h,
            padding_top = pad_v, padding_bottom = pad_v,
            margin = 0, background = bg, radius = Screen:scaleBySize(12),
            tw,
        }
        local ic = InputContainer:new{ dimen = Geom:new{ w = fc:getSize().w, h = fc:getSize().h }, fc }
        ic.ges_events = { TapSelect = { GestureRange:new{ ges = "tap", range = ic.dimen } } }
        ic.onTapSelect = function() self:_onChipTap(chip.key); return true end
        return ic
    end

    -- Greedy left-to-right packing into rows.
    local rows = {}
    local current_row = HorizontalGroup:new{ align = "center" }
    local current_w = 0
    for i, chip in ipairs(chips) do
        local cw = buildChip(chip)
        local cw_w = cw:getSize().w
        local needed = (i == 1) and cw_w or (current_w + chip_gap + cw_w)
        if needed > content_width and #current_row > 0 then
            -- start a new row
            table.insert(rows, current_row)
            current_row = HorizontalGroup:new{ align = "center", cw }
            current_w = cw_w
        else
            if i > 1 and current_w > 0 then
                table.insert(current_row, HorizontalSpan:new{ width = chip_gap })
                current_w = current_w + chip_gap
            end
            table.insert(current_row, cw)
            current_w = current_w + cw_w
        end
        -- Hard cap at 2 rows; if we'd need a 3rd, truncate (no domain currently
        -- needs more than 2 rows, but defensive bound prevents UI explosion).
        if #rows >= 2 then break end
    end
    table.insert(rows, current_row)

    -- Stack rows into a single vertical group with row gaps
    local vg = VerticalGroup:new{ align = "left" }
    for i, row in ipairs(rows) do
        if i > 1 then table.insert(vg, VerticalSpan:new{ width = row_gap }) end
        table.insert(vg, row)
    end
    return vg
end

function LibraryModal:_onChipTap(chip_key)
    if self.active_chip == chip_key then return end
    self.active_chip = chip_key
    self.page = 1
    if self.config.on_chip_tap then self.config.on_chip_tap(chip_key) end
    self:refresh()
end
```

- [ ] **Step 2: Verify syntax**

```bash
luac -p menu/library_modal.lua
```

- [ ] **Step 3: Commit**

```bash
git add menu/library_modal.lua
git commit -m "feat(library-modal): add chip strip with two-row wrap"
```

### Task 5: List-mode result area

**Files:**
- Modify: `menu/library_modal.lua`

- [ ] **Step 1: Add the list-mode result-area renderer**

```lua
function LibraryModal:_renderListArea(content_width, area_height)
    local rows_per_page = self.config.rows_per_page or 5
    local total = self.config.item_count and self.config.item_count() or 0

    -- Empty-state callback fires only when zero items. Domain provides the
    -- panel widget if it wants to show one (e.g. the gallery's help panel).
    if total == 0 and self.config.empty_state then
        local panel = self.config.empty_state(content_width, area_height)
        if panel then return panel end
    end

    local total_pages = math.max(1, math.ceil(total / rows_per_page))
    if self.page > total_pages then self.page = total_pages end

    local start_idx = (self.page - 1) * rows_per_page + 1
    local end_idx = math.min(start_idx + rows_per_page - 1, total)

    local row_height = area_height / rows_per_page
    local vg = VerticalGroup:new{ align = "left" }
    for idx = start_idx, end_idx do
        local item = self.config.item_at(idx)
        if item then
            local slot_dimen = Geom:new{ w = content_width, h = row_height }
            table.insert(vg, self.config.row_renderer(item, slot_dimen))
        end
    end
    -- Pad with empty space if fewer than rows_per_page items remain on the
    -- last page, so the modal doesn't shrink mid-pagination.
    local rendered = end_idx - start_idx + 1
    if rendered < rows_per_page then
        local Spacer = require("ui/widget/spacer")
        for _i = rendered + 1, rows_per_page do
            table.insert(vg, VerticalSpan:new{ width = row_height })
        end
    end
    return vg
end
```

- [ ] **Step 2: Verify syntax**

```bash
luac -p menu/library_modal.lua
```

- [ ] **Step 3: Commit**

```bash
git add menu/library_modal.lua
git commit -m "feat(library-modal): add list-mode result area with pagination"
```

### Task 6: Grid-mode result area

**Files:**
- Modify: `menu/library_modal.lua`

- [ ] **Step 1: Add the grid-mode renderer**

```lua
function LibraryModal:_renderGridArea(content_width, area_height)
    local cells_per_page = self.config.cells_per_page(content_width)
    local total = self.config.item_count and self.config.item_count() or 0
    local total_pages = math.max(1, math.ceil(total / cells_per_page))
    if self.page > total_pages then self.page = total_pages end

    -- Determine column count from cell-renderer's preferred cell width
    local target_cell_w = Device.screen:scaleBySize(290)
    local cols = math.max(3, math.floor(content_width / target_cell_w))
    local rows = math.ceil(cells_per_page / cols)
    local cell_w = math.floor(content_width / cols)
    local cell_h = math.floor(area_height / rows)

    local start_idx = (self.page - 1) * cells_per_page + 1
    local end_idx = math.min(start_idx + cells_per_page - 1, total)

    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local vg = VerticalGroup:new{ align = "left" }
    local hg = HorizontalGroup:new{ align = "top" }
    local in_row = 0
    for idx = start_idx, end_idx do
        local item = self.config.item_at(idx)
        if item then
            local cell_dimen = Geom:new{ w = cell_w, h = cell_h }
            local cell_widget = self.config.cell_renderer(item, cell_dimen)
            if self.config.cell_long_tap then
                local GestureRange = require("ui/gesturerange")
                local ic = InputContainer:new{
                    dimen = Geom:new{ w = cell_w, h = cell_h },
                    cell_widget,
                }
                ic.ges_events = {
                    Hold = { GestureRange:new{ ges = "hold", range = ic.dimen } },
                }
                ic.onHold = function() self.config.cell_long_tap(item); return true end
                cell_widget = ic
            end
            table.insert(hg, cell_widget)
            in_row = in_row + 1
            if in_row >= cols then
                table.insert(vg, hg)
                hg = HorizontalGroup:new{ align = "top" }
                in_row = 0
            end
        end
    end
    if in_row > 0 then table.insert(vg, hg) end
    return vg
end
```

- [ ] **Step 2: Verify syntax**

```bash
luac -p menu/library_modal.lua
```

- [ ] **Step 3: Commit**

```bash
git add menu/library_modal.lua
git commit -m "feat(library-modal): add grid-mode result area"
```

### Task 7: Pagination footer (chevrons + page indicator)

**Files:**
- Modify: `menu/library_modal.lua`

- [ ] **Step 1: Add pagination-row renderer**

```lua
function LibraryModal:_renderPagination(content_width)
    local Button = require("ui/widget/button")
    local Font = require("ui/font")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local TextWidget = require("ui/widget/textwidget")
    local T = require("ffi/util").template

    local total = self.config.item_count and self.config.item_count() or 0
    local per_page = self.config.rows_per_page
        or (self.config.cells_per_page and self.config.cells_per_page(content_width))
        or 1
    local total_pages = math.max(1, math.ceil(total / per_page))

    local function chev(label, callback, enabled)
        return Button:new{
            text = label,
            text_func = nil,
            bordersize = 0,
            radius = 0,
            padding = Device.screen:scaleBySize(8),
            face = Font:getFace("cfont", 16),
            callback = enabled and callback or function() end,
            enabled = enabled,
        }
    end

    local first = chev("\xE2\x80\xB9\xE2\x80\xB9", function() self.page = 1; self:refresh() end, self.page > 1)
    local prev  = chev("\xE2\x80\xB9", function() self.page = self.page - 1; self:refresh() end, self.page > 1)
    local pageinfo = TextWidget:new{
        text = T(_("Page %1 of %2"), self.page, total_pages),
        face = Font:getFace("cfont", 14),
    }
    local nxt = chev("\xE2\x80\xBA", function() self.page = self.page + 1; self:refresh() end, self.page < total_pages)
    local last = chev("\xE2\x80\xBA\xE2\x80\xBA", function() self.page = total_pages; self:refresh() end, self.page < total_pages)
    local gap = HorizontalSpan:new{ width = Device.screen:scaleBySize(20) }

    return HorizontalGroup:new{ align = "center", first, gap, prev, gap, pageinfo, gap, nxt, gap, last }
end
```

- [ ] **Step 2: Verify syntax**

```bash
luac -p menu/library_modal.lua
```

- [ ] **Step 3: Commit**

```bash
git add menu/library_modal.lua
git commit -m "feat(library-modal): add pagination footer"
```

### Task 8: Footer button row

**Files:**
- Modify: `menu/library_modal.lua`

- [ ] **Step 1: Add footer-actions renderer**

```lua
function LibraryModal:_renderFooter(content_width)
    local Button = require("ui/widget/button")
    local Font = require("ui/font")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local LineWidget = require("ui/widget/linewidget")

    local actions = self.config.footer_actions or {}
    local btns = {}
    for _i, action in ipairs(actions) do
        local enabled = true
        if action.enabled_when then enabled = action.enabled_when() end
        table.insert(btns, Button:new{
            text = action.label,
            face = Font:getFace("cfont", 16),
            bold = action.primary == true,
            bordersize = 0,
            radius = 0,
            callback = function() if enabled then action.on_tap() end end,
            enabled = enabled,
        })
    end

    if #btns == 0 then return nil end

    -- Single button gets full width; multiple buttons split equally with thin
    -- vertical separators between them.
    if #btns == 1 then
        return btns[1]
    end

    local hg = HorizontalGroup:new{ align = "center" }
    local btn_width = math.floor(content_width / #btns)
    for i, btn in ipairs(btns) do
        btn.width = btn_width
        if i > 1 then
            table.insert(hg, LineWidget:new{
                background = Blitbuffer.COLOR_DARK_GRAY,
                dimen = Geom:new{ w = Size.line.thin, h = Device.screen:scaleBySize(28) },
            })
        end
        table.insert(hg, btn)
    end
    return hg
end
```

- [ ] **Step 2: Verify syntax**

```bash
luac -p menu/library_modal.lua
```

- [ ] **Step 3: Commit**

```bash
git add menu/library_modal.lua
git commit -m "feat(library-modal): add configurable footer button row"
```

### Task 9: Compose `:refresh()` and modal frame

**Files:**
- Modify: `menu/library_modal.lua`

- [ ] **Step 1: Replace the placeholder `_buildFrame` and `refresh` with the real implementations**

Replace those two methods (defined as stubs in Task 1) with:

```lua
function LibraryModal:_buildFrame()
    local Screen = Device.screen
    self.modal_w = math.floor(Screen:getWidth() * 0.9)
    self.modal_h = math.floor(Screen:getHeight() * 0.85)
    self.content_pad = Screen:scaleBySize(16)
    self.content_w = self.modal_w - 2 * self.content_pad

    self.frame = FrameContainer:new{
        bordersize = Size.border.window,
        padding = 0,
        padding_top = self.content_pad,
        padding_bottom = self.content_pad,
        padding_left = self.content_pad,
        padding_right = self.content_pad,
        margin = 0,
        radius = Screen:scaleBySize(8),
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left" },
    }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = Screen:getHeight() },
        self.frame,
    }
    self:refresh()
end

function LibraryModal:refresh()
    -- Recompute body height after fixed-height chrome (title, search, chips,
    -- pagination, footer) is laid out. Result area gets whatever's left.
    local cw = self.content_w
    local title = self:_renderTitleBar(cw)
    local search = self:_renderSearchInput(cw)
    local chips = self:_renderChipStrip(cw)
    local pagination = self:_renderPagination(cw)
    local footer = self:_renderFooter(cw)
    local body_height = self.modal_h - 2 * self.content_pad
        - title:getSize().h
        - search:getSize().h
        - (chips and chips:getSize().h or 0)
        - pagination:getSize().h
        - (footer and footer:getSize().h or 0)
        - 6 * Size.span.vertical_default

    local result_area
    if self.config.cell_renderer then
        result_area = self:_renderGridArea(cw, body_height)
    else
        result_area = self:_renderListArea(cw, body_height)
    end

    local body = VerticalGroup:new{
        align = "left",
        title,
        VerticalSpan:new{ width = Size.span.vertical_default },
        search,
        VerticalSpan:new{ width = Size.span.vertical_default },
    }
    if chips then
        table.insert(body, chips)
        table.insert(body, VerticalSpan:new{ width = Size.span.vertical_default })
    end
    table.insert(body, result_area)
    table.insert(body, VerticalSpan:new{ width = Size.span.vertical_default })
    table.insert(body, pagination)
    if footer then
        table.insert(body, VerticalSpan:new{ width = Size.span.vertical_default })
        table.insert(body, footer)
    end

    self.frame[1] = body
    UIManager:setDirty(self, "ui")
end
```

- [ ] **Step 2: Add the missing requires at the top**

Ensure these requires are present at the top of the file (add any missing):

```lua
local VerticalSpan = require("ui/widget/verticalspan")
```

- [ ] **Step 3: Verify syntax**

```bash
luac -p menu/library_modal.lua
```

- [ ] **Step 4: Commit**

```bash
git add menu/library_modal.lua
git commit -m "feat(library-modal): wire up refresh + frame composition"
```

### Task 10: Match function with TDD

**Files:**
- Create: `_test_library_modal.lua` (project root, alongside other `_test_*.lua` files)
- Modify: `menu/library_modal.lua`

- [ ] **Step 1: Write the failing test for the match function**

Create `_test_library_modal.lua`:

```lua
-- Dev-box test for menu/library_modal.lua's match function.
-- Pure-Lua, no KOReader dependencies.

-- Stub the requires that library_modal pulls in for chrome rendering — only
-- the match function is exercised here.
local stub_meta = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return function() end end }) end })
package.loaded["ffi/blitbuffer"] = setmetatable({}, { __index = function() return 0 end })
package.loaded["ui/widget/container/centercontainer"] = stub_meta
package.loaded["device"] = { screen = setmetatable({}, { __index = function() return function() return 1024 end end }) }
package.loaded["ui/widget/container/framecontainer"] = stub_meta
package.loaded["ui/geometry"] = { new = function(_, t) return t end }
package.loaded["ui/widget/container/inputcontainer"] = stub_meta
package.loaded["ui/size"] = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return 1 end end }) end })
package.loaded["ui/uimanager"] = stub_meta
package.loaded["ui/widget/verticalgroup"] = stub_meta
package.loaded["ui/widget/verticalspan"] = stub_meta
package.loaded["ui/widget/container/widgetcontainer"] = { extend = function(_, t) return t end }
package.loaded["bookends_i18n"] = { gettext = function(s) return s end }

local pass, fail = 0, 0
local function eq(a, b, msg) if a == b then pass = pass + 1 else fail = fail + 1; print(("FAIL %s: expected %q got %q"):format(msg or "", tostring(b), tostring(a))) end end
local function test(name, fn) print("--- " .. name); fn() end

-- Load the matches() helper. We expose it on the module for testability.
local LM = require("menu.library_modal")
local matches = LM._matchesQuery  -- to be added in next step

test("returns false for query under 2 chars", function()
    eq(matches("nf-fa-bookmark", ""), false, "empty")
    eq(matches("nf-fa-bookmark", "a"), false, "single char")
end)

test("single-term substring match", function()
    eq(matches("nf-fa-bookmark", "book"), true, "book in bookmark")
    eq(matches("nf-fa-bookmark", "BOOK"), true, "case-insensitive")
    eq(matches("nf-fa-bookmark", "xyzz"), false, "no match")
end)

test("multi-term AND match", function()
    eq(matches("nf-mdi-clock-outline", "clock outline"), true, "both terms present")
    eq(matches("nf-mdi-clock-outline", "clock smashed"), false, "second term absent")
    eq(matches("nf-fa-clock-o", "fa clock"), true, "set-prefix + concept")
end)

print(("\n%d passed, %d failed"):format(pass, fail))
if fail > 0 then os.exit(1) end
```

Run it:

```bash
cd /home/andyhazz/projects/bookends.koplugin && lua _test_library_modal.lua
```

Expected: FAIL with "_matchesQuery is nil" or similar.

- [ ] **Step 2: Add the match function to `library_modal.lua`**

Insert near the top of `menu/library_modal.lua` (after the requires, before the `LibraryModal:extend` line):

```lua
--- Multi-term substring AND match. Public for unit testing.
--- Empty or 1-char query returns false (avoids surfacing thousands of matches
--- on a single keystroke).
function LibraryModal._matchesQuery(text, query)
    if not query or #query < 2 then return false end
    local lc = (text or ""):lower()
    for term in query:lower():gmatch("%S+") do
        if not lc:find(term, 1, true) then return false end
    end
    return true
end
```

- [ ] **Step 3: Run the test to verify it passes**

```bash
lua _test_library_modal.lua
```

Expected: all pass, exit 0.

- [ ] **Step 4: Commit**

```bash
git add menu/library_modal.lua _test_library_modal.lua
git commit -m "feat(library-modal): add multi-term substring match function with tests"
```

### Task 11: Refactor `menu/preset_manager_modal.lua` to consume `library_modal`

This is the largest refactor task. The existing 1,784-line preset modal becomes a thin domain-config builder. All chrome rendering moves to the shared widget; preset-specific logic (data loading, row layout, empty state, footer actions) stays.

**Files:**
- Modify: `menu/preset_manager_modal.lua`

- [ ] **Step 1: Read the current preset_manager_modal.lua to identify chrome vs domain-specific code**

```bash
wc -l menu/preset_manager_modal.lua
grep -n "^function" menu/preset_manager_modal.lua | head -30
```

Tag each function as either "chrome" (now obsolete; the library_modal does it) or "domain" (kept). Chrome candidates: title-bar render, tab segments, sort segments, pagination chevrons, footer button row, modal frame, dismiss handler. Domain candidates: `renderPresetCard`, `galleryHelpPanel`, `setTab`, `setMySort`, `setGallerySort`, `Gallery.fetchIndex` callbacks, `Gallery.fetchCounts`, `installPreset`, overflow-action handlers.

- [ ] **Step 2: Create the domain-config builder at the top of the file**

Add this builder near the start of the module (after requires, before existing logic):

```lua
local function buildPresetLibraryConfig(self)
    return {
        title = _("Preset library"),
        tabs = {
            { key = "local",   label = _("My presets") },
            { key = "gallery", label = _("Gallery") },
        },
        on_tab_change = function(tab_key)
            if tab_key == "gallery" and galleryIsStale(self) then
                fetchGalleryIndex(self)
            end
        end,
        chip_strip = function(active_tab)
            if active_tab == "local" then
                return {
                    { key = "latest",  label = _("Latest"),  is_active = self.my_sort == "latest" },
                    { key = "starred", label = _("Starred"), is_active = self.my_sort == "starred" },
                }
            else
                local engaged = self.gallery_loading or self.gallery_index or self.gallery_error
                return {
                    { key = "latest",  label = _("Latest"),  is_active = engaged and self.gallery_sort == "latest" },
                    { key = "popular", label = _("Popular"), is_active = engaged and self.gallery_sort == "popular" },
                }
            end
        end,
        on_chip_tap = function(chip_key)
            if self.active_tab == "local" then
                self.setMySort(chip_key)
            else
                self.setGallerySort(chip_key)
            end
        end,
        search_placeholder = function(active_tab)
            if active_tab == "local" then return _("Search my presets by name…") end
            return _("Search gallery presets by name…")
        end,
        on_search_submit = function(query)
            self.current_search = query
        end,
        rows_per_page = 5,
        item_count = function() return #(currentItemList(self)) end,
        item_at = function(idx) return currentItemList(self)[idx] end,
        row_renderer = function(item, slot_dimen) return renderPresetCard(self, item, slot_dimen) end,
        empty_state = function(width, height)
            if self.active_tab == "gallery" and not self.gallery_index then
                return galleryHelpPanel(self, width, height)
            end
            return nil
        end,
        footer_actions = {
            { key = "close",   label = _("Close"),   on_tap = function() self:close() end },
            { key = "manage",  label = _("Manage…"), on_tap = function() self:openManageMenu() end,
              enabled_when = function() return self.selected_preset ~= nil end },
            { key = "install", label = _("Install"), on_tap = function() self:installSelected() end,
              primary = true, enabled_when = function() return self.active_tab == "gallery" and self.selected_preset ~= nil end },
        },
    }
end
```

- [ ] **Step 3: Replace the modal-frame init with library_modal instantiation**

Find the existing `function PresetManager:show()` (or equivalent entry point that constructs the modal frame). Replace its body with:

```lua
function PresetManager:show()
    local LibraryModal = require("menu.library_modal")
    local config = buildPresetLibraryConfig(self)
    self.modal = LibraryModal:new{ config = config }
    UIManager:show(self.modal)
end
```

- [ ] **Step 4: Identify and delete now-obsolete chrome-rendering code**

Remove from `menu/preset_manager_modal.lua`:
- The hand-rolled `segment(...)` helper for tab/sort pills (now in `library_modal._renderTabSegments` and `_renderChipStrip`).
- The pagination chevron buttons (now in `library_modal._renderPagination`).
- The footer Close/Manage/Install layout (now in `library_modal._renderFooter`).
- The modal frame setup (FrameContainer, CenterContainer wrapping, dimen calculations) — replaced by library_modal's frame.

Keep:
- `renderPresetCard(self, item, slot_dimen)` — the row renderer.
- `galleryHelpPanel(self, w, h)` — the empty-state callback.
- `currentItemList(self)` — returns the local or gallery list filtered/sorted by current chip.
- `setMySort`, `setGallerySort`, `setTab`.
- All Gallery.fetchIndex / Gallery.fetchCounts handlers.
- All preset-action handlers (install, manage, overflow actions).

- [ ] **Step 5: Verify syntax + run any existing tests**

```bash
luac -p menu/preset_manager_modal.lua
luac -p menu/library_modal.lua
lua _test_preset_naming.lua    # existing test, must still pass
```

- [ ] **Step 6: Commit the refactor**

```bash
git add menu/preset_manager_modal.lua
git commit -m "refactor(preset-modal): consume BookendsLibraryModal for chrome"
```

### Task 12: Verify Phase 1 on Kindle

**Files:**
- None modified

- [ ] **Step 1: Tar-pipe to Kindle**

```bash
tar -cf - --exclude=tools --exclude=.git --exclude=docs --exclude='_test_*.lua' . \
  | ssh kindle "cd /mnt/us/koreader/plugins/bookends.koplugin && tar -xf -"
```

- [ ] **Step 2: Ask the user to restart KOReader** (per memory: `killall -HUP` doesn't reload, manual restart required).

- [ ] **Step 3: User opens the preset library and verifies parity**

Checklist for the user:
- [ ] Title "Preset library" rendered at top.
- [ ] Tab row "My presets | Gallery" — tap toggles, active tab is filled black.
- [ ] Chip strip below title: My presets shows Latest/Starred; Gallery shows Latest/Popular.
- [ ] Search input is visible above the chips with the correct placeholder per tab.
- [ ] Tapping search opens InputDialog with keyboard up.
- [ ] Preset rows render exactly as before: bold name + author + description + ✓ on installed gallery items + 🎨 on colour presets.
- [ ] Pagination chevrons (‹‹ ‹ Page X of N › ››) work; advance and retreat as expected.
- [ ] Footer: Close / Manage… / Install with correct enable/disable rules.
- [ ] Long-tap on a Local-tab row opens overflow menu (rename / edit description / duplicate / delete).
- [ ] Gallery empty state renders the "Discover more presets" help panel before first refresh; tapping a chip triggers refresh.

- [ ] **Step 4: Capture a Kindle screenshot to confirm parity**

```bash
ssh kindle 'cat /dev/fb0' > /tmp/kindle_phase1.raw && python3 -c "
from PIL import Image
import numpy as np
data = np.fromfile('/tmp/kindle_phase1.raw', dtype=np.uint8)
img = Image.frombuffer('L', (1248, 1648), data[:1248*1648], 'raw', 'L', 1248, 1)
img.save('/tmp/kindle_phase1.png')
"
```

Read `/tmp/kindle_phase1.png` and visually compare with the pre-Phase-1 screenshot of the preset library. They should be visually identical (search input is the only addition).

- [ ] **Step 5: Iterate on any visual regressions**

If anything visually drifts (font sizes, spacing, alignment, button sizes), debug by comparing the chrome rendering in `library_modal.lua` against the original preset modal's rendering. Fix and re-tar-pipe until parity is achieved.

- [ ] **Step 6: Commit any fix-up changes**

```bash
git add -A
git commit -m "fix(library-modal): preset modal visual parity adjustments"
```

---

## Phase 2 — Icons modal

### Task 13: Build script `tools/build_nerdfont_names.py`

**Files:**
- Create: `tools/build_nerdfont_names.py`

- [ ] **Step 1: Verify Python + fontTools available**

```bash
python3 -c "from fontTools.ttLib import TTFont; print('ok')"
```

If missing: `pip install --user fonttools`.

- [ ] **Step 2: Write the script**

```python
#!/usr/bin/env python3
"""Generate bookends_nerdfont_names.lua from the bundled symbols.ttf
+ the upstream Nerd Fonts glyphnames.json.

Usage:
    python3 tools/build_nerdfont_names.py \\
        --symbols-ttf /usr/lib/koreader/fonts/nerdfonts/symbols.ttf \\
        --glyphnames-json /path/to/downloaded/glyphnames.json \\
        --output bookends_nerdfont_names.lua
"""

import argparse
import json
import sys
from datetime import datetime, UTC
from pathlib import Path

try:
    from fontTools.ttLib import TTFont
except ImportError:
    sys.exit("fontTools not installed. Run: pip install --user fonttools")


def collect_font_codepoints(ttf_path: Path) -> set[int]:
    """Return the set of PUA codepoints (U+E000-U+F8FF) present in the font's cmap."""
    f = TTFont(str(ttf_path))
    cmap = f.getBestCmap()
    return {cp for cp in cmap if 0xE000 <= cp <= 0xF8FF}


def parse_glyphnames(json_path: Path) -> dict[str, int]:
    """Return name → codepoint dict from upstream glyphnames.json."""
    with json_path.open() as f:
        data = json.load(f)
    out = {}
    for name, info in data.items():
        if not isinstance(info, dict): continue
        code = info.get("code")
        if not code: continue
        try:
            cp = int(code, 16)
        except ValueError:
            continue
        out[name] = cp
    return out


def emit_lua(entries: list[tuple[str, int]], output_path: Path,
             ttf_path: Path, json_path: Path, font_cmap_size: int):
    """Write the Lua file."""
    when = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [
        "-- Generated by tools/build_nerdfont_names.py — do not edit by hand.",
        f"-- Source font: {ttf_path}",
        f"-- Source font cmap: {font_cmap_size} glyphs in PUA range U+E000-U+F8FF",
        f"-- Source names: {json_path}",
        f"-- Generated: {when}",
        "",
        f"-- Total entries: {len(entries)}",
        "",
        "local M = {",
    ]
    for name, cp in entries:
        # name uses no characters that need Lua escaping; verify
        if '"' in name or '\\' in name:
            raise ValueError(f"unexpected character in name: {name!r}")
        lines.append(f'    {{name="{name}", code=0x{cp:04X}}},')
    lines.append("}")
    lines.append("")
    lines.append("return M")
    lines.append("")

    output_path.write_text("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--symbols-ttf", type=Path,
                    default=Path("/usr/lib/koreader/fonts/nerdfonts/symbols.ttf"))
    ap.add_argument("--glyphnames-json", type=Path, required=True)
    ap.add_argument("--output", type=Path,
                    default=Path("bookends_nerdfont_names.lua"))
    args = ap.parse_args()

    if not args.symbols_ttf.exists():
        sys.exit(f"--symbols-ttf not found: {args.symbols_ttf}")
    if not args.glyphnames_json.exists():
        sys.exit(f"--glyphnames-json not found: {args.glyphnames_json}")

    font_cps = collect_font_codepoints(args.symbols_ttf)
    print(f"Font cmap PUA glyph count: {len(font_cps)}")

    name_to_cp = parse_glyphnames(args.glyphnames_json)
    print(f"Upstream glyphnames entries: {len(name_to_cp)}")

    matched = [(name, cp) for name, cp in name_to_cp.items() if cp in font_cps]
    matched.sort(key=lambda nc: nc[0])
    print(f"Matched entries (font cmap ∩ glyphnames): {len(matched)}")

    emit_lua(matched, args.output, args.symbols_ttf, args.glyphnames_json,
             font_cmap_size=len(font_cps))
    print(f"Wrote {args.output}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Make executable**

```bash
chmod +x tools/build_nerdfont_names.py
```

- [ ] **Step 4: Commit**

```bash
git add tools/build_nerdfont_names.py
git commit -m "feat(tools): add Nerd Font names build script"
```

### Task 14: Generate `bookends_nerdfont_names.lua`

**Files:**
- Create: `bookends_nerdfont_names.lua` (generated)

- [ ] **Step 1: Download upstream glyphnames.json**

```bash
mkdir -p /tmp/nerd-fonts-data
curl -fsSL https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json \
    -o /tmp/nerd-fonts-data/glyphnames.json
ls -la /tmp/nerd-fonts-data/glyphnames.json
```

- [ ] **Step 2: Run the build script**

```bash
python3 tools/build_nerdfont_names.py \
    --symbols-ttf /usr/lib/koreader/fonts/nerdfonts/symbols.ttf \
    --glyphnames-json /tmp/nerd-fonts-data/glyphnames.json \
    --output bookends_nerdfont_names.lua
```

Expected output: ~3,500-3,700 matched entries written.

- [ ] **Step 3: Verify the generated Lua loads**

```bash
luac -p bookends_nerdfont_names.lua
lua -e "local m = dofile('bookends_nerdfont_names.lua'); print(#m, 'entries'); print(m[1].name, string.format('0x%04X', m[1].code))"
```

Expected: prints entry count + first entry name + codepoint.

- [ ] **Step 4: Commit**

```bash
git add bookends_nerdfont_names.lua
git commit -m "feat(icons): add generated Nerd Font names data"
```

### Task 15: Skeleton `menu/icons_library.lua`

**Files:**
- Create: `menu/icons_library.lua`

- [ ] **Step 1: Build the skeleton with the curated catalogue**

```lua
--- Icons library: replaces bookends_icon_picker.lua. Renders the curated
--- catalogue in browse mode (chip-filtered grid) and the full Nerd Font name
--- set in search mode (lazy-loaded on first search submit).

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local LibraryModal = require("menu.library_modal")
local UIManager = require("ui/uimanager")
local _ = require("bookends_i18n").gettext

local IconsLibrary = {}

-- Lifted from bookends_icon_picker.lua; restructured into per-chip lists.
IconsLibrary.CURATED_BY_CHIP = {
    dynamic = {
        { glyph = "\xEE\x9E\x90", label = _("Battery (changes with level)"), insert_value = "%batt_icon" },
        { glyph = "\xEE\xB2\xA8", label = _("Wi-Fi (changes with status)"),  insert_value = "%wifi" },
    },
    device = {
        { glyph = "\xEF\x83\xAB", label = _("Lightbulb") },
        { glyph = "\xF0\x9F\x92\xA1", label = _("Lightbulb emoji") },
        -- ... (full list lifted from existing IconPicker.CATALOG; see Step 2)
    },
    -- reading, time, status, symbols, arrows, progress, separators sections
    -- are filled in Step 2.
}

--- Lazy-loaded full Nerd Font names data. nil until first search.
local nerdfont_names = nil

local function loadNerdFontNames()
    if nerdfont_names == nil then
        nerdfont_names = require("bookends_nerdfont_names")
    end
    return nerdfont_names
end

--- Extract the source set name from a Nerd Font canonical name.
--- "nf-fa-bookmark" → "FontAwesome 4"
--- "nf-mdi-clock-outline" → "Material Design Icons"
local SET_LABELS = {
    cod = "Codicons", custom = "Nerd Fonts custom", dev = "Devicons",
    fa = "FontAwesome 4", fab = "FontAwesome Brands", fae = "FontAwesome Extra",
    far = "FontAwesome Regular", fas = "FontAwesome Solid",
    iec = "IEC Power", linea = "Linea", md = "Material Design Icons",
    mdi = "Material Design Icons", oct = "Octicons", pl = "Powerline",
    ple = "Powerline Extra", pom = "Pomicons", seti = "Seti UI",
    weather = "Weather Icons",
}
function IconsLibrary._setLabelOf(name)
    local set = name:match("^nf%-([%w]+)%-")
    return SET_LABELS[set] or "Nerd Fonts"
end

--- Strip the "nf-{set}-" prefix to get the user-facing suffix.
function IconsLibrary._suffixOf(name)
    return name:gsub("^nf%-[%w]+%-", "")
end

return IconsLibrary
```

- [ ] **Step 2: Lift the full curated catalogue from `bookends_icon_picker.lua`**

Open `bookends_icon_picker.lua` and find `IconPicker.CATALOG` (around line 10-154). Each top-level entry is `{ category_label, { {display, description, insert_value}, ... } }`. Translate this into the chip-keyed structure:

```lua
IconsLibrary.CURATED_BY_CHIP = {
    dynamic = { ... },     -- entries from the "Dynamic" category
    device = { ... },      -- entries from "Device"
    reading = { ... },     -- "Reading"
    time = { ... },        -- "Time"
    status = { ... },      -- "Status"
    symbols = { ... },     -- "Symbols"
    arrows = { ... },      -- "Arrows"
    progress = { ... },    -- "Progress blocks"
    separators = { ... },  -- "Separators"
}
```

Each entry retains: `glyph` (the display character), `label` (the description from the original), `insert_value` (optional; falls back to glyph for static entries).

- [ ] **Step 3: Verify syntax**

```bash
luac -p menu/icons_library.lua
```

- [ ] **Step 4: Add tests for the helper functions**

Append to `_test_library_modal.lua`:

```lua
-- ============================================================================
-- icons_library helpers
-- ============================================================================

package.loaded["menu.library_modal"] = LM
package.loaded["bookends_nerdfont_names"] = {
    {name="nf-fa-bookmark", code=0xF02E},
    {name="nf-mdi-clock-outline", code=0xF150},
}
local IconsLibrary = require("menu.icons_library")

test("setLabelOf returns canonical set names", function()
    eq(IconsLibrary._setLabelOf("nf-fa-bookmark"), "FontAwesome 4", "fa")
    eq(IconsLibrary._setLabelOf("nf-mdi-clock"), "Material Design Icons", "mdi")
    eq(IconsLibrary._setLabelOf("nf-cod-account"), "Codicons", "cod")
    eq(IconsLibrary._setLabelOf("nf-unknown-foo"), "Nerd Fonts", "fallback")
end)

test("suffixOf strips the nf-set- prefix", function()
    eq(IconsLibrary._suffixOf("nf-fa-bookmark"), "bookmark", "fa")
    eq(IconsLibrary._suffixOf("nf-mdi-clock-outline"), "clock-outline", "compound suffix")
end)
```

Run:

```bash
lua _test_library_modal.lua
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add menu/icons_library.lua _test_library_modal.lua
git commit -m "feat(icons-library): skeleton + curated catalogue + helpers"
```

### Task 16: Icons modal entry-point + chip-scoped browse

**Files:**
- Modify: `menu/icons_library.lua`

- [ ] **Step 1: Add the show entry-point**

Append to `menu/icons_library.lua`:

```lua
local CHIPS = {
    { key = "all",        label = _("All") },
    { key = "dynamic",    label = _("Dynamic") },
    { key = "device",     label = _("Device") },
    { key = "reading",    label = _("Reading") },
    { key = "time",       label = _("Time") },
    { key = "status",     label = _("Status") },
    { key = "symbols",    label = _("Symbols") },
    { key = "arrows",     label = _("Arrows") },
    { key = "progress",   label = _("Progress") },
    { key = "separators", label = _("Separators") },
}

--- Build the visible item list for the current chip + search state.
local function currentItemList(state)
    local items
    if state.search_query then
        local names = loadNerdFontNames()
        items = {}
        for _i, entry in ipairs(names) do
            if LibraryModal._matchesQuery(entry.name, state.search_query) then
                table.insert(items, {
                    glyph = utf8FromCodepoint(entry.code),
                    label = IconsLibrary._suffixOf(entry.name),
                    secondary = IconsLibrary._setLabelOf(entry.name),
                    canonical = entry.name,
                    code = entry.code,
                    insert_value = utf8FromCodepoint(entry.code),
                })
                if #items >= 200 then break end
            end
        end
    elseif state.active_chip == "all" or not state.active_chip then
        items = {}
        for _, chip in ipairs(CHIPS) do
            if chip.key ~= "all" then
                local list = IconsLibrary.CURATED_BY_CHIP[chip.key] or {}
                for _i, e in ipairs(list) do table.insert(items, e) end
            end
        end
    else
        items = IconsLibrary.CURATED_BY_CHIP[state.active_chip] or {}
    end
    return items
end

--- Convert a Unicode codepoint integer to its UTF-8 byte sequence.
function utf8FromCodepoint(cp)
    if cp < 0x80 then
        return string.char(cp)
    elseif cp < 0x800 then
        return string.char(0xC0 + math.floor(cp/0x40), 0x80 + (cp % 0x40))
    elseif cp < 0x10000 then
        return string.char(
            0xE0 + math.floor(cp/0x1000),
            0x80 + math.floor((cp%0x1000)/0x40),
            0x80 + (cp%0x40))
    else
        return string.char(
            0xF0 + math.floor(cp/0x40000),
            0x80 + math.floor((cp%0x40000)/0x1000),
            0x80 + math.floor((cp%0x1000)/0x40),
            0x80 + (cp%0x40))
    end
end

function IconsLibrary:show(on_select)
    local state = { active_chip = "all", search_query = nil }
    local config = {
        title = _("Icons library"),
        chip_strip = function()
            local out = {}
            for _, c in ipairs(CHIPS) do
                table.insert(out, { key = c.key, label = c.label, is_active = c.key == state.active_chip })
            end
            return out
        end,
        on_chip_tap = function(chip_key) state.active_chip = chip_key end,
        search_placeholder = function()
            local names = loadNerdFontNames()
            return string.format(_("Search %d icons by name…"), #names)
        end,
        on_search_submit = function(query) state.search_query = query end,
        cells_per_page = function(content_w)
            local target = Device.screen:scaleBySize(290)
            local cols = math.max(3, math.floor(content_w / target))
            return cols * 6
        end,
        cell_renderer = function(item, dimen)
            return IconsLibrary._renderCell(item, dimen)
        end,
        cell_long_tap = function(item)
            IconsLibrary._showCellTooltip(item)
        end,
        item_count = function() return #currentItemList(state) end,
        item_at = function(idx) return currentItemList(state)[idx] end,
        footer_actions = {
            { key = "close", label = _("Close"), on_tap = function() UIManager:close(self.modal) end },
        },
    }
    -- Wire row tap to call on_select with the insert_value.
    config.on_item_tap = function(item)
        local val = item.insert_value or item.glyph
        UIManager:close(self.modal)
        if on_select then on_select(val) end
    end
    self.modal = LibraryModal:new{ config = config }
    UIManager:show(self.modal)
end
```

- [ ] **Step 2: Implement `_renderCell` and `_showCellTooltip` stubs**

Append:

```lua
function IconsLibrary._renderCell(item, dimen)
    local Font = require("ui/font")
    local TextWidget = require("ui/widget/textwidget")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Size = require("ui/size")

    local glyph_w = TextWidget:new{
        text = item.glyph or "",
        face = Font:getFace("symbols", 36),  -- KOReader's Nerd Font symbols face
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local label_w = TextWidget:new{
        text = item.label or "",
        face = Font:getFace("cfont", 11),
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = dimen.w - 8,
    }
    local stack = VerticalGroup:new{
        align = "center",
        glyph_w,
        VerticalSpan:new{ width = Size.span.vertical_default },
        label_w,
    }
    return CenterContainer:new{ dimen = dimen, stack }
end

function IconsLibrary._showCellTooltip(item)
    local Notification = require("ui/widget/notification")
    local UIManager = require("ui/uimanager")
    local code_str = item.code and string.format("U+%04X", item.code) or ""
    local body = item.canonical and (item.canonical .. " · " .. code_str) or item.label
    UIManager:show(Notification:new{ text = body, timeout = 3 })
end
```

- [ ] **Step 3: Hook the cell tap into `library_modal._renderGridArea`**

Modify `_renderGridArea` in `menu/library_modal.lua` to also wire a tap handler in addition to the existing long-tap handler. Replace the cell-input-container construction:

```lua
-- in _renderGridArea, replace the existing cell wrapping
local ic = InputContainer:new{ dimen = Geom:new{ w = cell_w, h = cell_h }, cell_widget }
ic.ges_events = {
    TapSelect = { GestureRange:new{ ges = "tap", range = ic.dimen } },
}
if self.config.cell_long_tap then
    ic.ges_events.Hold = { GestureRange:new{ ges = "hold", range = ic.dimen } }
    ic.onHold = function() self.config.cell_long_tap(item); return true end
end
ic.onTapSelect = function()
    if self.config.on_item_tap then self.config.on_item_tap(item) end
    return true
end
cell_widget = ic
```

(Same wiring should exist for the list area's row tap. Add an analogous `on_item_tap` hook to `_renderListArea` if not already present.)

- [ ] **Step 4: Verify syntax**

```bash
luac -p menu/icons_library.lua
luac -p menu/library_modal.lua
```

- [ ] **Step 5: Commit**

```bash
git add menu/icons_library.lua menu/library_modal.lua
git commit -m "feat(icons-library): show entry + grid renderer + tap routing"
```

### Task 17: Wire the line editor's icon-picker call site

**Files:**
- Modify: `bookends_line_editor.lua`

- [ ] **Step 1: Read the current call site**

```bash
sed -n '40,50p' bookends_line_editor.lua
sed -n '340,355p' bookends_line_editor.lua
```

- [ ] **Step 2: Swap the require + show invocation**

In `bookends_line_editor.lua` line 42:

```lua
-- Before:
local IconPicker = require("bookends_icon_picker")

-- After:
local IconsLibrary = require("menu.icons_library")
```

In line 342:

```lua
-- Before:
IconPicker:show(function(value)

-- After:
IconsLibrary:show(function(value)
```

- [ ] **Step 3: Verify syntax**

```bash
luac -p bookends_line_editor.lua
```

- [ ] **Step 4: Commit**

```bash
git add bookends_line_editor.lua
git commit -m "refactor(line-editor): swap IconPicker for IconsLibrary"
```

### Task 18: Delete `bookends_icon_picker.lua`

**Files:**
- Delete: `bookends_icon_picker.lua`

- [ ] **Step 1: Verify no remaining references**

```bash
grep -rn "bookends_icon_picker\|IconPicker" --include="*.lua" .
```

Expected: only references in `menu/token_picker.lua` (which Phase 3 deletes).

- [ ] **Step 2: If `menu/token_picker.lua` references IconPicker, leave the file alone** for now. Phase 3 will replace it. Skip to Step 3.

- [ ] **Step 3: Delete the file**

```bash
git rm bookends_icon_picker.lua
```

- [ ] **Step 4: But wait — token_picker still requires it.** Check Phase 3 ordering. We need to either (a) defer the deletion until Phase 3, or (b) shim IconPicker temporarily.

The pragmatic approach: defer deletion to after Phase 3 builds the tokens modal. Revert the deletion:

```bash
git checkout HEAD -- bookends_icon_picker.lua
```

Note in commit history that the deletion is deferred. No commit needed — the file is back.

### Task 19: Verify Phase 2 on Kindle

**Files:**
- None modified

- [ ] **Step 1: Tar-pipe to Kindle**

```bash
tar -cf - --exclude=tools --exclude=.git --exclude=docs --exclude='_test_*.lua' . \
  | ssh kindle "cd /mnt/us/koreader/plugins/bookends.koplugin && tar -xf -"
```

- [ ] **Step 2: Ask user to restart KOReader**

- [ ] **Step 3: Open the line editor, tap the icon-picker entry**

User checks:
- [ ] Modal opens with title "Icons library".
- [ ] Search input is visible above the chip strip with placeholder "Search 3,xxx icons by name…" (count populated from data file).
- [ ] Chip strip wraps to two rows on the Kindle's display.
- [ ] Active chip "All" by default; tapping a chip narrows the curated catalogue.
- [ ] Icons render as a grid (3 or 4 columns, depending on width) with glyph + label per cell.
- [ ] Tapping a curated icon inserts its glyph (or token, for dynamic entries) into the line and closes the modal.
- [ ] Tapping the search input opens InputDialog with keyboard up.
- [ ] Submitting "bookmark" returns matches across all sets, alphabetically grouped.
- [ ] Submitting "fa clock" returns FontAwesome clock variants only.
- [ ] Submitting "xyzz" returns the no-matches message.
- [ ] Long-tap on a cell shows the canonical name + codepoint tooltip.
- [ ] Pagination chevrons advance through the result pages.
- [ ] Footer Close button dismisses the modal.

- [ ] **Step 4: Capture screenshot and review**

```bash
ssh kindle 'cat /dev/fb0' > /tmp/kindle_phase2.raw && python3 -c "
from PIL import Image
import numpy as np
data = np.fromfile('/tmp/kindle_phase2.raw', dtype=np.uint8)
img = Image.frombuffer('L', (1248, 1648), data[:1248*1648], 'raw', 'L', 1248, 1)
img.save('/tmp/kindle_phase2.png')
"
```

Read `/tmp/kindle_phase2.png` and confirm visual quality.

- [ ] **Step 5: Iterate on issues**

If grid spacing / glyph size / label truncation feels off, adjust `_renderCell` and the cell-width target in `cells_per_page`. Re-verify on Kindle.

- [ ] **Step 6: Commit any tweaks**

```bash
git add -A
git commit -m "fix(icons-library): cell layout adjustments after Kindle review"
```

---

## Phase 3 — Tokens modal

### Task 20: Skeleton `menu/tokens_library.lua`

**Files:**
- Create: `menu/tokens_library.lua`
- Reference: `menu/token_picker.lua` (existing token + conditional catalogues)

- [ ] **Step 1: Read the existing token catalogue structure**

```bash
grep -n "Bookends.TOKEN_CATALOG\|Bookends.CONDITIONAL_CATALOG\|^local " menu/token_picker.lua | head -20
sed -n '1,100p' menu/token_picker.lua
```

Note the catalogue shape: each entry has `description`, `token` (or `expression` for conditionals), and is grouped under category headers.

- [ ] **Step 2: Build the skeleton**

```lua
--- Tokens library: replaces menu/token_picker.lua. Renders the token + condit-
--- ional catalogues on a chip-filtered list, with conditionals as the
--- "If/else" chip. Search submits across descriptions, token literals, and
--- (for conditionals) expressions.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local LibraryModal = require("menu.library_modal")
local Tokens = require("bookends_tokens")
local UIManager = require("ui/uimanager")
local _ = require("bookends_i18n").gettext

local TokensLibrary = {}

local CHIPS = {
    { key = "all",        label = _("All") },
    { key = "book",       label = _("Book") },
    { key = "chapter",    label = _("Chapter") },
    { key = "time",       label = _("Time") },
    { key = "battery",    label = _("Battery") },
    { key = "frontlight", label = _("Frontlight") },
    { key = "format",     label = _("Format") },
    { key = "ifelse",     label = _("If/else") },
}

return TokensLibrary
```

- [ ] **Step 3: Verify syntax**

```bash
luac -p menu/tokens_library.lua
```

- [ ] **Step 4: Commit**

```bash
git add menu/tokens_library.lua
git commit -m "feat(tokens-library): skeleton"
```

### Task 21: Port the token + conditional catalogues with chip mapping

**Files:**
- Modify: `menu/tokens_library.lua`
- Reference: `menu/token_picker.lua`

- [ ] **Step 1: Read the full catalogues**

```bash
sed -n '1,260p' menu/token_picker.lua
```

Identify each token entry's category. The catalogue today has implicit categories via section headers; map each entry to a chip key.

- [ ] **Step 2: Translate to a flat list with chip tags**

Append to `menu/tokens_library.lua`:

```lua
--- All token entries, each tagged with its chip keys. An entry can belong to
--- multiple chips (e.g. %book_pct shows under both All and Book).
TokensLibrary.TOKENS = {
    -- Book category
    { description = _("Book percentage"), token = "%book_pct", chips = {"book"} },
    { description = _("Book pages read"), token = "%page_num", chips = {"book"} },
    -- ... (continue with every token from menu/token_picker.lua's TOKEN_CATALOG)
    -- Chapter category
    { description = _("Chapter percentage"), token = "%chap_pct", chips = {"chapter"} },
    -- Time
    { description = _("Time (12-hour)"), token = "%time_12h", chips = {"time"} },
    -- ...
    -- Battery, Frontlight, Format ...
}

--- All conditional entries; tagged with chip "ifelse".
TokensLibrary.CONDITIONALS = {
    { description = _("If after 11pm"), expression = "[if:time>=23]…[/if]", chips = {"ifelse"} },
    -- ... (continue with every conditional from menu/token_picker.lua's CONDITIONAL_CATALOG)
}
```

The Step 2 paste must include EVERY entry from the existing catalogues — no omissions. Cross-check entry counts:

```bash
# count existing tokens (rough)
grep -cE 'description = ' menu/token_picker.lua
```

Match this count in the new file.

- [ ] **Step 3: Verify syntax**

```bash
luac -p menu/tokens_library.lua
```

- [ ] **Step 4: Commit**

```bash
git add menu/tokens_library.lua
git commit -m "feat(tokens-library): port full token + conditional catalogues"
```

### Task 22: Filter / search logic for the tokens library

**Files:**
- Modify: `menu/tokens_library.lua`

- [ ] **Step 1: Add the filter function**

```lua
--- Returns the visible item list for the given chip + search query.
--- "All" includes both tokens and conditionals; "If/else" includes only
--- conditionals; other chips include only tokens that have that chip in
--- their `chips` array.
function TokensLibrary._currentItems(active_chip, search_query)
    local items
    if active_chip == "all" or not active_chip then
        items = {}
        for _, t in ipairs(TokensLibrary.TOKENS) do table.insert(items, t) end
        for _, c in ipairs(TokensLibrary.CONDITIONALS) do table.insert(items, c) end
    elseif active_chip == "ifelse" then
        items = {}
        for _, c in ipairs(TokensLibrary.CONDITIONALS) do table.insert(items, c) end
    else
        items = {}
        for _, t in ipairs(TokensLibrary.TOKENS) do
            for _, k in ipairs(t.chips) do
                if k == active_chip then table.insert(items, t); break end
            end
        end
    end
    if search_query then
        local filtered = {}
        for _, item in ipairs(items) do
            local hay = (item.description or "") .. " " .. (item.token or "") .. " " .. (item.expression or "")
            if LibraryModal._matchesQuery(hay, search_query) then
                table.insert(filtered, item)
                if #filtered >= 200 then break end
            end
        end
        return filtered
    end
    return items
end
```

- [ ] **Step 2: Add tests for the filter**

Append to `_test_library_modal.lua`:

```lua
-- ============================================================================
-- tokens_library filter
-- ============================================================================

package.loaded["bookends_tokens"] = { expand = function() return "" end }
local TokensLibrary = require("menu.tokens_library")

test("All chip includes both tokens and conditionals", function()
    local n_all = #TokensLibrary._currentItems("all", nil)
    local n_tokens = #TokensLibrary.TOKENS
    local n_conds = #TokensLibrary.CONDITIONALS
    eq(n_all, n_tokens + n_conds, "all = tokens + conds")
end)

test("If/else chip includes only conditionals", function()
    local items = TokensLibrary._currentItems("ifelse", nil)
    eq(#items, #TokensLibrary.CONDITIONALS, "count matches CONDITIONALS")
end)

test("Search filters across description + token + expression", function()
    local items = TokensLibrary._currentItems("all", "book")
    -- book_pct + page_num shouldn't match; book_pct's description is "Book percentage"
    -- so "book" should match it. Exact count depends on the imported catalogues
    -- but we expect at least 1.
    if #items < 1 then fail = fail + 1; print("FAIL: expected matches for 'book'") end
end)
```

Run:

```bash
lua _test_library_modal.lua
```

Expected: all pass.

- [ ] **Step 3: Commit**

```bash
git add menu/tokens_library.lua _test_library_modal.lua
git commit -m "feat(tokens-library): chip + search filter logic with tests"
```

### Task 23: Token row renderer + entry-point

**Files:**
- Modify: `menu/tokens_library.lua`

- [ ] **Step 1: Add the row renderer**

Append:

```lua
function TokensLibrary._renderRow(item, slot_dimen, doc, toc)
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Size = require("ui/size")

    -- Line 1: bold description
    local line1 = TextWidget:new{
        text = item.description or "",
        face = Font:getFace("cfont", 16),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = slot_dimen.w - 16,
    }
    -- Line 2: for tokens, "%token → expansion"; for conditionals, the bare expression.
    local line2_text
    if item.expression then
        line2_text = item.expression
    else
        local expansion = doc and Tokens.expand(item.token, doc, toc) or ""
        line2_text = item.token .. (expansion ~= "" and " → " .. expansion or "")
    end
    local line2 = TextWidget:new{
        text = line2_text,
        face = Font:getFace("cfont", 14),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = slot_dimen.w - 16,
    }

    local stack = VerticalGroup:new{
        align = "left",
        line1,
        VerticalSpan:new{ width = Size.span.vertical_small or 4 },
        line2,
    }

    return FrameContainer:new{
        bordersize = Size.border.thin,
        padding = 8, margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        radius = 4,
        LeftContainer:new{ dimen = slot_dimen, stack },
    }
end
```

- [ ] **Step 2: Add the show entry-point**

Append:

```lua
function TokensLibrary:show(on_select, doc, toc)
    local state = { active_chip = "all", search_query = nil }
    local config = {
        title = _("Tokens library"),
        chip_strip = function()
            local out = {}
            for _, c in ipairs(CHIPS) do
                table.insert(out, { key = c.key, label = c.label, is_active = c.key == state.active_chip })
            end
            return out
        end,
        on_chip_tap = function(chip_key) state.active_chip = chip_key end,
        search_placeholder = function() return _("Search tokens…") end,
        on_search_submit = function(query) state.search_query = query end,
        rows_per_page = 6,
        item_count = function() return #TokensLibrary._currentItems(state.active_chip, state.search_query) end,
        item_at = function(idx) return TokensLibrary._currentItems(state.active_chip, state.search_query)[idx] end,
        row_renderer = function(item, dimen)
            return TokensLibrary._renderRow(item, dimen, doc, toc)
        end,
        on_item_tap = function(item)
            local val = item.token or item.expression
            UIManager:close(self.modal)
            if on_select then on_select(val) end
        end,
        footer_actions = {
            { key = "close", label = _("Close"), on_tap = function() UIManager:close(self.modal) end },
        },
    }
    self.modal = LibraryModal:new{ config = config }
    UIManager:show(self.modal)
end
```

- [ ] **Step 3: Verify syntax**

```bash
luac -p menu/tokens_library.lua
```

- [ ] **Step 4: Commit**

```bash
git add menu/tokens_library.lua
git commit -m "feat(tokens-library): row renderer + show entry point"
```

### Task 24: Wire line editor's token-picker call site

**Files:**
- Modify: `bookends_line_editor.lua`

- [ ] **Step 1: Read the current call site**

```bash
sed -n '348,360p' bookends_line_editor.lua
```

- [ ] **Step 2: Swap the call site**

```lua
-- Before:
self:showTokenPicker(function(token)

-- After:
local TokensLibrary = require("menu.tokens_library")
TokensLibrary:show(function(token)
    -- existing callback body unchanged
    ...
end, self.doc, self.toc)
```

(The existing `showTokenPicker` was a method on `Bookends`; the new approach is a direct call on the library module. The doc/toc args are needed for live token expansion.)

- [ ] **Step 3: Verify syntax**

```bash
luac -p bookends_line_editor.lua
```

- [ ] **Step 4: Commit**

```bash
git add bookends_line_editor.lua
git commit -m "refactor(line-editor): swap showTokenPicker for TokensLibrary"
```

### Task 25: Delete legacy modules

**Files:**
- Delete: `bookends_icon_picker.lua`
- Delete: `menu/token_picker.lua`
- Modify: `main.lua` (remove old registration)

- [ ] **Step 1: Verify no remaining references**

```bash
grep -rn "bookends_icon_picker\|IconPicker\|menu.token_picker\|showTokenPicker" --include="*.lua" .
```

Expected: zero matches. If any remain, fix them before deleting.

- [ ] **Step 2: Remove the registration in main.lua**

```bash
grep -n "token_picker" main.lua
```

Delete the line `require("menu.token_picker")(Bookends)` (around line 162).

- [ ] **Step 3: Delete the legacy modules**

```bash
git rm bookends_icon_picker.lua menu/token_picker.lua
```

- [ ] **Step 4: Verify the project still loads**

```bash
luac -p main.lua
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: delete legacy IconPicker + token_picker modules"
```

### Task 26: Verify Phase 3 on Kindle

**Files:**
- None modified

- [ ] **Step 1: Tar-pipe**

```bash
tar -cf - --exclude=tools --exclude=.git --exclude=docs --exclude='_test_*.lua' . \
  | ssh kindle "cd /mnt/us/koreader/plugins/bookends.koplugin && tar -xf -"
```

- [ ] **Step 2: User restarts KOReader**

- [ ] **Step 3: Open line editor + tap token-picker entry**

User checks:
- [ ] Modal title "Tokens library".
- [ ] Search input above chips with placeholder "Search tokens…".
- [ ] Chip strip: All / Book / Chapter / Time / Battery / Frontlight / Format / If/else (wraps to two rows if needed).
- [ ] All chip is active by default; the result list shows both tokens and conditionals.
- [ ] Tapping Book chip narrows to book tokens only.
- [ ] Tapping If/else chip shows only conditional entries.
- [ ] Each row: bold description on line 1; token literal + " → " + live expansion on line 2 (for tokens), bare expression on line 2 (for conditionals).
- [ ] Tapping a row inserts the token / expression at the cursor and closes the modal.
- [ ] Search "battery" returns rows from any chip whose description / token / expression contains "battery".
- [ ] Footer: single Close button.

- [ ] **Step 4: Capture screenshot**

```bash
ssh kindle 'cat /dev/fb0' > /tmp/kindle_phase3.raw && python3 -c "
from PIL import Image
import numpy as np
data = np.fromfile('/tmp/kindle_phase3.raw', dtype=np.uint8)
img = Image.frombuffer('L', (1248, 1648), data[:1248*1648], 'raw', 'L', 1248, 1)
img.save('/tmp/kindle_phase3.png')
"
```

Read `/tmp/kindle_phase3.png`.

- [ ] **Step 5: Iterate on any visual issues**

- [ ] **Step 6: Commit any tweaks**

```bash
git add -A
git commit -m "fix(tokens-library): row layout adjustments after Kindle review"
```

---

## Final verification

### Task 27: Cross-domain regression sweep

**Files:**
- None modified

- [ ] **Step 1: Run all `_test_*.lua` files**

```bash
for f in _test_*.lua; do echo "=== $f ==="; lua "$f" || echo "FAILED: $f"; done
```

Expected: all tests pass.

- [ ] **Step 2: User opens each surface and exercises each path**

- Preset library: open, switch tabs, sort chips, search by name, install a gallery preset, manage own preset.
- Icons library: open from line editor, scroll the curated catalogue, search by Nerd Font name, insert a glyph.
- Tokens library: open from line editor, scroll the catalogue, switch to If/else chip, search, insert a token AND a conditional.

- [ ] **Step 3: Capture a final composite screenshot of each modal**

```bash
# Capture each modal in turn, save as kindle_final_<name>.png
```

- [ ] **Step 4: Confirm no console errors in `crash.log`**

```bash
ssh kindle 'tail -100 /mnt/us/koreader/crash.log' | grep -iE 'error|nil value|stack trace' | head
```

Expected: no errors related to `library_modal`, `icons_library`, or `tokens_library`.

### Task 28: Polish + release notes

**Files:**
- Modify (potentially): visual / spacing tweaks across `library_modal.lua` and the three domain modules.
- Reference: existing release-notes pattern in `docs/release-notes-*.md`.

- [ ] **Step 1: Polish pass**

Open the three modals on Kindle one more time. Tweak any visual details that didn't quite settle (cell spacing, font sizes, chip padding, etc).

- [ ] **Step 2: Write release notes draft**

Per project memory ("release notes prep process: audit `git diff <prev-tag>..HEAD` and the previous release body; verify each claim isn't already in the previous tag"). Use the user-facing tone from memory ("skip internal mechanics users expect to 'just work'; skip test coverage").

A draft (not for the engineer to write — surface to the user for approval):

```
## Library modals + name search

- The preset library, icon picker, and token picker have moved to a unified
  modal design with a search affordance.
- Type any word into the search box to find icons, tokens, or presets by
  name. Icon search now covers ~3,700 Nerd Font glyphs — including all the
  ones presets in the gallery may use that weren't pickable before.
- The icon picker is now a grid view rather than a long list.
- Conditionals (`[if:…][/if]`) are now a chip in the tokens library rather
  than a buried sub-menu.
```

- [ ] **Step 3: User reviews the draft**

Surface to the user: "Release notes draft attached. Anything to add or rephrase before this becomes the v6 release body?"

### Task 29: PR preparation

**Files:**
- None modified

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/library-modal
```

- [ ] **Step 2: Confirm with user before creating the PR**

(Per memory: "Confirm before posting on PRs/issues — Always show draft and ask before commenting on GitHub.") Surface the PR title and body to the user before running `gh pr create`.

- [ ] **Step 3: Open the PR (after user approval)**

```bash
gh pr create --title "feat: BookendsLibraryModal + unified search across pickers" --body "$(cat <<'EOF'
## Summary
- Unifies the preset library, icons picker, and tokens picker on a shared `BookendsLibraryModal` widget.
- Adds submit-then-show name search to all three modals.
- Icon search expands from ~70 curated entries to all ~3,700 Nerd Font glyphs in KOReader's bundled symbols font.
- Conditionals migrate from a buried sub-menu to an `If/else` chip in the tokens library.
- Icons render as a glyph + label grid.

## Test plan
- [ ] Preset library opens, both tabs work, sort chips work, search filters within tab, install/manage flow unchanged.
- [ ] Icons library opens from line editor, curated catalogue browses by chip, search returns Nerd Font names, glyph cells insert into the line.
- [ ] Tokens library opens from line editor, both tokens and conditionals visible under All chip, If/else chip narrows to conditionals, search filters across description/token/expression.
- [ ] No console errors in crash.log after exercising every path.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review notes (run during writing-plans, captured for traceability)

- **Spec coverage check:** Each numbered scope item in the spec maps to at least one task. The shared widget, the data file + script, all three domain modules, the legacy module deletions, and the line-editor wire-ups are each covered.
- **Type consistency:** Method names (`_renderTitleBar`, `_renderSearchInput`, `_renderChipStrip`, `_renderListArea`, `_renderGridArea`, `_renderPagination`, `_renderFooter`, `refresh`) used consistently across tasks. Domain config field names (`chip_strip`, `search_placeholder`, `rows_per_page`, `cells_per_page`, `row_renderer`, `cell_renderer`, `cell_long_tap`, `item_count`, `item_at`, `empty_state`, `footer_actions`) match between spec, BookendsLibraryModal task code, and the three domain config builders.
- **No placeholders:** Every task's code is concrete; the only "..." placeholders are inside lifted-from-existing-file paste blocks (the curated icons catalogue and the token catalogues), where the engineer must paste the full content from the named source file. The references are exact (line numbers in the source file when relevant).
- **Frequent commits:** Every task ends in a commit step. ~30 commits total — granular enough that a bad turn can be reverted cleanly.
