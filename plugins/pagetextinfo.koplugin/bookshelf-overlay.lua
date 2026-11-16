-- patches/2-bookshelf-overlay.lua
--
-- 1) East North -> "Bookshelf (park, never close)": a toggle that parks the book
--    and shows Bookshelf, or goes back to the book if it was already parked.
--
-- 2) West South is NOT reassigned: it stays the native "File browser" action
--    (event Home). When the book is parked it ALWAYS goes back to it instead of
--    closing it. When it is NOT parked, the original ReaderUI:onHome is reused
--    (the one that shows the MultiConfirmBox: save progress / TBR / exit).
--
-- IMPORTANT (found through logs): once the Bookshelf plugin has been instantiated
-- in the session (self.bookshelf exists), the "Home" event does NOT reach
-- ReaderUI:onHome directly. It reaches BookshelfClass:onHome first (main.lua of
-- bookshelf.koplugin). Bookshelf's native onHome uses _isShowing()/_safeShow() and,
-- with the shelf not visible, does nothing useful: it just swallows the event by
-- returning true, without showing the MultiConfirmBox or closing anything properly.
-- That is why, in the NOT PARKED branch of BookshelfClass:onHome, we explicitly
-- delegate to the REAL ReaderUI onHome (captured at module level), using self.ui
-- (the ReaderUI instance, see main.lua: self.ui.document) instead of calling
-- Bookshelf's native onHome.
--
-- The ReaderUI:onHome override is kept as a safety net, in case in some flow the
-- event DOES reach ReaderUI directly without going through Bookshelf (e.g. a book
-- opened before the Bookshelf plugin has been instantiated in the session).
--
-- LOGGING VERSION: every key step writes a "[bookshelf-overlay]" line to the debug
-- log. Look for them in:
--   menu -> Help -> View debug log
-- or in the crash.log file of the KOReader folder.
--
-- File layout:
--   1. Requires and debounce
--   2. Action registration and captured originals
--   3. Bookshelf class patch (onHome) and widget class patch (onHome -> false)
--   4. ReaderUI: park toggle, onHome safety net, eager patch on init
--   5. Raw gesture blocking while parked

local Dispatcher = require("dispatcher")
local ReaderUI = require("apps/reader/readerui")
local logger = require("logger")
local _ = require("gettext")

logger.info("[bookshelf-overlay] patch file loaded")

-- ---------------------------------------------------------------------------
-- 1. Debounce
--
-- The multiswipe sometimes fires the same gesture 2-3 times in a row (bounce),
-- which throws the "parked" state off before the next gesture arrives. We ignore
-- re-triggers of the SAME event that come in less than DEBOUNCE_S seconds after the
-- last ACCEPTED one. (Ignored events do not move the window: a chain of bounces
-- cannot keep itself ignored forever.)
-- ---------------------------------------------------------------------------
local ok_time, socket = pcall(require, "socket")
local gettime = (ok_time and socket and socket.gettime) or os.time

local DEBOUNCE_S = 0.7
local _last_trigger = {} -- { [event_name] = timestamp of the last accepted event }

local function isDebounced(event_name)
    local now = gettime()
    local last = _last_trigger[event_name]
    if last and (now - last) < DEBOUNCE_S then
        logger.dbg("[bookshelf-overlay] DEBOUNCED:", event_name,
            "(", tostring(now - last), "s since the previous one)")
        return true
    end
    _last_trigger[event_name] = now
    return false
end

-- Park module of Bookshelf, loaded once on first use (it is asked for on every
-- event while the gestures are filtered, so it is cached).
local park_module
local function getPark()
    if park_module == nil then
        local ok, mod = pcall(require, "lib/bookshelf_reader_park")
        logger.dbg("[bookshelf-overlay] require Park ok=", tostring(ok))
        if not (ok and mod) then
            return nil -- not cached: it is tried again next time
        end
        park_module = mod
    end
    return park_module
end

-- ---------------------------------------------------------------------------
-- 2. Action registration and captured originals
-- ---------------------------------------------------------------------------
Dispatcher:registerAction("show_bookshelf_overlay", {
    category = "none",
    event    = "ParkAndShowBookshelf",
    title    = _("Bookshelf (aparcar, nunca cerrar)"),
    general  = true,
})

logger.dbg("[bookshelf-overlay] action 'show_bookshelf_overlay' registered")

-- We capture the ORIGINAL onHome of ReaderUI (the one with the MultiConfirmBox for
-- save progress / TBR / exit, Document 1) at module level, before anything else
-- touches it. It is reused both from BookshelfClass:onHome (main case, see logs)
-- and from the ReaderUI:onHome override (safety net).
local original_readerui_onHome = ReaderUI.onHome
logger.dbg("[bookshelf-overlay] original_readerui_onHome captured:", tostring(original_readerui_onHome))

