--[[
Start-menu / hero micro-module: reading speed (WPM) for the current session.
See README.md in this directory for the module spec contract.

Data comes from a small JSON file written by the statistics plugin on every
page turn (asynchronously via UIManager:scheduleIn so it has zero impact on
page-turn latency). The file lives at:
  <settings>/bookshelf/wpm_session.json

If the file is absent or stale (> 5 minutes since last page turn) the module
shows a placeholder. No network, no sqlite — works offline.
]]
local _ = require("lib/bookshelf_i18n").gettext

local STALE_S = 300 -- 5 minutes: session is considered over

local function readWpm()
    local DataStorage = require("datastorage")
    local path = DataStorage:getSettingsDir() .. "/wpm_session.json"
    local f = io.open(path, "r")
    if not f then return nil end
    local raw = f:read("*a")
    f:close()
    if not raw or raw == "" then return nil end
    local wpm     = tonumber(raw:match('"wpm"%s*:%s*(%d+)'))
    local updated = tonumber(raw:match('"updated"%s*:%s*(%d+)'))
    if not wpm or not updated then return nil end
    if os.time() - updated > STALE_S then return nil end
    return wpm
end

return {
    key     = "wpm_session",
    title   = _("Reading speed"),
    summary = _("Current session WPM. Works offline."),

    render = function(ctx)
        local width, scale_pct = ctx.width, ctx.scale
        local Fonts           = require("lib/bookshelf_fonts")
        local TextWidget      = require("ui/widget/textwidget")
        local VerticalGroup   = require("ui/widget/verticalgroup")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan  = require("ui/widget/horizontalspan")
        local VerticalSpan    = require("ui/widget/verticalspan")
        local SM              = require("lib/bookshelf_start_menu_modules")
        local mw = math.max(50, width)
        local function sc(n) return math.max(1, math.floor(n * (scale_pct or 100) / 100 + 0.5)) end
        local BLACK = SM.COLOR_PRIMARY

        local wpm = readWpm()

        if not wpm then
            return TextWidget:new{
                text      = _("No active session"),
                face      = Fonts:getFace("cfont", sc(15)),
                fgcolor   = SM.COLOR_MUTED,
                max_width = mw,
            }
        end

        local big_face, big_bold = Fonts:getFace("cfont", sc(40), {bold=true})
        local label_face, label_bold = Fonts:getFace("cfont", sc(20), {bold=true})
        local big_tw = TextWidget:new{
            text    = tostring(wpm),
            face    = big_face,
            bold    = big_bold,
            fgcolor = BLACK,
        }
        local label_tw = TextWidget:new{
            text    = _("wpm"),
            face    = label_face,
            bold    = label_bold,
            fgcolor = SM.COLOR_MUTED,
        }
        local dy = math.max(0, big_tw:getBaseline() - label_tw:getBaseline())
        return HorizontalGroup:new{
            align = "top",
            big_tw,
            HorizontalSpan:new{ width = sc(12) },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = dy },
                label_tw,
            },
        }
    end,
}

