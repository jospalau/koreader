--[[
Start-menu / hero micro-module: reading differential (ΔL).
See README.md in this directory for the module spec contract.

Shows how many hours ahead or behind a configurable h/day reading pace
you are this year. Positive = ahead, negative = behind.

Data comes from wpm_stat_data in statistics.sqlite3, the same query
used by TopBar:getReadThisYearSoFar(). TTL-cached at 30s. Works offline.

Also shows today's total reading time (from the DB + any live/open
session) to the right of ΔL, same source data as session_time.lua.
]]
local _ = require("lib/bookshelf_i18n").gettext

local STATS_TTL_S = 30
local _cache -- { at = <epoch>, value = <number> }

local PACE_KEY = "micromodule_reading_delta_pace" -- hours/day target
local function readPace()
    local Store = require("lib/bookshelf_settings_store")
    local v = tonumber(Store.read(PACE_KEY))
    return (v and v > 0) and v or 2
end

local function fmtPace(h)
    if h == math.floor(h) then
        return tostring(math.floor(h)) .. "h/d"
    end
    return string.format("%.1fh/d", h)
end

local function readDelta(pace)
    local now = os.time()
    if _cache and now - _cache.at < STATS_TTL_S and _cache.pace == pace then
        return _cache.value
    end
    local ok, result = pcall(function()
        local DataStorage = require("datastorage")
        local path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        local lfs = require("libs/libkoreader-lfs")
        if lfs.attributes(path, "mode") ~= "file" then return nil end
        local SQ3  = require("lua-ljsqlite3/init")
        local conn = SQ3.open(path, "ro")
        local val
        local ok_q, err = pcall(function()
            conn:exec("PRAGMA busy_timeout=200;")
            local exists = conn:rowexec(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='wpm_stat_data'")
            if not exists then val = nil; return end
            local yday = os.date("*t").yday
            local row = conn:rowexec(string.format([[
                SELECT sum(duration)
                FROM   wpm_stat_data
                WHERE  DATE(start_time,'unixepoch','localtime') >= DATE('now', '-%d day','localtime')
            ]], yday))
            local secs = tonumber(row) or 0
            val = math.ceil((secs / 3600) - (yday * pace))
        end)
        conn:close()
        if not ok_q then error(err) end
        return val
    end)
    if not ok then
        require("logger").warn("[bookshelf] reading_delta query failed:", result)
        result = nil
    end
    _cache = { at = now, value = result, pace = pace }
    return result
end

-- Today's total reading time (DB + live open session), same logic as
-- session_time.lua's getTodaySecs. Kept as its own copy with its own
-- cache so this module has no dependency on session_time.lua internals.
local _today_cache

local function dayStart(now)
    local t = os.date("*t", now)
    return os.time{ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
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

local function getTodaySecs()
    local now = os.time()
    local day_start = dayStart(now)

    if _today_cache and now - _today_cache.at < STATS_TTL_S and _today_cache.day_start == day_start then
        return _today_cache.secs
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
            local effective_start = math.max(sp.start_current_period, day_start)
            live = math.max(0, now - effective_start)
        end
    end)

    local total = db_secs + live
    _today_cache = { at = now, day_start = day_start, secs = total }
    return total
end

-- Shrinks font size until `text` fits within `max_w` at the given face,
-- same approach as session_time.lua's fitFontSize.
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

local function showSettings(ctx)
    local ButtonDialog = require("ui/widget/buttondialog")
    local UIManager    = require("ui/uimanager")
    local Store        = require("lib/bookshelf_settings_store")
    local dialog
    local cur_pace = readPace()
    local function apply(h)
        Store.save(PACE_KEY, h)
        _cache = nil
        UIManager:close(dialog)
        if ctx and ctx.menu and ctx.menu._reload then ctx.menu:_reload() end
        showSettings(ctx)
    end
    local function btn(h)
        return {
            text = (cur_pace == h and "\xE2\x9C\x93 " or "  ") .. fmtPace(h),
            callback = function()
                if cur_pace == h then return end
                apply(h)
            end,
        }
    end
    local function customBtn()
        return {
            text = _("Custom..."),
            callback = function()
                UIManager:close(dialog)
                local InputDialog = require("ui/widget/inputdialog")
                local input_dlg
                input_dlg = InputDialog:new{
                    title      = _("Hours per day target"),
                    input_type = "number",
                    input      = tostring(cur_pace),
                    buttons    = {{
                        {
                            text = _("Cancel"),
                            callback = function()
                                UIManager:close(input_dlg)
                                showSettings(ctx)
                            end,
                        },
                        {
                            text = _("Save"),
                            is_enter_default = true,
                            callback = function()
                                local v = tonumber(input_dlg:getInputText())
                                if v and v > 0 then apply(v) end
                                UIManager:close(input_dlg)
                            end,
                        },
                    }},
                }
                UIManager:show(input_dlg)
                input_dlg:onShowKeyboard()
            end,
        }
    end
    dialog = ButtonDialog:new{
        title        = _("Reading differential"),
        title_align  = "center",
        width_factor = 0.75,
        buttons      = {
            { { text = _("Daily target: ") .. fmtPace(cur_pace), enabled = false } },
            { btn(0.5), btn(1), btn(1.5), btn(2), btn(2.5) },
            { btn(3), btn(3.5), btn(4), btn(4.5), btn(5), customBtn() },
        },
    }
    UIManager:show(dialog)
end

return {
    key     = "reading_delta",
    title   = _("Reading differential"),
    summary = _("Hours ahead/behind your daily pace. Works offline."),
    show_settings = showSettings,

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

        local pace  = readPace()
        local delta = readDelta(pace)

        if delta == nil then
            return TextWidget:new{
                text      = _("Stats unavailable"),
                face      = Fonts:getFace("cfont", sc(15)),
                fgcolor   = SM.COLOR_MUTED,
                max_width = mw,
            }
        end

        local display = (delta > 0 and "+" or "") .. tostring(delta)
        local today_str = fmtTime(getTodaySecs())

        -- Reserve roughly half the module width for each side (minus the
        -- gap between them), then shrink each big number independently so
        -- neither block overflows or crowds the other. ΔL's "display" text
        -- is short (e.g. "-78") so it rarely needs shrinking, but Today's
        -- "Xh Ym" can be noticeably wider at the same font size.
        local gap        = sc(20)
        local half_w      = math.floor((mw - gap) / 2)
        local delta_sz    = fitFontSize(Fonts, display,   sc(40), sc(20), half_w, true)
        local today_sz    = fitFontSize(Fonts, today_str, sc(40), sc(20), half_w, true)
        local big_sz      = math.min(delta_sz, today_sz)

        local big_face, big_bold     = Fonts:getFace("cfont", big_sz, {bold=true})
        local label_face, label_bold = Fonts:getFace("cfont", sc(20), {bold=true})
        local sub_face               = Fonts:getFace("cfont", sc(13))
        -- Same sizes as the ΔL block so both feel like peers, not
        -- primary/secondary.
        local today_face, today_bold             = Fonts:getFace("cfont", big_sz, {bold=true})
        local today_label_face, today_label_bold = Fonts:getFace("cfont", sc(20), {bold=true})

        local big_tw = TextWidget:new{
            text    = display,
            face    = big_face,
            bold    = big_bold,
            fgcolor = BLACK,
        }
        local label_tw = TextWidget:new{
            text    = "ΔL",
            face    = label_face,
            bold    = label_bold,
            fgcolor = SM.COLOR_MUTED,
        }
        local pace_tw = TextWidget:new{
            text      = fmtPace(pace),
            face      = sub_face,
            fgcolor   = SM.COLOR_MUTED,
            max_width = mw,
        }

        -- ΔL baseline-aligned to the right of the number
        local dy = math.max(0, big_tw:getBaseline() - label_tw:getBaseline())
        local delta_block = HorizontalGroup:new{
            align = "top",
            big_tw,
            HorizontalSpan:new{ width = sc(8) },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = dy },
                label_tw,
            },
        }

        -- "Today" block: value stacked over its caption, same scale as
        -- the ΔL block, placed to its right.
        local today_block = VerticalGroup:new{
            align = "center",
            TextWidget:new{
                text    = today_str,
                face    = today_face,
                bold    = today_bold,
                fgcolor = BLACK,
            },
            VerticalSpan:new{ width = sc(2) },
            TextWidget:new{
                text    = _("Today"),
                face    = today_label_face,
                bold    = today_label_bold,
                fgcolor = SM.COLOR_MUTED,
            },
        }

        local row_h = math.max(delta_block:getSize().h, today_block:getSize().h)
        local header = HorizontalGroup:new{
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{ w = delta_block:getSize().w, h = row_h },
                delta_block,
            },
            HorizontalSpan:new{ width = gap },
            CenterContainer:new{
                dimen = Geom:new{ w = today_block:getSize().w, h = row_h },
                today_block,
            },
        }

        local header_w = header:getSize().w
        local pace_w   = pace_tw:getSize().w
        local content_w = math.max(header_w, pace_w)

        local col = VerticalGroup:new{
            align = "left",
            CenterContainer:new{
                dimen = Geom:new{ w = content_w, h = header:getSize().h },
                header,
            },
            VerticalSpan:new{ width = sc(4) },
            CenterContainer:new{
                dimen = Geom:new{ w = content_w, h = pace_tw:getSize().h },
                pace_tw,
            },
        }

        return CenterContainer:new{
            dimen = Geom:new{ w = mw, h = col:getSize().h },
            col,
        }
    end,
}
