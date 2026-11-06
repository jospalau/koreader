--[[
Start-menu / hero micro-module: reading speed (WPM) for the current session.
See README.md in this directory for the module spec contract.

Data comes from a small JSON file written by the statistics plugin on every
page turn (asynchronously via UIManager:scheduleIn so it has zero impact on
page-turn latency). The file lives at:
  <settings>/bookshelf/wpm_session.json

Shows the session WPM and the number of pages counted in the session.
If the file is absent or stale (> 5 minutes since last page turn) the module
shows 0 for both. No network, no sqlite — works offline.
]]
local _ = require("lib/bookshelf_i18n").gettext

local STALE_S = 300 -- 5 minutes: session is considered over

-- Returns wpm, pages (both 0 if the file is missing, invalid or stale)
local function readSession()
    local DataStorage = require("datastorage")
    local path = DataStorage:getSettingsDir() .. "/wpm_session.json"
    local f = io.open(path, "r")
    if not f then return 0, 0 end
    local raw = f:read("*a")
    f:close()
    if not raw or raw == "" then return 0, 0 end
    local wpm     = tonumber(raw:match('"wpm"%s*:%s*(%d+)'))
    local pages   = tonumber(raw:match('"Pages"%s*:%s*(%d+)'))
    local updated = tonumber(raw:match('"updated"%s*:%s*(%d+)'))
    if not wpm or not updated then return 0, 0 end
    if os.time() - updated > STALE_S then return 0, 0 end
    return wpm, pages or 0
end

local function fitFontSize(Fonts, text, max_sz, min_sz, max_w, bold)
    local sz = max_sz
    while sz > min_sz do
        local face, b = Fonts:getFace("cfont", sz, bold and {bold=true} or nil)
        local tw = require("ui/widget/textwidget"):new{
            text = text, face = face, bold = b }
        local w = tw:getSize().w
        tw:free()
        if w <= max_w then return sz end
        sz = sz - 2
    end
    return min_sz
end

return {
    key     = "wpm_session",
    title   = _("Reading speed"),
    summary = _("Current session WPM and pages read. Works offline."),

    render = function(ctx)
        local width, scale_pct = ctx.width, ctx.scale
        local Fonts           = require("lib/bookshelf_fonts")
        local TextWidget      = require("ui/widget/textwidget")
        local VerticalGroup   = require("ui/widget/verticalgroup")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan  = require("ui/widget/horizontalspan")
        local VerticalSpan    = require("ui/widget/verticalspan")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Geom            = require("ui/geometry")
        local SM              = require("lib/bookshelf_start_menu_modules")
        local mw = math.max(50, width)
        local function sc(n) return math.max(1, math.floor(n * (scale_pct or 100) / 100 + 0.5)) end
        local BLACK = SM.COLOR_PRIMARY

        local wpm, pages = readSession()

        local wpm_str   = tostring(wpm)
        local pages_str = tostring(pages)

        local gap    = sc(24)
        local col_w  = math.floor((mw - gap) / 2)
        local col_w2 = mw - gap - col_w

        local label_face, label_bold = Fonts:getFace("cfont", sc(20), {bold=true})

        local wpm_sz_fit   = fitFontSize(Fonts, wpm_str,   sc(40), sc(18), col_w,  true)
        local pages_sz_fit = fitFontSize(Fonts, pages_str, sc(40), sc(18), col_w2, true)
        local big_sz       = math.min(wpm_sz_fit, pages_sz_fit)
        local big_face, big_bold = Fonts:getFace("cfont", big_sz, {bold=true})

        local function makeCol(value, label, w)
            return VerticalGroup:new{
                align = "center",
                TextWidget:new{
                    text      = value,
                    face      = big_face,
                    bold      = big_bold,
                    fgcolor   = BLACK,
                    max_width = w,
                },
                VerticalSpan:new{ width = sc(2) },
                TextWidget:new{
                    text      = label,
                    face      = label_face,
                    bold      = label_bold,
                    fgcolor   = SM.COLOR_MUTED,
                    max_width = w,
                },
            }
        end

        local wpm_col   = makeCol(wpm_str,   _("wpm"),   col_w)
        local pages_col = makeCol(pages_str, _("pages"), col_w2)

        local max_h = math.max(wpm_col:getSize().h, pages_col:getSize().h)

        return HorizontalGroup:new{
            align = "top",
            CenterContainer:new{
                dimen = Geom:new{ w = col_w, h = max_h },
                wpm_col,
            },
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{
                dimen = Geom:new{ w = col_w2, h = max_h },
                pages_col,
            },
        }
    end,
}