-- ---------------------------------------------------------------------------
-- 3. Bookshelf class patch
--
-- Patches the Bookshelf CLASS (shared by all instances, present and future) only
-- ONCE per KOReader start. Patching the instance (as we did before) only fixed the
-- current reading session: every new book creates a new, unpatched instance of the
-- plugin.
-- ---------------------------------------------------------------------------
local bookshelf_patched = false
local function patchBookshelfOnce(plugin)
    if bookshelf_patched then
        return
    end

    local BookshelfClass = getmetatable(plugin)
    if not BookshelfClass then
        logger.dbg("[bookshelf-overlay] could not get the class via getmetatable(plugin)")
        return
    end
    logger.dbg("[bookshelf-overlay] patchBookshelfOnce: patching the Bookshelf CLASS onHome:", tostring(BookshelfClass))

    local original_onHome = BookshelfClass.onHome
    logger.dbg("[bookshelf-overlay] original_onHome (native Bookshelf) captured:", tostring(original_onHome))

    function BookshelfClass:onHome()
        logger.dbg("[bookshelf-overlay] onHome() FIRED")

        if isDebounced("onHome") then
            return true -- we ignore the bounce, we touch nothing
        end

        local Park = getPark()
        local parked = Park and Park.isParked()
        logger.dbg("[bookshelf-overlay] onHome: Park.isParked()=", tostring(parked))

        if parked then
            logger.dbg("[bookshelf-overlay] onHome: PARKED branch -> Park.unpark()")
            local unpark_ok, unpark_err = pcall(function()
                Park.unpark(self._widget)
            end)
            logger.dbg("[bookshelf-overlay] onHome: unpark_ok=", tostring(unpark_ok),
                "unpark_err=", tostring(unpark_err))
            return true
        end

        -- NOT PARKED: the Home event reached the Bookshelf widget (not ReaderUI
        -- directly). Bookshelf's native onHome (original_onHome) uses
        -- _isShowing()/_safeShow() and here does nothing useful (the shelf is not
        -- visible), so we do NOT call it. Instead we delegate to the REAL onHome of
        -- ReaderUI (the one with the MultiConfirmBox), using self.ui, which is the
        -- ReaderUI instance (see main.lua: self.ui.document).
        logger.dbg("[bookshelf-overlay] onHome: NOT PARKED branch -> delegating to the real ReaderUI:onHome (self.ui)")
        local reader_ui = self.ui
        logger.dbg("[bookshelf-overlay] onHome: reader_ui=", tostring(reader_ui))

        if original_readerui_onHome and reader_ui then
            local ret = original_readerui_onHome(reader_ui)
            logger.dbg("[bookshelf-overlay] onHome: original_readerui_onHome returned=", tostring(ret))
            return ret
        end

        logger.dbg("[bookshelf-overlay] onHome: could not delegate (original_readerui_onHome=",
            tostring(original_readerui_onHome), " reader_ui=", tostring(reader_ui), ") -> falling back to the native original_onHome")
        if original_onHome then
            local ret = original_onHome(self)
            logger.dbg("[bookshelf-overlay] onHome: original_onHome (fallback) returned=", tostring(ret))
            return ret
        end
    end

    bookshelf_patched = true
    logger.dbg("[bookshelf-overlay] patchBookshelfOnce: patched OK (class, permanent)")
end

-- Allow Bookshelf onHome() event handler to execute again. This stopped working
-- after the official change adding support for onHome events
-- (InputContainer:onHome added a default daisy-chain: close self via onClose() +
-- resend Home to the next widget down the stack). Because BookshelfWidget has no
-- onHome of its own, it inherited that default, which closed the bookshelf widget
-- and daisy-chained Home straight to FileManager -- bypassing
-- BookshelfClass:onHome (parked/unpark logic) entirely. Fix: give the Bookshelf
-- widget class its own onHome that returns false, so the event is NOT consumed
-- there and falls through to BookshelfClass:onHome, same as before onHome was added
-- to InputContainer. Only the widget class is touched (InputContainer is not).
--
-- The class is looked up without loading anything new: first the module that
-- Bookshelf already loaded, then the metatable of the live widget. If neither
-- exists yet (the widget was never created), nothing is marked as done and it is
-- tried again on the next call.
local widget_class_patched = false
local function patchWidgetClassOnce(plugin)
    if widget_class_patched then
        return
    end

    local WidgetClass = package.loaded["lib/bookshelf_widget"]
    if type(WidgetClass) ~= "table" and plugin and plugin._widget then
        WidgetClass = getmetatable(plugin._widget)
    end
    if type(WidgetClass) ~= "table" then
        logger.dbg("[bookshelf-overlay] patchWidgetClassOnce: widget class not available yet")
        return
    end

    if rawget(WidgetClass, "onHome") == nil then
        function WidgetClass:onHome()
            logger.dbg("[bookshelf-overlay] BookshelfWidget:onHome -> return false, letting it through to BookshelfClass:onHome")
            return false
        end
        logger.dbg("[bookshelf-overlay] patchWidgetClassOnce: onHome added to the widget class:", tostring(WidgetClass))
    else
        logger.dbg("[bookshelf-overlay] patchWidgetClassOnce: the widget class already has its own onHome, not touching it")
    end
    widget_class_patched = true
