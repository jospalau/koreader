-- Exit timing: where the time goes when a book is closed and the file manager
-- (or Bookshelf) is built again. The data is collected while it happens and shown
-- in a window once everything has settled, like the diagtiming plugin does.
--
-- Switched on and off with the "Exit timing" toggle (setting "exittiming_enabled").
-- While it is off NOTHING is hooked: the wrappers are installed when it is switched
-- on and taken out again when it is switched off.
--
--     local ExitTiming = require("exit_timing")
--     ExitTiming.setEnabled(G_reader_settings:isTrue("exittiming_enabled"))
--     ExitTiming.record(label, ms)      -- add an item to the current measurement
--
-- Two measurements, each one with its own window:
--   * leaving the book: starts when ReaderUI.onClose is called; the window is shown when
--     nothing has been measured for QUIET_MS (file manager built and painted).
--   * entering the book: starts when the reader is created (ReaderUI.doShowReader / init);
--     the window is shown QUIET_MS after the reader is ready (PageTextInfo calls
--     ExitTiming.readerReady() from its onReaderReady).
-- Both list the slowest items and the plugins that took longest to start.
-- Times of wrapped functions are INCLUSIVE: ReaderUI.onClose contains
-- closeDocument, saveSettings..., and Menu.init is contained in FileChooser.init.
-- A wrapper around ReaderUI.onClose installed by another plugin (e.g. a closing
-- cover) is part of the ReaderUI.onClose total.
--
-- The summary window has two buttons: "Close" (also tapping outside it) and
-- "× Switch off", which switches the toggle off (setting "exittiming_enabled"), takes the
-- wrappers out and calls the function given to ExitTiming.setOnClose (the menus that
-- show the toggle are redrawn from there). Closing it any other way keeps measuring, so
-- a book can be entered and left as many times as needed.
--
-- A wrapper that cannot be taken out (something else wrapped the same function
-- afterwards) stays in place but only calls the original while the toggle is off.

local time = require("ui/time")

local QUIET_MS = 1000       -- nothing measured for this long = finished
local MAX_WAIT_MS = 10000   -- never wait longer than this after the close started
local TOP_ITEMS = 14        -- items in the "slowest" list
local TOP_PLUGINS = 8       -- plugins in the "plugins started" list
local ENABLED_SETTING = "exittiming_enabled"

local M = { enabled = false }
local on_close_cb   -- optional, set with M.setOnClose()

function M.setOnClose(fn) on_close_cb = fn end

-- { obj, name, orig, wrapper, own } for every function wrapped
local installed = {}

---------------------------------------------------------------------------
-- Data collection
---------------------------------------------------------------------------
local collecting = false
local session = 0
local items = {}        -- label -> { label, count, total, max }
local phase = "close"   -- "open" (entering the book) or "close" (leaving it)
local open_depth = 0    -- doShowReader and init are nested: only the outer one starts
local t_close = nil     -- when the measurement started
local last_end = nil    -- when the last item was recorded

function M.record(label, ms)
    if not collecting then return end
    local it = items[label]
    if not it then
        it = { label = label, count = 0, total = 0, max = 0 }
        items[label] = it
    end
    it.count = it.count + 1
    it.total = it.total + ms
    if ms > it.max then it.max = ms end
    last_end = time.now()
end

