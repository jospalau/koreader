local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local _ = require("gettext")
local Screen = Device.screen

local ScreenSaverWidget = InputContainer:extend{
    name = "ScreenSaver",
    widget = nil,
    background = nil,
}

function ScreenSaverWidget:init()
    -- local i, timages, popen = 0, {}, io.popen
    -- local pfile = popen('find /mnt/onboard/.adds/wallpapers -maxdepth 1 -type f -name "*.jpg" -o -name "*.png"')
    -- for filename in pfile:lines() do
    --     i = i + 1
    --     timages[i] = filename
    -- end
    -- pfile:close()

    -- local random_fav = math.random(1, #timages)
    -- local image = timages[random_fav]

    -- G_reader_settings:saveSetting("screensaver_image", image)
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end
    if Device:isTouchDevice() then
        local range = Geom:new{
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
        self.ges_events.Tap = { GestureRange:new{ ges = "tap", range = range } }
    end
    self:update()
end

function ScreenSaverWidget:update()
    self.height = Screen:getHeight()
    self.width = Screen:getWidth()

    self.region = Geom:new{
        x = 0, y = 0,
        w = self.width,
        h = self.height,
    }
    self.main_frame = FrameContainer:new{
        radius = 0,
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = self.background,
        width = self.width,
        height = self.height,
        self.widget,
    }
    self.dithered = true
    self[1] = self.main_frame
end

function ScreenSaverWidget:onShow()
    UIManager:setDirty(self, function()
        return "full", self.main_frame.dimen
    end)
    return true
end

function ScreenSaverWidget:onTap(_, ges)
    if ges.pos:intersectWith(self.main_frame.dimen) then
        self:onClose()
    end
    return true
end

function ScreenSaverWidget:onClose()
    -- If we happened to shortcut a delayed close via user input, unschedule it to avoid a spurious refresh.
    local Screensaver = require("ui/screensaver")
    if Screensaver.delayed_close then
        UIManager:unschedule(Screensaver.close_widget)
    end

    UIManager:close(self)
    return true
end
ScreenSaverWidget.onAnyKeyPressed = ScreenSaverWidget.onClose
ScreenSaverWidget.onExitScreensaver = ScreenSaverWidget.onClose

function ScreenSaverWidget:onCloseWidget()
    -- Restore to previous rotation mode, if need be.
    if Device.orig_rotation_mode then
        Screen:setRotationMode(Device.orig_rotation_mode)
        Device.orig_rotation_mode = nil
    end

    -- Make it full-screen (self.main_frame.dimen might be in a different orientation, and it's already full-screen anyway...)
    -- This does not have any effect in Kobo or PocketBook because it seems to be instantaneous while picture disappears
    -- The refresh can be done in a OutOfScreenSaver() event handler like the one in devicelistener.lua
    -- However, it wors in Android in which I think the refreshes are a bit delayed and it works perfectly flashing
    -- If it is commented and a full refresh is done in a OutOfScreenSaver(), there are artifacts of the image in Kobo
    -- Ommited then just for Android
    if not Device:isAndroid() then
        UIManager:setDirty(nil, "full")
    end

    -- Will come after the Resume event, iff screensaver_delay is set.
    -- Comes *before* it otherwise.
    UIManager:broadcastEvent(Event:new("OutOfScreenSaver"))

    -- NOTE: ScreenSaver itself is neither a Widget nor an instantiated object, so make sure we cleanup behind us...
    local Screensaver = require("ui/screensaver")
    Screensaver:cleanup()
end

function ScreenSaverWidget:onResume()
    -- If we actually catch this event, it means screensaver_delay is set.
    -- Tell Device about it, so that further power button presses while we're still shown send us back to suspend.
    -- NOTE: This only affects devices where we handle Power events ourselves (i.e., rely on Device -> Generic's onPowerEvent),
    --       and it *always* implies that Device.screen_saver_mode is true.
    Device.screen_saver_lock = true
end

function ScreenSaverWidget:onSuspend()
    -- Also flip this back on suspend, in case we suspend again on a delayed screensaver (e.g., via SleepCover or AutoSuspend).
    Device.screen_saver_lock = false
end

return ScreenSaverWidget
