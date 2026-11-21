-- Widget time overlay: how long each widget takes to be created, live, scrollable
-- and movable, on every screen (File Manager, bookshelf, reader), toggled with a
-- setting. Same box and gestures as memory_overlay.
--
--   local WidgetTimeOverlay = require("widget_time_overlay")
--   WidgetTimeOverlay.setEnabled(true / false)   -- idempotent, deferred, never throws
--
-- While it is enabled, every widget that is created (Widget:new -> init) adds
-- one line, newest at the bottom:
--
--   08:12:03  ReaderView  45.2 ms  (self 3.1)
--
--   45.2 ms     total time of new(): the widget plus everything it created inside init
--   (self 3.1)  the same without the widgets created inside it (only shown when
--               it created children that were also logged or measured)
--
-- Two more kinds of line, for dialogs that were built earlier and only shown now:
--   08:12:05  show FontsMenu  12.0 ms   time of UIManager:show (Show event handlers)
--   08:12:05  paint FontsMenu  80 ms    first paint after it was shown
--
-- And the one that answers "how long until the window is on screen":
--   08:12:05  screen FontsMenu  85 ms  (show 20 ms)
--   85 ms = from the gesture that reached UIManager (when there was one in the
--           last 2 s) until the repaint that draws the widget has sent its refresh
--           to the screen; "show 20 ms" = the same counted from UIManager:show.
--   Without a recent gesture only the show time is printed. The e-ink panel
--   itself takes some more ms to update after that, which no code can measure.
--
-- Children finish before their parent, so they appear just above it, indented
-- one space per nesting level.
-- Nothing is recorded while the overlay is off (the hook is a plain pass-through)
-- and the overlay's own widgets are never recorded.
--
-- Gestures inside the box:
--   drag the top bar   move the box (applied on release, position is saved)
--   drag in the text   scroll, the lines follow the finger
--   tap on "clear" (left end of the top bar)   clear the list (a tap in the text does nothing)
--   swipe up/down      scroll toward newer / older lines (by swipe length, at most one page)
--   swipe left         back to the live end (newest line)
--   swipe right        jump to the oldest line kept
--   tap on the "×" (right end of the top bar)   close the overlay
-- Anything outside the box goes to the screen below as usual.
--
--   WidgetTimeOverlay.setOnClose(function() ... end)
--       optional, called after the "×" closed the overlay (the flag
--       "widgettimeoverlay_enabled" is already switched off by the "×" itself)

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local Screen = Device.screen

-- ─── settings ────────────────────────────────────────────────────────────────

local FACE_NAME = "infont"
local FONT_SIZE = 9
local N_LINES = 8            -- visible text lines (fixed height)
local MAX_LINES = 500        -- lines kept in memory (how far back you can scroll)
local MIN_MS = 0.5           -- widgets faster than this (ms) are not listed (0 = all)
-- Also time what happens when a widget is shown (UIManager:show) and its first
-- paint. Needed for dialogs that were built before (cached / pre-built) and only
-- shown now: their creation happened earlier, the cost is in show / paint.
local TRACK_SHOW_PAINT = true
local REFRESH_SECS = 0.5     -- the box is redrawn at most this often
local START_DELAY = 1        -- seconds to wait before touching the UI
local MARGIN = Screen:scaleBySize(6)
local PADDING = Size.padding.small
local SCROLLBAR_W = Screen:scaleBySize(3)
local POS_SETTING = "widgettimeoverlay_pos"   -- saved position {x=, y=}
-- Default position is the bottom of the screen, so it does not cover
-- memory_overlay (top of the screen). Moving the box saves a new position.
local DEFAULT_AT_BOTTOM = true

local SCROLL_ENABLED = true   -- false = no gesture hook at all (no scroll/tap/move)
local DEBUG_GESTURES = false  -- log every gesture that lands in the box
-- It changes in bursts: "ui" is the fastest (leaves some ghosting).
-- "partial": cleaner text. "flashui": full flash, cleanest.
local REFRESH_MODE = "ui"

