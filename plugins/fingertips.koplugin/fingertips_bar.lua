--[[
FingerTips: the action bar shown after you lift your finger.

It sits above the selection (below it when there's no room), never over it.
It shows one set of actions at a time; More swaps in the next set, and from
the last set it wraps around to the first.

The bar is shown as a transparent full-screen layer so it also sees touches
outside itself: dragging a handle adjusts the selection (the bar hides and
the lifted panel comes back meanwhile), a tap elsewhere closes the bar and
clears the selection, and a long-press elsewhere starts a new selection.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local Actions = require("fingertips_actions")
local _ = require("gettext")

local Screen = Device.screen

local Bar = InputContainer:extend{
    plugin = nil,   -- the FingerTips plugin
    hl = nil,       -- the reader's ReaderHighlight
    actions = nil,  -- from Actions.forBar()
    rows = 1,
    border = 3,     -- screen-scaled units, like the panel's outline
    radius = 9,
}

function Bar:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local function on(ges) return { GestureRange:new{ ges = ges, range = self.dimen } } end
    self.ges_events = {
        FtTouch = on("touch"),
        FtTap = on("tap"),
        FtPan = on("pan"),
        FtPanRelease = on("pan_release"),
        FtSwipe = on("swipe"),
        FtHold = on("hold"),
        FtHoldPan = on("hold_pan"),
        FtHoldRelease = on("hold_release"),
    }
    if Device:hasKeys() then
        self.key_events = { FtClose = { { Device.input.group.Back } } }
    end
    self.visible = true
    self.set_index = 1
    self:makeSets()
    self:build()
end

-- Splits the actions into sets; every set but a lone one ends with More.
function Bar:makeSets()
    local n = #self.actions
    local per, need_more = Actions.perSet(self.rows, n)
    self.cols = need_more and 4 or math.max(1, math.min(4, n))
    self.sets = {}
    local i = 1
    while i <= n do
        local set = {}
        for j = i, math.min(n, i + per - 1) do
            table.insert(set, self.actions[j].button)
        end
        i = i + per
        if need_more then
            table.insert(set, {
                text = Actions.MORE,
                callback = function()
                    -- After the button has finished its own tap feedback.
                    UIManager:nextTick(function() self:nextSet() end)
                end,
            })
        end
        table.insert(self.sets, set)
    end
end

-- The rows of buttons for one set, padded with blank cells so every set
-- has the same layout and More is always in the last cell.
function Bar:tableRows(set)
    local multi = #self.sets > 1
    local count = multi and #set - 1 or #set
    local list = {}
    for i = 1, count do list[i] = set[i] end
    local cells = multi and self.cols * self.rows or math.ceil(count / self.cols) * self.cols
    local target = multi and cells - 1 or cells
    while #list < target do
        table.insert(list, { text = "", enabled = false, callback = function() end })
    end
    if multi then table.insert(list, set[#set]) end
    local rows, r = {}, {}
    for i = 1, #list do
        table.insert(r, list[i])
        if #r == self.cols then
            table.insert(rows, r)
            r = {}
        end
    end
    if #r > 0 then table.insert(rows, r) end
    return rows
end

local function copyButton(b)
    return {
        text = b.text,
        text_func = b.text_func,
        enabled = b.enabled,
        enabled_func = b.enabled_func,
        callback = b.callback,
        hold_callback = b.hold_callback,
        allow_hold_when_disabled = b.allow_hold_when_disabled,
    }
end

function Bar:makeTable(rows, width, shrink)
    local buttons = {}
    for i, row in ipairs(rows) do
        buttons[i] = {}
        for j, b in ipairs(row) do buttons[i][j] = copyButton(b) end
    end
    return ButtonTable:new{
        width = width,
        shrink_unneeded_width = shrink,
        buttons = buttons,
        show_parent = self,
    }
end

-- Builds the frame for the current set. All sets get the same width (the
-- widest one needs), so More doesn't make the bar jump around.
function Bar:build()
    local border = math.max(1, Screen:scaleBySize(self.border))
    local margin = Screen:scaleBySize(6)
    local max_w = Screen:getWidth() - 2 * margin - 2 * border
    if not self.table_w then
        local w = 0
        for _, set in ipairs(self.sets) do
            local t = self:makeTable(self:tableRows(set), max_w, true)
            w = math.max(w, t:getSize().w)
            t:free()
        end
        self.table_w = math.min(max_w, w)
    end
    if self.frame then self.frame:free() end
    self.frame = FrameContainer:new{
        bordersize = border,
        radius = Screen:scaleBySize(self.radius),
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        self:makeTable(self:tableRows(self.sets[self.set_index]), self.table_w, false),
    }
    self[1] = self.frame
    self:place()
end

function Bar:place()
    local size = self.frame:getSize()
    local x, y = self.plugin:barPosition(size.w, size.h)
    self.bar_rect = Geom:new{ x = x, y = y, w = size.w, h = size.h }
end

function Bar:paintTo(bb, x, y)
    if not self.visible then return end
    self.frame:paintTo(bb, x + self.bar_rect.x, y + self.bar_rect.y)
end

-- Repaints the page (and this bar on top of it) over the given area.
function Bar:refresh(region)
    UIManager:setDirty(self.hl.dialog, "ui", region)
end

function Bar:nextSet()
    if not self.sets or #self.sets < 2 then return end
    local old = self.bar_rect
    self.set_index = self.set_index % #self.sets + 1
    self:build()
    self:refresh(old:combine(self.bar_rect))
end

function Bar:insideBar(pos)
    return self.visible and self.bar_rect and pos:intersectWith(self.bar_rect)
end

---------------------------------------------------------------------------
-- Handle dragging
---------------------------------------------------------------------------

function Bar:startDrag(grab)
    self.dragging = grab
    self.visible = false
    self:refresh(self.bar_rect)
    self.plugin:beginHandleDrag(grab.which, grab.touch_y)
end

function Bar:moveDrag(pos)
    local g = self.dragging
    -- Sideways, the handle keeps its offset from the finger; up and down,
    -- the plugin's line lock works from where the finger really is.
    self.plugin:moveHandle(Geom:new{ x = pos.x + g.dx, y = pos.y, w = 0, h = 0 })
end

function Bar:endDrag()
    self.dragging = nil
    self.grab = nil
    self.plugin:endHandleDrag()
    local old = self.bar_rect
    -- The selection changed, so which actions apply may have too (Follow
    -- Link, Hyphenate...): rebuild, starting again from the first set.
    local actions = Actions.forBar(self.hl)
    if #actions > 0 then
        self.actions = actions
        self.set_index = 1
        self.table_w = nil
        self:makeSets()
        self:build()
    else
        self:place()
    end
    self.visible = true
    self:refresh(old:combine(self.bar_rect))
end

function Bar:onFtTouch(_, ges)
    self.grab = nil
    if self:insideBar(ges.pos) then return false end
    self.grab = self.plugin:handleAt(ges.pos)
    return true
end

function Bar:onFtPan(_, ges)
    if not self.dragging then
        local grab = self.grab or self.plugin:handleAt(ges.start_pos or ges.pos)
        if not grab then return true end
        self:startDrag(grab)
    end
    self:moveDrag(ges.pos)
    return true
end

function Bar:onFtPanRelease(_, ges)
    if self.dragging then
        if ges and ges.pos then self:moveDrag(ges.pos) end
        self:endDrag()
    end
    return true
end

function Bar:onFtSwipe(_, ges)
    -- A quick flick on a handle: move it straight to where it ended.
    local grab = self.plugin:handleAt(ges.pos)
    if grab and ges.end_pos then
        self:startDrag(grab)
        self:moveDrag(ges.end_pos)
        self:endDrag()
    end
    return true
end

function Bar:onFtHold(_, ges)
    if self:insideBar(ges.pos) then return true end
    local grab = self.plugin:handleAt(ges.pos)
    if grab then
        self:startDrag(grab)
        return true
    end
    -- Long-press elsewhere: drop this selection and start a new one there.
    local hl = self.hl
    hl:onClose()
    hl:onHold(nil, ges)
    return true
end

function Bar:onFtHoldPan(_, ges)
    if self.dragging then self:moveDrag(ges.pos) end
    return true
end

function Bar:onFtHoldRelease(_, ges)
    if self.dragging then
        if ges and ges.pos then self:moveDrag(ges.pos) end
        self:endDrag()
    end
    return true
end

function Bar:onFtTap(_, ges)
    if self:insideBar(ges.pos) then return true end
    if self.plugin:handleAt(ges.pos) then return true end
    -- Like KOReader's popup: a tap elsewhere closes it and drops the selection.
    self.hl:onClose()
    return true
end

function Bar:onFtClose()
    self.hl:onClose()
    return true
end

function Bar:onCloseWidget()
    local rect = self.bar_rect
    if self.frame then self.frame:free() end
    self.plugin:onBarClosed(self)
    if rect then self:refresh(rect) end
end

return Bar
