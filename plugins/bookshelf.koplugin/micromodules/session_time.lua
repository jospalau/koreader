--[[
Start-menu / hero micro-module: current session reading time.
Shows how long you have been reading in the current session.
Uses topbar.start_session_time from the active ReaderUI instance.
Works offline.
]]
local _ = require("lib/bookshelf_i18n").gettext

local function getSessionSecs()
    local ok, ui = pcall(function()
        return require("apps/reader/readerui").instance
    end)
    if not ok or not ui then return nil end
    local topbar = ui.view and ui.view.topbar
    if not topbar or not topbar.start_session_time then return nil end
    local secs = os.time() - topbar.start_session_time
    return secs > 0 and secs or nil
end

local function fmtTime(secs)
    if not secs or secs < 0 then return "0m" end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then
        return string.format("%dh %dm", h, m)
    end
    return string.format("%dm", m)
end

return {
    key     = "session_time",
    title   = _("Session time"),
    summary = _("Time read in the current session. Works offline."),

    render = function(ctx)
        local width, scale_pct = ctx.width, ctx.scale
        local Fonts           = require("lib/bookshelf_fonts")
        local TextWidget      = require("ui/widget/textwidget")
        local VerticalGroup   = require("ui/widget/verticalgroup")
        local VerticalSpan    = require("ui/widget/verticalspan")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan  = require("ui/widget/horizontalspan")
        local SM              = require("lib/bookshelf_start_menu_modules")
        local mw = math.max(50, width)
        local function sc(n) return math.max(1, math.floor(n * (scale_pct or 100) / 100 + 0.5)) end
        local BLACK = SM.COLOR_PRIMARY

        local secs = getSessionSecs()

        if secs == nil then
            return TextWidget:new{
                text      = _("Not reading"),
                face      = Fonts:getFace("cfont", sc(15)),
                fgcolor   = SM.COLOR_MUTED,
                max_width = mw,
            }
        end

        local big_face, big_bold     = Fonts:getFace("cfont", sc(40), {bold=true})
        local label_face, label_bold = Fonts:getFace("cfont", sc(20), {bold=true})
        local sub_face               = Fonts:getFace("cfont", sc(13))

        local big_tw = TextWidget:new{
            text    = fmtTime(secs),
            face    = big_face,
            bold    = big_bold,
            fgcolor = BLACK,
        }
        local label_tw = TextWidget:new{
            text    = _("Session"),
            face    = label_face,
            bold    = label_bold,
            fgcolor = SM.COLOR_MUTED,
        }
        local dy = math.max(0, big_tw:getBaseline() - label_tw:getBaseline())
        local header = HorizontalGroup:new{
            align = "top",
            big_tw,
            HorizontalSpan:new{ width = sc(12) },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = dy },
                label_tw,
            },
        }

        local sub_tw = TextWidget:new{
            text      = _("current session"),
            face      = sub_face,
            fgcolor   = SM.COLOR_MUTED,
            max_width = mw,
        }

        return VerticalGroup:new{
            align = "left",
            header,
            VerticalSpan:new{ width = sc(4) },
            sub_tw,
        }
    end,
}

