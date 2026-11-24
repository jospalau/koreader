--[[--
Card shown while something is running: an icon in a round badge, a title, a line with the
subject (a searched word, a script name...), optional animated dots and an optional hint.

Used by readerhighlightsearch.lua (search) and actions_menu.lua (scripts).

    local BusyWidget = require("busy_widget")
    local w = BusyWidget:new{ title = "Pulling config…", subtitle = "pullConfig.sh", animate = false, dismissable = false }
    UIManager:show(w)
    UIManager:forceRePaint()
    ...
    UIManager:close(w)

Options:
    icon              icon name (default "appbar.search")
    title             first line, bold
    subtitle          second line, bigger and bold (nil = none)
    hint              small gray line at the bottom (nil = none), e.g. "Tap to cancel"
    animate           true (default): moving dots. They only move while the UI loop is running, so
                      use false when a blocking call (io.popen:read, os.execute) is in progress
    dismissable       true (default): a tap or any key closes it and calls dismiss_callback
                      (Trapper:dismissableRunInSubprocess uses that); false: it ignores input
    dismiss_callback  called when the user dismisses it
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = Device.screen
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")

local TICK_SECONDS = 0.4   -- animation step of the dots

-- Row of dots; one is black, its neighbours fade out. Drawn by hand (no child widgets).
local DotsWidget = Widget:extend{
    count = 5,
    active = 1,
}

function DotsWidget:init()
    self.dot = Screen:scaleBySize(12)
    self.gap = Screen:scaleBySize(12)
    self.dimen = Geom:new{
        w = self.count * self.dot + (self.count - 1) * self.gap,
        h = self.dot,
    }
end

function DotsWidget:step()
    self.active = self.active % self.count + 1
end

function DotsWidget:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    for i = 1, self.count do
        local dist = math.abs(i - self.active)
        local color = dist == 0 and Blitbuffer.COLOR_BLACK
            or dist == 1 and Blitbuffer.COLOR_DARK_GRAY
            or Blitbuffer.COLOR_LIGHT_GRAY
        bb:paintRoundedRect(x + (i - 1) * (self.dot + self.gap), y, self.dot, self.dot,
                            color, math.floor(self.dot / 2))
    end
end

local BusyWidget = InputContainer:extend{
    icon = "appbar.search",
    title = "",
    subtitle = nil,
    hint = nil,
    animate = true,
    dismissable = true,
    dismiss_callback = nil,
}

function BusyWidget:init()
    local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
    local inner_w = math.floor(math.min(screen_w, screen_h) * 0.55)

    -- Icon inside a round badge.
    local icon_size = Screen:scaleBySize(56)
    local badge_pad = Screen:scaleBySize(14)
    local badge_border = Size.border.thick
    local badge_size = icon_size + 2 * badge_pad + 2 * badge_border
    local badge = FrameContainer:new{
        radius = math.floor(badge_size / 2),
        bordersize = badge_border,
        padding = badge_pad,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        IconWidget:new{ icon = self.icon, width = icon_size, height = icon_size },
    }

    local function gap(n) return VerticalSpan:new{ width = Screen:scaleBySize(n) } end

    local group = VerticalGroup:new{ align = "center", badge, gap(14) }
    -- the title is a box too, so a long one wraps instead of making the card wider than the screen
    group[#group + 1] = TextBoxWidget:new{
        text = self.title,
        face = Font:getFace("tfont", 22),
        width = inner_w,
        alignment = "center",
    }
    if self.subtitle and self.subtitle ~= "" then
        group[#group + 1] = gap(8)
        group[#group + 1] = TextBoxWidget:new{
            text = self.subtitle,
            face = Font:getFace("tfont", 28),
            width = inner_w,
            alignment = "center",
        }
    end
    if self.animate then
        self.dots = DotsWidget:new{}
        group[#group + 1] = gap(18)
        group[#group + 1] = self.dots
    end
    if self.hint and self.hint ~= "" then
        group[#group + 1] = gap(18)
        group[#group + 1] = TextWidget:new{
            text = self.hint,
            face = Font:getFace("cfont", 16),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
    end

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window,
        radius = Size.radius.window,
        padding = Screen:scaleBySize(24),
        margin = 0,
        group,
    }
    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = screen_w, h = screen_h },
        self.frame,
    }

    if self.dismissable then
        self.ges_events = {
            TapClose = { GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h },
            } },
        }
        if Device:hasKeys() then
            self.key_events = { AnyKeyPressed = { { Device.input.group.Any } } }
        end
    end
end

function BusyWidget:dismiss()
    UIManager:close(self)
    if self.dismiss_callback then self.dismiss_callback() end
    return true
end
function BusyWidget:onTapClose() return self:dismiss() end
function BusyWidget:onAnyKeyPressed() return self:dismiss() end

function BusyWidget:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    if self.animate then
        self._tick = function()
            if self._closed then return end
            self.dots:step()
            UIManager:setDirty(self, function() return "fast", self.dots.dimen end)
            UIManager:scheduleIn(TICK_SECONDS, self._tick)
        end
        UIManager:scheduleIn(TICK_SECONDS, self._tick)
    end
    return true
end

function BusyWidget:onCloseWidget()
    self._closed = true
    if self._tick then UIManager:unschedule(self._tick) end
    UIManager:setDirty(nil, function() return "ui", self.frame.dimen end)
end

return BusyWidget
