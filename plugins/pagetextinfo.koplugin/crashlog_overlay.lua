-- Crash log overlay: crash.log, live, scrollable and movable, on every screen
-- (File Manager, bookshelf, reader), toggled with a setting.
--
--   local CrashLog = require("crashlog_overlay")
--   CrashLog.setEnabled(true / false)   -- idempotent, deferred, never throws
--
-- Gestures inside the box:
--   drag the top bar   move the box (applied on release, position is saved)
--   tap                reload the file and redraw now
--   swipe up/down      scroll toward newer / older lines (by swipe length)
--   swipe left         back to the live end (newest line)
--   swipe right        jump to the oldest line kept
-- Anything outside the box goes to the screen below as usual.

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Screen = Device.screen

-- ─── settings ────────────────────────────────────────────────────────────────

local FACE_NAME = "infont"
local FONT_SIZE = 9
local N_LINES = 8            -- visible text lines (fixed height)
local MAX_LINES = 500        -- lines kept in memory (how far back you can scroll)
local POLL_SECS = 2
local TAIL_BYTES = 65536     -- how much of the end of the file is read
local START_DELAY = 1        -- seconds to wait before touching the UI
local MARGIN = Screen:scaleBySize(6)
local PADDING = Size.padding.small
local SCROLLBAR_W = Screen:scaleBySize(3)
local POS_SETTING = "crashlog_pos"   -- saved position {x=, y=}

local SCROLL_ENABLED = true   -- false = no gesture hook at all (no scroll/tap/move)
local DEBUG_GESTURES = true   -- log every gesture that lands in the box
-- "partial": clean text, little ghosting. "flashui": full flash, cleanest.
-- "ui": fastest, leaves ghosting.
local REFRESH_MODE = "partial"

-- ─── the file ────────────────────────────────────────────────────────────────

local function findLogPath()
    local candidates = {
        DataStorage:getDataDir() .. "/crash.log",
        (lfs.currentdir() or ".") .. "/crash.log",
        "crash.log",
    }
    for _, p in ipairs(candidates) do
        if lfs.attributes(p, "mode") == "file" then return p end
    end
    return candidates[1]
end

