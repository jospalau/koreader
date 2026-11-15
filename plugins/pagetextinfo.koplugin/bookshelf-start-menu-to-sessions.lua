-- bookshelf-start-menu-to-sessions.lua
--
-- Every way of opening the Bookshelf START MENU opens the top reading sessions
-- window (the Reading Summary screen) instead:
--   * the "Bookshelf: open start menu" gesture      (Bookshelf:onBookshelfOpenStartMenu)
--   * the hamburger in the Bookshelf footer         (BookshelfWidget:_openStartMenu)
--   * the hamburger inside the reader               (Bookshelf:_openReaderStartMenu)
-- "Bookshelf: open modules" is NOT touched.
--
-- Loaded from reader.lua, after bookshelf-overlay.lua:
--     pcall(dofile, "plugins/pagetextinfo.koplugin/bookshelf-start-menu-to-sessions.lua")
--
-- The plugin class is patched once. The widget class is only reachable through
-- package.loaded["lib/bookshelf_widget"], so it is looked for at several moments
-- (file load, after every init, after the shelf is toggled) until it is found.
-- Whenever the window cannot be shown, the original handler runs, so a menu
-- entry point never ends up doing nothing.

local logger = require("logger")
local ReaderUI = require("apps/reader/readerui")
local FileManager = require("apps/filemanager/filemanager")

logger.info("[bookshelf-start-menu-to-sessions] patch file loaded")

local plugin_patched = false
local widget_patched = false

-- Open the window. `ui` is the ReaderUI / FileManager instance when known.
local function showSessions(ui)
    -- explicit indexes: ipairs would stop at the first nil entry
    local candidates = { ui, ReaderUI.instance, FileManager.instance }
    for i = 1, 3 do
        local u = candidates[i]
        if u then
            if u.pagetextinfo and u.pagetextinfo.onShowLongestSessions then
                return u.pagetextinfo:onShowLongestSessions()
            end
            if u.onShowLongestSessions then
                return u:onShowLongestSessions()
            end
        end
    end
end

-- Run showSessions protected; true when the window was handled
local function trySessions(ui, tag)
    local ok, handled = pcall(showSessions, ui)
    if ok and handled then return true end
    logger.warn("[bookshelf-start-menu-to-sessions] " .. tag
        .. ": could not show the sessions window, using the original handler:", tostring(handled))
    return false
end

-- ── Plugin class: gesture + hamburger inside the reader ─────────────────────
local function patchPluginClass(class)
    if plugin_patched then return end
    if type(class) ~= "table" or not class.onBookshelfOpenStartMenu then return end

    local original_gesture = class.onBookshelfOpenStartMenu
    function class:onBookshelfOpenStartMenu(...)
        if trySessions(self.ui, "gesture") then return true end
        return original_gesture(self, ...)
    end

    local original_reader = class._openReaderStartMenu
    if original_reader then
        function class:_openReaderStartMenu(...)
            if trySessions(self.ui, "reader hamburger") then return true end
            return original_reader(self, ...)
        end
    end

    -- The widget class may only exist once the shelf has been shown
    local original_toggle = class.onToggleBookshelf
    if original_toggle then
        function class:onToggleBookshelf(...)
            local ret = original_toggle(self, ...)
            pcall(_G.__bsm_patch_widget)
            return ret
        end
    end

    plugin_patched = true
    logger.info("[bookshelf-start-menu-to-sessions] Bookshelf plugin class patched")
end

local function patchFromInstance(plugin)
    if plugin then patchPluginClass(getmetatable(plugin)) end
end

-- ── Widget class: hamburger in the Bookshelf footer ─────────────────────────
-- The class is found in three ways: any loaded module whose name ends in
-- "bookshelf_widget", or the class of any widget that goes through
-- UIManager:show and has _openStartMenu (see the hook below).
local function patchWidgetClass(class)
    if widget_patched then return end
    if type(class) ~= "table" or type(rawget(class, "_openStartMenu")) ~= "function" then return end

    local original = class._openStartMenu
    function class:_openStartMenu(force, ...)
        -- keep the original guards: Off position (unless forced) and parked reader
        local blocked = false
        if not force then
            local ok_p, Park = pcall(require, "lib/bookshelf_reader_park")
            if ok_p and Park and Park.isParked and Park.isParked() then blocked = true end
            if not blocked and self._startMenuPosition and self:_startMenuPosition() == "off" then
                blocked = true
            end
        end
        if not blocked and trySessions(self.ui, "footer hamburger") then return true end
        return original(self, force, ...)
    end

    widget_patched = true
    logger.info("[bookshelf-start-menu-to-sessions] BookshelfWidget._openStartMenu patched")
end

local function patchWidget()
    if widget_patched then return end
    for name, mod in pairs(package.loaded) do
        if type(name) == "string" and name:find("bookshelf_widget$") then
            patchWidgetClass(mod)
            if widget_patched then return end
        end
    end
end

-- Class of an instance: walk the metatable chain until one owns the method
local function patchWidgetFromInstance(w)
    if widget_patched or type(w) ~= "table" then return end
    local mt = getmetatable(w)
    local guard = 0
    while type(mt) == "table" and guard < 8 do
        if type(rawget(mt, "_openStartMenu")) == "function" then
            patchWidgetClass(mt)
            return
        end
        local nxt = rawget(mt, "__index")
        if type(nxt) == "table" then mt = nxt else mt = getmetatable(mt) end
        guard = guard + 1
    end
end

local function hookUIManagerShow()
    local ok, UIManager = pcall(require, "ui/uimanager")
    if not ok or not UIManager then return end
    local original_show = UIManager.show
    function UIManager:show(widget, ...)
        if not widget_patched then pcall(patchWidgetFromInstance, widget) end
        return original_show(self, widget, ...)
    end
end
hookUIManagerShow()
_G.__bsm_patch_widget = patchWidget

-- Try everything that is reachable right now
local function patchNow()
    pcall(function()
        local PluginLoader = require("pluginloader")
        local loaded = PluginLoader.loaded_plugins
        patchPluginClass(loaded and loaded.bookshelf)
    end)
    pcall(function() patchFromInstance(ReaderUI.instance and ReaderUI.instance.bookshelf) end)
    pcall(function() patchFromInstance(FileManager.instance and FileManager.instance.bookshelf) end)
    pcall(patchWidget)
end

-- And after every init, in case the plugin or the widget did not exist yet
local function patchAfterInit(Class)
    local original_init = Class.init
    function Class:init(...)
        local ret
        if original_init then ret = original_init(self, ...) end
        pcall(patchFromInstance, self.bookshelf)
        pcall(patchWidget)
        return ret
    end
end

patchAfterInit(ReaderUI)
patchAfterInit(FileManager)
patchNow()
