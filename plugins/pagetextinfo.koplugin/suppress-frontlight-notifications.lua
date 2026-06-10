local Device = require("device")

if Device:hasFrontlight() then
    local DeviceListener = require("device/devicelistener")
    local _fl_was_off = nil

    function DeviceListener:onShowIntensity()
        local powerd = Device:getPowerDevice()
        local is_off = powerd:isFrontlightOff()

        if is_off and _fl_was_off == false then
            local Notification = require("ui/widget/notification")
            local _ = require("gettext")
            Notification:notify(_("Frontlight off."))
        elseif not is_off and _fl_was_off == true then
            local Notification = require("ui/widget/notification")
            local _ = require("gettext")
            Notification:notify(_("Frontlight on."))
        end

        _fl_was_off = is_off
        return true
    end

    if Device:hasNaturalLight() then
        local _warmth_was_off = nil

        function DeviceListener:onShowWarmth()
            local powerd = Device:getPowerDevice()
            local is_off = (powerd:frontlightWarmth() == 0)

            if is_off and _warmth_was_off == false then
                local Notification = require("ui/widget/notification")
                local _ = require("gettext")
                Notification:notify(_("Warmth off."))
            elseif not is_off and _warmth_was_off == true then
                local Notification = require("ui/widget/notification")
                local _ = require("gettext")
                Notification:notify(_("Warmth on."))
            end

            _warmth_was_off = is_off
            return true
        end
    end
end
