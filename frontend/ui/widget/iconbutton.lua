--[[--
Button with a big icon image! Designed for touch devices.
--]]

local BD = require("ui/bidi")
local Device = require("device")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local IconWidget = require("ui/widget/iconwidget")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen

local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

local IconButton = InputContainer:extend{
    icon = "notice-warning",
    icon_rotation_angle = 0,
    dimen = nil,
    -- show_parent is used for UIManager:setDirty, so we can trigger repaint
    show_parent = nil,
    width = Screen:scaleBySize(DGENERIC_ICON_SIZE), -- our icons are square
    height = Screen:scaleBySize(DGENERIC_ICON_SIZE),
    padding = 0,
    padding_top = nil,
    padding_right = nil,
    padding_bottom = nil,
    padding_left = nil,
    enabled = true,
    callback = nil,
    allow_flash = true, -- set to false for any IconButton that may close its container
}

function IconButton:init()
    self.image = IconWidget:new{
        icon = self.icon,
        rotation_angle = self.icon_rotation_angle,
        width = self.width,
        height = self.height,
    }

    self.show_parent = self.show_parent or self

    self.horizontal_group = HorizontalGroup:new{}
    table.insert(self.horizontal_group, HorizontalSpan:new{})
    table.insert(self.horizontal_group, self.image)
    table.insert(self.horizontal_group, HorizontalSpan:new{})

    self.button = VerticalGroup:new{}
    table.insert(self.button, VerticalSpan:new{})
    table.insert(self.button, self.horizontal_group)
    table.insert(self.button, VerticalSpan:new{})

    self[1] = self.button
    self:update()
end

function IconButton:update()
    if not self.padding_top then self.padding_top = self.padding end
    if not self.padding_right then self.padding_right = self.padding end
    if not self.padding_bottom then self.padding_bottom = self.padding end
    if not self.padding_left then self.padding_left = self.padding end

    self.horizontal_group[1].width = self.padding_left
    self.horizontal_group[3].width = self.padding_right
    self.dimen = self.image:getSize()
    self.dimen.w = self.dimen.w + self.padding_left+self.padding_right

    self.button[1].width = self.padding_top
    self.button[3].width = self.padding_bottom
    self.dimen.h = self.dimen.h + self.padding_top+self.padding_bottom
    self:initGesListener()
end

function IconButton:initGesListener()
    self.ges_events = {
        TapIconButton = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldIconButton = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
        HoldReleaseIconButton = {
            GestureRange:new{
                ges = "hold_release",
                range = self.dimen,
            },
        }
    }
end

function IconButton:onTapIconButton()
    if not self.callback then return end

    -- if self.icon and (self.icon == "appbar.tools" or self.icon == "appbar.settings" or self.icon == "appbar.search"  or self.icon == "appbar.filebrowser" or self.icon == "appbar.menu" or self.icon == "appbar.navigation" or self.icon == "appbar.typeset") then
    --     self.allow_flash = false
    -- end

    local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
    if G_reader_settings:isFalse("flash_ui") or not self.allow_flash then
        self.callback()
    else
        -- Mimic BiDi left/right switcheroos...
        local h_padding
        if BD.mirroredUILayout() then
            h_padding = self.padding_right
        else
            h_padding = self.padding_left
        end
        -- c.f., ui/widget/button for more gnarly details about the implementation, but the flow of the flash_ui codepath essentially goes like this:
        -- 1. Paint the highlight
        -- 2. Refresh the highlighted item (so we can see the highlight)
        -- 3. Paint the unhighlight
        -- 4. Do NOT refresh the highlighted item, but enqueue a refresh request
        -- 5. Run the callback
        -- 6. Explicitly drain the paint & refresh queues; i.e., refresh (so we get to see both the callback results, and the unhighlight).

        -- Highlight
        --

        self.image.invert = true
        UIManager:widgetInvert(self.image, self.dimen.x + h_padding, self.dimen.y + self.padding_top)

        -- When using Kobo Libra 2 and Kobo Clara 2E (same for Kindle devices) in fm and display mode is set to detailed, if we tap on the top home and + icons,
        -- the first horizontal line of the list is overlapped a bit with white.
        -- Fix this using ui refresh in the icon button widget when tapping.
        if self.show_parent.root_path and ui.pagetextinfo and ui.pagetextinfo.settings:isTrue("enable_devices_flashes_tweaks") and (Device.model == "Kobo_io" or Device.model == "Kobo_goldfinch" or Device:isKindle()) then
            UIManager:setDirty(nil, "ui", self.dimen)
         else
            UIManager:setDirty(nil, "fast", self.dimen)
         end

        UIManager:forceRePaint()
        if (Device:isKindle() or Device.model == "Kobo_io" or Device.model == "Kobo_goldfinch") and ui.pagetextinfo and ui.pagetextinfo.settings:isTrue("enable_devices_flashes_tweaks") then
            UIManager:yieldToEPDC(25000)
        elseif (Device:isPocketBook() or Device.model == "Kobo_cadmus") and ui.pagetextinfo and ui.pagetextinfo.settings:isTrue("enable_devices_flashes_tweaks") then
            UIManager:yieldToEPDC(300000)
        else
            UIManager:yieldToEPDC(5000)
        end

        -- Unhighlight
        --
        self.image.invert = false
        UIManager:widgetInvert(self.image, self.dimen.x + h_padding, self.dimen.y + self.padding_top)

        -- local ui = require("apps/filemanager/filemanager").instance or require("apps/reader/readerui").instance
        -- -- There are no glitches in the new Libra Colour but there is a flash after pressing a button. We avoid it
        -- if ui.pagetextinfo and ui.pagetextinfo.settings:isTrue("enable_devices_flashes_tweaks") and (Device.model == "Kobo_monza" or Device:isPocketBook()) then
        --     -- local util = require("ffi/util")
        --     -- util.usleep(250000)
        --     UIManager:yieldToEPDC(100000)
        -- end
        -- Callback
        --
        self.callback()

        -- We need the Kindle devices, the Kobo Libra 2 and the Kobo Clara 2E to perform a ui refresh here as well
        -- when reverting the highlighting
        if self.show_parent.root_path and ui.pagetextinfo and ui.pagetextinfo.settings:isTrue("enable_devices_flashes_tweaks") and (Device.model == "Kobo_io" or Device.model == "Kobo_goldfinch" or Device:isKindle()) then
           UIManager:setDirty(nil, "ui", self.dimen)
        else
           UIManager:setDirty(nil, "fast", self.dimen)
        end
        UIManager:forceRePaint()
    end
    return true
end

function IconButton:onHoldIconButton()
    -- If we're going to process this hold, we must make
    -- sure to also handle its hold_release below, so it's
    -- not propagated up to a MovableContainer
    self._hold_handled = nil
    if self.enabled and self.hold_callback then
        self.hold_callback()
    elseif self.hold_input then
        self:onInput(self.hold_input)
    elseif type(self.hold_input_func) == "function" then
        self:onInput(self.hold_input_func())
    elseif not self.hold_callback then -- nil or false
        return
    end
    self._hold_handled = true
    return true
end

function IconButton:onHoldReleaseIconButton()
    if self._hold_handled then
        self._hold_handled = nil
        return true
    end
    return false
end

function IconButton:onFocus()
    --quick and dirty, need better way to show focus
    self.image.invert = true
    return true
end

function IconButton:onUnfocus()
    self.image.invert = false
    return true
end

function IconButton:onTapSelect()
    self:onTapIconButton()
end

function IconButton:setIcon(icon)
    if icon ~= self.icon then
        self.icon = icon
        self:free()
        self:init()
    end
end

return IconButton
