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

local function dayStart(now)
    local t = os.date("*t", now)
    return os.time{ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
end

local STATS_TTL_S = 30
local _cache

local function getTodaySecs()
    local now = os.time()
    local day_start = dayStart(now)

    -- FIX: previously only keyed on STATS_TTL_S, so a render right after
    -- midnight (within the 30s window) could return a value computed for
    -- the previous calendar day. Invalidate as soon as the day rolls over.
    if _cache and now - _cache.at < STATS_TTL_S and _cache.day_start == day_start then
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
            -- FIX: previously used `now - start_current_period` unclamped,
            -- so a session spanning midnight (still open, not yet flushed
            -- to the DB) leaked yesterday's minutes into "Today". Clamp the
            -- effective start to the current day's midnight, matching how
            -- db_secs is already bounded by day_start in the SQL query.
            local effective_start = math.max(sp.start_current_period, day_start)
            live = math.max(0, now - effective_start)
        end
    end)

    local total = db_secs + live
    _cache = { at = now, day_start = day_start, secs = total }
    return total
end

local function fitFontSize(Fonts, text, max_sz, min_sz, max_w, bold)
    local sz = max_sz
    while sz > min_sz do
        local face, b = Fonts:getFace("cfont", sz, bold and {bold=true} or nil)
        local tw = require("ui/widget/textwidget"):new{
            text = text, face = face, bold = b }
        if tw:getSize().w <= max_w then return sz end
        sz = sz - 2
    end
    return min_sz
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

        local gap    = sc(24)
        local col_w  = math.floor((mw - gap) / 2)
        local col_w2 = mw - gap - col_w

        local session_sz_fit = fitFontSize(Fonts, session_str, sc(40), sc(18), col_w,  true)
        local today_sz_fit   = fitFontSize(Fonts, today_str,   sc(40), sc(18), col_w2, true)
        local big_sz         = math.min(session_sz_fit, today_sz_fit)
        local big_face, big_bold     = Fonts:getFace("cfont", big_sz, {bold=true})
        local label_face, label_bold = Fonts:getFace("cfont", sc(20), {bold=true})

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
                max_width = col_w2,
            },
            VerticalSpan:new{ width = sc(2) },
            TextWidget:new{
                text      = _("Today"),
                face      = label_face,
                bold      = label_bold,
                fgcolor   = SM.COLOR_MUTED,
                max_width = col_w2,
            },
        }

        local max_h = math.max(session_col:getSize().h, today_col:getSize().h)

        return HorizontalGroup:new{
            align = "top",
            CenterContainer:new{
                dimen = Geom:new{ w = col_w, h = max_h },
                session_col,
            },
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{
                dimen = Geom:new{ w = col_w2, h = max_h },
                today_col,
            },
        }
    end,
}

