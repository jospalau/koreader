-- plugins/diagtiming.koplugin/main.lua
--[[
Diagnostic-only plugin: times require() calls for other plugins' modules,
how long each event dispatch takes across all registered event handlers,
and how long each Screen:refresh* call takes. Purely additive/logging —
does not change behavior. Remove/disable once you've found the slow spot.
]]


-- This is a debug plugin, remove the following if block to enable it
if true then
    return { disabled = true, }
end

local logger  = require("logger")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local THRESHOLD_MS = 15 -- only log things slower than this, to cut noise

local UIManager = require("ui/uimanager")

local orig_scheduleIn = UIManager.scheduleIn

UIManager.scheduleIn = function(self, delay, callback, ...)
    local info = debug.getinfo(callback, "Sl")

    local wrapped = function(...)
        local t0 = os.clock()

        print(string.format(
            "[diag] scheduleIn START %s:%d",
            info.short_src or "?",
            info.linedefined or 0
        ))

        local ret = { callback(...) }

        local dt = (os.clock() - t0) * 1000

        print(string.format(
            "[diag] scheduleIn END %.1fms %s:%d",
            dt,
            info.short_src or "?",
            info.linedefined or 0
        ))

        return unpack(ret)
    end

    return orig_scheduleIn(self, delay, wrapped, ...)
end

local orig_nextTick = UIManager.nextTick

UIManager.nextTick = function(self, callback, ...)
    local info = debug.getinfo(callback, "Sl")

    local wrapped = function(...)
        local t0 = os.clock()

        print(string.format(
            "[diag] nextTick START %s:%d",
            info.short_src or "?",
            info.linedefined or 0
        ))

        local ret = { callback(...) }

        local dt = (os.clock() - t0) * 1000

        print(string.format(
            "[diag] nextTick END %.1fms %s:%d",
            dt,
            info.short_src or "?",
            info.linedefined or 0
        ))

        return unpack(ret)
    end

    return orig_nextTick(self, wrapped, ...)
end

-- 1) Time require() calls
local orig_require = require
_G.require = function(name)
    local t0 = os.clock()
    local ok, result = pcall(orig_require, name)
    local dt = (os.clock() - t0) * 1000
    if dt > THRESHOLD_MS then
        logger.warn(string.format("[diag] require(%s) took %.1fms", name, dt))
    end
    if not ok then error(result) end
    return result
end

-- 2) Time UIManager:sendEvent
local orig_sendEvent = UIManager.sendEvent
UIManager.sendEvent = function(self, event)
    local t0 = os.clock()
    local ret = orig_sendEvent(self, event)
    local dt = (os.clock() - t0) * 1000
    if dt > THRESHOLD_MS then
        local ev_name = (event and event.handler) or (event and event.name) or "?"
        logger.warn(string.format("[diag] event %s took %.1fms total", tostring(ev_name), dt))
    end
    return ret
end

-- 3) Time every Screen:refresh* call
local Device = require("device")
local Screen = Device.screen
for name, fn in pairs(Screen) do
    if type(fn) == "function" and name:match("^refresh") then
        Screen[name] = function(self, ...)
            local t0 = os.clock()
            local a, b, c, d, e = fn(self, ...)
            local dt = (os.clock() - t0) * 1000
            if dt > 15 then
                logger.warn(string.format("[diag] Screen:%s took %.1fms", name, dt))
            end
            return a, b, c, d, e
        end
    end
end

local DiagTiming = WidgetContainer:extend{
    name = "diagtiming",
    is_doc_only = false,
}

function DiagTiming:onReaderReady()
    logger.warn("[diag] onReaderReady fired at clock=", os.clock())
    UIManager:nextTick(function()
        logger.warn("[diag] first tick after ready at clock=", os.clock())
    end)
end

function DiagTiming:onGesture(ges)
    logger.warn("[diag] gesture:", ges and ges.ges, "at clock=", os.clock())
end

return DiagTiming
