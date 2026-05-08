--[[
File-Browser Persistent Bar
===========================
Manages the "Persistent bar at top" placement for the file-browser toolbar.

The bar is inserted directly into the FileChooser's content_group VerticalGroup,
between the title bar (position 1) and the item list (position 2).  This keeps
it within the normal widget tree so positioning and repaints work automatically.

  content_group = VerticalGroup{
    [1] title_bar
    [2] ← our bar widget (when active)
    [3] item_group (file list)
  }

To compensate for the reduced available area, Menu.inner_dimen.h is shrunk by
the bar height and _recalculateDimen + updateItems are called to reflow the list.

Public API:
  M.inject(fb_config)  – activate / refresh bar (idempotent)
  M.remove()           – deactivate bar and restore list
--]]

local Device    = require("device")
local Screen    = Device.screen
local UIManager = require("ui/uimanager")

local FrameContainer = require("ui/widget/container/framecontainer")
local Blitbuffer     = require("ffi/blitbuffer")

local M = {}

-- Module-level state.
local _saved_inner_h = nil -- original inner_dimen.h before shrinking
local _label_text_widget = nil
local _patched         = false

-- ==========================================================================
-- Helpers
-- ==========================================================================

--- Build bar content by reusing createHomeContent with a minimal fake menu.
local function buildBarContent(fc, fb_config)
    local HomeContent = require("home_content")
    local width = fc.inner_dimen and fc.inner_dimen.w or fc.dimen and fc.dimen.w or Screen:getWidth()
    local fake_menu = {
        width            = width,
        dimen            = { w = width },
        inner_dimen      = { w = width },
        tab_item_table   = {},
        item_table       = {},
        item_table_stack = {},
        page             = 1,
        close_callback   = nil,
        _is_fb_context   = true,
    }
    local on_refresh = function()
        M.inject(fb_config)
    end
    local ok, content = pcall(HomeContent.createHomeContent, fake_menu, fb_config, on_refresh)
    return ok and content or nil
end

--- Return the live FileChooser, or nil.
local function getFileChooser()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    if not ok then return nil end
    local fm = FileManager.instance
    if not (fm and fm.file_chooser and fm.file_chooser.content_group) then
        return nil
    end
    return fm.file_chooser
end

--- Remove any existing bar widget from content_group (by sentinel flag).
local function removeFromContentGroup(fc)
    local cg = fc.content_group
    if not cg then return end
    for i = #cg, 1, -1 do
        if cg[i] and cg[i]._is_persistent_bar then
            table.remove(cg, i)
        end
    end
end

--- Restore inner_dimen.h and reflow the file list.
local function restoreLayout(fc)
    if _saved_inner_h then
        fc.inner_dimen.h = _saved_inner_h
        _saved_inner_h   = nil
    end
    fc:_recalculateDimen()
    fc:updateItems()
    UIManager:setDirty(fc, "ui")
end

local function getLabel(fc)
    local lfs = require("libs/libkoreader-lfs")
    local home_dir = G_reader_settings:readSetting("home_dir") or Device.home_dir or lfs.currentdir()
    local path = fc.path

    if not fc.item_table then
        return path:match("([^/]+)$") or "KOReader"
    end

    local file_count = 0
    local dir_count = 0
    for _, item in ipairs(fc.item_table) do
        if item.is_file then
            file_count = file_count + 1
        else
            dir_count = dir_count + 1
        end
    end

    local folder_name, count_label
    if path == home_dir or path == "/" then
        folder_name = "KOReader"
        count_label = dir_count .. " authors"
    elseif path:match("/✪ Collections$") then
        folder_name = "Collections"
        count_label = dir_count .. " collections"
    elseif path:match("/✪ Collections/") then
        folder_name = "Collection " .. (path:match("/✪ Collections/(.+)$") or "")
        count_label = file_count .. " books"
    else
        folder_name = path:match("([^/]+)$")
        if file_count == 0 and dir_count > 0 then
            count_label = dir_count .. " authors"
        elseif file_count > 0 then
            count_label = file_count .. " books"
        end
    end

    if count_label then
        return folder_name .. " · " .. count_label
    else
        return folder_name
    end
end

local function updateLabel(fc)
    if not _label_text_widget then return end
    _label_text_widget:setText(getLabel(fc))
    UIManager:setDirty(fc, "ui")
end

