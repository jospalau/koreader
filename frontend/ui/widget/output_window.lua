--[[--
Window that shows the output of something that ran (a script...): an icon in a round badge, a title,
a subtitle, the output in a scrollable box, an optional note and a row of buttons.
Same look as busy_widget.lua. It can ONLY be closed with its buttons: taps outside and swipes are swallowed.

Save it as  koreader/frontend/ui/widget/output_window.lua

    local OutputWindow = require("ui/widget/output_window")
    UIManager:show(OutputWindow:new{
        icon = "check",                 -- "check", "notice-warning"...
        title = "Done",
        subtitle = "pullConfig.sh",
        text = output,                  -- scrolls when it does not fit
        face = Font:getFace("myfont"),  -- optional, face of the output
        note = "KOReader needs to be restarted.",   -- optional, bold line under the output
        buttons = {                     -- one row, left to right; the window closes first, then callback runs
            { text = "No need to restart", callback = function() ... end },
            { text = "Restart", flash = true, callback = function() ... end },
        },
    })
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Screen = Device.screen
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local OutputWindow = InputContainer:extend{
    modal = true,
    name = "output_window",
    icon = "check",
    title = "",
    subtitle = nil,
    text = "",
    face = nil,
    note = nil,
    buttons = nil,
}

function OutputWindow:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local w = math.floor(math.min(sw * 0.9, sh))
    local border = Size.border.window
    local pad = Screen:scaleBySize(20)
    local inner_w = w - 2 * (border + pad)
    local function gap(n) return VerticalSpan:new{ width = Screen:scaleBySize(n) } end

    -- Header: icon in a round badge, title, subtitle.
    local icon_size = Screen:scaleBySize(44)
    local badge_pad = Screen:scaleBySize(12)
    local badge_border = Size.border.thick
    local badge_size = icon_size + 2 * badge_pad + 2 * badge_border
    local top = VerticalGroup:new{
        align = "center",
        FrameContainer:new{
            radius = math.floor(badge_size / 2),
            bordersize = badge_border,
            padding = badge_pad,
            margin = 0,
            background = Blitbuffer.COLOR_WHITE,
            IconWidget:new{ icon = self.icon, width = icon_size, height = icon_size },
        },
        gap(12),
        TextBoxWidget:new{
            text = self.title,
            face = Font:getFace("tfont", 22),
            width = inner_w,
            alignment = "center",
        },
    }
    if self.subtitle and self.subtitle ~= "" then
        top[#top + 1] = gap(4)
        top[#top + 1] = TextWidget:new{
            text = self.subtitle,
            face = Font:getFace("cfont", 16),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = inner_w,
        }
    end
    top[#top + 1] = gap(14)

    -- Footer: optional note, then the buttons (the only way out).
    local row = {}
    for _i, b in ipairs(self.buttons or {}) do
        row[#row + 1] = { text = b.text, callback = function() self:onButton(b) end }
    end
    local bottom = VerticalGroup:new{ align = "center" }
    if self.note and self.note ~= "" then
        bottom[#bottom + 1] = gap(12)
        bottom[#bottom + 1] = TextBoxWidget:new{
            text = self.note,
            face = Font:getFace("tfont", 16),
            width = inner_w,
            alignment = "center",
        }
    end
    bottom[#bottom + 1] = gap(14)
    bottom[#bottom + 1] = ButtonTable:new{
        width = inner_w,
        buttons = { row },
        show_parent = self,
    }

    -- Output: a soft gray box; the text scrolls when the window would be taller than the screen.
    local soft_pad = Screen:scaleBySize(8)
    local content_w = inner_w - 2 * soft_pad
    local body_w = content_w - ScrollableContainer:getScrollbarWidth()
    local text = (tostring(self.text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if text == "" then text = "(no output)" end
    local body = TextBoxWidget:new{
        text = text,
        face = self.face or Font:getFace("cfont", 16),
        width = body_w,
    }
    local max_card_h = math.floor(sh * 0.88)
    local chrome = 2 * (border + pad) + top:getSize().h + bottom:getSize().h + 2 * soft_pad
    local max_text_h = math.max(Screen:scaleBySize(80), max_card_h - chrome)
    local content = body
    if body:getSize().h > max_text_h then
        content = ScrollableContainer:new{
            dimen = Geom:new{ w = content_w, h = max_text_h },
            show_parent = self,
            body,
        }
    end
    local box = FrameContainer:new{
        width = inner_w,
        background = Blitbuffer.Color8(240),
        bordersize = 0,
        radius = Screen:scaleBySize(8),
        padding = soft_pad,
        margin = 0,
        content,
    }

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = border,
        radius = Size.radius.window,
        padding = pad,
        margin = 0,
        VerticalGroup:new{ align = "center", top, box, bottom },
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self[1] = CenterContainer:new{ dimen = self.dimen, self.frame }

    -- Taps, swipes and holds outside the buttons and the scrolling box do nothing (and do not reach the
    -- reader underneath). Children get the gesture first, so buttons and scrolling still work.
    if Device:isTouchDevice() then
        self.ges_events = self.ges_events or {}
        self.ges_events.TapSwallow = { GestureRange:new{ ges = "tap", range = self.dimen } }
        self.ges_events.SwipeSwallow = { GestureRange:new{ ges = "swipe", range = self.dimen } }
        self.ges_events.HoldSwallow = { GestureRange:new{ ges = "hold", range = self.dimen } }
    end
end

function OutputWindow:onTapSwallow() return true end
function OutputWindow:onSwipeSwallow() return true end
function OutputWindow:onHoldSwallow() return true end

function OutputWindow:onButton(b)
    UIManager:close(self, b.flash and "flashui" or "ui", self.frame.dimen)
    if b.callback then b.callback() end
end

function OutputWindow:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    return true
end

return OutputWindow
