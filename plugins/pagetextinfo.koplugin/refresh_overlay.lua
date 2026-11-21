-- Refresh overlay: what UIManager does with the screen refreshes, live, scrollable and
-- movable, on every screen (File Manager, bookshelf, reader), toggled with a setting.
-- Same box and gestures as memory_overlay / crashlog_overlay. It shows what the
-- `debug_refresh` flag of uimanager.lua prints to the console, without the traceback.
--
--   local RefreshOverlay = require("refresh_overlay")
--   RefreshOverlay.setEnabled(true / false)   -- idempotent, deferred, never throws
--
-- REQUIRES the small patch in uimanager.lua (refresh_logger hook, see uimanager.patch):
-- without it the box opens but nothing arrives, and it says so in its first line.
-- While the overlay is off the hook is not installed: zero cost.
--
-- One line per event, newest at the bottom:
--
--   14:10:42 SET ui    ReaderUI 10,20 100x50 @readerview.lua:312
--   14:10:42 REF ui    0,0 1272x1696 dither c=3/6
--
--   SET  UIManager:setDirty(widget, mode, region) was called
--          mode      the refresh type asked for ("fn" when it is a function, resolved later)
--          widget    "all", the window-level widget, or "-" when nil
--          region    only when one was given (otherwise the whole screen)
--          @file:line  who called setDirty
--   REF  a refresh that UIManager really sends to the screen (after merging the queue)
--          mode      the final mode, after merging, downgrades and the partial -> full promotion
--          c=n/N     refresh_count / FULL_REFRESH_COUNT (the flash promotion counter)
--   Identical consecutive lines are folded into one with " xN".
--   Events caused by the overlays themselves (this one and the memory one) are not shown.
--
-- Gestures inside the box:
--   drag the top bar   move the box (applied on release, position is saved)
--   tap                redraw now
--   tap on the left end of the top bar ("LIVE"/"PAUSED")   pause / resume the capture
--   swipe up/down      scroll toward newer / older lines (by swipe length)
--   swipe left         back to the live end (newest line)
--   swipe right        jump to the oldest line kept
--   tap on the "×" (right end of the top bar)   close the overlay
-- Anything outside the box goes to the screen below as usual.
--
--   RefreshOverlay.setOnClose(function() ... end)
--       optional, called after the "×" closed the overlay (the flag
--       "refreshoverlay_enabled" is already switched off by the "×" itself)

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
local STACK_FRAMES = 3           -- callers shown under each SET (0 = only the first)
local N_LINES = 12               -- visible text lines (fixed height)
local MAX_LINES = 500            -- events kept in memory (how far back you can scroll)
local REDRAW_SECS = 1            -- the box is redrawn at most once per this many seconds
local START_DELAY = 1            -- seconds to wait before touching the UI
local MARGIN = Screen:scaleBySize(6)
local PADDING = Size.padding.small
local SCROLLBAR_W = Screen:scaleBySize(3)
local POS_SETTING = "refreshoverlay_pos"   -- saved position {x=, y=}
local ENABLED_SETTING = "refreshoverlay_enabled"   -- flag the "×" switches off

local SCROLL_ENABLED = true   -- false = no gesture hook at all (no scroll/tap/move)
local DEBUG_GESTURES = false  -- log every gesture that lands in the box
-- The box is redrawn about once a second while events arrive: "ui" is the fastest.
local REFRESH_MODE = "ui"

-- ─── the events ──────────────────────────────────────────────────────────────

local function widgetName(w)
    if w == nil then return "-" end
    if w == "all" then return "all" end
    if type(w) ~= "table" then return tostring(w) end
    return tostring(w.name or w.id or w)
end

local function regionText(r)
    if not r then return "full" end
    return string.format("%d,%d %dx%d", r.x or 0, r.y or 0, r.w or 0, r.h or 0)
end

local function frameText(fi)
    return (fi.short_src:match("[^/]+$") or fi.short_src) .. ":" .. tostring(fi.currentline or "?")
end

