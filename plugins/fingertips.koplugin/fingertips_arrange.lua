--[[
FingerTips: the "Action bar" settings screen.

Lists every action of KOReader's highlight popup, grouped the way the bar
will show them (first set, then what More brings up, ...), followed by the
ones left off the bar. Tap an action to pick it, then Move up / Move down;
tap its box to put it on the bar or take it off. Rows per set: one row
(three actions and More) or two rows (seven and More).
]]

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local ButtonTable = require("ui/widget/buttontable")
local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Actions = require("fingertips_actions")
local _ = require("gettext")
local T = require("ffi/util").template

local Screen = Device.screen

local SET_NAMES = { _("First set"), _("Second set"), _("Third set"), _("Fourth set"), _("Fifth set") }

local Arrange = InputContainer:extend{
    hl = nil,
    covers_fullscreen = true,
}

function Arrange:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events = {
        FtArrangeTap = { GestureRange:new{ ges = "tap", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events = { FtArrangeClose = { { Device.input.group.Back } } }
    end
    self.shown, self.hidden, self.all = Actions.arrangement(self.hl)
    self.info = {}
    for _, a in ipairs(self.all) do self.info[a.id] = a end
    self.rows = Actions.rows()
    self:build()
end

function Arrange:labelFor(id)
    local a = self.info[id]
    if not a then return id end
    if a.conditional then
        return T(_("%1 (only when it applies)"), a.label)
    end
    return a.label
end

-- The list as it will be drawn: headings and actions, in order.
function Arrange:entries()
    local list = {}
    local per, need_more = Actions.perSet(self.rows, #self.shown)
    for i, id in ipairs(self.shown) do
        if (i - 1) % per == 0 then
            local k = math.floor((i - 1) / per) + 1
            local name
            if not need_more then
                name = _("In the popup")
            else
                name = SET_NAMES[k] or T(_("Set %1"), k)
                if k > 1 then name = T(_("%1, after More"), name) end
            end
            table.insert(list, { heading = name })
        end
        table.insert(list, { id = id, checked = true })
    end
    if #self.hidden > 0 then
        table.insert(list, { heading = _("Not in the popup") })
        for _, id in ipairs(self.hidden) do
            table.insert(list, { id = id, checked = false })
        end
    end
    return list
end

function Arrange:build()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(16)
    if self[1] then self[1]:free() end

    local title = TitleBar:new{
        width = sw,
        fullscreen = true,
        title = _("Customize popup"),
        with_bottom_line = true,
        close_callback = function() self:onFtArrangeClose() end,
        show_parent = self,
    }
    local rows_table = ButtonTable:new{
        width = sw - 2 * pad,
        buttons = {{
            {
                text = (self.rows == 1 and "✓ " or "") .. _("One row per set"),
                callback = function() self:setRows(1) end,
            },
            {
                text = (self.rows == 2 and "✓ " or "") .. _("Two rows per set"),
                callback = function() self:setRows(2) end,
            },
        }},
        show_parent = self,
    }
    local hint = TextBoxWidget:new{
        text = _("Tap an action to pick it, then move it. Tap its box to put it in the popup or take it out."),
        face = Font:getFace("cfont", 16),
        width = sw - 2 * pad,
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    local selected = self.selected
    local bottom = ButtonTable:new{
        width = sw,
        zero_sep = true,
        buttons = {{
            {
                text = "▲ " .. _("Move up"),
                enabled = selected ~= nil,
                callback = function() self:move(-1) end,
            },
            {
                text = "▼ " .. _("Move down"),
                enabled = selected ~= nil,
                callback = function() self:move(1) end,
            },
        }},
        show_parent = self,
    }

    local head = VerticalGroup:new{
        align = "left",
        title,
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
        LeftContainer:new{
            dimen = Geom:new{ w = sw, h = rows_table:getSize().h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, rows_table },
        },
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
        LeftContainer:new{
            dimen = Geom:new{ w = sw, h = hint:getSize().h },
            HorizontalGroup:new{ HorizontalSpan:new{ width = pad }, hint },
        },
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
    }
    local head_h = head:getSize().h

    -- Fit the list in the space left, shrinking rows if there are many.
    local entries = self:entries()
    local n_items, n_heads = 0, 0
    for _, e in ipairs(entries) do
        if e.heading then n_heads = n_heads + 1 else n_items = n_items + 1 end
    end
    local avail = sh - head_h - bottom:getSize().h - Screen:scaleBySize(4)
    local item_h = Screen:scaleBySize(46)
    local head_h_each = math.floor(item_h * 0.65)
    local need = n_items * item_h + n_heads * head_h_each
    if need > avail then
        local f = avail / need
        item_h = math.floor(item_h * f)
        head_h_each = math.floor(head_h_each * f)
    end
    local font_size = math.max(12, math.min(20, math.floor(20 * item_h / Screen:scaleBySize(46))))
    local face = Font:getFace("cfont", font_size)
    local small = Font:getFace("cfont", math.max(11, font_size - 4))

    local list = VerticalGroup:new{ align = "left" }
    self.hit = {}
    local y = head_h
    for _, e in ipairs(entries) do
        if e.heading then
            table.insert(list, LeftContainer:new{
                dimen = Geom:new{ w = sw, h = head_h_each },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = pad },
                    TextWidget:new{ text = e.heading, face = small, fgcolor = Blitbuffer.COLOR_DARK_GRAY },
                },
            })
            y = y + head_h_each
        else
            local is_sel = e.id == selected
            local check = CheckMark:new{ checked = e.checked, face = face }
            local check_w = check:getSize().w
            table.insert(list, FrameContainer:new{
                bordersize = 0,
                padding = 0,
                margin = 0,
                background = is_sel and Blitbuffer.COLOR_LIGHT_GRAY or nil,
                LeftContainer:new{
                    dimen = Geom:new{ w = sw, h = item_h },
                    HorizontalGroup:new{
                        HorizontalSpan:new{ width = pad },
                        check,
                        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                        TextWidget:new{
                            text = self:labelFor(e.id),
                            face = face,
                            bold = is_sel,
                            max_width = sw - 2 * pad - check_w - Screen:scaleBySize(10),
                        },
                    },
                },
            })
            table.insert(self.hit, {
                id = e.id, y0 = y, y1 = y + item_h,
                -- the box and a bit around it toggles; the rest picks the row
                box_x1 = pad + check_w + Screen:scaleBySize(10),
            })
            y = y + item_h
        end
    end

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        OverlapGroup:new{
            dimen = Geom:new{ w = sw, h = sh },
            VerticalGroup:new{ align = "left", head, list },
            BottomContainer:new{
                dimen = Geom:new{ w = sw, h = sh },
                bottom,
            },
        },
    }
end

function Arrange:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

function Arrange:save()
    Actions.save(self.hl, self.shown, self.hidden)
end

local function indexOf(list, id)
    for i, v in ipairs(list) do
        if v == id then return i end
    end
end

function Arrange:setRows(rows)
    if self.rows == rows then return end
    self.rows = rows
    Actions.setRows(rows)
    UIManager:nextTick(function() self:refresh() end)
end

function Arrange:toggle(id)
    local i = indexOf(self.shown, id)
    if i then
        table.remove(self.shown, i)
        table.insert(self.hidden, id)
    else
        i = indexOf(self.hidden, id)
        if i then table.remove(self.hidden, i) end
        table.insert(self.shown, id)
    end
    self:save()
    self:refresh()
end

function Arrange:move(delta)
    local id = self.selected
    if not id then return end
    for _, list in ipairs({ self.shown, self.hidden }) do
        local i = indexOf(list, id)
        if i then
            local j = i + delta
            if j >= 1 and j <= #list then
                list[i], list[j] = list[j], list[i]
                self:save()
            end
            break
        end
    end
    UIManager:nextTick(function() self:refresh() end)
end

function Arrange:onFtArrangeTap(_, ges)
    local pos = ges.pos
    for _, h in ipairs(self.hit) do
        if pos.y >= h.y0 and pos.y < h.y1 then
            if pos.x < h.box_x1 then
                self:toggle(h.id)
            else
                self.selected = (self.selected ~= h.id) and h.id or nil
                self:refresh()
            end
            return true
        end
    end
    return true
end

function Arrange:onFtArrangeClose()
    UIManager:close(self, "ui")
    return true
end

return Arrange
