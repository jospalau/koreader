--[[
Start-menu / hero micro-module: current session reading time.
Shows how long you have been reading in the current session,
total reading time today from the statistics DB, and total time on this book.
Uses topbar.start_session_time from the active ReaderUI instance.
Works offline.
]]
local _ = require("lib/bookshelf_i18n").gettext

local function getSessionSecs()
    local ok, ui = pcall(function()
        return require("apps/reader/readerui").instance
    end)
    if not ok or not ui then return 0 end
    local topbar = ui.view and ui.view.topbar
    if not topbar or not topbar.start_session_time then return 0 end
    local secs = os.time() - topbar.start_session_time
    return secs > 0 and secs or 0
end

local function getBookSecs()
    local ok, ui = pcall(function()
        return require("apps/reader/readerui").instance
    end)
    if not ok or not ui then return nil end
    local topbar = ui.view and ui.view.topbar
    if not topbar or not topbar.start_session_time then return nil end
    local session_secs = os.time() - topbar.start_session_time
    local total_secs = (topbar.initial_total_time_book or 0) + session_secs
    return total_secs > 0 and total_secs or nil
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

    -- Only the DB sum is expensive/cacheable. `live` (the still-open
    -- session/stat period) must be recomputed every call, or it goes
    -- stale for up to STATS_TTL_S and drifts away from getSessionSecs(),
    -- which is never cached. Caching `db_secs + live` together was the
    -- bug: "Today" would freeze mid-render-cycle while "Session" kept
    -- ticking, making them disagree by a few seconds.
    local db_secs
    if _cache and now - _cache.at < STATS_TTL_S and _cache.day_start == day_start then
        db_secs = _cache.db_secs
    else
        db_secs = 0
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
        _cache = { at = now, day_start = day_start, db_secs = db_secs }
    end

    local live = 0
    pcall(function()
        local ReaderUI = require("apps/reader/readerui")
        local sp = ReaderUI.instance and ReaderUI.instance.statistics
        if sp and sp.start_current_period and sp.start_current_period > 0 then
            local effective_start = math.max(sp.start_current_period, day_start)
            live = math.max(0, now - effective_start)
        end
    end)

    return db_secs + live
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
    key     = "session_time",
    title   = _("Session time"),
    summary = _("Time read in the current session, today and on this book. Works offline."),

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

        local session_str = fmtTime(secs)
        local today_str   = fmtTime(getTodaySecs())
        local book_str    = fmtTime(getBookSecs())

        local gap    = sc(16)
        local col_w1 = math.floor((mw - 2 * gap) / 3)
        local col_w2 = col_w1
        local col_w3 = mw - 2 * gap - col_w1 - col_w2

        local big_sz = math.min(
            fitFontSize(Fonts, session_str, sc(40), sc(18), col_w1, true),
            fitFontSize(Fonts, today_str,   sc(40), sc(18), col_w2, true),
            fitFontSize(Fonts, book_str,    sc(40), sc(18), col_w3, true)
        )
        local big_face, big_bold     = Fonts:getFace("cfont", big_sz, {bold=true})
        local label_face, label_bold = Fonts:getFace("cfont", sc(20), {bold=true})

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

        local session_col = makeCol(session_str, _("Session"),   col_w1)
        local today_col   = makeCol(today_str,   _("Today"),     col_w2)
        local book_col    = makeCol(book_str,    _("This book"), col_w3)

        local max_h = math.max(session_col:getSize().h, today_col:getSize().h, book_col:getSize().h)

        return HorizontalGroup:new{
            align = "top",
            CenterContainer:new{ dimen = Geom:new{ w = col_w1, h = max_h }, session_col },
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{ dimen = Geom:new{ w = col_w2, h = max_h }, today_col },
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{ dimen = Geom:new{ w = col_w3, h = max_h }, book_col },
        }
    end,
}