end

-- ---------------------------------------------------------------------------
-- 4. ReaderUI
-- ---------------------------------------------------------------------------

-- pagemap_current_page_label (stable page numbers) only gets written by
-- ReaderPageMap:onCloseDocument, which hot-parking deliberately never fires (that's
-- the whole point of not closing). Without this, the hero's "page N of M" stays
-- frozen at whatever it was on the last REAL close/open. Mirror onCloseDocument's
-- own write here.
local function savePageLabels(rui)
    pcall(function()
        local pm = rui.pagemap
        if pm and pm.has_pagemap and pm.use_page_labels then
            rui.doc_settings:saveSetting(
                "pagemap_last_page_label",
                pm:getLastPageLabel(true)
            )
            rui.doc_settings:saveSetting(
                "pagemap_current_page_label",
                select(1, pm:getCurrentPageLabel(true))
            )
        end
    end)
end

-- Refreshes the hero card and the chips of the shelf widget, if it has them.
local function refreshHero(plugin)
    if plugin._widget and plugin._widget._rebuildRefreshHeroAndChips then
        pcall(function()
            plugin._widget:_rebuildRefreshHeroAndChips()
        end)
    end
end

-- Book opened directly from the real File Manager: the Bookshelf widget does not
-- exist yet in this session, so there is nothing to "park" over (_raiseInPlace
-- needs the widget already in the stack). We create/show it ourselves (show() does
-- not touch the document or the reader, it only covers it) and then register the
-- park by hand.
local function parkWithColdCreate(plugin, rui, Park, now_ms, t_start)
    logger.dbg("[bookshelf-overlay] plugin._widget is nil -> cold-create via plugin:show()")

    pcall(function()
        rui:saveSettings()
    end)

    logger.dbg(string.format("[TIMING] until saveSettings: %.3f ms", now_ms() - t_start))

    local ok_repo, Repo = pcall(require, "lib/bookshelf_book_repository")
    if ok_repo and Repo and Repo.invalidateProgressCache then
        Repo.invalidateProgressCache(rui.document.file)
    end

    plugin:show()
    patchWidgetClassOnce(plugin)

    logger.dbg(string.format("[TIMING] until show: %.3f ms", now_ms() - t_start))

    if plugin._widget then
        plugin._widget._hero_current_memo = nil
        plugin._widget._preview_book = nil
    end

    refreshHero(plugin)

    logger.dbg(string.format("[TIMING] until _rebuildRefreshHeroAndChips: %.3f ms", now_ms() - t_start))

    local park_ok = Park.park(plugin, plugin._widget)
    logger.dbg("[bookshelf-overlay] Park.park manual after cold-create =", tostring(park_ok))
end

-- The widget already exists: park and show it, or go back to the book if it was
-- already parked.
local function toggleExistingWidget(plugin, rui, now_ms, t_start)
    -- pcall(function()
    --     if rui and rui.document and rui.document.file then
    --         G_reader_settings:saveSetting("lastfile", rui.document.file)
    --     end
    -- end)
    pcall(function()
        rui:saveSettings()
    end)
    -- pcall(function()
    --     local ok_repo, Repo = pcall(require, "lib/bookshelf_book_repository")
    --     if ok_repo and Repo and Repo.invalidateProgressCache then
    --         Repo.invalidateProgressCache()
    --     end
    -- end)
    -- -- For the hero card to be updated every time we show Bookshelf parked
    -- -- Other option is setting local HERO_MEMO_TTL_S = 0 in bookshelf_widget.lua
    if plugin._widget then
        plugin._widget._hero_current_memo = nil
        plugin._widget._preview_book = nil
    end

    -- This really measures how long onToggleBookshelf() takes.
    local toggle_start = now_ms()

    plugin:onToggleBookshelf() -- opens and parks / or goes back to the book if it was already parked
    logger.dbg(string.format("[TIMING] until toggle: %.3f ms", now_ms() - toggle_start))

    local UIManager = require("ui/uimanager")

    local t_first = now_ms()
    local previous = t_first
    local tick = 0

    local function measureNextTick()
        tick = tick + 1

        UIManager:nextTick(function()
            local current = now_ms()

            logger.dbg(string.format(
                "[TIMING] nextTick %d: +%.3f ms (total %.3f ms)",
                tick,
                current - previous,
                current - t_first
            ))

            previous = current

            if tick < 10 then
                measureNextTick()
            end
        end)
    end

    -- measureNextTick()
    refreshHero(plugin)

    logger.dbg(string.format("[TIMING] until _rebuildRefreshHeroAndChips: %.3f ms", now_ms() - t_start))
