--[[
Start-menu module: reading time breakdown — today, this month, last month, this year.
]]
local _ = require("lib/bookshelf_i18n").gettext

local function fmtDuration(secs)
    secs = tonumber(secs) or 0
    local h = secs / 3600
    if h >= 24 then
        return string.format("%.1fd", h / 24)
    elseif h >= 1 then
        return string.format("%.1fh", h)
    else
        return string.format("%dm", math.floor(secs / 60))
    end
end

local STATS_TTL_S = 30
local _cache

local function queryStats()
    local DataStorage = require("datastorage")
    local path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(path, "mode") ~= "file" then return nil end
    local ok, res = pcall(function()
        local SQ3 = require("lua-ljsqlite3/init")
        local conn = SQ3.open(path, "ro")
        local out
        local ok_q, err = pcall(function()
            conn:exec("PRAGMA busy_timeout=200;")
            local now = os.time()
            local t = os.date("*t", now)

            local day_start   = os.time{ year=t.year, month=t.month, day=t.day, hour=0, min=0, sec=0 }
            local month_start = os.time{ year=t.year, month=t.month, day=1,     hour=0, min=0, sec=0 }
            local yesterday_start = day_start - 86400
            local yesterday_end   = day_start - 1
            local year_start  = os.time{ year=t.year, month=1,       day=1,     hour=0, min=0, sec=0 }
            local lm = t.month - 1 == 0 and 12 or t.month - 1
            local ly = t.month - 1 == 0 and t.year - 1 or t.year
            local lmonth_start = os.time{ year=ly,    month=lm,      day=1,     hour=0, min=0, sec=0 }
            local lmonth_end   = month_start - 1

            local stmt = conn:prepare([[
                SELECT COALESCE(SUM(duration), 0)
                FROM page_stat_data WHERE start_time >= ? AND start_time <= ?]])

            local function query(from, to)
                local row = stmt:bind(from, to):step()
                stmt:clearbind():reset()
                return tonumber(row[1]) or 0
            end

            out = {
                today_secs   = query(day_start,    now),
                yesterday_secs = query(yesterday_start, yesterday_end),
                month_secs   = query(month_start,  now),
                lmonth_secs  = query(lmonth_start, lmonth_end),
                year_secs    = query(year_start,   now),
            }
            stmt:close()
        end)
        conn:close()
        if not ok_q then error(err) end
        return out
    end)
    if not ok then
        require("logger").warn("[bookshelf] reading_time_breakdown unavailable:", res)
        return nil
    end
    return res
end

local function readStats()
    if _cache and os.time() - _cache.at < STATS_TTL_S then
        return _cache.data or nil
    end
    local result = queryStats()
    _cache = { at = os.time(), data = result or false }
    return result
end

return {
    key     = "reading_time_breakdown",
    title   = _("Reading time"),
    summary = _("Today / this month / last month / this year. From KOReader statistics."),
    render  = function(ctx)
        local width, scale_pct, _preview, avail_h = ctx.width, ctx.scale, ctx.preview, ctx.height
        local Fonts           = require("lib/bookshelf_fonts")
        local TextWidget      = require("ui/widget/textwidget")
        local VerticalGroup   = require("ui/widget/verticalgroup")
        local VerticalSpan    = require("ui/widget/verticalspan")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Geom            = require("ui/geometry")
        local SM              = require("lib/bookshelf_start_menu_modules")

        local function sc(n) return math.max(1, math.floor(n * (scale_pct or 100) / 100 + 0.5)) end
        local BLACK = SM.COLOR_PRIMARY
        local mw    = math.max(50, width)

        local data = readStats()
        local ROWS = {
            { label = _("Today"),      secs = data and data.today_secs  or 0 },
            { label = _("Yesterday"),  secs = data and data.yesterday_secs or 0 },
            { label = _("Month"),      secs = data and data.month_secs  or 0 },
            { label = _("Last month"), secs = data and data.lmonth_secs or 0 },
            { label = _("Year"),       secs = data and data.year_secs   or 0 },
        }

        local head_face        = Fonts:getFace("cfont", sc(12))
        local count_face, count_bold = Fonts:getFace("cfont", sc(18), {bold=true})
        local n     = #ROWS
        local col_w = math.floor(mw / n)

        local row = HorizontalGroup:new{ align = "top" }
        for _, r in ipairs(ROWS) do
            local col = VerticalGroup:new{
                align = "center",
                TextWidget:new{ text = r.label,          face = head_face,  fgcolor = SM.COLOR_MUTED, max_width = col_w },
                VerticalSpan:new{ width = sc(2) },
                TextWidget:new{ text = fmtDuration(r.secs), face = count_face, bold = count_bold, fgcolor = BLACK, max_width = col_w },
            }
            row[#row + 1] = CenterContainer:new{
                dimen = Geom:new{ w = col_w, h = col:getSize().h }, col }
        end

        return VerticalGroup:new{ align = "left", row }
    end,
}