local ENABLED_SETTING = "widgettimeoverlay_enabled"   -- flag the "×" switches off

-- ─── time ────────────────────────────────────────────────────────────────────

local time = require("ui/time")

local function nowT() return time.now() end

-- microseconds elapsed since t0 (works with any version of the time module)
local function elapsedUs(t0)
    local d = time.since(t0)
    if time.to_us then return time.to_us(d) end
    return time.to_ms(d) * 1000
end

local function fmtMs(us)
    local ms = us / 1000
    if ms >= 100 then return string.format("%d ms", math.floor(ms + 0.5)) end
    return string.format("%.1f ms", ms)
end

-- ─── the recorder ────────────────────────────────────────────────────────────

local overlay            -- the box, when on screen (singleton, shared by FM and reader)
local recording = false  -- true while the overlay is on
local suppress = 0       -- > 0: creations are not measured (the overlay's own widgets)
local frames = {}        -- stack of widgets being created: { child_us = , depth = }
local name_cache = setmetatable({}, { __mode = "k" })   -- init function -> name
local flush_scheduled = false

-- Runs fn without measuring the widgets it creates. Errors are re-thrown.
local function quiet(fn, ...)
    suppress = suppress + 1
    local ok, a, b, c = pcall(fn, ...)
    suppress = suppress - 1
    if not ok then error(a, 0) end
    return a, b, c
end

-- Name of a widget: its "name" or "id" field; else the file of a function the
-- widget defines on itself (e.g. dialog:onSwipe in font_selection_menu.lua);
-- else the file of the nearest init in its class chain.
local function fileOf(fn)
    local info = debug.getinfo(fn, "S")
    if not info then return nil end
    local src = info.short_src or "?"
    return (src:match("([^/\\]+)%.lua$") or src), info.linedefined
end

local function widgetName(w)
    local n = rawget(w, "name") or w.name
    if type(n) == "string" and n ~= "" then return n end
    n = rawget(w, "id") or w.id
    if type(n) == "string" and n ~= "" then return n end
    local init = w.init
    if type(init) == "function" and name_cache[init] then return name_cache[init] end
    -- functions defined on the instance itself: they come from the code that built it
    for k, v in pairs(w) do
        if type(v) == "function" then
            local f, line = fileOf(v)
            if f and not f:match("^widget$") then return f .. ":" .. tostring(line) end
        end
    end
    if type(init) == "function" then
        local f = fileOf(init) or "?"
        name_cache[init] = f
        return f
    end
    return "widget"
end

local flush   -- defined below

local function scheduleFlush()
    if flush_scheduled then return end
    flush_scheduled = true
    UIManager:scheduleIn(REFRESH_SECS, flush)
end

local function record(w, total_us, child_us, depth)
    if not overlay or total_us < MIN_MS * 1000 then return end
    local line = string.format("%s  %s%s  %s", os.date("%H:%M:%S"),
        string.rep(" ", math.min(depth, 6)), widgetName(w), fmtMs(total_us))
    if child_us > 0 then
        line = line .. string.format("  (self %s)", fmtMs(math.max(0, total_us - child_us)))
    end
    overlay:addLine(line)
    scheduleFlush()
end

-- Line for something that is not a creation: tag = "show" / "paint"
local function recordEvent(tag, w, us)
    if not overlay or us < MIN_MS * 1000 then return end
    overlay:addLine(string.format("%s  %s %s  %s", os.date("%H:%M:%S"), tag,
        widgetName(w), fmtMs(us)))
    scheduleFlush()
end

-- Windows shown and not yet drawn: { w =, t_show =, t_gesture = }
local pending = {}
local last_gesture_t = nil   -- when the last gesture reached UIManager

local function markGesture()
    if recording then last_gesture_t = nowT() end
end

local function addPending(w, t_show)
    local g = last_gesture_t
    if g and elapsedUs(g) > 2000000 then g = nil end   -- older than 2 s: not the cause
    if #pending > 20 then table.remove(pending, 1) end
    pending[#pending + 1] = { w = w, t_show = t_show, t_gesture = g }
end

-- Called after every UIManager:_repaint: whatever was shown before it is now drawn
-- and its refresh has been sent.
local function flushPending(ui)
    if #pending == 0 then return end
    local list = pending
    pending = {}
    if not overlay then return end
    local on_stack = {}
    for _, win in ipairs(ui._window_stack) do on_stack[win.widget] = true end
    for _, p in ipairs(list) do
        if on_stack[p.w] then
            local show_us = elapsedUs(p.t_show)
            local line
            if p.t_gesture then
                line = string.format("%s  screen %s  %s  (show %s)", os.date("%H:%M:%S"),
                    widgetName(p.w), fmtMs(elapsedUs(p.t_gesture)), fmtMs(show_us))
            else
                line = string.format("%s  screen %s  %s", os.date("%H:%M:%S"),
                    widgetName(p.w), fmtMs(show_us))
            end
            overlay:addLine(line)
            scheduleFlush()
        end
    end
end

-- Times the first paint of a widget that has just been shown. The instance
-- override removes itself on that first call, so later paints are untouched.
local function trackFirstPaint(w)
    if rawget(w, "_wto_paint") then return end
    local orig = w.paintTo
    if type(orig) ~= "function" then return end
    local own = rawget(w, "paintTo")   -- the widget's own instance field, if any
    w._wto_paint = true
    w.paintTo = function(self, ...)
        self.paintTo = own
        self._wto_paint = nil
        if not recording or suppress > 0 then return orig(self, ...) end
        local t0 = nowT()
        local r = orig(self, ...)
        local ok, err = pcall(recordEvent, "paint", self, elapsedUs(t0))
        if not ok then logger.warn("widget time overlay (paint):", err) end
        return r
    end
end

-- Finds the table (Widget or one of its parents) that really defines "new" and
-- wraps it there, so every widget class goes through it.
local hook_installed = false
local function installNewHook()
    if hook_installed then return end
    local Widget = require("ui/widget/widget")
    local holder = Widget
    while holder and rawget(holder, "new") == nil do
        local mt = getmetatable(holder)
        holder = mt and mt.__index
        if type(holder) ~= "table" then holder = nil end
    end
    if not holder then
        logger.warn("widget time overlay: could not find Widget:new")
        return
    end
    hook_installed = true
    local orig_new = holder.new
    holder.new = function(self, ...)
        if not recording or suppress > 0 then
            return orig_new(self, ...)
        end
        local depth = #frames
        local frame = { child_us = 0 }
        frames[depth + 1] = frame
        local t0 = nowT()
        local ok_new, w = pcall(orig_new, self, ...)
        local total = elapsedUs(t0)
        -- heal the stack also when init threw (frames above this one are leftovers)
        for i = #frames, depth + 1, -1 do frames[i] = nil end
        if not ok_new then error(w, 0) end
        local parent = frames[depth]
        if parent then parent.child_us = parent.child_us + total end
        if type(w) == "table" then
            local ok, err = pcall(record, w, total, frame.child_us, depth)
            if not ok then logger.warn("widget time overlay (record):", err) end
        end
        return w
    end
end

-- ─── the widget ──────────────────────────────────────────────────────────────
-- toast = true: never the top widget, so events keep reaching the screen below.

local Overlay = WidgetContainer:extend{
    name = "widget_time_overlay",
    toast = true,
    skip_topmost = true,   -- see installTopmostHook(): not counted as "topmost visible widget"
}

function Overlay:init()
    self.face = Font:getFace(FACE_NAME, FONT_SIZE)
    self.lines = {}
    self.widgets = {}
    self.offset = 0          -- lines scrolled back from the end (0 = live)
    self.drag = nil
    local saved = G_reader_settings:readSetting(POS_SETTING)
    if type(saved) == "table" and saved.x and saved.y then
        self.pos = { x = saved.x, y = saved.y }
    end
    local probe = TextWidget:new{ text = "Ay", face = self.face }
    self.line_h = probe:getSize().h
    probe:free()
    self.bar_h = self.line_h + PADDING
    self.close_w = self.bar_h * 2          -- touch area of the "×"
    self.clear_widget = TextWidget:new{ text = "clear", face = self.face,
        fgcolor = Blitbuffer.COLOR_BLACK }
    self.clear_w = self.clear_widget:getSize().w + 2 * PADDING   -- touch area of "clear"
    self.close_widget = TextWidget:new{ text = "×", face = self.face,
        fgcolor = Blitbuffer.COLOR_BLACK }
    self:updateDimen()
    self:rebuild()
end

-- Recomputed on every paint so it survives rotation. Uses the saved/moved
-- position when there is one (kept inside the screen), else bottom of the screen.
function Overlay:updateDimen()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local w = sw - 2 * MARGIN
    local h = self.bar_h + self.line_h * N_LINES + 2 * PADDING + 3 * Size.border.thin
    local x, y = MARGIN, MARGIN
    if DEFAULT_AT_BOTTOM then y = sh - h - MARGIN end
    if self.pos then
        x = math.max(0, math.min(self.pos.x, sw - w))
        y = math.max(0, math.min(self.pos.y, sh - h))
    end
    self.dimen = Geom:new{ x = x, y = y, w = w, h = h }
end

function Overlay:maxOffset()
    return math.max(0, #self.lines - N_LINES)
end

function Overlay:clearWidgets()
    for _, w in ipairs(self.widgets) do w:free() end
    self.widgets = {}
end

-- Builds the widgets of the visible window only (never measured).
function Overlay:rebuild()
    self:clearWidgets()
    local last = #self.lines - self.offset
    local first = math.max(1, last - N_LINES + 1)
    local max_w = Screen:getWidth() - 2 * MARGIN - 2 * PADDING
        - 2 * Size.border.thin - SCROLLBAR_W
    quiet(function()
        for i = first, last do
            self.widgets[#self.widgets + 1] = TextWidget:new{
                text = self.lines[i],
                face = self.face,
                max_width = max_w, -- longer lines are truncated
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
        end
    end)
end

-- Adds a line (the view is rebuilt later, by flush()).
function Overlay:addLine(line)
    self.lines[#self.lines + 1] = line
    -- scrolled back: keep looking at the same lines while new ones arrive
    if self.offset > 0 then self.offset = self.offset + 1 end
    if #self.lines > MAX_LINES then table.remove(self.lines, 1) end
    self.offset = math.max(0, math.min(self.offset, self:maxOffset()))
end

function Overlay:clearLines()
    self.lines = {}
    self.offset = 0
    self:rebuild()
    self:refresh()
end

function Overlay:refresh()
    UIManager:setDirty(self, REFRESH_MODE, self.dimen)
end

-- delta > 0 goes toward older lines. lazy = called while the finger is moving: the
-- text is rebuilt at once but the e-ink refresh is sent at most every 150 ms (the
-- last one is sent when the finger is lifted).
function Overlay:scrollBy(delta, lazy)
    local new = math.max(0, math.min(self.offset + delta, self:maxOffset()))
    if new == self.offset then return end
    self.offset = new
    self:rebuild()
    if lazy and self.pan_refresh_t and elapsedUs(self.pan_refresh_t) < 150000 then
        self.pan_dirty = true
    else
        self.pan_refresh_t = nowT()
        self.pan_dirty = nil
        self:refresh()
    end
end

function Overlay:paintTo(bb, x, y)
    self:updateDimen()
    local d = self.dimen
    local bt = Size.border.thin
    bb:paintRect(d.x, d.y, d.w, d.h, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(d.x, d.y, d.w, d.h, bt, Blitbuffer.COLOR_BLACK, 0)

    -- drag bar: three grip lines + separator
    local grip_h = Screen:scaleBySize(10)
    local gy = d.y + bt + math.floor((self.bar_h - grip_h) / 2)
    local gx = math.floor(d.x + d.w / 2 - Screen:scaleBySize(20))
    for i = 0, 2 do
        bb:paintRect(gx, gy + Screen:scaleBySize(4) * i,
            Screen:scaleBySize(40), Screen:scaleBySize(2), Blitbuffer.COLOR_DARK_GRAY)
    end
    bb:paintRect(d.x + bt, d.y + bt + self.bar_h, d.w - 2 * bt, bt, Blitbuffer.COLOR_BLACK)

    -- close button: "×" at the right end of the bar
    -- "clear" at the left end of the bar
    self.clear_widget:paintTo(bb, d.x + bt + PADDING,
        d.y + bt + math.floor((self.bar_h - self.clear_widget:getSize().h) / 2))
    local cs = self.close_widget:getSize()
    self.close_widget:paintTo(bb,
        d.x + d.w - bt - math.floor((self.close_w + cs.w) / 2),
        d.y + bt + math.floor((self.bar_h - cs.h) / 2))

    -- text, bottom-aligned: the newest visible line is always the last one
    local px = d.x + bt + PADDING
    local top = d.y + bt + self.bar_h + bt + PADDING
    local first = N_LINES - #self.widgets
    for i, w in ipairs(self.widgets) do
        w:paintTo(bb, px, top + (first + i - 1) * self.line_h)
    end

    -- scrollbar (only when there is something to scroll)
    local total = #self.lines
    if total > N_LINES then
        local inner_h = self.line_h * N_LINES
        local thumb_h = math.max(Screen:scaleBySize(8), math.floor(inner_h * N_LINES / total))
        local last = total - self.offset
        local ty = math.floor((inner_h - thumb_h) * (last - N_LINES) / (total - N_LINES))
        bb:paintRect(d.x + d.w - bt - SCROLLBAR_W, top + ty, SCROLLBAR_W, thumb_h,
            Blitbuffer.COLOR_DARK_GRAY)
    end
end

-- Plain bounds check (no Geom methods).
function Overlay:contains(pos)
    local d = self.dimen
    return pos and pos.x and pos.y
        and pos.x >= d.x and pos.x < d.x + d.w
        and pos.y >= d.y and pos.y < d.y + d.h
end

-- True when pos is on the drag bar.
function Overlay:inHandle(pos)
    return self:contains(pos)
        and pos.y < self.dimen.y + Size.border.thin + self.bar_h
end

-- True when pos is on the close button (right end of the bar).
function Overlay:inClose(pos)
    return self:inHandle(pos)
        and pos.x >= self.dimen.x + self.dimen.w - Size.border.thin - self.close_w
end

-- True when pos is on "clear" (left end of the bar).
function Overlay:inClear(pos)
    return self:inHandle(pos) and pos.x < self.dimen.x + Size.border.thin + self.clear_w
end

function Overlay:beginDrag(x, y)
    self.drag = {
        start_x = x, start_y = y,
        orig_x = self.dimen.x, orig_y = self.dimen.y,
        dx = 0, dy = 0,
    }
end

-- Applies a displacement to where the drag started; saves and repaints.
function Overlay:finishDrag(dx, dy)
    local drag = self.drag
    self.drag = nil
    if not drag then return end
    if math.abs(dx) < 2 and math.abs(dy) < 2 then return end
    local old = Geom:new{ x = self.dimen.x, y = self.dimen.y, w = self.dimen.w, h = self.dimen.h }
    self.pos = { x = drag.orig_x + dx, y = drag.orig_y + dy }
    self:updateDimen()          -- clamps to the screen
    self.pos = { x = self.dimen.x, y = self.dimen.y }
    G_reader_settings:saveSetting(POS_SETTING, self.pos)
    G_reader_settings:flush()
    -- repaint what is under the old spot, and draw the box in the new one
    UIManager:setDirty("all", REFRESH_MODE, old)
    UIManager:setDirty("all", REFRESH_MODE, self.dimen)
end

local closeSelf     -- defined with the module state below (closes the overlay)
local on_close_cb   -- optional callback set with setOnClose()

-- Displacement of a swipe, from whatever the gesture carries.
local function swipeDelta(ges)
    if ges.relative and ges.relative.x then return ges.relative.x, ges.relative.y end
    local n, dist = ges.direction, ges.distance or 0
    local dx = (n == "east" and dist) or (n == "west" and -dist) or 0
    local dy = (n == "south" and dist) or (n == "north" and -dist) or 0
    return dx, dy
end

-- Returns true only for gestures that belong to the box.
-- Everything else (outside the box, other gestures) is left alone.
function Overlay:onBoxGesture(ges)
    if not ges then return false end
    local kind, pos = ges.ges, ges.pos

    if DEBUG_GESTURES and (self.drag or self:contains(pos)) then
        logger.dbg("widgettimeoverlay gesture:", kind, ges.direction,
            pos and pos.x, pos and pos.y, self.drag and "(dragging)" or "")
    end

    -- a drag in progress owns every pan/hold/swipe, wherever the finger is
    if self.drag and pos then
        local d = self.drag
        if kind == "pan" or kind == "hold_pan" then
            if ges.relative and ges.relative.x then
                d.dx, d.dy = ges.relative.x, ges.relative.y
            else
                d.dx, d.dy = pos.x - d.start_x, pos.y - d.start_y
            end
            return true
        elseif kind == "pan_release" or kind == "hold_release" then
            if kind == "hold_release" or (d.dx == 0 and d.dy == 0) then
                d.dx, d.dy = pos.x - d.start_x, pos.y - d.start_y
            end
            self:finishDrag(d.dx, d.dy)
            return true
        elseif kind == "swipe" then
            local dx, dy = d.dx, d.dy
            if dx == 0 and dy == 0 then dx, dy = swipeDelta(ges) end
            self:finishDrag(dx, dy)
            return true
        end
    end

    if not pos then return false end

    -- start a drag from the bar (pan, swipe or hold)
    if kind == "pan" then
        local sx = pos.x - ((ges.relative and ges.relative.x) or 0)
        local sy = pos.y - ((ges.relative and ges.relative.y) or 0)
        if self:inHandle({ x = sx, y = sy }) then
            self:beginDrag(sx, sy)
            self.drag.dx = pos.x - sx
            self.drag.dy = pos.y - sy
            return true
        end
    elseif kind == "hold" and self:inHandle(pos) then
        self:beginDrag(pos.x, pos.y)
        return true
    elseif kind == "swipe" and self:inHandle(pos) then
        self:beginDrag(pos.x, pos.y)
        local dx, dy = swipeDelta(ges)
        self:finishDrag(dx, dy)
        return true
    end

    -- scroll by dragging in the text: the lines follow the finger
    if kind == "pan" then
        local sx = pos.x - ((ges.relative and ges.relative.x) or 0)
        local sy = pos.y - ((ges.relative and ges.relative.y) or 0)
        if self.pan_lines or (self:contains({ x = sx, y = sy }) and not self:inHandle({ x = sx, y = sy })) then
            local rel = (ges.relative and ges.relative.y) or (pos.y - sy)
            local target = math.floor(rel / self.line_h)   -- finger down = older lines
            self.pan_lines = self.pan_lines or 0
            if target ~= self.pan_lines then
                local step = target - self.pan_lines
                self.pan_lines = target
                self:scrollBy(step, true)
            end
            self.panned_t = nowT()
            return true
        end
    elseif kind == "pan_release" and self.pan_lines then
        self.pan_lines = nil
        self.panned_t = nowT()
        if self.pan_dirty then
            self.pan_dirty = nil
            self.pan_refresh_t = nowT()
            self:refresh()
        end
        return true
    end

    if not self:contains(pos) then return false end

    if kind == "tap" then
        if self:inClose(pos) then
            closeSelf()
            return true
        end
        if self:inClear(pos) then
            self:clearLines()
        end
        return true     -- a tap in the text does nothing (it used to clear the list)
    elseif kind == "swipe" then
        -- a pan has just scrolled: the swipe that may follow it is not a second scroll
        if self.panned_t and elapsedUs(self.panned_t) < 600000 then
            self.panned_t = nil
            return true
        end
        local dir = ges.direction
        if dir == "north" or dir == "south" then
            local n = math.max(1, math.min(N_LINES - 1, math.floor((ges.distance or 0) / self.line_h)))
            self:scrollBy(dir == "south" and n or -n)
        elseif dir == "west" then
            self:scrollBy(-self.offset)       -- back to live
        elseif dir == "east" then
            self:scrollBy(self:maxOffset())   -- oldest
        else
            return false
        end
        return true
    end
    return false
end

function Overlay:free()
    self:clearWidgets()
    if self.close_widget then self.close_widget:free() end
    if self.clear_widget then self.clear_widget:free() end
end

-- Throttled redraw: lines are added as widgets are created, the box is rebuilt
-- and repainted at most every REFRESH_SECS (never inside a widget's init).
flush = function()
    flush_scheduled = false
    if not overlay then return end
    local ok, err = pcall(function()
        overlay:rebuild()
        overlay:refresh()
    end)
    if not ok then logger.warn("widget time overlay (flush):", err) end
end

-- ─── module state ────────────────────────────────────────────────────────────

-- Core code (e.g. ReaderRolling's background re-render / reload automation, the
-- footer and header repaint checks) only acts when getTopmostVisibleWidget() is
-- the ReaderUI. A toast overlay on top of the stack hides it, so a typographic
-- change would never be reloaded. Make UIManager skip widgets flagged with
-- `skip_topmost`. Shared marker: install once, whichever overlay loads first.
local function installTopmostHook()
    if UIManager._pti_topmost_hooked then return end
    UIManager._pti_topmost_hooked = true
    local orig = UIManager.getTopmostVisibleWidget
    UIManager.getTopmostVisibleWidget = function(self, ...)
        for i = #self._window_stack, 1, -1 do
            local w = self._window_stack[i].widget
            if not w.invisible and not w.skip_topmost then
                return w
            end
        end
        return orig(self, ...)
    end
end
installTopmostHook()

-- Code that moves windows around by hand (e.g. Bookshelf "park" re-orders
-- UIManager._window_stack without going through UIManager:show) bypasses the show
-- hook below and can leave a non-toast widget above the overlays. Before every
-- repaint, put any registered overlay back above all non-toast windows (a plain
-- table move, no close/show) and mark it dirty. Shared registry: whichever overlay
-- loads first installs the hook, all of them register their widget in it.
local function keepOverlaysOnTop(ui)
    local stack = ui._window_stack
    for ov in pairs(ui._pti_overlays) do
        local idx, blocked
        for i = #stack, 1, -1 do
            local w = stack[i].widget
            if w == ov then
                idx = i
                break
            elseif not w.toast then
                blocked = true
            end
        end
        if idx and blocked then
            local win = table.remove(stack, idx)
            table.insert(stack, win)
            ui:setDirty(ov, REFRESH_MODE, ov.dimen)
        end
    end
end

local function installRepaintHook()
    UIManager._pti_overlays = UIManager._pti_overlays or {}
    if UIManager._pti_repaint_hooked then return end
    UIManager._pti_repaint_hooked = true
    local orig_repaint = UIManager._repaint
    UIManager._repaint = function(self, ...)
        local ok, err = pcall(keepOverlaysOnTop, self)
        if not ok then logger.warn("overlay (keep on top):", err) end
        return orig_repaint(self, ...)
    end
end

-- Own wrapper (separate from the shared "keep on top" one): runs after the repaint.
local screen_hooked = false
local function installScreenHook()
    if screen_hooked or not TRACK_SHOW_PAINT then return end
    screen_hooked = true
    local orig_repaint = UIManager._repaint
    UIManager._repaint = function(self, ...)
        local a, b, c = orig_repaint(self, ...)
        if recording and #pending > 0 then
            local ok, err = pcall(flushPending, self)
            if not ok then logger.warn("widget time overlay (screen):", err) end
        end
        return a, b, c
    end
end

local show_hooked = false
local send_hooked = false
local desired = false

-- Every time another widget is shown (open a book, back to the FM, menus,
-- dialogs...) the overlay goes back on top of the stack.
local function installShowHook()
    if show_hooked then return end
    show_hooked = true
    local orig_show = UIManager.show
    UIManager.show = function(self, widget, ...)
        local track = TRACK_SHOW_PAINT and recording and suppress == 0
            and widget and widget ~= overlay and not widget.toast
        local t0 = track and nowT() or nil
        local ret = orig_show(self, widget, ...)
        if track then
            local ok, err = pcall(function()
                recordEvent("show", widget, elapsedUs(t0))
                trackFirstPaint(widget)
                addPending(widget, t0)
            end)
            if not ok then logger.warn("widget time overlay (show):", err) end
        end
        if overlay and widget ~= overlay and widget and not widget.toast then
            local ok, err = pcall(function()
                UIManager:close(overlay)
                UIManager:show(overlay)
            end)
            if not ok then logger.warn("widget time overlay (raise):", err) end
        end
        return ret
    end
end

-- Gestures that belong to the box are ours; everything else goes on untouched.
-- Only installed once the overlay is on screen.
local function installSendHook()
    if send_hooked or not SCROLL_ENABLED then return end
    send_hooked = true
    local orig_send = UIManager.sendEvent
    UIManager.sendEvent = function(self, event, ...)
        if overlay and event and event.handler == "onGesture" then
            local ok, handled = pcall(overlay.onBoxGesture, overlay,
                event.args and event.args[1])
            if not ok then logger.warn("widget time overlay (gesture):", handled) end
            if ok and handled == true then return end
            markGesture()
        end
        return orig_send(self, event, ...)
    end
end

local function apply()
    if desired then
        if overlay then return end
        installShowHook()
        installNewHook()
        overlay = quiet(function() return Overlay:new{} end)
        installRepaintHook()
        installScreenHook()
        UIManager._pti_overlays[overlay] = true
        UIManager:show(overlay)
        installSendHook()
        frames = {}
        recording = true
    elseif overlay then
        recording = false
        frames = {}
        pending = {}
        last_gesture_t = nil
        UIManager:unschedule(flush)
        flush_scheduled = false
        local o = overlay
        overlay = nil
        UIManager._pti_overlays[o] = nil
        -- explicit refresh of the area the box covered: a plain close() queues
        -- no refresh, so the box would stay on screen until the next repaint
        local d = o.dimen
        local region = d and Geom:new{ x = d.x, y = d.y, w = d.w, h = d.h } or nil
        UIManager:close(o, region and REFRESH_MODE or nil, region)
        o:free()
    end
end

-- Close button: same as setEnabled(false), at once, and the saved flag goes off too
closeSelf = function()
    desired = false
    G_reader_settings:saveSetting(ENABLED_SETTING, false)
    G_reader_settings:flush()
    UIManager:nextTick(function()
        local ok, err = pcall(apply)
        if not ok then
            logger.warn("widget time overlay (close):", err)
            overlay = nil
            recording = false
        end
        if on_close_cb then
            local ok2, err2 = pcall(on_close_cb)
            if not ok2 then logger.warn("widget time overlay (on close):", err2) end
        end
    end)
end

local function setEnabled(enable)
    desired = enable and true or false
    -- deferred: never touch the UI while the plugin is still initialising
    UIManager:scheduleIn(START_DELAY, function()
        local ok, err = pcall(apply)
        if not ok then
            logger.warn("widget time overlay:", err)
            overlay = nil   -- leave a clean state; KOReader keeps running
            recording = false
        end
    end)
end

return {
    setEnabled = setEnabled,
    setOnClose = function(fn) on_close_cb = fn end,
}