-- Last n lines of the file, or nil when it cannot be read.
local function readTail(path, n)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    local start = math.max(0, size - TAIL_BYTES)
    f:seek("set", start)
    local data = f:read("*a") or ""
    f:close()
    local lines = {}
    for line in (data .. "\n"):gmatch("(.-)\r?\n") do
        lines[#lines + 1] = (line:gsub("\t", "    "):gsub("[%c]", ""))
    end
    if start > 0 then table.remove(lines, 1) end -- first line is probably cut
    while #lines > 0 and lines[#lines] == "" do lines[#lines] = nil end
    local out = {}
    for i = math.max(1, #lines - n + 1), #lines do out[#out + 1] = lines[i] end
    return out
end

-- Displacement of a swipe, from whatever the gesture carries.
local function swipeDelta(ges)
    if ges.relative and ges.relative.x then return ges.relative.x, ges.relative.y end
    local n, dist = ges.direction, ges.distance or 0
    local dx = (n == "east" and dist) or (n == "west" and -dist) or 0
    local dy = (n == "south" and dist) or (n == "north" and -dist) or 0
    return dx, dy
end

-- ─── the widget ──────────────────────────────────────────────────────────────
-- toast = true: never the top widget, so events keep reaching the screen below.

local Overlay = WidgetContainer:extend{
    name = "crashlog_overlay",
    toast = true,
}

function Overlay:init()
    self.face = Font:getFace(FACE_NAME, FONT_SIZE)
    self.path = findLogPath()
    self.lines = {}
    self.widgets = {}
    self.offset = 0          -- lines scrolled back from the end (0 = live)
    self.last_sig = nil
    self.drag = nil
    local saved = G_reader_settings:readSetting(POS_SETTING)
    if type(saved) == "table" and saved.x and saved.y then
        self.pos = { x = saved.x, y = saved.y }
    end
    local probe = TextWidget:new{ text = "Ay", face = self.face }
    self.line_h = probe:getSize().h
    probe:free()
    self.bar_h = self.line_h + PADDING
    self:updateDimen()
    self:reload(true)
end

-- Recomputed on every paint so it survives rotation. Uses the saved/moved
-- position when there is one (kept inside the screen), else bottom-left.
function Overlay:updateDimen()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local w = sw - 2 * MARGIN
    local h = self.bar_h + self.line_h * N_LINES + 2 * PADDING + 3 * Size.border.thin
    local x, y = MARGIN, sh - h - MARGIN
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

-- Builds the widgets of the visible window only.
function Overlay:rebuild()
    self:clearWidgets()
    local last = #self.lines - self.offset
    local first = math.max(1, last - N_LINES + 1)
    local max_w = Screen:getWidth() - 2 * MARGIN - 2 * PADDING
        - 2 * Size.border.thin - SCROLLBAR_W
    for i = first, last do
        self.widgets[#self.widgets + 1] = TextWidget:new{
            text = self.lines[i],
            face = self.face,
            max_width = max_w, -- longer lines are truncated
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
    end
end

-- Re-reads the file when it changed (or always with force).
-- Returns true if the view changed.
function Overlay:reload(force)
    local attr = lfs.attributes(self.path)
    local sig = attr and (attr.modification .. ":" .. attr.size) or "missing"
    if not force and sig == self.last_sig then return false end
    self.last_sig = sig

    local lines = attr and readTail(self.path, MAX_LINES)
    if not lines then lines = { "crash.log: " .. (attr and "unreadable" or "not found") } end
    if #lines == 0 then lines = { "crash.log: empty" } end

    -- scrolled back: keep looking at the same lines while new ones arrive
    if self.offset > 0 then
        self.offset = self.offset + (#lines - #self.lines)
    end
    self.lines = lines
    self.offset = math.max(0, math.min(self.offset, self:maxOffset()))
    self:rebuild()
    return true
end

function Overlay:refresh()
    UIManager:setDirty(self, REFRESH_MODE, self.dimen)
end

-- delta > 0 goes toward older lines.
function Overlay:scrollBy(delta)
    local new = math.max(0, math.min(self.offset + delta, self:maxOffset()))
    if new == self.offset then return end
    self.offset = new
    self:rebuild()
    self:refresh()
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
    -- repaint what is under the old spot, and draw the box in the new one
    UIManager:setDirty("all", REFRESH_MODE, old)
    UIManager:setDirty("all", REFRESH_MODE, self.dimen)
end

-- Returns true only for gestures that belong to the box.
-- Everything else (outside the box, other gestures) is left alone.
function Overlay:onBoxGesture(ges)
    if not ges then return false end
    local kind, pos = ges.ges, ges.pos

    if DEBUG_GESTURES and (self.drag or self:contains(pos)) then
        logger.dbg("crashlog gesture:", kind, ges.direction,
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

    if not self:contains(pos) then return false end

    if kind == "tap" then
        self:reload(true)
        self:refresh()
        return true
    elseif kind == "swipe" then
        local dir = ges.direction
        if dir == "north" or dir == "south" then
            local n = math.max(1, math.floor((ges.distance or 0) / self.line_h))
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
end

-- ─── module state (singleton, shared by FM and reader) ──────────────────────

local overlay
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
        local ret = orig_show(self, widget, ...)
        if overlay and widget ~= overlay and widget and not widget.toast then
            local ok, err = pcall(function()
                UIManager:close(overlay)
                UIManager:show(overlay)
            end)
            if not ok then logger.warn("crashlog overlay (raise):", err) end
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
            if not ok then logger.warn("crashlog overlay (gesture):", handled) end
            if ok and handled == true then return end
        end
        return orig_send(self, event, ...)
    end
end

-- Poll loop: only asks for a screen refresh when the file changed.
local function poll()
    if not overlay then return end
    local ok, err = pcall(function()
        if overlay:reload(false) then overlay:refresh() end
    end)
    if not ok then logger.warn("crashlog overlay (poll):", err) end
    UIManager:scheduleIn(POLL_SECS, poll)
end

local function apply()
    if desired then
        if overlay then return end
        installShowHook()
        overlay = Overlay:new{}
        UIManager:show(overlay)
        installSendHook()
        UIManager:scheduleIn(POLL_SECS, poll)
    elseif overlay then
        UIManager:unschedule(poll)
        local o = overlay
        overlay = nil
        UIManager:close(o)
        o:free()
    end
end

local function setEnabled(enable)
    desired = enable and true or false
    -- deferred: never touch the UI while the plugin is still initialising
    UIManager:scheduleIn(START_DELAY, function()
        local ok, err = pcall(apply)
        if not ok then
            logger.warn("crashlog overlay:", err)
            overlay = nil   -- leave a clean state; KOReader keeps running
        end
    end)
end

return {
    setEnabled = setEnabled,
}
