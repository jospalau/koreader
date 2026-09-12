--[[--
Widget that shows a confirmation alert with a message and No/Yes buttons.

This is a variant of ConfirmBox with "Yes" / "No" as the default button
texts instead of "OK" / "Cancel".

Example:

    UIManager:show(ConfirmBoxYesNo:new{
        text = _("Do you want to continue?"),
        ok_text = _("Yes"),   -- defaults to _("Yes")
        cancel_text = _("No"), -- defaults to _("No")
        ok_callback = function()
            -- continue
        end,
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
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Input = Device.input
local Screen = Device.screen

local ConfirmBoxYesNo = InputContainer:extend{
    modal = true,
    keep_dialog_open = false,
    text = _("no text"),
    face = Font:getFace("infofont"),
    icon = "notice-question",
    ok_text = _("Yes"),
    cancel_text = _("No"),
    ok_callback = function() end,
    cancel_callback = function() end,
    other_buttons = nil,
    other_buttons_first = false, -- set to true to place other buttons above No-Yes row
    no_ok_button = false,
    margin = Size.margin.default,
    padding = Size.padding.default,
    dismissable = true, -- set to false if any button callback is required
    flush_events_on_show = false, -- set to true when it might be displayed after
                                  -- some processing, to avoid accidental dismissal
}

function ConfirmBoxYesNo:init()
    if self.dismissable then
        if Device:isTouchDevice() then
            self.ges_events.TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(),
                        h = Screen:getHeight(),
                    }
                }
            }
        end
        if Device:hasKeys() then
            self.key_events.Close = { { Device.input.group.Back } }
        end
    end

    self.text_widget_width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 2/3)
    local text_widget = TextBoxWidget:new{
        text = self.text,
        face = self.face,
        width = self.text_widget_width,
    }
    self.text_group = VerticalGroup:new{
        align = "left",
        text_widget,
    }
    if self._added_widgets then
        table.insert(self.text_group, VerticalSpan:new{ width = Size.padding.large })
        for _, widget in ipairs(self._added_widgets) do
            table.insert(self.text_group, widget)
        end
    end
    local content = HorizontalGroup:new{
        align = "center",
        IconWidget:new{
            icon = self.icon,
            alpha = true,
        },
        HorizontalSpan:new{ width = Size.span.horizontal_default },
        self.text_group,
    }

    -- "Yes" (ok) on the left, "No" (cancel) on the right
    local buttons = {{ -- single row
        {
            text = self.ok_text,
            flash_button = self.flash_yes,
            callback = function()
                self.ok_callback()
                if self.keep_dialog_open then return end
                UIManager:close(self)
            end,
        },
        {
            text = self.cancel_text,
            flash_button = self.flash_no,
            callback = function()
                self.cancel_callback()
                UIManager:close(self)
            end,
        },
    }}
    if self.no_ok_button then
        table.remove(buttons[1], 1) -- ok/Yes button is now first
    end

    if self.other_buttons then -- additional rows
        local rownum = self.other_buttons_first and 0 or 1
        for i, buttons_row in ipairs(self.other_buttons) do
            local row = {}
            for _, button in ipairs(buttons_row) do
                table.insert(row, {
                    text = button.text,
                    callback = function()
                        if button.callback then
                            button.callback()
                        end
                        if self.keep_dialog_open then return end
                        UIManager:close(self)
                    end,
                })
            end
            table.insert(buttons, rownum + i, row)
        end
    end

    local button_table = ButtonTable:new{
        width = content:getSize().w,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        radius = Size.radius.window,
        padding = self.padding,
        padding_bottom = 0, -- no padding below buttontable
        VerticalGroup:new{
            align = "left",
            content,
            -- Add same vertical space after than before content
            VerticalSpan:new{ width = self.margin + self.padding },
            button_table,
        }
    }
    self.movable = MovableContainer:new{
        frame,
        unmovable = self.unmovable,
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable,
    }

    -- Reduce font size until widget fit screen height if needed
    local cur_size = frame:getSize()
    if cur_size and cur_size.h > 0.95 * Screen:getHeight() then
        local orig_font = text_widget.face.orig_font
        local orig_size = text_widget.face.orig_size
        local real_size = text_widget.face.size
        if orig_size > 10 then -- don't go too small
            while true do
                orig_size = orig_size - 1
                self.face = Font:getFace(orig_font, orig_size)
                -- scaleBySize() in Font:getFace() may give the same
                -- real font size even if we decreased orig_size,
                -- so check we really got a smaller real font size
                if self.face.size < real_size then
                    break
                end
            end
            -- re-init this widget
            if self._added_widgets then
                self:_preserveAddedWidgets()
            end
            self:free()
            self:init()
        end
    end
end

function ConfirmBoxYesNo:addWidget(widget)
    if self._added_widgets then
        self:_preserveAddedWidgets()
    else
        self._added_widgets = {}
    end
    table.insert(self._added_widgets, widget)
    self:free()
    self:init()
end

function ConfirmBoxYesNo:_preserveAddedWidgets()
    -- remove added widgets to preserve their subwidgets from being free'ed
    for i = 1, #self._added_widgets do
        table.remove(self.text_group)
    end
end

function ConfirmBoxYesNo:getAddedWidgetAvailableWidth()
    return self.text_widget_width
end

function ConfirmBoxYesNo:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
    if self.flush_events_on_show then
        -- Discard queued and upcoming input events to avoid accidental dismissal
        Input:inhibitInputUntil(true)
    end
end

function ConfirmBoxYesNo:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

function ConfirmBoxYesNo:onClose()
    -- Call cancel_callback, parent may expect a choice
    self.cancel_callback()
    UIManager:close(self)
    return true
end

function ConfirmBoxYesNo:onTapClose(arg, ges)
    if ges.pos:notIntersectWith(self.movable.dimen) then
        self:onClose()
    end
    -- Don't let it propagate to underlying widgets
    return true
end

return ConfirmBoxYesNo
