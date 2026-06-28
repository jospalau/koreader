--[[
Start-menu / hero micro-module: reading differential (ΔL).
See README.md in this directory for the module spec contract.

Shows how many hours ahead or behind a configurable h/day reading pace
you are this year. Positive = ahead, negative = behind.

Data comes from wpm_stat_data in statistics.sqlite3, the same query
used by TopBar:getReadThisYearSoFar(). TTL-cached at 30s. Works offline.
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

        local big_face, big_bold     = Fonts:getFace("cfont", sc(40), {bold=true})
        local label_face, label_bold = Fonts:getFace("cfont", sc(20), {bold=true})
        local sub_face               = Fonts:getFace("cfont", sc(13))

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
        local header = HorizontalGroup:new{
            align = "top",
            big_tw,
            HorizontalSpan:new{ width = sc(8) },
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = dy },
                label_tw,
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

