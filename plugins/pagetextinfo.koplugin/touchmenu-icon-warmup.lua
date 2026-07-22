-- patches/touchmenu-icon-warmup.lua
--
-- KOReader lazily renders every icon SVG the first time it's shown (e.g.
-- ReaderMenu:onShowMenu() creates the TouchMenu + its tab-bar icons only on
-- first tap). That means the first real menu open always pays the full
-- SVG-decode cost live. ImageCache is explicitly sized for this though
-- (8 MiB / 128 slots, "overwhelmingly used for our icons... < 100" per its
-- own comment in imagewidget.lua), so warming the whole mdlight/ icon set
-- fits comfortably inside its budget.
--
-- Fix: pre-render every icon in resources/icons/mdlight/ (47px, TouchMenu
-- tab-bar size) AND every shortcutstoolbar plugin icon (31px, its own
-- toolbar size), ONCE per KOReader process, right at startup -- patches
-- load exactly once, so no re-entrancy guard is needed. Deferred to
-- nextTick so it doesn't compete with KOReader's own startup rendering.

-- Measured in readermenu.lua
-- if Device:isTouchDevice() or Device:hasDPad() then
--     local socket = require("socket")
--     local t = socket.gettime()

--     local TouchMenu = require("ui/widget/touchmenu")
--     main_menu = TouchMenu:new{
--         width = Screen:getWidth(),
--         last_index = tab_index or self.last_tab_index,
--         tab_item_table = self.tab_item_table,
--         show_parent = menu_container,
--         not_shown = do_not_show,
--     }
--     logger.info(string.format(
--         "[MENU PERF] TouchMenu:new %.0f ms",
--         (socket.gettime() - t) * 1000
--     ))
-- ...

-- First time and second time without warmup
-- 07/22/26-10:21:58 INFO  [MENU PERF] TouchMenu:new 240 ms
-- 07/22/26-10:22:01 INFO  [MENU PERF] TouchMenu:new 18 ms

-- First time and second time with warmup
-- 07/22/26-10:24:05 INFO  [MENU PERF] TouchMenu:new 31 ms
-- 07/22/26-10:24:08 INFO  [MENU PERF] TouchMenu:new 10 ms

local Device      = require("device")
local Screen      = Device.screen
local IconWidget  = require("ui/widget/iconwidget")
local UIManager   = require("ui/uimanager")
local logger      = require("logger")
local lfs         = require("libs/libkoreader-lfs")

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")
local ICONS_DIR = "resources/icons/mdlight"

local function listIconNames()
    local names = {}
    for entry in lfs.dir(ICONS_DIR) do
        local name = entry:match("^(.+)%.svg$")
        if name then table.insert(names, name) end
    end
    return names
end

local function warmIcon(spec, w, h)
    pcall(function()
        local widget
        if type(spec) == "table" then
            if spec.icon_file then
                widget = IconWidget:new{ file = spec.icon_file, width = w, height = h }
            elseif spec.icon then
                widget = IconWidget:new{ icon = spec.icon, width = w, height = h }
            else
                return
            end
        else
            widget = IconWidget:new{ icon = spec, width = w, height = h }
        end
        widget:getSize() -- forces _render() -> RenderImage:renderSVGImageFile -> ImageCache:insert
        if widget.free then widget:free() end
    end)
end

UIManager:nextTick(function()
    local t0 = os.clock()

    -- 1) KOReader core icons (mdlight/), at the TouchMenu tab-bar size
    local core_size = Screen:scaleBySize(DGENERIC_ICON_SIZE)
    local core_names = listIconNames()
    for _, name in ipairs(core_names) do
        warmIcon(name, core_size, core_size)
    end

    -- 2) shortcutstoolbar plugin icons, if the plugin is installed
    local sc_count = 0
    local ok_req, SHORTCUT_DATA = pcall(require, "shortcuts_data")
    if ok_req and SHORTCUT_DATA then
        local ok_settings, reader_config_icon_size = pcall(function()
            local ToolbarSettings = require("toolbar_settings")
            local cfg = {}
            ToolbarSettings.refreshInto(cfg, "reader")
            return cfg.icon_size
        end)
        local sc_size = Screen:scaleBySize((ok_settings and reader_config_icon_size) or 26)
        for _, spec in ipairs(SHORTCUT_DATA) do
            warmIcon(spec, sc_size, sc_size)
            sc_count = sc_count + 1
        end
    end

    logger.info(string.format(
        "[icon-warmup] warmed %d core icons (mdlight/, %dpx) + %d shortcutstoolbar icons in %.0fms",
        #core_names, core_size, sc_count, (os.clock() - t0) * 1000))
end)
