--[[
Start-menu / hero micro-module: current session reading time.
Shows how long you have been reading in the current session,
plus total reading time today from the statistics DB.
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

local STATS_TTL_S = 30
local _cache

local function getTodaySecs()
    local now = os.time()
    if _cache and now - _cache.at < STATS_TTL_S then
        return _cache.secs
    end
    local db_secs = 0
    pcall(function()
        local DataStorage = require("datastorage")
        local path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        local lfs = require("libs/libkoreader-lfs")
        if lfs.attributes(path, "mode") ~= "file" then return end
        local SQ3 = require("lua-ljsqlite3/init")
        local conn = SQ3.open(path, "ro")
        pcall(function()
            conn:exec("PRAGMA busy_timeout=200;")
            local t = os.date("*t", now)
            local day_start = os.time{ year=t.year, month=t.month, day=t.day, hour=0, min=0, sec=0 }
            local stmt = conn:prepare([[
                SELECT COALESCE(SUM(
                    MIN(start_time + duration, ?) - MAX(start_time, ?)
                ), 0)
                FROM wpm_stat_data
                WHERE start_time + duration >= ? AND start_time <= ?
            ]])
            local row = stmt:bind(now, day_start, day_start, now):step()
            stmt:clearbind():reset()
            stmt:close()
            db_secs = tonumber(row[1]) or 0
        end)
        conn:close()
    end)
    local live = 0
    pcall(function()
        local ReaderUI = require("apps/reader/readerui")
        local sp = ReaderUI.instance and ReaderUI.instance.statistics
        if sp and sp.start_current_period and sp.start_current_period > 0 then
            live = math.max(0, now - sp.start_current_period)
        end
    end)
    local total = db_secs + live
    _cache = { at = now, secs = total }
    return total
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
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Geom            = require("ui/geometry")
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

        local today_secs = getTodaySecs()

        local session_str = fmtTime(secs)
        local today_str   = fmtTime(today_secs)
        local longest     = #session_str > #today_str and session_str or today_str
        local big_sz      = sc(40)
        if #longest > 6 then big_sz = sc(32) end
        if #longest > 9 then big_sz = sc(26) end

        local big_face, big_bold     = Fonts:getFace("cfont", big_sz, {bold=true})
        local label_face, label_bold = Fonts:getFace("cfont", sc(20), {bold=true})
        local dot_face               = Fonts:getFace("cfont", sc(20))

        local dot_tw = TextWidget:new{
            text    = "•",
            face    = dot_face,
            fgcolor = SM.COLOR_MUTED,
        }
        local dot_w = dot_tw:getSize().w + sc(16)
        local col_w = math.floor((mw - dot_w) / 2)

        local session_col = VerticalGroup:new{
            align = "center",
            TextWidget:new{
                text      = session_str,
                face      = big_face,
                bold      = big_bold,
                fgcolor   = BLACK,
                max_width = col_w,
            },
            VerticalSpan:new{ width = sc(2) },
            TextWidget:new{
                text      = _("Session"),
                face      = label_face,
                bold      = label_bold,
                fgcolor   = SM.COLOR_MUTED,
                max_width = col_w,
            },
        }

        local today_col = VerticalGroup:new{
            align = "center",
            TextWidget:new{
                text      = today_str,
                face      = big_face,
                bold      = big_bold,
                fgcolor   = BLACK,
                max_width = col_w,
            },
            VerticalSpan:new{ width = sc(2) },
            TextWidget:new{
                text      = _("Today"),
                face      = label_face,
                bold      = label_bold,
                fgcolor   = SM.COLOR_MUTED,
                max_width = col_w,
            },
        }

        local session_sz = session_col:getSize()
        local today_sz   = today_col:getSize()
        local dot_sz     = dot_tw:getSize()
        local max_h      = math.max(session_sz.h, today_sz.h, dot_sz.h)

        return HorizontalGroup:new{
            align = "top",
            CenterContainer:new{
                dimen = Geom:new{ w = col_w, h = max_h },
                session_col,
            },
            CenterContainer:new{
                dimen = Geom:new{ w = dot_w, h = max_h },
                dot_tw,
            },
            CenterContainer:new{
                dimen = Geom:new{ w = col_w, h = max_h },
                today_col,
            },
        }
    end,
}