local function hookPathChange()
    if _patched then return end
    _patched = true

    local FileChooser = require("ui/widget/filechooser")
    local original = FileChooser.changeToPath
    FileChooser.changeToPath = function(self, path, ...)
        local result = original(self, path, ...)
        UIManager:scheduleIn(0, function()
            updateLabel(self)
        end)
        return result
    end
end

-- ==========================================================================
-- Public API
-- ==========================================================================

--- Activate or refresh the persistent bar.
-- Safe to call repeatedly – removes any existing bar first.
function M.inject(fb_config)
    local TextWidget      = require("ui/widget/textwidget")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Geom            = require("ui/geometry")
    local VerticalGroup   = require("ui/widget/verticalgroup")
    local Font            = require("ui/font")

    M.remove()

    local fc = getFileChooser()
    if not fc then return end  -- FM not ready yet; main.lua schedules a retry

    local content = buildBarContent(fc, fb_config)
    if not content then return end

    -- Wrap in a FrameContainer for a clean white background.
    local frame = FrameContainer:new{
        padding    = 0,
        bordersize = 0, --3
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    local bar_h = frame:getSize().h
    local bar_w = frame:getSize().w
    local mid_x = math.floor(bar_w / 2)

    -- local original_paintTo = frame.paintTo
    -- -- frame.paintTo = function(self, bb, x, y)
    -- --     original_paintTo(self, bb, x, y)
    -- --     -- línea vertical de 1px en el centro
    -- --     bb:paintRect(x + mid_x, y, 1, bar_h, Blitbuffer.COLOR_BLACK)
    -- -- end
    -- frame.paintTo = function(self, bb, x, y)
    --     original_paintTo(self, bb, x, y)
    --     -- línea horizontal en el punto medio vertical
    --     bb:paintRect(x, y + math.floor(bar_h / 2), bar_w, 1, Blitbuffer.COLOR_BLACK)
    -- end
    -- frame._is_persistent_bar = true

    local bar_h = frame:getSize().h

    -- Shrink inner_dimen so _recalculateDimen computes fewer rows.

    -- local ref_face = Font:getFace("NotoSans-Regular.ttf", 14)
    -- local ref_w = TextWidget:new{ text = "", face = ref_face }
    -- local forced_baseline = ref_w:getBaseline()
    -- local forced_height = ref_w:getSize().h
    -- ref_w:free()

    _label_text_widget = TextWidget:new{
        text = getLabel(fc),
        face = Font:getFace("smallinfofont", 18),
        max_width = Screen:getWidth() / 3,
        truncate_left = true,
        -- forced_baseline = forced_baseline,
        -- forced_height = forced_height,
    }

    local label_frame = FrameContainer:new{
        padding    = 0,
        bordersize = 0,--3,
        -- background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = Screen:getWidth(), h = _label_text_widget:getSize().h },
            _label_text_widget,
        }
    }

    local LineWidget = require("ui/widget/linewidget")
    local separator = LineWidget:new{
        dimen = Geom:new{ w = Screen:getWidth(), h = Screen:scaleBySize(3) },
    }

    local combined = VerticalGroup:new{
        align = "left",
        _is_persistent_bar = true,
        frame,
        separator,
    }
    local OverlapGroup = require("ui/widget/overlapgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local label_offset = math.floor((frame:getSize().h - label_frame:getSize().h) / 2)
    local overlapped = OverlapGroup:new{
        _is_persistent_bar = true,
        dimen = Geom:new{ w = Screen:getWidth(), h = combined:getSize().h },
        combined,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = label_offset },
            label_frame,
        },
    }

    local bar_h = combined:getSize().h

    if _saved_inner_h == nil then
        _saved_inner_h = fc.inner_dimen.h
    end
    fc.inner_dimen.h = _saved_inner_h - bar_h

    -- Insert between title_bar (idx 1) and item_group (idx 2).
    local cg = fc.content_group
    table.insert(cg, 2, overlapped)

    fc:_recalculateDimen()
    fc:updateItems()
    hookPathChange()
    UIManager:setDirty(fc, "ui")
end

--- Deactivate the persistent bar and restore the file list.
function M.remove()
    _label_text_widget = nil
    local fc = getFileChooser()
    if fc then
        removeFromContentGroup(fc)
        restoreLayout(fc)
    end
    _saved_inner_h = nil
end

return M