local function addItem(lines, i, it)
    if it.count > 1 then
        lines[#lines + 1] = string.format("%d. %.0f ms (%d times, max %.0f) %s",
            i, it.total, it.count, it.max, it.label)
    else
        lines[#lines + 1] = string.format("%d. %.0f ms %s", i, it.total, it.label)
    end
end

local function startSession(new_phase)
    session = session + 1
    items = {}
    collecting = true
    phase = new_phase
    t_close = time.now()
    last_end = t_close
    return session
end

local function buildSummary()
    local span = (t_close and last_end) and time.to_ms(last_end - t_close) or 0
    local lines = {
        string.format("%s: %.0f ms until the last measured item",
            phase == "open" and "Exit timing (entering the book)" or "Exit timing (leaving the book)", span),
        "(times are inclusive: nested items are counted in their parent)",
        "",
    }
    local plugins, others = {}, {}
    for __, it in pairs(items) do
        if it.label:find("^plugin%-init:") then
            plugins[#plugins + 1] = it
        else
            others[#others + 1] = it
        end
    end
    local function byTotal(a, b) return a.total > b.total end
    table.sort(plugins, byTotal)
    table.sort(others, byTotal)

    if #others == 0 and #plugins == 0 then
        lines[#lines + 1] = "Nothing went over the thresholds."
        return table.concat(lines, "\n")
    end
    lines[#lines + 1] = string.format("Slowest %d:", math.min(TOP_ITEMS, #others))
    for i = 1, math.min(TOP_ITEMS, #others) do
        addItem(lines, i, others[i])
    end
    if #plugins > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("Plugins started (top %d):", math.min(TOP_PLUGINS, #plugins))
        for i = 1, math.min(TOP_PLUGINS, #plugins) do
            plugins[i].label = plugins[i].label:gsub("^plugin%-init:", "")
            addItem(lines, i, plugins[i])
        end
    end
    return table.concat(lines, "\n")
end

local function showSummary()
    collecting = false   -- the window itself must not be measured
    local text = buildSummary()
    -- print("[exit-timing]\n" .. text)   -- also in the terminal, for reference
    local UIManager = require("ui/uimanager")
    -- Tapping outside only closes the window (to measure again); the "×" button also
    -- switches Exit timing off
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    dialog = ButtonDialog:new{
        title = text,
        title_align = "left",
        buttons = {
            {
                {
                    text = "Close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = "× Switch off",
                    callback = function()
                        UIManager:close(dialog)
                        -- later, not in the middle of closing the window
                        UIManager:nextTick(function()
                            G_reader_settings:saveSetting(ENABLED_SETTING, false)
                            G_reader_settings:flush()
                            M.setEnabled(false)
                            if on_close_cb then pcall(on_close_cb) end
                        end)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

local function scheduleSummary(id)
    local UIManager = require("ui/uimanager")
    local function check()
        if id ~= session or not M.enabled then return end
        local quiet = time.to_ms(time.since(last_end))
        local waited = time.to_ms(time.since(t_close))
        if quiet < QUIET_MS and waited < MAX_WAIT_MS then
            UIManager:scheduleIn((QUIET_MS - quiet) / 1000 + 0.05, check)
            return
        end
        showSummary()
    end
    UIManager:scheduleIn(QUIET_MS / 1000, check)
end

-- Called when the book is ready (from PageTextInfo:onReaderReady): the window of the
-- opening is scheduled from here
function M.readerReady()
    if M.enabled and collecting and phase == "open" then
        scheduleSummary(session)
    end
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------
local function isHooked(obj, name)
    for __, e in ipairs(installed) do
        if e.obj == obj and e.name == name then return true end
    end
    return false
end

-- Replaces obj[name] with make(orig). `permanent`: not recorded (it is on an object
-- that is thrown away anyway, like the modules of one book).
local function hook(obj, name, make, permanent)
    if not obj then return end
    local orig = obj[name]
    if type(orig) ~= "function" then
        -- print("[exit-timing] cannot wrap", name)
        return
    end
    if not permanent and isHooked(obj, name) then return end
    local wrapper = make(orig)
    if not permanent then
        installed[#installed + 1] = { obj = obj, name = name, orig = orig,
            wrapper = wrapper, own = rawget(obj, name) ~= nil }
    end
    obj[name] = wrapper
end

-- Generic timing wrapper: records `label` when the call takes min_ms (10) or more
local function wrap(obj, name, label, min_ms, permanent)
    hook(obj, name, function(orig)
        return function(...)
            if not M.enabled or not collecting then return orig(...) end
            local t = time.now()
            local r = table.pack(orig(...))
            local ms = time.to_ms(time.since(t))
            if ms >= (min_ms or 10) then M.record(label, ms) end
            return table.unpack(r, 1, r.n)
        end
    end, permanent)
end

-- CoverBrowser (and Project Title) replace some list functions when their plugin
-- starts: they are wrapped every time a FileChooser is created
local function wrapFileList()
    local Menu = require("ui/widget/menu")
    local FileChooser = require("ui/widget/filechooser")
    -- Menu first: FileChooser inherits from it and is then not wrapped twice
    for __, obj in ipairs({ Menu, FileChooser }) do
        wrap(obj, "updateItems", "updateItems")
        wrap(obj, "_recalculateDimen", "_recalculateDimen")
        wrap(obj, "switchItemTable", "switchItemTable")
    end
end

-- Every step is protected on its own: one that fails prints its error and the
-- rest still get installed
local function step(name, f)
    local ok, err = pcall(f)
    if not ok then end -- print("[exit-timing] step failed:", name, err)
end

local function install()
    local PluginLoader, ReaderUI, DocCache, FileManager, FileChooser, Menu, UIManager
    step("require", function()
        PluginLoader = require("pluginloader")
        ReaderUI = require("apps/reader/readerui")
        DocCache = require("document/doccache")
        FileManager = require("apps/filemanager/filemanager")
        FileChooser = require("ui/widget/filechooser")
        Menu = require("ui/widget/menu")
        UIManager = require("ui/uimanager")
    end)

    -- Start of a measurement: the whole reader close. Not a plain wrapper: it
    -- also resets the data and schedules the window.
    step("ReaderUI.onClose", function()
        hook(ReaderUI, "onClose", function(orig)
            return function(...)
                if not M.enabled then return orig(...) end
                local id = startSession("close")
                local r = table.pack(orig(...))
                M.record("ReaderUI.onClose", time.to_ms(time.since(t_close)))
                scheduleSummary(id)
                return table.unpack(r, 1, r.n)
            end
        end)
    end)

    -- Start of the opening: the reader is created. doShowReader contains init (and the
    -- loading of the document); only the outer one of the two starts the measurement.
    step("reader-open", function()
        for __, name in ipairs({ "doShowReader", "init" }) do
            hook(ReaderUI, name, function(orig)
                return function(...)
                    if not M.enabled then return orig(...) end
                    if open_depth == 0 then startSession("open") end
                    open_depth = open_depth + 1
                    local t = time.now()
                    local r = table.pack(pcall(orig, ...))
                    open_depth = open_depth - 1
                    M.record("ReaderUI." .. name, time.to_ms(time.since(t)))
                    if not r[1] then error(r[2], 0) end
                    return table.unpack(r, 2, r.n)
                end
            end)
        end
    end)

    -- Plugin init (reader plugins on entering, FileManager plugins on leaving)
    step("plugin-init", function()
        hook(PluginLoader, "createPluginInstance", function(orig)
            return function(this, plugin, attr)
                if not M.enabled or not collecting then return orig(this, plugin, attr) end
                local t = time.now()
                local ok, re = orig(this, plugin, attr)
                local ms = time.to_ms(time.since(t))
                if ms >= 5 then M.record("plugin-init:" .. tostring(plugin.name), ms) end
                return ok, re
            end
        end)
    end)

    -- Reader close
    step("reader-close", function()
        wrap(ReaderUI, "saveSettings", "ReaderUI.saveSettings")
        wrap(ReaderUI, "closeDocument", "ReaderUI.closeDocument")
        wrap(DocCache, "serialize", "DocCache.serialize")
        wrap(PluginLoader, "finalize", "PluginLoader.finalize")
        wrap(UIManager, "close", "UIManager.close", 30)
    end)
    step("readhistory", function()
        wrap(require("readhistory"), "updateLastBookTime", "readhistory.updateLastBookTime")
    end)
    step("readcollection", function()
        wrap(require("readcollection"), "updateLastBookTime", "readcollection.updateLastBookTime")
    end)
    step("booklist", function()
        wrap(require("ui/widget/booklist"), "setBookInfoCacheProperty", "BookList.setBookInfoCache")
    end)
    -- Time the onCloseDocument / onReaderReady of every child (each plugin / module) of
    -- the reader. They are wrapped the first time the event is dispatched.
    step("child-events", function()
        local done = setmetatable({}, { __mode = "k" })
        local prefixes = { onCloseDocument = "CloseDocument:", onReaderReady = "ReaderReady:" }
        hook(ReaderUI, "handleEvent", function(orig)
            return function(self, event, ...)
                local h = event and event.handler
                if M.enabled and prefixes[h] then
                    for __, w in ipairs(self) do
                        if type(w) == "table" and type(w[h]) == "function" then
                            done[w] = done[w] or {}
                            if not done[w][h] then
                                done[w][h] = true
                                wrap(w, h, prefixes[h] .. tostring(w.name or w.id or "?"), 5, true)
                            end
                        end
                    end
                end
                return orig(self, event, ...)
            end
        end)
    end)

    -- FileManager creation
    step("filemanager", function()
        wrap(FileManager, "init", "FileManager.init")
        wrap(FileManager, "setupLayout", "FileManager.setupLayout")
        wrap(FileChooser, "genItemTableFromPath", "FileChooser.genItemTable")
        wrap(Menu, "init", "Menu.init")
    end)
    step("titlebar", function() wrap(require("ui/widget/titlebar"), "new", "TitleBar.new", 15) end)
    step("button", function() wrap(require("ui/widget/button"), "new", "Button.new", 15) end)
    step("iconwidget", function() wrap(require("ui/widget/iconwidget"), "new", "IconWidget.new", 15) end)
    step("renderimage", function()
        local RenderImage = require("ui/renderimage")
        wrap(RenderImage, "renderSVGImageFile", "RenderImage.svg", 15)
        wrap(RenderImage, "renderImageFile", "RenderImage.file", 15)
    end)
    step("filelist", wrapFileList)
    step("FileChooser.init", function()
        hook(FileChooser, "init", function(orig)
            return function(fc, ...)
                if not M.enabled or not collecting then return orig(fc, ...) end
                wrapFileList()
                local t = time.now()
                local r = table.pack(orig(fc, ...))
                M.record("FileChooser.init", time.to_ms(time.since(t)))
                return table.unpack(r, 1, r.n)
            end
        end)
    end)
end

-- Takes every wrapper out again. One that something else wrapped afterwards cannot
-- be taken out: it stays (and only calls the original while the toggle is off).
local function uninstall()
    collecting = false
    session = session + 1   -- cancels a window that is still pending
    local left = {}
    for i = #installed, 1, -1 do
        local e = installed[i]
        if e.obj[e.name] == e.wrapper then
            if e.own then e.obj[e.name] = e.orig else e.obj[e.name] = nil end
        else
            table.insert(left, 1, e)
        end
    end
    installed = left
end

function M.setEnabled(enable)
    enable = enable and true or false
    if enable == M.enabled then return end
    M.enabled = enable
    local ok, err = pcall(enable and install or uninstall)
    if not ok then
        -- print("[exit-timing] error:", err)
    end
end

return M