end

-- East North: park and show / go back if already parked (toggle)
function ReaderUI:onParkAndShowBookshelf()
    local util = require("ffi/util")

    local function now_ms()
        local sec, usec = util.gettime()
        return sec * 1000 + usec / 1000
    end

    local t_start = now_ms()

    if G_reader_settings:readSetting("start_with") ~= "bookshelf" then
        local UIManager = require("ui/uimanager")
        local Event = require("ui/event")
        return UIManager:sendEvent(Event:new("ShowHist"))
    end
    logger.dbg("[bookshelf-overlay] onParkAndShowBookshelf() FIRED")

    if isDebounced("onParkAndShowBookshelf") then
        return true -- we ignore the bounce, we touch nothing
    end

    local plugin = self.bookshelf
    if not plugin then
        logger.dbg("[bookshelf-overlay] Bookshelf plugin is NOT loaded (self.bookshelf is nil)")
        return true
    end
    logger.dbg("[bookshelf-overlay] plugin found:", tostring(plugin))

    patchBookshelfOnce(plugin)
    patchWidgetClassOnce(plugin)

    local Park = getPark()
    if not Park then
        logger.dbg("[bookshelf-overlay] Could not load lib/bookshelf_reader_park")
        return true
    end

    logger.dbg("[bookshelf-overlay] isParked BEFORE the toggle:", tostring(Park.isParked()))

    local original_enabled = Park.enabled
    Park.enabled = function() return true end
    logger.dbg("[bookshelf-overlay] Park.enabled forced to true (temporarily)")

    local ok, err = pcall(function()
        local rui = plugin and plugin.ui

        savePageLabels(rui)

        if not plugin._widget then
            parkWithColdCreate(plugin, rui, Park, now_ms, t_start)
        else
            toggleExistingWidget(plugin, rui, now_ms, t_start)
        end
    end)

    Park.enabled = original_enabled
    logger.dbg("[bookshelf-overlay] Park.enabled restored")

    logger.dbg("[bookshelf-overlay] toggle pcall ok=", tostring(ok), "err=", tostring(err))
    logger.dbg("[bookshelf-overlay] isParked AFTER the toggle:", tostring(Park.isParked()))

    if not ok then
        logger.warn("[bookshelf-overlay] ERROR in toggle:", err)
    end

    logger.dbg(string.format("[TIMING] SYNC TIME: %.3f ms", now_ms() - t_start))

    return true
end

-- Why ReaderUI:init? It is the one point where the patch can run before the user
-- does anything, and where the Bookshelf plugin is guaranteed to exist.
--
-- Not earlier (at load time): no book is open yet, so there is no self.bookshelf
-- instance, and the patch needs one because it gets the class through
-- getmetatable(plugin).
--
-- Not later (only on East North): that was the original bug. The class was patched
-- only the first time the park gesture was used, so a West South done BEFORE ever
-- having parked reached the unpatched native Bookshelf onHome, which does not show
-- the MultiConfirmBox and swallows the event.
--
-- KOReader creates ReaderUI when a book opens and, inside init, instantiates all
-- the plugins (including Bookshelf). So right after the original init returns,
-- self.bookshelf exists and its class is reachable, before any gesture can happen.
-- The original init runs first, so KOReader sets everything up exactly as usual.
-- The patch functions have a "done" flag: after the first book they do nothing, and
-- since the class is shared by all instances, patching once covers every later book.
local original_readerui_init = ReaderUI.init
logger.dbg("[bookshelf-overlay] original_readerui_init captured:", tostring(original_readerui_init))

function ReaderUI:init(...)
    local ret
    if original_readerui_init then
        ret = original_readerui_init(self, ...)
    end

    if self.bookshelf then
        logger.dbg("[bookshelf-overlay] ReaderUI:init: self.bookshelf exists -> eager patchBookshelfOnce")
        patchBookshelfOnce(self.bookshelf)
        patchWidgetClassOnce(self.bookshelf)
    else
        logger.dbg("[bookshelf-overlay] ReaderUI:init: self.bookshelf still nil after init")
    end

    return ret
end
