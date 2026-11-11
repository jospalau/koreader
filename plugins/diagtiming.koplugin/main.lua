-- plugins/diagtiming.koplugin/main.lua
--[[
Diagnostic-only plugin: times require(), UIManager scheduled callbacks,
event dispatch, event handlers and Screen:refresh* calls. Logging only;
it does not change behavior.

Toggled from the pagetextinfo menu, which saves the "diagtiming_enabled"
setting and emits the "DiagTimingToggled" event.

All times are SELF times (exclusive): the time an item took minus the time of
the measured items nested inside it. This way categories do not overlap and
the numbers can be added up. The log also shows the inclusive time when it
differs from the self time.

When a document finishes opening (ReaderReady + SUMMARY_DELAY_S) it shows an
InfoMessage with a top list of the slowest items measured during the opening.
Each item in the top shows "at file:line", the source line where it hooks in:
  - scheduleIn/nextTick : the line that scheduled the callback
  - require             : the line that requested the module
  - event               : the line that sent the event
  - handler             : the line where the handler function is defined
  - Screen:refresh*     : the line that triggered the refresh
The log also has the full list of callers (and a stack for events/refreshes).

NEW: the same is done when the document is CLOSED. ReaderUI:onClose is hooked:
a new measurement starts when it is called and, SUMMARY_DELAY_S after it returns
(to catch the first repaint of the file manager), a second InfoMessage shows the
slowest items of the closing. Extra kind in that summary:
  - close               : ReaderUI methods and document:close() timed one by one
                          (saveSettings, notifyCloseDocument, document:close...)
Handlers of every event (onCloseDocument, onSaveSettings, onFlushSettings,
onCloseWidget...) are listed in the handlers section, see FOCUS_EVENT_CLOSE.
]]

local Device = require("device")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local EventListener = require("ui/widget/eventlistener")
local InfoMessage = require("ui/widget/infomessage")
local logger = require("logger")
local time = require("ui/time")

local SETTING = "diagtiming_enabled"
local THRESHOLD_MS = 15      -- only log/record anything slower than this
local SUMMARY_DELAY_S = 1    -- wait after ReaderReady to catch the first repaint
local TOP_N = 8              -- number of slowest entries in the summary
local TRACE = true           -- log the full stack of slow events/refreshes
local TRACE_LINES = 14       -- max stack lines per entry
local CALLSITE_DEPTH = 3     -- how many callers to list in the log
-- Handlers (and the anonymous callbacks ReaderUI runs after init/ReaderReady) use
-- a lower threshold, as there are many of them and each one is usually small.
local HANDLER_THRESHOLD_MS = 3
local TOP_HANDLERS = 8       -- number of entries in the handlers section of the summary
-- The handlers section only lists handlers of this event (plus the anonymous
-- post-ReaderReady callbacks). Set to nil to list every handler.
-- OLD: local FOCUS_EVENT = "onReaderReady"
-- NEW: nil = every handler that runs while opening, not only onReaderReady's.
-- Put "onReaderReady" back to focus on that event only.
local FOCUS_EVENT = nil
-- NEW: same as FOCUS_EVENT but for the closing summary. nil = every handler,
-- since all the events sent while closing (CloseDocument, SaveSettings,
-- FlushSettings, CloseWidget...) are of interest.
local FOCUS_EVENT_CLOSE = nil
-- NEW: show a summary when the document is closed (set to false to disable)
local SHOW_CLOSE_SUMMARY = true
-- NEW: threshold for the "close" kind (methods timed one by one while closing)
local CLOSE_THRESHOLD_MS = 5
-- NEW: ReaderUI instance methods timed while closing. Only the ones that exist
-- are wrapped (type-checked), so a name that is missing in your KOReader
-- version is simply skipped. document:close() is wrapped separately.
local CLOSE_METHODS = { "saveSettings", "notifyCloseDocument", "onCloseDocument", "showFileManager" }

-- LuaJIT / Lua 5.2+ compatibility
local pack = table.pack or function(...) return { n = select("#", ...), ... } end
local unpack = table.unpack or unpack

-- Kinds that use HANDLER_THRESHOLD_MS and go in the handlers section.
local HANDLER_KINDS = { handler = true, postInit = true, postReaderReady = true }

local function now() return time.now() end
local function since_ms(t0) return time.to_ms(time.since(t0)) end