-- info is the call stack (array of getinfo tables, caller first). C frames carry no
-- information ("[C]:-1"), so they are skipped everywhere.
local function luaFrames(info)
    local out = {}
    if not info then return out end
    if info.short_src then info = { info } end   -- a single frame
    for _, fi in ipairs(info) do
        if fi.short_src and fi.short_src ~= "[C]" then out[#out + 1] = fi end
    end
    return out
end

local function srcText(info)
    local fr = luaFrames(info)
    return fr[1] and (" @" .. frameText(fr[1])) or ""
end

-- Extra lines with the next callers after the first Lua frame
local function stackLines(info)
    local out, fr = {}, luaFrames(info)
    for i = 2, math.min(#fr, 1 + STACK_FRAMES) do
        out[#out + 1] = "      < " .. frameText(fr[i])
    end
    return out
end

local function eventText(kind, mode, widget, region, info, dither, count, total)
    local m = type(mode) == "function" and "fn" or tostring(mode)
    if kind == "set" then
        local head = string.format("SET %-5s %s%s%s", m, widgetName(widget),
            region and (" " .. regionText(region)) or "", srcText(info))
        local extra = stackLines(info)
        if #extra > 0 then head = head .. "\n" .. table.concat(extra, "\n") end
        return head
    end
    return string.format("REF %-5s %s%s%s", m, regionText(region),
        dither and " dither" or "",
        (count and total and total > 0) and string.format(" c=%d/%d", count, total) or "")
end

-- Plain bounds check: is the rectangle r completely inside d?
local function rectInside(r, d)
    return r and d and r.x and r.y and r.w and r.h and d.x and d.y and d.w and d.h
        and r.x >= d.x and r.y >= d.y
        and r.x + r.w <= d.x + d.w and r.y + r.h <= d.y + d.h
end

-- Displacement of a swipe, from whatever the gesture carries.
local function swipeDelta(ges)
    if ges.relative and ges.relative.x then return ges.relative.x, ges.relative.y end
    local n, dist = ges.direction, ges.distance or 0
    local dx = (n == "east" and dist) or (n == "west" and -dist) or 0
    local dy = (n == "south" and dist) or (n == "north" and -dist) or 0
    return dx, dy
end

local closeSelf     -- defined with the module state below (closes the overlay)
local on_close_cb   -- optional callback set with setOnClose()
local in_own = false   -- true while the overlay asks for ITS OWN refresh (not logged)

-- ─── the widget ──────────────────────────────────────────────────────────────
-- toast = true: never the top widget, so events keep reaching the screen below.

local Overlay = WidgetContainer:extend{
    name = "refresh_overlay",
    toast = true,
    skip_topmost = true,   -- see installTopmostHook(): not counted as "topmost visible widget"
}

function Overlay:init()
    self.face = Font:getFace(FACE_NAME, FONT_SIZE)
    self.lines = {}
    self.widgets = {}
    self.offset = 0          -- lines scrolled back from the end (0 = live)
    self.paused = false
    self.last_text, self.last_n, self.last_ts = nil, 0, nil
    self.drag = nil
    local saved = G_reader_settings:readSetting(POS_SETTING)
    if type(saved) == "table" and saved.x and saved.y then
        self.pos = { x = saved.x, y = saved.y }
    end
    local probe = TextWidget:new{ text = "Ay", face = self.face }
    self.line_h = probe:getSize().h
    probe:free()
    self.bar_h = self.line_h + PADDING
    self.close_w = self.bar_h * 2          -- touch area of the "×" (and of the pause label)
    self.close_widget = TextWidget:new{ text = "×", face = self.face,
        fgcolor = Blitbuffer.COLOR_BLACK }
    self.live_widget = TextWidget:new{ text = "LIVE", face = self.face,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY }
    self.paused_widget = TextWidget:new{ text = "PAUSED", face = self.face,
        fgcolor = Blitbuffer.COLOR_BLACK }
    self:updateDimen()
end

-- Recomputed on every paint so it survives rotation. Uses the saved/moved
-- position when there is one (kept inside the screen), else the BOTTOM of the
-- screen (the memory overlay lives at the top).
function Overlay:updateDimen()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local w = sw - 2 * MARGIN
    local h = self.bar_h + self.line_h * N_LINES + 2 * PADDING + 3 * Size.border.thin
    local x, y = MARGIN, sh - h - MARGIN
    if self.pos then
        x, y = self.pos.x, self.pos.y
    end
    x = math.max(0, math.min(x, sw - w))
    y = math.max(0, math.min(y, sh - h))
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

-- Adds an event (consecutive identical ones are folded into one line with " xN").
-- Does NOT redraw. Returns true if the lines changed.
function Overlay:addEvent(text)
    if self.paused then return false end
    -- an event may have several lines (first one + callers); only the first is timestamped
    local parts = {}
    for l in (text .. "\n"):gmatch("(.-)\n") do parts[#parts + 1] = l end
    if text == self.last_text and #self.lines >= (self.last_len or 1) then
        self.last_n = self.last_n + 1
        self.lines[#self.lines - (self.last_len or 1) + 1] =
            string.format("%s %s x%d", self.last_ts, parts[1], self.last_n)
        return true
    end
    self.last_text, self.last_n, self.last_ts = text, 1, os.date("%H:%M:%S")
    self.last_len = #parts
    self.lines[#self.lines + 1] = self.last_ts .. " " .. parts[1]
    for i = 2, #parts do self.lines[#self.lines + 1] = parts[i] end
    -- (the scroll offset below grows by one; for extra lines it is adjusted here)
    if self.offset > 0 then self.offset = self.offset + (#parts - 1) end
    -- scrolled back: keep looking at the same lines while new ones arrive
    if self.offset > 0 then self.offset = self.offset + 1 end
    if #self.lines > MAX_LINES then table.remove(self.lines, 1) end
    self.offset = math.max(0, math.min(self.offset, self:maxOffset()))
    return true
end

-- Asks for a refresh of the box. It is flagged as "own" so that the SET it causes
-- is not logged (otherwise every redraw would produce the event that causes the
-- next redraw).
function Overlay:refresh()
    in_own = true
    local ok, err = pcall(UIManager.setDirty, UIManager, self, REFRESH_MODE, self.dimen)
    in_own = false
    if not ok then error(err, 0) end
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

    -- live / paused label: left end of the bar
    local sw = self.paused and self.paused_widget or self.live_widget
    local ss = sw:getSize()
    sw:paintTo(bb, d.x + bt + PADDING,
        d.y + bt + math.floor((self.bar_h - ss.h) / 2))

    -- close button: "×" at the right end of the bar
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

-- True when pos is on the pause label (left end of the bar).
function Overlay:inPause(pos)
    return self:inHandle(pos)
        and pos.x < self.dimen.x + Size.border.thin + self.close_w * 2
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
    in_own = true
    local ok, err = pcall(function()
        UIManager:setDirty("all", REFRESH_MODE, old)
        UIManager:setDirty("all", REFRESH_MODE, self.dimen)
    end)
    in_own = false
    if not ok then error(err, 0) end
end

-- Returns true only for gestures that belong to the box.
-- Everything else (outside the box, other gestures) is left alone.
function Overlay:onBoxGesture(ges)
    if not ges then return false end
    local kind, pos = ges.ges, ges.pos

    if DEBUG_GESTURES and (self.drag or self:contains(pos)) then
        logger.dbg("refreshoverlay gesture:", kind, ges.direction,
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
        if self:inClose(pos) then
            closeSelf()
            return true
        end
        if self:inPause(pos) then
            self.paused = not self.paused
        end
        self:rebuild()
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
    if self.close_widget then self.close_widget:free() end
    if self.live_widget then self.live_widget:free() end
    if self.paused_widget then self.paused_widget:free() end
end

-- ─── module state (singleton, shared by FM and reader) ──────────────────────

local overlay
-- Core code (e.g. ReaderRolling's background re-render / reload automation, the
-- footer and header repaint checks) only acts when getTopmostVisibleWidget() is
-- the ReaderUI. A toast overlay on top of the stack hides it, so a typographic
-- change would never be reloaded. Make UIManager skip widgets flagged with
-- `skip_topmost`. Shared marker: install once, whichever overlay loads first.
local function installTopmostHook()
    if UIManager._pti_topmost_hooked then return end
    UIManager._pti_topmost_hooked = true
    local orig = UIManager.getTopmostVisibleWidget
    local raw = rawget(UIManager, "getTopmostVisibleWidget")
    local wrapper = function(self, ...)
        for i = #self._window_stack, 1, -1 do
            local w = self._window_stack[i].widget
            if not w.invisible and not w.skip_topmost then
                return w
            end
        end
        return orig(self, ...)
    end
    UIManager.getTopmostVisibleWidget = wrapper
    -- removed again when the last overlay stops (see apply)
    UIManager._pti_unhook_topmost = function()
        if UIManager.getTopmostVisibleWidget == wrapper then
            UIManager.getTopmostVisibleWidget = raw
            UIManager._pti_topmost_hooked = nil
            UIManager._pti_unhook_topmost = nil
        end
    end
end

-- Code that moves windows around by hand (e.g. Bookshelf "park" re-orders
-- UIManager._window_stack without going through UIManager:show) bypasses the show
-- hook below and can leave a non-toast widget above the overlays. Before every
-- repaint, put any registered overlay back above all non-toast windows (a plain
-- table move, no close/show) and mark it dirty. Shared registry: whichever overlay
-- loads first installs the hook, both register their widget in it.
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
    local wrapper = function(self, ...)
        local ok, err = pcall(keepOverlaysOnTop, self)
        if not ok then logger.warn("overlay (keep on top):", err) end
        return orig_repaint(self, ...)
    end
    UIManager._repaint = wrapper
    UIManager._pti_unhook_repaint = function()
        if UIManager._repaint == wrapper then
            UIManager._repaint = orig_repaint
            UIManager._pti_repaint_hooked = nil
            UIManager._pti_unhook_repaint = nil
        end
    end
end

local show_hooked = false
local send_hooked = false
local unhook_show, unhook_send   -- restore the originals (set when the hooks are installed)
local desired = false

-- Every time another widget is shown (open a book, back to the FM, menus,
-- dialogs...) the overlay goes back on top of the stack.
local function installShowHook()
    if show_hooked then return end
    show_hooked = true
    local orig_show = UIManager.show
    local raw_show = rawget(UIManager, "show")
    local wrapper = function(self, widget, ...)
        local ret = orig_show(self, widget, ...)
        if overlay and widget ~= overlay and widget and not widget.toast then
            local ok, err = pcall(function()
                UIManager:close(overlay)
                UIManager:show(overlay)
            end)
            if not ok then logger.warn("refresh overlay (raise):", err) end
        end
        return ret
    end
    UIManager.show = wrapper
    -- put the original back when the overlay stops (only if nobody wrapped it after us;
    -- then it just stays as a pass-through)
    unhook_show = function()
        if UIManager.show == wrapper then
            UIManager.show = raw_show
            show_hooked = false
        end
    end
end

-- Gestures that belong to the box are ours; everything else goes on untouched.
-- Only installed once the overlay is on screen.
local function installSendHook()
    if send_hooked or not SCROLL_ENABLED then return end
    send_hooked = true
    local orig_send = UIManager.sendEvent
    local raw_send = rawget(UIManager, "sendEvent")
    local wrapper = function(self, event, ...)
        if overlay and event and event.handler == "onGesture" then
            local ok, handled = pcall(overlay.onBoxGesture, overlay,
                event.args and event.args[1])
            if not ok then logger.warn("refresh overlay (gesture):", handled) end
            if ok and handled == true then return end
        end
        return orig_send(self, event, ...)
    end
    UIManager.sendEvent = wrapper
    unhook_send = function()
        if UIManager.sendEvent == wrapper then
            UIManager.sendEvent = raw_send
            send_hooked = false
        end
    end
end

-- ─── the feed ────────────────────────────────────────────────────────────────

-- The box is redrawn at most once per REDRAW_SECS, however many events arrive.
local redraw_pending = false
local function flush()
    redraw_pending = false
    if not overlay then return end
    local ok, err = pcall(function()
        overlay:rebuild()
        overlay:refresh()
    end)
    if not ok then logger.warn("refresh overlay (redraw):", err) end
end

local function scheduleRedraw()
    if redraw_pending then return end
    redraw_pending = true
    UIManager:scheduleIn(REDRAW_SECS, flush)
end

-- True when the rectangle is completely inside the box of any overlay (this one or
-- the memory one, they register in UIManager._pti_overlays): their own refreshes.
local function insideAnOverlay(region)
    for ov in pairs(UIManager._pti_overlays or {}) do
        if rectInside(region, ov.dimen) then return true end
    end
    return false
end

-- Called by UIManager (see uimanager.patch):
--   kind "set": from setDirty;   kind "ref": from _repaint, once per refresh really sent
-- It runs inside setDirty / _repaint, so it must be fast and must never touch the
-- screen: it only stores the text and asks for a deferred redraw.
-- UIManager merges the pending requests of a repaint: the strongest mode wins
local MODE_RANK = { a2 = 1, fast = 2, ui = 3, partial = 4, flashui = 5, flashpartial = 6, full = 7 }
local function modeName(m) return type(m) == "function" and "fn" or tostring(m) end

local function rectsTouch(a, b)
    if not a or not b or not a.x or not b.x then return true end   -- nil region = whole screen
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local pending = {}   -- SETs seen since they were last merged into a REF: { mode, x, y, w, h }

-- Text added to a REF: which SETs (in arrival order) were merged into it and who won.
-- Takes those SETs out of the pending list.
local function mergedText(ref_mode, region)
    local used, keep = {}, {}
    for _, p in ipairs(pending) do
        if rectsTouch(p.region, region) then used[#used + 1] = p else keep[#keep + 1] = p end
    end
    pending = keep
    if #used == 0 then return "" end
    local names, best, best_rank = {}, nil, -1
    for _, p in ipairs(used) do
        names[#names + 1] = p.mode
        local r = MODE_RANK[p.mode] or 0
        if r > best_rank then best, best_rank = p.mode, r end
    end
    local out = " <= " .. table.concat(names, "+")
    if #used > 1 and best then out = out .. " (wins " .. best .. ")" end
    local final = modeName(ref_mode)
    if best and final ~= best then out = out .. " [" .. best .. ">" .. final .. "]" end
    return out
end

local function onRefreshEvent(kind, mode, widget, region, info, dither, count, total)
    if not overlay or in_own then return end
    -- events of the overlays themselves
    if type(widget) == "table" and widget.skip_topmost then return end
    if region and insideAnOverlay(region) then return end
    local text = eventText(kind, mode, widget, region, info, dither, count, total)
    if kind == "set" then
        pending[#pending + 1] = { mode = modeName(mode), region = region }
        if #pending > 60 then table.remove(pending, 1) end
    elseif kind == "ref" then
        text = text .. mergedText(mode, region)
    end
    if overlay:addEvent(text) then
        scheduleRedraw()
    end
end

local function apply()
    if desired then
        if overlay then return end
        installShowHook()
        overlay = Overlay:new{}
        installTopmostHook()
        installRepaintHook()
        UIManager._pti_overlays[overlay] = true
        UIManager:show(overlay)
        installSendHook()
        UIManager.refresh_logger = onRefreshEvent
        if not UIManager._has_refresh_logger then
            overlay:addEvent("uimanager.lua is not patched: no events will arrive")
        elseif UIManager._has_refresh_logger ~= 2 then
            overlay:addEvent("OLD uimanager.lua: no call stack, copy the new one")
        else
            overlay:addEvent("capturing refreshes (SET = setDirty, REF = real refresh)")
        end
        scheduleRedraw()
    elseif overlay then
        UIManager.refresh_logger = nil
        UIManager:unschedule(flush)
        redraw_pending = false
        local o = overlay
        overlay = nil
        UIManager._pti_overlays[o] = nil
        -- explicit refresh of the area the box covered: a plain close() queues
        -- no refresh, so the box would stay on screen until the next repaint
        local d = o.dimen
        local region = d and Geom:new{ x = d.x, y = d.y, w = d.w, h = d.h } or nil
        UIManager:close(o, region and REFRESH_MODE or nil, region)
        o:free()
        -- take the hooks off again: nothing of this overlay stays in UIManager
        for _, undo in ipairs({ unhook_show or false, unhook_send or false }) do
            if undo then pcall(undo) end
        end
        -- the hooks shared by the overlays go when no overlay is left
        if next(UIManager._pti_overlays) == nil then
            for _, name in ipairs({ "_pti_unhook_repaint", "_pti_unhook_topmost" }) do
                local undo = UIManager[name]
                if undo then pcall(undo) end
            end
        end
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
            logger.warn("refresh overlay (close):", err)
            overlay = nil
            UIManager.refresh_logger = nil
        end
        if on_close_cb then
            local ok2, err2 = pcall(on_close_cb)
            if not ok2 then logger.warn("refresh overlay (on close):", err2) end
        end
    end)
end

local function setEnabled(enable)
    desired = enable and true or false
    -- deferred: never touch the UI while the plugin is still initialising
    UIManager:scheduleIn(START_DELAY, function()
        local ok, err = pcall(apply)
        if not ok then
            logger.warn("refresh overlay:", err)
            overlay = nil   -- leave a clean state; KOReader keeps running
            UIManager.refresh_logger = nil
        end
    end)
end

return {
    setEnabled = setEnabled,
    setOnClose = function(fn) on_close_cb = fn end,
}
