-- X-Ray Utility Functions
local Device = require("device")

local M = {}

function M:isLowPowerDevice()
    -- PW1 (Kindle 5), Touch (Kindle 4), and older are considered low power.
    -- Most of these report as Kindle 5 or lower in the model string.
    -- PW2/3 are significantly faster but still benefit from some optimizations.
    local model = Device:getModel() or ""
    if Device:isKindle() then
        -- PW1 (K5), Touch (K4), etc.
        if model:find("K5") or model:find("K4") or model:find("K3") then
            return true
        end
    end
    -- PocketBook and older Kobo devices can also be slow
    if Device:isPocketBook() or (Device:isKobo() and not Device:isKoboV2()) then
        return true
    end
    return false
end

return M