-- "file:line" where a function is defined.
local function describe(fn)
    local info = type(fn) == "function" and debug.getinfo(fn, "S")
    if not info then return tostring(fn) end
    return string.format("%s:%d", info.short_src, info.linedefined)
end

-- Readable name for the widget that owns a handler: its "name" field if it has
-- one, otherwise the file where the handler is defined (e.g. "readerfooter").
local function widgetName(widget, fn)
    if widget.name then return tostring(widget.name) end
    local info = type(fn) == "function" and debug.getinfo(fn, "S")
    if info then
        local base = info.short_src:match("([^/\\]+)%.lua$")
        if base then return base end
    end
    return "?"
end

-- Source of this file, so its own wrapper frames are never reported as callers.
local SELF_SRC = debug.getinfo(1, "S").short_src

-- List of "file:line" callers, innermost first, skipping this file's own frames.
-- level=2 means the function that called the one that calls callsites().
local function callsites(level, depth)
    local list = {}
    local lvl = level + 1
    while #list < (depth or CALLSITE_DEPTH) do
        local info = debug.getinfo(lvl, "Sl")
        if not info then break end
        -- OLD: if info.short_src ~= SELF_SRC then
        -- NEW: also skip C frames ("[C]:-1"), they say nothing useful about the caller
        if info.short_src ~= SELF_SRC and info.what ~= "C" then
            list[#list + 1] = string.format("%s:%d", info.short_src, info.currentline or 0)
        end
        lvl = lvl + 1
    end
    return list
end

-- Multi-line text with the callers, for the log.
local function callersText(list)
    if #list == 0 then return nil end
    return "[diag]   called from:\n[diag]     " .. table.concat(list, "\n[diag]     ")
end

-- Truncated traceback (at most TRACE_LINES lines).
local function stack(level)
    local tb = debug.traceback("", level + 1)
    local out, n = {}, 0
    for line in tb:gmatch("[^\n]+") do
        n = n + 1
        if n > TRACE_LINES then
            out[#out + 1] = "\t..."
            break
        end
        out[#out + 1] = line
    end
    return table.concat(out, "\n")
end

local function isEnabled()
    return G_reader_settings:isTrue(SETTING)
end

---------------------------------------------------------------------------
-- Self-time measurement
---------------------------------------------------------------------------
-- OLD: -- Shared stack: each level accumulates the total time of its measured children.
-- OLD: local tstack = {}
-- NEW: one stack per coroutine. Each level accumulates the total time of its
-- measured children. Time spent yielded is still counted in the item (it is
-- wall-clock time), but other coroutines no longer corrupt its accounting.
local MAIN = {}
local tstacks = setmetatable({}, { __mode = "k" })
local function curStack()
    local co = coroutine.running() or MAIN
    local s = tstacks[co]
    if not s then s = {}; tstacks[co] = s end
    return s
end

-- Collection state (declared here because timed() accounts self time).
local collecting = false
local open_t0 = nil      -- when stats were reset
local first_t0 = nil     -- start of the earliest item measured since the reset
local self_total = 0     -- sum of ALL self times (any size) since the reset
-- NEW: when ReaderReady fired (or, for the closing phase, when ReaderUI:onClose
-- returned), so the deliberate SUMMARY_DELAY_S wait is not counted as idle
-- time in the summary
local ready_t = nil
-- NEW: "open" or "close": which part of the document life is being measured
local phase = "open"
-- NEW: incremented on every reset, so a summary scheduled for an earlier
-- measurement (e.g. another book was opened meanwhile) is never shown
local session_id = 0

-- NEW: error handler that adds the traceback only once. Nested wrappers
-- (callback -> event -> handler) rethrow the error, and with debug.traceback
-- directly each level appended another traceback and changed the message.
local function errhandler(e)
    if type(e) == "string" and not e:find("stack traceback:", 1, true) then
        return debug.traceback(e, 2)
    end
    return e
end

-- Runs f(), returns its packed results (xpcall style: res[1] is the status),
-- the total (inclusive) time and the own (exclusive) time, both in ms.
local function timed(f)
    local tstack = curStack()   -- NEW: per-coroutine stack
    local depth = #tstack + 1
    tstack[depth] = 0
    local t0 = now()
    -- OLD: local r = pack(xpcall(f, debug.traceback))
    local r = pack(xpcall(f, errhandler))
    local total = since_ms(t0)
    local child = tstack[depth]
    -- Pop this level (and anything left above it, to be safe after errors).
    for i = #tstack, depth, -1 do tstack[i] = nil end
    -- Our total counts as child time for the parent level.
    if depth > 1 then tstack[depth - 1] = tstack[depth - 1] + total end
    local own = total - child
    if collecting then
        -- Items that started before the reset (e.g. the callback that is opening
        -- the document) still count, so the timeline starts at the earliest one.
        if not first_t0 or t0 < first_t0 then first_t0 = t0 end
        self_total = self_total + own
    end
    return r, total, own
end

---------------------------------------------------------------------------
-- Data collection for the summary
---------------------------------------------------------------------------
local by_kind = {}   -- kind -> { count = n, total = ms }
local by_item = {}   -- "kind label" -> { kind, label, where, count, total, max }

-- NEW: new_phase is optional ("open" by default)
local function resetStats(new_phase)
    by_kind = {}
    by_item = {}
    open_t0 = now()
    first_t0 = nil
    self_total = 0
    ready_t = nil   -- NEW: a new document starts clean
    phase = new_phase or "open"
    session_id = session_id + 1
    collecting = true
end

local function record(kind, label, dt, where)
    local k = by_kind[kind]
    if not k then k = { count = 0, total = 0 }; by_kind[kind] = k end
    k.count = k.count + 1
    k.total = k.total + dt

    local key = kind .. " " .. label
    local it = by_item[key]
    if not it then
        it = { kind = kind, label = label, where = where, count = 0, total = 0, max = 0 }
        by_item[key] = it
    end
    it.count = it.count + 1
    it.total = it.total + dt
    if dt > it.max then it.max = dt end
end

-- dt: own (self) time in ms
-- where: one "file:line" string (shown in the summary and the log)
-- extra: optional multi-line text for the log only (callers, chain, stack)
-- total: optional inclusive time in ms, shown in the log only
local function report(kind, label, dt, where, extra, total)
    -- OLD: if dt <= (HANDLER_KINDS[kind] and HANDLER_THRESHOLD_MS or THRESHOLD_MS) then return end
    -- NEW: the "close" kind has its own threshold
    local threshold = THRESHOLD_MS
    if HANDLER_KINDS[kind] then
        threshold = HANDLER_THRESHOLD_MS
    elseif kind == "close" then
        threshold = CLOSE_THRESHOLD_MS
    end
    if dt <= threshold then return end
    local msg = string.format("[diag] %s %s took %.1fms (own)", kind, label, dt)
    if total and math.abs(total - dt) > 0.5 then
        msg = msg .. string.format(", %.1fms inclusive", total)
    end
    if where and where ~= "" then
        msg = msg .. "\n[diag]   at " .. where
    end
    if extra then
        msg = msg .. "\n" .. extra
    end
    logger.dbg(msg)
    if collecting then record(kind, label, dt, where) end
end

-- Keep the tail of a string, which is the most informative part of a path.
local function shorten(s, n)
    if #s <= n then return s end
    return "…" .. s:sub(-(n - 1))
end

-- Appends the lines of one item of a top list.
local function addItem(lines, i, it)
    local name = it.label ~= "" and (it.kind .. " " .. shorten(it.label, 34)) or it.kind
    if it.count > 1 then
        lines[#lines + 1] = string.format("%d. %.0fms (%d times, max %.0fms) %s",
            i, it.total, it.count, it.max, name)
    else
        lines[#lines + 1] = string.format("%d. %.0fms %s", i, it.total, name)
    end
    if it.where and it.where ~= "" then
        lines[#lines + 1] = "    at " .. shorten(it.where, 56)
    end
end

-- NEW: event the handlers section is focused on, depending on the phase
local function focusEvent()
    if phase == "close" then return FOCUS_EVENT_CLOSE end
    return FOCUS_EVENT
end

-- Is this item part of the handlers section?
local function inHandlerSection(it)
    -- OLD: used FOCUS_EVENT directly
    -- NEW: focusEvent() gives FOCUS_EVENT or FOCUS_EVENT_CLOSE
    local focus = focusEvent()
    if not HANDLER_KINDS[it.kind] then return false end
    if not focus then return true end
    if it.kind == "postReaderReady" then return focus == "onReaderReady" end
    return it.kind == "handler" and it.label:sub(-(#focus + 1)) == ":" .. focus
end

local function buildSummary()
    local start = first_t0 or open_t0
    local elapsed = start and since_ms(start) or 0
    local lines = {
        -- OLD: string.format("Diag timing: %.0fms elapsed (self time per item)", elapsed),
        -- NEW: says whether it is the opening or the closing
        string.format("Diag timing (%s): %.0fms elapsed (self time per item)", phase, elapsed),
        string.format("(only items slower than %dms; handlers %dms)", THRESHOLD_MS, HANDLER_THRESHOLD_MS),
        "",
    }

    -- Totals per kind, slowest first
    local kinds = {}
    for kind, k in pairs(by_kind) do
        kinds[#kinds + 1] = { kind = kind, count = k.count, total = k.total }
    end
    table.sort(kinds, function(a, b) return a.total > b.total end)

    if #kinds == 0 then
        lines[#lines + 1] = "Nothing went over the threshold."
        return table.concat(lines, "\n")
    end

    local recorded = 0
    for _, k in ipairs(kinds) do
        recorded = recorded + k.total
        lines[#lines + 1] = string.format("%s: %d times, %.0fms", k.kind, k.count, k.total)
    end
    -- The rest, so that everything adds up to the elapsed time.
    local small = math.max(0, self_total - recorded)
    -- OLD: local idle = math.max(0, elapsed - self_total)
    -- NEW: the SUMMARY_DELAY_S wait is not idle time. This is approximate, since the
    -- repaint measured inside that window is also in self_total, hence the clamp.
    local waited = ready_t and since_ms(ready_t) or 0
    local idle = math.max(0, elapsed - self_total - waited)
    lines[#lines + 1] = string.format("small items (below threshold): %.0fms", small)
    lines[#lines + 1] = string.format("idle/unmeasured: %.0fms", idle)

    -- Top N individual items
    local items = {}
    for _, it in pairs(by_item) do items[#items + 1] = it end
    table.sort(items, function(a, b) return a.total > b.total end)

    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("Top %d slowest:", math.min(TOP_N, #items))
    for i = 1, math.min(TOP_N, #items) do
        addItem(lines, i, items[i])
    end

    -- Handlers section (ranked on their own, not mixed with nextTick and co.)
    local hitems = {}
    for _, it in ipairs(items) do   -- items is already sorted, slowest first
        if inHandlerSection(it) then hitems[#hitems + 1] = it end
    end
    -- NEW: the focused event depends on the phase
    local focus = focusEvent()
    -- NEW: readable title with and without a focused event
    local what = focus and (focus .. " handlers") or "handlers (any event)"
    lines[#lines + 1] = ""
    if #hitems == 0 then
        -- OLD: string.format("No %s handlers over %dms.", focus or "", HANDLER_THRESHOLD_MS)
        lines[#lines + 1] = string.format("No %s over %dms.", what, HANDLER_THRESHOLD_MS)
    else
        -- OLD: string.format("Top %d %s handlers (over %dms):", math.min(TOP_HANDLERS, #hitems), focus or "", HANDLER_THRESHOLD_MS)
        lines[#lines + 1] = string.format("Top %d %s (over %dms):",
            math.min(TOP_HANDLERS, #hitems), what, HANDLER_THRESHOLD_MS)
        for i = 1, math.min(TOP_HANDLERS, #hitems) do
            addItem(lines, i, hitems[i])
        end
    end
    return table.concat(lines, "\n")
end

local function showSummary()
    local text = buildSummary()
    -- Stop collecting: the InfoMessage itself triggers refreshes, don't measure them.
    collecting = false
    logger.dbg("[diag] summary:\n" .. text)
    UIManager:show(InfoMessage:new{ text = text })
end

---------------------------------------------------------------------------
-- Hook state
---------------------------------------------------------------------------
-- Already-created wrappers check this flag, so they go transparent when disabled.
local active = false
local originals = nil                                  -- originals to restore
-- OLD: local wrapped_for = setmetatable({}, { __mode = "k" }) -- original -> wrapper
-- NEW: "kv" because the wrapper closes over its own key, which pins it under LuaJIT's
-- weak-table semantics. The scheduler holds pending wrappers strongly, so unschedule() still works.
local wrapped_for = setmetatable({}, { __mode = "kv" }) -- original -> wrapper
local origin_for = setmetatable({}, { __mode = "k" })  -- original -> latest scheduling site
local our_wrappers = setmetatable({}, { __mode = "k" }) -- set of wrappers created here
-- Installed once and left in place (it is cheap).
local unschedule_hooked = false

-- Wrap a callback, caching the wrapper so unschedule() can find it later.
local function wrap_callback(kind, fn, origin)
    if type(fn) ~= "function" then return fn end
    -- UIManager may call scheduleIn/nextTick from inside each other: never wrap
    -- a wrapper again, or the time is counted twice and points at this file.
    if our_wrappers[fn] then return fn end
    origin_for[fn] = origin
    local w = wrapped_for[fn]
    if w then return w end
    local label = describe(fn)
    w = function(...)
        if not active then return fn(...) end
        -- Forward arguments with a closure and give back the callback's own return
        -- values, so the wrapped callback behaves exactly like the original.
        local args = pack(...)
        local res, total, own = timed(function() return fn(unpack(args, 1, args.n)) end)
        local sites = origin_for[fn] or {}
        report(kind, label, own, sites[1], callersText(sites), total)
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2, res.n)
    end
    wrapped_for[fn] = w
    our_wrappers[w] = true
    return w
end

-- NEW: temporarily wraps obj[name] (an instance method) so its self time is
-- reported as kind "close". The function that undoes it is added to `restores`.
-- Methods that do not exist are skipped. Arguments and return values are
-- forwarded as they are, like in wrap_callback.
local function wrapInstanceMethod(obj, name, label, restores)
    if type(obj) ~= "table" then return end
    local fn = obj[name]
    if type(fn) ~= "function" then return end
    local own_value = rawget(obj, name)   -- nil if it was inherited from the class
    obj[name] = function(self, ...)
        local args = pack(...)
        local res, total, own = timed(function() return fn(self, unpack(args, 1, args.n)) end)
        report("close", label, own, describe(fn), nil, total)
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2, res.n)
    end
    restores[#restores + 1] = function() obj[name] = own_value end
end

-- NEW: shows the closing summary SUMMARY_DELAY_S after ReaderUI:onClose
-- returned, so the first repaint of the file manager is included.
local function scheduleCloseSummary()
    ready_t = now()   -- the wait below is not idle time
    local id = session_id
    UIManager:scheduleIn(SUMMARY_DELAY_S, function()
        -- Not shown if another document was opened in the meantime (new session)
        if active and phase == "close" and id == session_id then showSummary() end
    end)
end

local function install()
    if active then return end
    active = true
    originals = {}

    -- 1) scheduleIn / nextTick (records where each callback was scheduled)
    local orig_scheduleIn = UIManager.scheduleIn
    local orig_nextTick = UIManager.nextTick
    originals.scheduleIn = orig_scheduleIn
    originals.nextTick = orig_nextTick

    UIManager.scheduleIn = function(self, delay, cb, ...)
        return orig_scheduleIn(self, delay, wrap_callback("scheduleIn", cb, callsites(2)), ...)
    end
    UIManager.nextTick = function(self, cb, ...)
        return orig_nextTick(self, wrap_callback("nextTick", cb, callsites(2)), ...)
    end

    -- unschedule stays hooked even after disabling, so callbacks that were
    -- already wrapped can still be cancelled.
    if not unschedule_hooked then
        unschedule_hooked = true
        local orig_unschedule = UIManager.unschedule
        UIManager.unschedule = function(self, fn, ...)
            return orig_unschedule(self, wrapped_for[fn] or fn, ...)
        end
    end

    -- 2) require() with own time (excludes nested requires)
    local orig_require = require
    originals.require = orig_require
    local chain = {}   -- stack of modules being loaded
    _G.require = function(name)
        if package.loaded[name] then return orig_require(name) end
        local sites = callsites(2, CALLSITE_DEPTH)
        chain[#chain + 1] = name
        local res, total, own = timed(function() return orig_require(name) end)
        -- Modules that were being loaded when this one was requested (outer ones)
        local outer = {}
        for i = 1, #chain - 1 do outer[#outer + 1] = chain[i] end
        chain[#chain] = nil
        if own > THRESHOLD_MS then
            local extra = string.format("[diag]   own %.1fms, total %.1fms", own, total)
            if #outer > 0 then
                extra = extra .. "\n[diag]   loaded while loading: " .. table.concat(outer, ", ")
            end
            local c = callersText(sites)
            if c then extra = extra .. "\n" .. c end
            report("require", name, own, sites[1], extra, total)
        end
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2, res.n)
    end

    -- 3) Events (where they are sent from, plus a stack if slow)
    local orig_sendEvent = UIManager.sendEvent
    originals.sendEvent = orig_sendEvent
    UIManager.sendEvent = function(self, event)
        local res, total, own = timed(function() return orig_sendEvent(self, event) end)
        if own > THRESHOLD_MS then
            local sites = callsites(2, CALLSITE_DEPTH)
            local extra = callersText(sites)
            if TRACE then
                extra = (extra and (extra .. "\n") or "") .. stack(2)
            end
            report("event", tostring(event and (event.handler or event.name) or "?"),
                own, sites[1], extra, total)
        end
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2, res.n)
    end

    -- 3b) Which widget/function runs each handler (self handler time)
    local orig_handleEvent = EventListener.handleEvent
    originals.handleEvent = orig_handleEvent
    EventListener.handleEvent = function(self, event, ...)
        -- OLD: if not active then return orig_handleEvent(self, event, ...) end
        -- NEW: also bail out early when this widget has no handler for the event, so most
        -- calls skip pack/closure/xpcall and the probe disturbs the timings less.
        -- Note: handleEvent forwards to children inside orig_handleEvent, so skipping
        -- the timer here only drops the entry for widgets that don't handle the event.
        local h = event and event.handler
        if not active or not (h and self[h]) then
            return orig_handleEvent(self, event, ...)
        end
        local args = pack(...)
        local res, total, own = timed(function()
            return orig_handleEvent(self, event, unpack(args, 1, args.n))
        end)
        if own > HANDLER_THRESHOLD_MS then
            -- OLD: local h = event and event.handler   (now declared above)
            local fn = h and self[h]
            report("handler",
                string.format("%s:%s", widgetName(self, fn), tostring(h or "?")),
                own, describe(fn), nil, total)
        end
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2, res.n)
    end

    -- 3c) Anonymous callbacks that ReaderUI runs right after init and right after
    -- ReaderReady (registerPostInitCallback / registerPostReaderReadyCallback).
    -- They are called as plain functions, not through handleEvent, so without this
    -- their time would be counted inside the enclosing scheduled callback.
    -- Only callbacks registered after this point are seen.
    local ok, ReaderUI = pcall(orig_require, "apps/reader/readerui")
    if ok and type(ReaderUI) == "table" then
        originals.readerui = { class = ReaderUI, methods = {} }
        local hooks = {
            registerPostInitCallback = "postInit",
            registerPostReaderReadyCallback = "postReaderReady",
        }
        for method, kind in pairs(hooks) do
            local orig = ReaderUI[method]
            if type(orig) == "function" then
                originals.readerui.methods[method] = { own = rawget(ReaderUI, method) }
                ReaderUI[method] = function(self, cb, ...)
                    return orig(self, wrap_callback(kind, cb, callsites(2)), ...)
                end
            end
        end

        -- 3d) NEW: closing the document. ReaderUI:onClose starts a new measurement
        -- (phase "close"), times the closing methods one by one while it runs
        -- and schedules the closing summary when it returns. Everything else
        -- (handlers of CloseDocument/SaveSettings/FlushSettings/CloseWidget,
        -- refreshes, scheduled callbacks...) is already measured by the hooks above.
        local orig_onClose = ReaderUI.onClose
        if SHOW_CLOSE_SUMMARY and type(orig_onClose) == "function" then
            originals.readerui.methods.onClose = { own = rawget(ReaderUI, "onClose") }
            ReaderUI.onClose = function(self, ...)
                if not active then return orig_onClose(self, ...) end
                logger.dbg("[diag] ReaderUI:onClose hook fired")   -- NEW: to check in the log that the hook runs
                -- Starts from scratch. The handleEvent/sendEvent call that is running
                -- this very function started before the reset: timed() takes that
                -- into account (see first_t0), as it does when opening a document.
                resetStats("close")
                local restores = {}
                for _, name in ipairs(CLOSE_METHODS) do
                    wrapInstanceMethod(self, name, "ReaderUI:" .. name, restores)
                end
                wrapInstanceMethod(self.document, "close", "document:close", restores)
                local args = pack(...)
                local res, total, own = timed(function()
                    return orig_onClose(self, unpack(args, 1, args.n))
                end)
                -- Remove the temporary instance wrappers (pcall: never break closing)
                for _, undo in ipairs(restores) do pcall(undo) end
                report("close", "ReaderUI:onClose", own, describe(orig_onClose), nil, total)
                scheduleCloseSummary()
                if not res[1] then error(res[2], 0) end
                return unpack(res, 2, res.n)
            end
        end
    end

    -- 4) Screen:refresh* (also walking the metatable chain)
    local Screen = Device.screen
    originals.screen = {}

    -- Collect first, assign afterwards (never modify a table while iterating it).
    local found = {}
    local seen = {}
    local obj = Screen
    while obj do
        for name, fn in pairs(obj) do
            if type(fn) == "function" and type(name) == "string"
                and name:match("^refresh") and not seen[name] then
                seen[name] = true
                found[name] = fn
            end
        end
        local mt = getmetatable(obj)
        obj = mt and type(mt.__index) == "table" and mt.__index or nil
    end

    for name, fn in pairs(found) do
        -- own = nil if the method was inherited
        originals.screen[name] = { own = rawget(Screen, name) }
        Screen[name] = function(self, ...)
            if not active then return fn(self, ...) end
            local args = pack(...)
            local res, total, own = timed(function()
                return fn(self, unpack(args, 1, args.n))
            end)
            if own > THRESHOLD_MS then
                local sites = callsites(2, CALLSITE_DEPTH)
                local extra = callersText(sites)
                if TRACE then
                    extra = (extra and (extra .. "\n") or "") .. stack(2)
                end
                report("Screen:" .. name, "", own, sites[1], extra, total)
            end
            if not res[1] then error(res[2], 0) end
            return unpack(res, 2, res.n)
        end
    end

    logger.dbg("[diag] timing hooks installed")
end

local function uninstall()
    if not active then return end
    -- Already-scheduled callback wrappers become transparent.
    active = false
    collecting = false

    UIManager.scheduleIn = originals.scheduleIn
    UIManager.nextTick = originals.nextTick
    UIManager.sendEvent = originals.sendEvent
    EventListener.handleEvent = originals.handleEvent
    _G.require = originals.require

    -- NEW: this loop also restores ReaderUI.onClose (saved in methods.onClose)
    if originals.readerui then
        for method, saved in pairs(originals.readerui.methods) do
            originals.readerui.class[method] = saved.own
        end
    end

    -- If the method was inherited, setting it back to nil lets the metatable resolve it again.
    local Screen = Device.screen
    for name, saved in pairs(originals.screen) do
        Screen[name] = saved.own
    end

    originals = nil
    logger.dbg("[diag] timing hooks removed")
end

-- If it was already enabled in a previous session, hook in as early as
-- possible (so require() calls from plugins loaded later are captured).
if isEnabled() then
    install()
    resetStats()
end

---------------------------------------------------------------------------
-- Plugin
---------------------------------------------------------------------------
local DiagTiming = WidgetContainer:extend{
    name = "diagtiming",
    is_doc_only = false,
}

function DiagTiming:init()
    -- Every time a ReaderUI is created (a document is opened) start from scratch.
    -- OLD: if active then
    -- NEW: only when a document is open. The plugin is also created in the
    -- FileManager (is_doc_only = false), which is shown right when a document
    -- is closed: resetting there threw away the closing stats, switched the
    -- phase back to "open" and invalidated the pending closing summary.
    if active and self.ui and self.ui.document then
        resetStats()
    end
end

-- Emitted from the pagetextinfo menu.
function DiagTiming:onDiagTimingToggled(enable)
    if enable then
        install()
        resetStats()
    else
        uninstall()
    end
    return true
end

function DiagTiming:onReaderReady()
    if not active then return end
    logger.dbg("[diag] onReaderReady")
    -- NEW: remember when ReaderReady fired, so buildSummary() can exclude the wait below
    ready_t = now()
    -- NEW: the summary is only shown if nothing started a new measurement meanwhile
    -- (e.g. the document was closed before SUMMARY_DELAY_S elapsed)
    local id = session_id
    -- Wait a bit so the first page repaint is included.
    UIManager:scheduleIn(SUMMARY_DELAY_S, function()
        -- OLD: if active then showSummary() end
        if active and phase == "open" and id == session_id then showSummary() end
    end)
end

return DiagTiming
