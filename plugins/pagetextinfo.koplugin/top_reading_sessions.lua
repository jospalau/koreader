local logger = require("logger")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Screen = Device.screen
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")

-- ── Performance logging ──────────────────────────────────────────────────────
-- Timings go to the log (crash.log) with the prefix [LS-PERF]:
--     grep LS-PERF crash.log
-- Kept in one table to use a single top-level local.

local DEBUG_PERF = false  -- true: log timings; false: no timing work at all

local Perf = { open_t0 = nil }  -- open_t0: start of the opening (set by the event handler)

function Perf.start()
    if not DEBUG_PERF then return nil end
    return require("ui/time").now()
end

function Perf.log(label, start)
    if not DEBUG_PERF or not start then return end
    local UITime = require("ui/time")
    logger.info(string.format("[LS-PERF] %-40s %8.1f ms", label,
        UITime.to_ms(UITime.since(start))))
end

local DEVICE_NAMES = {
    [0]   = _("Unknown device"),
    [1]   = "Kobo Libra 2",
    [2]   = "Kobo Sage",
    [3]   = "Kobo Clara 2E",
    [4]   = "Kindle Paperwhite 6",
    [5]   = "Kindle Basic",
    [6]   = "Boox Palma",
    [7]   = "PocketBook",
    [8]   = "Likebook Ares",
    [9]   = "Kobo Elipsa 2E",
    [10]  = "Kobo Clara BW",
    [11]  = "Kobo Clara Colour",
    [12]  = "Kobo Libra Colour",
    [97]  = "Xiaomi 14T Pro",
    [98]  = "Boox Go6",
    [99]  = _("Physical book"),
    [100] = _("Emulator"),
}

local MONTH_NAMES = {
    _("Jan"), _("Feb"), _("Mar"), _("Apr"), _("May"), _("Jun"),
    _("Jul"), _("Aug"), _("Sep"), _("Oct"), _("Nov"), _("Dec"),
}

local ShowLongestSessionsWindow = InputContainer:extend{
    modal = true,
    name = "show_longest_sessions_window",
}

-- ── Palette ──────────────────────────────────────────────────────────────────
-- A small set of grays so every view looks the same.

local function gray(v) return Blitbuffer.Color8(v) end

local COLOR_TEXT      = Blitbuffer.COLOR_BLACK
local COLOR_MUTED     = gray(110)  -- secondary text
local COLOR_ACCENT    = gray(30)   -- highlighted bars and dots
local COLOR_BAR       = gray(150)  -- regular bars and card borders
local COLOR_TRACK     = gray(225)  -- grid lines, separators and empty tracks
local COLOR_SOFT      = gray(238)  -- card background and empty heatmap cells

-- ── Fonts and spacing ────────────────────────────────────────────────────────
-- One face and one scale of sizes (in points) for the whole window.

local FONT_FACE = "cfont"

local FONT_HERO        = 34  -- shelf total
local FONT_BIG         = 24  -- book title, biggest value of a card
local FONT_SUBTITLE    = 18  -- series, year and publisher line, shelf label
local FONT_TITLE       = 20  -- window title
local FONT_LABEL       = 16  -- year of the per-year rows
local FONT_TEXT        = 15  -- rows, titles of the lists
local FONT_SUMMARY     = 14  -- summary lines, captions of a card
local FONT_CAPTION     = 13  -- counter, second line of a row, chart labels
local FONT_SMALL       = 12  -- second line of the per-year rows, smallest value
local FONT_TINY        = 11  -- heatmap labels
local FONT_CAPTION_MIN = 9   -- smallest caption of a card

local function getFace(size)
    return Font:getFace(FONT_FACE, size)
end

-- Spacing scale (scaled to the screen)
local SPACE = {
    xs = Screen:scaleBySize(2),
    s  = Screen:scaleBySize(4),
    m  = Screen:scaleBySize(6),
    l  = Screen:scaleBySize(8),
    xl = Screen:scaleBySize(10),
}

-- ── Formatting helpers ───────────────────────────────────────────────────────

local SECONDS_PER_DAY = 86400

local DOT = "\xC2\xB7"
local SUMMARY_SEPARATOR = "  " .. DOT .. "  "  -- between the parts of a summary line
local TITLE_SEPARATOR = " " .. DOT .. " "       -- between a title and its year
local DELTA_L = "\xCE\x94L"                      -- reading differential

local function formatDateTime(ts)
    ts = math.floor(tonumber(ts) or 0)
    local t = os.date("*t", ts)
    return string.format("%02d/%02d/%04d %02d:%02d",
        t.day, t.month, t.year, t.hour, t.min)
end

local function secondsToHMS(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h >= 24 then
        local d = math.floor(h / 24)
        h = h % 24
        return string.format("%dd %02d:%02d:%02d", d, h, m, s)
    end
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- Compact "12h 05m" form, used in the chart summary
local function secondsToHM(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
end

-- "3d 05h" from one day up, "12h 05m" below (used for the monthly totals)
local function secondsToDH(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    local h = math.floor(seconds / 3600)
    if h >= 24 then
        return string.format("%dd %02dh", math.floor(h / 24), h % 24)
    end
    return string.format("%dh %02dm", h, math.floor((seconds % 3600) / 60))
end

-- "1h 8m" / "25m" (the cards)
local function secondsToShortHM(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local h, m = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

-- "2h" for a whole hour, otherwise as secondsToShortHM (reading stats module)
local function secondsToStatsTime(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local h, m = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)
    if h > 0 and m == 0 then return string.format("%dh", h) end
    return secondsToShortHM(seconds)
end

-- "12.5h" / "1.2d" / "40m" (reading time module)
local function secondsToBreakdownTime(seconds)
    seconds = tonumber(seconds) or 0
    local h = seconds / 3600
    if h >= 24 then return string.format("%.1fd", h / 24) end
    if h >= 1 then return string.format("%.1fh", h) end
    return string.format("%dm", math.floor(seconds / 60))
end

-- "2h/d" / "1.5h/d"
local function formatPace(h)
    if h == math.floor(h) then return string.format("%dh/d", h) end
    return string.format("%.1fh/d", h)
end

-- Hours with one decimal below 10, rounded above (keeps chart labels short)
local function formatHours(h)
    if h >= 10 then
        return string.format("%d", math.floor(h + 0.5))
    elseif h == math.floor(h) then
        return string.format("%d", h)
    end
    return string.format("%.1f", h)
end

-- Rounds a value up to a "nice" axis maximum (1, 2, 5 times a power of ten)
local function niceCeil(v)
    if v <= 0 then return 1 end
    local exp = 10 ^ math.floor(math.log(v) / math.log(10))
    local f = v / exp
    local nice = (f <= 1 and 1) or (f <= 2 and 2) or (f <= 5 and 5) or 10
    return nice * exp
end

-- ── Shared helpers ───────────────────────────────────────────────────────────

local ROW_HEIGHT_TALL = Screen:scaleBySize(66)   -- sessions (title + date + bar)
local ROW_HEIGHT_NORMAL = Screen:scaleBySize(46) -- the rest of the views

local function makeVerticalSpacing(w_padding_internal, h)
    h = h or 1
    return VerticalSpan:new{ width = math.floor(w_padding_internal * h) }
end

local function makeSeparator(w_width)
    return LineWidget:new{
        background = COLOR_TRACK,
        dimen = Geom:new{
            w = w_width - ScrollableContainer:getScrollbarWidth(),
            h = Size.line.thin,
        },
    }
end

-- The muted one-line summary under a chart, a list or a card.
local function makeSummaryLine(w_width, text)
    return TextWidget:new{
        text = text,
        face = getFace(FONT_SUMMARY),
        fgcolor = COLOR_MUTED,
        max_width = w_width,
    }
end

local function getStatsDbPath()
    return DataStorage:getSettingsDir() .. "/statistics.sqlite3"
end

-- The reader instance, or nil outside the reader.
local function getReaderUI()
    local ok, ui = pcall(function() return require("apps/reader/readerui").instance end)
    return ok and ui or nil
end

-- Runs a query on the statistics database and returns its rows, each one
-- turned into an item by `map` (which gets the row table, reused between
-- rows, so it must copy what it needs; it also gets the row number). Returns
-- nil and a message when the database cannot be read; the connection is
-- closed in every case.
local function queryAll(sql_stmt, map)
    local t0 = Perf.start()
    local SQ3 = require("lua-ljsqlite3/init")
    local items = {}
    local ok, err = pcall(function()
        local conn = SQ3.open(getStatsDbPath())
        local ok_query, err_query = pcall(function()
            local stmt = conn:prepare(sql_stmt)
            local row = {}
            while stmt:step(row) do
                items[#items + 1] = map(row, #items + 1)
            end
            stmt:close()
        end)
        conn:close()
        if not ok_query then error(err_query, 0) end
    end)
    if not ok then
        logger.warn("longest sessions: query failed:", err)
        return nil, _("Could not read the statistics database")
    end
    if DEBUG_PERF then
        Perf.log("queryAll (" .. #items .. " rows) " .. (sql_stmt:gsub("%s+", " ")):sub(1, 40), t0)
    end
    return items
end

-- Swipes left and right change the view, so the list must not take them.
local SwipePassthroughScrollable = ScrollableContainer:extend{}

function SwipePassthroughScrollable:onScrollableSwipe(arg, ges)
    if ges.direction == "east" or ges.direction == "west" then
        return false
    end
    -- A swipe down closes the window, unless the content is taller than the
    -- list: then it scrolls.
    if ges.direction == "south" then
        local content = self[1]
        local content_h = content and content.getSize and content:getSize().h or 0
        if content_h <= self.dimen.h then return false end
    end
    return ScrollableContainer.onScrollableSwipe(self, arg, ges)
end

-- ── Small custom widgets ─────────────────────────────────────────────────────

-- A horizontal pill, used as the progress bar under each row.
local PillBar = Widget:extend{
    width = 0,
    height = 0,
    color = COLOR_BAR,
}

function PillBar:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function PillBar:getSize()
    return self.dimen
end

function PillBar:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRoundedRect(x, y, self.width, self.height, self.color, math.floor(self.height / 2))
end

-- A rounded progress track: a light pill with a darker one filling `ratio` of it.
local ProgressTrack = Widget:extend{
    width = 0,
    height = 0,
    ratio = 0,
    color = COLOR_BAR,
}

function ProgressTrack:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function ProgressTrack:getSize()
    return self.dimen
end

function ProgressTrack:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local radius = math.floor(self.height / 2)
    bb:paintRoundedRect(x, y, self.width, self.height, COLOR_TRACK, radius)
    if self.ratio > 0 then
        local w = math.max(self.height, math.floor(self.width * math.min(self.ratio, 1)))
        bb:paintRoundedRect(x, y, w, self.height, self.color, radius)
    end
end

-- The "page" dots at the bottom: the current view is a longer, darker pill.
local PagerDots = Widget:extend{
    count = 1,
    current = 1,
}

function PagerDots:init()
    self.dot = SPACE.m
    self.gap = SPACE.m
    self.active_w = self.dot * 3
    self.dimen = Geom:new{
        w = (self.count - 1) * (self.dot + self.gap) + self.active_w,
        h = self.dot,
    }
end

function PagerDots:getSize()
    return self.dimen
end

function PagerDots:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local cx = x
    for i = 1, self.count do
        local active = (i == self.current)
        local w = active and self.active_w or self.dot
        bb:paintRoundedRect(cx, y, w, self.dot, active and COLOR_ACCENT or COLOR_TRACK, math.floor(self.dot / 2))
        cx = cx + w + self.gap
    end
end

-- Bar chart with one slot per value (months, years...): value labels over the
-- bars, labels under them, and a light grid with an axis in hours.
local BarChart = Widget:extend{
    width = 0,
    height = 0,
    values = nil,      -- one number (hours) per slot
    labels = nil,      -- one label per slot
    current = nil,     -- index of the slot to highlight
    font_size = FONT_CAPTION,
}

function BarChart:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.count = #self.values
    local face = getFace(self.font_size)

    local max_value = 0
    for _i, v in ipairs(self.values) do
        if v > max_value then max_value = v end
    end
    self.y_max = niceCeil(max_value)

    self.month_widgets, self.value_widgets, self.tick_widgets = {}, {}, {}
    for i = 1, self.count do
        self.month_widgets[i] = TextWidget:new{
            text = self.labels[i],
            face = face,
            bold = (i == self.current),
            fgcolor = (i == self.current) and COLOR_TEXT or COLOR_MUTED,
        }
        if self.values[i] > 0 then
            self.value_widgets[i] = TextWidget:new{
                text = formatHours(self.values[i]),
                face = face,
                fgcolor = COLOR_TEXT,
            }
        end
    end

    -- Axis ticks: 0, half and full scale
    self.axis_w = 0
    for i = 0, 2 do
        local tw = TextWidget:new{ text = formatHours(self.y_max * i / 2), face = face, fgcolor = COLOR_MUTED }
        self.tick_widgets[i + 1] = tw
        self.axis_w = math.max(self.axis_w, tw:getSize().w)
    end
    self.gap = SPACE.m
    self.axis_w = self.axis_w + self.gap
    self.label_h = self.month_widgets[1]:getSize().h
end

function BarChart:getSize()
    return self.dimen
end

function BarChart:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y

    local top_pad = self.label_h + SPACE.s  -- room for the value labels
    local plot_top = y + top_pad
    local plot_h = self.height - top_pad - self.label_h - self.gap
    local plot_x = x + self.axis_w
    local plot_w = self.width - self.axis_w

    -- Grid lines (0, 1/2 and full scale) with their labels
    for i = 0, 2 do
        local gy = plot_top + plot_h - math.floor(plot_h * i / 2)
        bb:paintRect(plot_x, gy, plot_w, Size.line.thin, i == 0 and COLOR_BAR or COLOR_TRACK)
        local tw = self.tick_widgets[i + 1]
        local sz = tw:getSize()
        tw:paintTo(bb, plot_x - self.gap - sz.w + self.gap, gy - math.floor(sz.h / 2))
    end

    -- Bars, value labels and slot labels
    local slot = plot_w / self.count
    local bar_w = math.floor(slot * 0.58)
    local min_h = Screen:scaleBySize(3)
    for i = 1, self.count do
        local cx = plot_x + math.floor((i - 0.5) * slot)
        local value = self.values[i]
        if value > 0 then
            local h = math.max(min_h, math.floor(plot_h * value / self.y_max))
            local bx = cx - math.floor(bar_w / 2)
            local by = plot_top + plot_h - h
            local color = (i == self.current) and COLOR_ACCENT or COLOR_BAR
            local radius = math.min(math.floor(bar_w / 3), math.floor(h / 2))
            if radius >= 1 then
                bb:paintRoundedRect(bx, by, bar_w, h, color, radius)
            else
                bb:paintRect(bx, by, bar_w, h, color)
            end
            local vw = self.value_widgets[i]
            local vs = vw:getSize()
            vw:paintTo(bb, cx - math.floor(vs.w / 2), by - vs.h - SPACE.xs)
        end
        local mw = self.month_widgets[i]
        local ms = mw:getSize()
        mw:paintTo(bb, cx - math.floor(ms.w / 2), y + self.height - self.label_h)
    end
end

function BarChart:free()
    for _i, list in ipairs({ self.month_widgets, self.value_widgets, self.tick_widgets }) do
        for _k, w in pairs(list) do w:free() end
    end
end

-- ── View builder ─────────────────────────────────────────────────────────────
-- Most views are the same list: something on the left, the time on the right,
-- and a thin bar under the label showing the share of the longest item.
-- A view says its query (sql), how a row becomes an item (map), what to show
-- on the left (left) and how tall a row is; this builds the rows from that.
-- (A view with its own `build` function, like the heatmap, does not use it.)

local function buildRows(view, w_width)
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local padding = SPACE.xl * 2
    local time_widget_width = Screen:scaleBySize(90)
    local bar_max_width = w_width - scrollbar_width - padding - time_widget_width - SPACE.xl
    local bar_height = SPACE.s
    local bar_indent = view.bar_indent or 0  -- the bar lines up with the text, not with a rank number

    -- `sql` can be a function, for queries that depend on the current date
    local sql = type(view.sql) == "function" and view.sql() or view.sql
    local items, err = queryAll(sql, view.map)
    if not items then return nil, err end
    if #items == 0 then return nil, type(view.empty) == "function" and view.empty() or view.empty end

    local longest = 0
    for _i, item in ipairs(items) do
        longest = math.max(longest, item.duration or 0)
    end

    local ctx = { max_width = bar_max_width }
    local row_height = view.row_height
    local rows = VerticalGroup:new{}

    for i, item in ipairs(items) do
        local ratio = longest > 0 and (item.duration or 0) / longest or 0
        local left = VerticalGroup:new{
            align = "left",
            view.left(item, ctx),
            VerticalSpan:new{ width = SPACE.s },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = bar_indent },
                PillBar:new{
                    width = math.max(bar_height, math.floor((bar_max_width - bar_indent) * ratio)),
                    height = bar_height,
                    color = (i == 1) and COLOR_ACCENT or COLOR_BAR,
                },
            },
        }

        rows[#rows + 1] = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = bar_max_width, h = row_height },
                left,
            },
            HorizontalSpan:new{ width = SPACE.xl },
            RightContainer:new{
                dimen = Geom:new{ w = time_widget_width, h = row_height },
                TextWidget:new{
                    text = secondsToHMS(item.duration),
                    face = getFace(FONT_TEXT),
                    bold = true,
                },
            },
        }
        if i < #items then
            rows[#rows + 1] = makeSeparator(w_width)
        end
    end

    return rows, #items, row_height, items
end

-- ── Chart views ──────────────────────────────────────────────────────────────
-- Shared body of the chart views: the chart and a one-line summary under it.

local function chartBody(w_width, chart_args, summary_text)
    chart_args.width = w_width
    chart_args.height = math.min(Screen:scaleBySize(250), math.floor(Screen:getHeight() * 0.4))
    chart_args.font_size = FONT_CAPTION
    return {
        BarChart:new(chart_args),
        makeVerticalSpacing(SPACE.l),
        makeSummaryLine(w_width, summary_text),
    }
end

-- Bar chart of the hours read in each month of the current year.
local function buildMonthlyHoursView(w_width)
    local now = os.date("*t")
    local year_start = os.time({ year = now.year, month = 1, day = 1, hour = 0 })

    -- seconds read in each month of this year (local time)
    local items, err = queryAll(string.format([[
        SELECT CAST(strftime('%%m', start_time, 'unixepoch', 'localtime') AS INTEGER), SUM(duration)
        FROM wpm_stat_data
        WHERE start_time >= %d
        GROUP BY 1
    ]], year_start), function(row)
        return { month = tonumber(row[1]), seconds = tonumber(row[2]) or 0 }
    end)
    if not items then return nil, err end
    if #items == 0 then return nil, _("No reading data found for this year") end

    local values, total, best = {}, 0, 1
    for i = 1, 12 do values[i] = 0 end
    for _i, item in ipairs(items) do
        if item.month and item.month >= 1 and item.month <= 12 then
            values[item.month] = item.seconds / 3600
            total = total + item.seconds
        end
    end
    for i = 2, 12 do
        if values[i] > values[best] then best = i end
    end

    local summary = string.format("%s %s" .. SUMMARY_SEPARATOR .. "%s %s (%s)",
        _("Total"), secondsToDH(total),
        _("Best:"), MONTH_NAMES[best], secondsToDH(values[best] * 3600))
    return chartBody(w_width, {
        values = values,
        labels = MONTH_NAMES,
        current = now.month,
    }, summary)
end

-- ── Per-year views ───────────────────────────────────────────────────────────

local MAX_YEARS = 8
-- A day counts as read only with at least this much reading in total, so
-- opening a book for a few seconds does not add a day.
local MIN_DAY_SECONDS = 300

local function isLeapYear(y)
    return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
end

-- Shared layout of the per-year views, one row per year (newest first):
-- the year, a track filled with `ratio`, and two lines on the right
-- (`main` in bold, `sub` small). entries = { { year, ratio, main, sub }, ... }
local function buildYearRows(w_width, entries, summary_text)
    local now = os.date("*t")
    local gap = SPACE.xl
    local row_h = Screen:scaleBySize(48)
    local year_w = Screen:scaleBySize(54)
    local count_w = Screen:scaleBySize(84)
    local track_w = w_width - year_w - count_w - 2 * gap
    local face = getFace(FONT_LABEL)
    local face_small = getFace(FONT_SMALL)

    local rows = VerticalGroup:new{}
    for _i, e in ipairs(entries) do
        local is_current = (e.year == now.year)
        rows[#rows + 1] = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = year_w, h = row_h },
                TextWidget:new{
                    text = tostring(e.year),
                    face = face,
                    bold = true,
                    fgcolor = is_current and COLOR_TEXT or COLOR_MUTED,
                },
            },
            ProgressTrack:new{
                width = track_w,
                height = Screen:scaleBySize(14),
                ratio = e.ratio,
                color = is_current and COLOR_ACCENT or COLOR_BAR,
            },
            HorizontalSpan:new{ width = gap },
            RightContainer:new{
                dimen = Geom:new{ w = count_w, h = row_h },
                VerticalGroup:new{
                    align = "right",
                    TextWidget:new{ text = e.main, face = face, bold = true },
                    TextWidget:new{ text = e.sub, face = face_small, fgcolor = COLOR_MUTED },
                },
            },
        }
    end

    return {
        rows,
        makeVerticalSpacing(SPACE.l),
        makeSummaryLine(w_width, summary_text),
    }
end

-- Days per year: the share of the year's days that had reading.
local function buildDaysPerYearView(w_width)
    -- number of different days with enough reading in each year (local time)
    local items, err = queryAll(string.format([[
        SELECT year, COUNT(*) FROM (
            SELECT CAST(strftime('%%Y', start_time, 'unixepoch', 'localtime') AS INTEGER) AS year,
                   strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS day
            FROM wpm_stat_data
            WHERE start_time > 0
            GROUP BY day
            HAVING SUM(duration) >= %d
        )
        GROUP BY year
        ORDER BY year DESC
        LIMIT %d
    ]], MIN_DAY_SECONDS, MAX_YEARS), function(row)
        return { year = tonumber(row[1]), days = tonumber(row[2]) or 0 }
    end)
    if not items then return nil, err end
    if #items == 0 then return nil, _("No reading data found") end

    local entries, total, best = {}, 0, items[1]
    for _i, item in ipairs(items) do
        total = total + item.days
        if item.days > best.days then best = item end
        local ratio = item.days / (isLeapYear(item.year) and 366 or 365)
        entries[#entries + 1] = {
            year = item.year,
            ratio = ratio,
            main = string.format("%dd", item.days),
            sub = string.format("%d%%", math.floor(ratio * 100 + 0.5)),
        }
    end
    local summary = string.format("%s %d %s" .. SUMMARY_SEPARATOR .. "%s %d (%d)",
        _("Total"), total, _("days"), _("Best:"), best.year, best.days)
    return buildYearRows(w_width, entries, summary)
end

-- Days read per year: all the reading time of each year added up and shown
-- in days (24 hours each). The track is relative to the best year.
local function buildDaysReadPerYearView(w_width)
    local items, err = queryAll(string.format([[
        SELECT CAST(strftime('%%Y', start_time, 'unixepoch', 'localtime') AS INTEGER) AS year,
               SUM(duration)
        FROM wpm_stat_data
        WHERE start_time > 0
        GROUP BY year
        ORDER BY year DESC
        LIMIT %d
    ]], MAX_YEARS), function(row)
        return { year = tonumber(row[1]), seconds = tonumber(row[2]) or 0 }
    end)
    if not items then return nil, err end
    if #items == 0 then return nil, _("No reading data found") end

    local total, best = 0, items[1]
    for _i, item in ipairs(items) do
        total = total + item.seconds
        if item.seconds > best.seconds then best = item end
    end
    local entries = {}
    for _i, item in ipairs(items) do
        entries[#entries + 1] = {
            year = item.year,
            ratio = best.seconds > 0 and item.seconds / best.seconds or 0,
            main = secondsToDH(item.seconds),
            sub = string.format("%.1f %s", item.seconds / SECONDS_PER_DAY, _("days")),
        }
    end
    local summary = string.format("%s %s" .. SUMMARY_SEPARATOR .. "%s %d (%s)",
        _("Total"), secondsToDH(total), _("Best:"), best.year, secondsToDH(best.seconds))
    return buildYearRows(w_width, entries, summary)
end

-- ── Reading heatmap ──────────────────────────────────────────────────────────
-- Calendar heatmap drawn with the same look as the charts: rounded cells,
-- the same grays, month names on top and a light legend. One column per week,
-- one row per weekday. The view stacks one grid per year, the last
-- HEATMAP_YEARS years, each one from January 1st to December 31st. In the
-- current year the days still to come are drawn as an outline (like in the
-- month view). All of them share the same color scale and one legend.

local HEATMAP_WEEK_STARTS_ON_SUNDAY = false
local HEATMAP_YEARS = 4  -- years shown, newest first
-- Columns of the widest possible year (366 days starting on the last weekday
-- of the week = 54 weeks). Every grid sizes its cells for this many columns,
-- so all years show the same square size, whatever their number of weeks.
local HEATMAP_MAX_COLS = 54

-- Reading time of each day of the week over ALL the saved sessions (in days of 24 hours): which days you like to read most. The second look
-- of the "Days Read per Year" window (a tap switches, see ShowLongestSessionsWindow:onTapClose). A session counts on
-- the day it started.
local function buildWeekdaysView(w_width)
    local items, err = queryAll([[
        SELECT CAST(strftime('%w', start_time, 'unixepoch', 'localtime') AS INTEGER), SUM(duration)
        FROM wpm_stat_data
        WHERE start_time > 0
        GROUP BY 1
    ]], function(row)
        return { wday = tonumber(row[1]), seconds = tonumber(row[2]) or 0 }
    end)
    if not items then return nil, err end
    if #items == 0 then return nil, _("No reading data found") end

    -- strftime %w: 0 is Sunday. The chart starts on the first day of the week of the other views.
    local week_start = HEATMAP_WEEK_STARTS_ON_SUNDAY and 0 or 1
    local by_wday = {}
    for _i, item in ipairs(items) do by_wday[item.wday] = item.seconds end

    local values, labels, total, best = {}, {}, 0, 1
    for i = 1, 7 do
        local wday = (week_start + i - 1) % 7
        local seconds = by_wday[wday] or 0
        values[i] = seconds / SECONDS_PER_DAY   -- days of 24 hours, as the years look of this window
        total = total + seconds
        -- 2024-01-07 was a Sunday: the short name of the day, in the language of the system
        labels[i] = os.date("%a", os.time({ year = 2024, month = 1, day = 7 + wday, hour = 12 }))
        if values[i] > values[best] then best = i end
    end
    if total <= 0 then return nil, _("No reading data found") end

    local summary = string.format("%s %s %.1f %s (%d%%)",
        _("Best:"), labels[best], values[best], _("days"),
        math.floor(values[best] * SECONDS_PER_DAY * 100 / total + 0.5))
    return chartBody(w_width, {
        values = values,
        labels = labels,
        current = best,
    }, summary)
end

-- The "Days Read per Year" window has two looks (parent.days_mode): the days read in each year, or the days of the week.
local function buildDaysReadChartView(w_width, parent)
    if parent and parent.days_mode == "weekdays" then return buildWeekdaysView(w_width) end
    return buildDaysReadPerYearView(w_width)
end

-- No reading, then 0-25%, 25-50%, 50-75% and 75-100% of the busiest day
local HEAT_COLORS = { COLOR_SOFT, gray(200), gray(155), gray(100), COLOR_ACCENT }
local DAY_LETTERS = { _("S"), _("M"), _("T"), _("W"), _("T"), _("F"), _("S") } -- Sunday first

local function heatLevel(seconds, max_seconds)
    if seconds <= 0 or max_seconds <= 0 then return 1 end
    local r = seconds / max_seconds
    return (r <= 0.25 and 2) or (r <= 0.5 and 3) or (r <= 0.75 and 4) or 5
end

-- Legend aligned to `right`: Less [] [] [] [] [] More
local function paintHeatLegend(bb, right, y, less_widget, more_widget, text_h)
    local sq = math.floor(text_h * 0.8)
    local pad = SPACE.m
    local legend_w = less_widget:getSize().w + pad + 5 * (sq + pad) + more_widget:getSize().w
    local lx = right - legend_w
    less_widget:paintTo(bb, lx, y)
    lx = lx + less_widget:getSize().w + pad
    for i = 1, 5 do
        bb:paintRoundedRect(lx, y + math.floor((text_h - sq) / 2), sq, sq, HEAT_COLORS[i], math.floor(sq / 4))
        lx = lx + sq + pad
    end
    more_widget:paintTo(bb, lx, y)
end

local HeatmapGrid = Widget:extend{
    width = 0,
    daily = nil,       -- seconds read per day, keyed by "YYYY-MM-DD"
    start_t = 0,       -- first day shown (noon timestamp)
    end_t = 0,         -- last day shown (noon timestamp)
    max_seconds = nil, -- busiest day of the color scale (nil: this grid's own)
    layout_cols = nil, -- columns used to size the cells (nil: this grid's own)
    today_t = nil,     -- last day that is not in the future (noon timestamp; nil: none is)
    show_legend = true,
    font_size = FONT_TINY,
}

function HeatmapGrid:init()
    local face = getFace(self.font_size)
    local week_start = HEATMAP_WEEK_STARTS_ON_SUNDAY and 0 or 1
    self.week_start = week_start

    -- Align the grid to the start of the week. Timestamps are taken at noon
    -- so daylight saving changes never move a day.
    local first = os.date("*t", self.start_t)
    local offset = (first.wday - 1 - week_start) % 7
    local ts = self.start_t - offset * SECONDS_PER_DAY

    self.cells, self.month_widgets, self.day_widgets = {}, {}, {}
    self.total, self.active = 0, 0
    local max_seconds, index = self.max_seconds or 0, 0
    local shared_scale = self.max_seconds ~= nil
    while ts <= self.end_t do
        if ts >= self.start_t then
            local d = os.date("*t", ts)
            local seconds = self.daily[os.date("%Y-%m-%d", ts)] or 0
            local col = math.floor(index / 7)
            self.cells[#self.cells + 1] = {
                col = col, row = index % 7, seconds = seconds, month = d.month,
                future = self.today_t ~= nil and ts > self.today_t,
            }
            if seconds > 0 then
                self.total = self.total + seconds
                self.active = self.active + 1
                if not shared_scale then max_seconds = math.max(max_seconds, seconds) end
            end
            -- a month name over the column where the month starts
            if d.day == 1 then
                self.month_widgets[#self.month_widgets + 1] = {
                    col = col, month = d.month,
                    widget = TextWidget:new{ text = MONTH_NAMES[d.month], face = face, fgcolor = COLOR_MUTED },
                }
            end
        end
        index = index + 1
        ts = ts + SECONDS_PER_DAY
    end
    for _i, cell in ipairs(self.cells) do
        cell.level = heatLevel(cell.seconds, max_seconds)
    end
    self.cols = math.floor((index - 1) / 7) + 1

    -- Weekday letters on rows 2, 4 and 6
    for _i, r in ipairs({ 1, 3, 5 }) do
        self.day_widgets[r] = TextWidget:new{
            text = DAY_LETTERS[(week_start + r) % 7 + 1],
            face = face,
            fgcolor = COLOR_MUTED,
        }
    end
    self.less_widget = TextWidget:new{ text = _("Less"), face = face, fgcolor = COLOR_MUTED }
    self.more_widget = TextWidget:new{ text = _("More"), face = face, fgcolor = COLOR_MUTED }

    self.label_w = Screen:scaleBySize(16)
    -- Size the cells for the widest year (layout_cols), so a year that is still
    -- in progress does not get bigger squares than the complete ones.
    local size_cols = math.max(self.cols, self.layout_cols or 0)
    self.cell = math.min(math.floor((self.width - self.label_w) / size_cols), Screen:scaleBySize(30))
    -- thinner gaps when the cells are small (a whole year is ~53 columns)
    self.gap = self.cell < 12 and 1 or math.max(2, math.floor(self.cell * 0.14))
    self.text_h = self.less_widget:getSize().h
    self.head_h = self.text_h + SPACE.s
    self.legend_gap = SPACE.xl
    self.dimen = Geom:new{
        w = self.width,
        h = self.head_h + 7 * self.cell + (self.show_legend and (self.legend_gap + self.text_h) or 0),
    }
end

function HeatmapGrid:getSize()
    return self.dimen
end

function HeatmapGrid:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local grid_x = x + self.label_w
    local grid_y = y + self.head_h
    local size = self.cell - self.gap
    local radius = math.floor(size / 4)

    for _i, mark in ipairs(self.month_widgets) do
        mark.widget:paintTo(bb, grid_x + mark.col * self.cell, y)
    end
    for r, w in pairs(self.day_widgets) do
        w:paintTo(bb, x, grid_y + r * self.cell + math.floor((self.cell - w:getSize().h) / 2))
    end
    for _i, cell in ipairs(self.cells) do
        local cx = grid_x + cell.col * self.cell
        local cy = grid_y + cell.row * self.cell
        if cell.future then
            -- a day still to come: only an outline
            bb:paintRoundedRect(cx, cy, size, size, COLOR_TRACK, radius)
            bb:paintRoundedRect(cx + Size.border.thin, cy + Size.border.thin,
                size - 2 * Size.border.thin, size - 2 * Size.border.thin,
                Blitbuffer.COLOR_WHITE, math.max(0, radius - Size.border.thin))
        else
            bb:paintRoundedRect(cx, cy, size, size, HEAT_COLORS[cell.level], radius)
        end
    end

    if not self.show_legend then return end
    paintHeatLegend(bb, x + self.width, grid_y + 7 * self.cell + self.legend_gap,
        self.less_widget, self.more_widget, self.text_h)
end

-- The month under a tap (on a day square or on a month name), or nil. Months still to come give nil.
function HeatmapGrid:monthAt(pos)
    if not (pos and self.dimen and self.dimen.x) then return nil end
    local grid_x = self.dimen.x + self.label_w
    local grid_y = self.dimen.y + self.head_h
    if pos.y < self.dimen.y or pos.y >= grid_y + 7 * self.cell then return nil end
    local col = math.floor((pos.x - grid_x) / self.cell)
    if col < 0 or col >= self.cols then return nil end
    local month
    if pos.y < grid_y then
        -- on the row of month names: the month whose name starts at or before this column
        for _i, mark in ipairs(self.month_widgets) do
            if mark.col <= col then month = mark.month end
        end
    else
        local row = math.floor((pos.y - grid_y) / self.cell)
        for _i, cell in ipairs(self.cells) do
            if cell.col == col and cell.row == row then month = cell.month break end
        end
    end
    if not month then return nil end
    local now = os.date("*t")
    if self.year and (self.year > now.year or (self.year == now.year and month > now.month)) then return nil end
    return month
end

function HeatmapGrid:free()
    for _i, mark in ipairs(self.month_widgets) do mark.widget:free() end
    for _r, w in pairs(self.day_widgets) do w:free() end
    self.less_widget:free()
    self.more_widget:free()
end

-- Seconds read on each day since `from_t` (local dates), keyed by "YYYY-MM-DD".
-- Returns that map and the busiest day, or nil and a message.
local function queryDailySeconds(from_t)
    local items, err = queryAll(string.format([[
        SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS day, SUM(duration)
        FROM wpm_stat_data
        WHERE start_time >= %d
        GROUP BY day
    ]], from_t - 2 * SECONDS_PER_DAY), function(row)
        return { day = row[1], seconds = tonumber(row[2]) or 0 }
    end)
    if not items then return nil, err end
    if #items == 0 then return nil, _("No reading data found") end

    local daily_map, max_seconds = {}, 0
    for _i, item in ipairs(items) do
        daily_map[item.day] = item.seconds
        max_seconds = math.max(max_seconds, item.seconds)
    end
    return daily_map, max_seconds
end

-- One year of the heatmap: its title row (the year on the left, its time and
-- active days on the right) and the grid.
local function buildHeatmapYear(w_width, year, daily_map, max_seconds, show_legend)
    local now = os.date("*t")
    local start_t = os.time({ year = year, month = 1, day = 1, hour = 12 })
    -- the whole year, also the current one: the days to come are drawn empty
    local end_t = os.time({ year = year, month = 12, day = 31, hour = 12 })
    local today_t = os.time({ year = now.year, month = now.month, day = now.day, hour = 12 })

    local grid = HeatmapGrid:new{
        width = w_width,
        daily = daily_map,
        start_t = start_t,
        end_t = end_t,
        today_t = today_t,
        max_seconds = max_seconds,
        layout_cols = HEATMAP_MAX_COLS,
        show_legend = show_legend,
        year = year,
    }

    local year_widget = TextWidget:new{
        text = tostring(year),
        face = getFace(FONT_TEXT),
        bold = true,
        fgcolor = (year == now.year) and COLOR_TEXT or COLOR_MUTED,
    }
    local total_widget = TextWidget:new{
        text = string.format("%s" .. SUMMARY_SEPARATOR .. "%d %s",
            secondsToDH(grid.total), grid.active, _("active days")),
        face = getFace(FONT_CAPTION),
        fgcolor = COLOR_MUTED,
    }
    local head_h = math.max(year_widget:getSize().h, total_widget:getSize().h)
    local head = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = w_width - total_widget:getSize().w, h = head_h },
            year_widget,
        },
        total_widget,
    }
    return grid, head
end

-- The widgets of the heatmap view (the window puts them under its title).
local function buildHeatmapView(w_width, parent)
    local now = os.date("*t")
    local first_year = now.year - HEATMAP_YEARS + 1
    -- the period starts on January 1st of the first year shown
    local start_t = os.time({ year = first_year, month = 1, day = 1, hour = 12 })

    local daily_map, max_seconds = queryDailySeconds(start_t)
    if not daily_map then return nil, max_seconds end

    if parent then parent._heat_grids = {} end
    -- newest year first; only the last grid carries the legend
    local widgets, total, active = {}, 0, 0
    for year = now.year, first_year, -1 do
        local grid, head = buildHeatmapYear(w_width, year, daily_map, max_seconds, year == first_year)
        -- a tap on a month opens it in the month view (see onTapClose)
        if parent then
            table.insert(parent._heat_grids, grid)
        end
        total, active = total + grid.total, active + grid.active
        widgets[#widgets + 1] = head
        widgets[#widgets + 1] = grid
        if year > first_year then
            widgets[#widgets + 1] = makeVerticalSpacing(SPACE.l)
        end
    end
    widgets[#widgets + 1] = makeVerticalSpacing(SPACE.l)
    widgets[#widgets + 1] = makeSummaryLine(w_width, string.format("%s %s" .. SUMMARY_SEPARATOR .. "%d %s",
        _("Total"), secondsToDH(total), active, _("active days")))
    return widgets
end

-- Fill color of a day of the month view: days without reading are white, the
-- rest use the heatmap colors.
local function monthCellColor(level)
    if level == 1 then return Blitbuffer.COLOR_WHITE end
    return HEAT_COLORS[level]
end

-- Calendar of the current month: one rounded cell per day with its number,
-- colored like the heatmap (days still to come are only an outline, today has
-- a dark border). Weekday letters on top and the same legend under it.
local MonthGrid = Widget:extend{
    width = 0,
    daily = nil,       -- seconds read per day, keyed by "YYYY-MM-DD"
    year = 0,
    month = 0,
    today = 0,         -- day of the month that is today
    font_size = FONT_TEXT,
}

function MonthGrid:init()
    local week_start = HEATMAP_WEEK_STARTS_ON_SUNDAY and 0 or 1
    local days = os.date("*t", os.time({ year = self.year, month = self.month + 1, day = 0, hour = 12 })).day
    local first = os.date("*t", os.time({ year = self.year, month = self.month, day = 1, hour = 12 }))
    local offset = (first.wday - 1 - week_start) % 7
    self.rows = math.ceil((offset + days) / 7)

    self.cells = {}
    self.total, self.active = 0, 0
    local max_seconds = 0
    for day = 1, days do
        local seconds = self.daily[string.format("%04d-%02d-%02d", self.year, self.month, day)] or 0
        -- A day counts as read only with enough reading (see MIN_DAY_SECONDS):
        -- opening a book for a few seconds leaves the day blank. The time still
        -- adds to the month total.
        local read = seconds >= MIN_DAY_SECONDS
        local index = offset + day - 1
        self.cells[#self.cells + 1] = {
            day = day, col = index % 7, row = math.floor(index / 7),
            seconds = read and seconds or 0, future = day > self.today,
        }
        self.total = self.total + seconds
        if read then
            self.active = self.active + 1
            max_seconds = math.max(max_seconds, seconds)
        end
    end
    for _i, cell in ipairs(self.cells) do
        cell.level = heatLevel(cell.seconds, max_seconds)
        -- dark cells get white numbers, the ones to come a light number
        local color = (cell.level >= 4 and Blitbuffer.COLOR_WHITE)
            or (cell.future and COLOR_BAR)
            or (cell.level == 1 and COLOR_MUTED)
            or COLOR_TEXT
        cell.widget = TextWidget:new{
            text = tostring(cell.day),
            face = getFace(self.font_size),
            bold = (cell.day == self.today),
            fgcolor = color,
        }
    end

    local face = getFace(FONT_CAPTION)
    self.letter_widgets = {}
    for c = 0, 6 do
        self.letter_widgets[c + 1] = TextWidget:new{
            text = DAY_LETTERS[(week_start + c) % 7 + 1], face = face, fgcolor = COLOR_MUTED,
        }
    end
    local legend_face = getFace(FONT_TINY)
    self.less_widget = TextWidget:new{ text = _("Less"), face = legend_face, fgcolor = COLOR_MUTED }
    self.more_widget = TextWidget:new{ text = _("More"), face = legend_face, fgcolor = COLOR_MUTED }

    self.cell = math.min(math.floor(self.width / 7), Screen:scaleBySize(56))
    self.gap = math.max(2, math.floor(self.cell * 0.1))
    self.letter_h = self.letter_widgets[1]:getSize().h
    self.head_h = self.letter_h + SPACE.l
    self.legend_gap = SPACE.xl
    self.legend_h = self.less_widget:getSize().h
    self.dimen = Geom:new{
        w = self.width,
        h = self.head_h + self.rows * self.cell + self.legend_gap + self.legend_h,
    }
end

-- The day under a screen position (only days already lived), or nil. Uses the position of the last paint.
function MonthGrid:dayAt(pos)
    if not (pos and self.dimen and self.dimen.x) then return nil end
    local grid_x = self.dimen.x + math.floor((self.width - 7 * self.cell) / 2)
    local grid_y = self.dimen.y + self.head_h
    local col = math.floor((pos.x - grid_x) / self.cell)
    local row = math.floor((pos.y - grid_y) / self.cell)
    if col < 0 or col > 6 or row < 0 or row >= self.rows then return nil end
    for _i, cell in ipairs(self.cells) do
        if cell.col == col and cell.row == row then
            if cell.future then return nil end
            return cell.day
        end
    end
    return nil
end

function MonthGrid:getSize()
    return self.dimen
end

function MonthGrid:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local grid_x = x + math.floor((self.width - 7 * self.cell) / 2)
    local grid_y = y + self.head_h
    local size = self.cell - self.gap
    local radius = math.floor(size / 4)
    local border = Screen:scaleBySize(2)

    for c, w in ipairs(self.letter_widgets) do
        local ws = w:getSize()
        w:paintTo(bb, grid_x + (c - 1) * self.cell + math.floor((size - ws.w) / 2), y)
    end
    for _i, cell in ipairs(self.cells) do
        local cx = grid_x + cell.col * self.cell
        local cy = grid_y + cell.row * self.cell
        if cell.future then
            -- only an outline
            bb:paintRoundedRect(cx, cy, size, size, COLOR_TRACK, radius)
            bb:paintRoundedRect(cx + Size.border.thin, cy + Size.border.thin,
                size - 2 * Size.border.thin, size - 2 * Size.border.thin,
                Blitbuffer.COLOR_WHITE, math.max(0, radius - Size.border.thin))
        elseif cell.day == self.today then
            -- dark border around the color of the day
            bb:paintRoundedRect(cx, cy, size, size, COLOR_ACCENT, radius)
            bb:paintRoundedRect(cx + border, cy + border, size - 2 * border, size - 2 * border,
                monthCellColor(cell.level), math.max(0, radius - border))
        else
            bb:paintRoundedRect(cx, cy, size, size, monthCellColor(cell.level), radius)
        end
        local ws = cell.widget:getSize()
        cell.widget:paintTo(bb, cx + math.floor((size - ws.w) / 2), cy + math.floor((size - ws.h) / 2))
    end

    paintHeatLegend(bb, x + self.width, grid_y + self.rows * self.cell + self.legend_gap,
        self.less_widget, self.more_widget, self.legend_h)
end

function MonthGrid:free()
    for _i, cell in ipairs(self.cells) do cell.widget:free() end
    for _i, w in ipairs(self.letter_widgets) do w:free() end
    self.less_widget:free()
    self.more_widget:free()
end

-- The widgets of the month view (the window puts them under its title).
local function buildMonthView(w_width, parent)
    local now = os.date("*t")
    -- the month shown: picked with a two-finger swipe (see onMonthSwipe), or the current one
    local year = parent and parent.month_y or now.year
    local month = parent and parent.month_m or now.month
    local start_t = os.time({ year = year, month = month, day = 1, hour = 12 })
    local daily_map, err = queryDailySeconds(start_t)
    if not daily_map then return nil, err end

    local current = (year == now.year and month == now.month)
    local days_in_month = os.date("*t", os.time({ year = year, month = month + 1, day = 0, hour = 12 })).day
    local grid = MonthGrid:new{
        width = w_width,
        daily = daily_map,
        year = year,
        month = month,
        today = current and now.day or 99,   -- a past month: every day lived, none marked as today
    }
    if parent then parent._month_grid = grid end   -- for the tap on a day (see onTapClose)
    return {
        grid,
        makeVerticalSpacing(SPACE.l),
        makeSummaryLine(w_width, string.format("%s %s" .. SUMMARY_SEPARATOR .. "%d %s" .. SUMMARY_SEPARATOR .. "%s %s",
            _("Total"), secondsToHM(grid.total), grid.active, _("active days"),
            secondsToShortHM(grid.total / (current and now.day or days_in_month)), _("a day"))),
    }
end

-- ── Reading summary (first screen) ───────────────────────────────────────────
-- The start-menu modules as stacked cards (shelf size, reading time with
-- differential, book info with session time and reading speed), like the
-- start menu. The reading figures come from one read-only connection to the
-- statistics database. No open-session time is added: showing this window
-- already saved the session in progress (see onShowLongestSessions), so it is
-- in the database.

local DELTA_PACE_KEY = "micromodule_reading_delta_pace"  -- same key as the module
local DEFAULT_PACE = 2                                    -- hours per day

-- The pace is a setting of the reading differential module. This plugin may
-- not be able to load that module's settings store; then the default is used.
local function readPace()
    local t0 = Perf.start()
    local loaders = {
        function() return require("lib/bookshelf_settings_store") end,
        function() return dofile("plugins/bookshelf.koplugin/lib/bookshelf_settings_store.lua") end,
    }
    for _i, load in ipairs(loaders) do
        local ok, Store = pcall(load)
        if ok and type(Store) == "table" and Store.read then
            local ok_read, v = pcall(Store.read, DELTA_PACE_KEY)
            v = ok_read and tonumber(v) or nil
            if v and v > 0 then
                Perf.log("readPace (loader " .. _i .. ")", t0)
                return v
            end
        end
    end
    Perf.log("readPace (default)", t0)
    return DEFAULT_PACE
end

-- Reads every figure of the summary. Returns nil when the database cannot be read.
local function loadSummaryData()
    local t0 = Perf.start()
    local lfs = require("libs/libkoreader-lfs")
    local path = getStatsDbPath()
    if lfs.attributes(path, "mode") ~= "file" then return nil end

    local now = os.time()
    local t = os.date("*t", now)
    local day_start   = os.time{ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
    local month_start = os.time{ year = t.year, month = t.month, day = 1,     hour = 0, min = 0, sec = 0 }
    local year_start  = os.time{ year = t.year, month = 1,       day = 1,     hour = 0, min = 0, sec = 0 }
    local week_start  = day_start - ((t.wday + 5) % 7) * SECONDS_PER_DAY  -- Monday
    local lm = t.month - 1 == 0 and 12 or t.month - 1
    local ly = t.month - 1 == 0 and t.year - 1 or t.year
    local lmonth_start = os.time{ year = ly, month = lm, day = 1, hour = 0, min = 0, sec = 0 }

    local out = { yday = t.yday }
    local SQ3 = require("lua-ljsqlite3/init")
    local ok, err = pcall(function()
        local conn = SQ3.open(path, "ro")
        local ok_q, err_q = pcall(function()
            conn:exec("PRAGMA busy_timeout=200;")

            -- Seconds read inside [from, to]; sessions that cross a border
            -- count proportionally in each period.
            local overlap = conn:prepare([[
                SELECT COALESCE(SUM(
                    MIN(start_time + duration, ?) - MAX(start_time, ?)
                ), 0)
                FROM wpm_stat_data
                WHERE start_time + duration >= ? AND start_time <= ?
            ]])
            local function span(from, to)
                local row = overlap:bind(to, from, from, to):step()
                local secs = tonumber(row[1]) or 0
                overlap:clearbind():reset()
                return secs
            end
            local t_span = Perf.start()
            out.today     = span(day_start, now)
            out.yesterday = span(day_start - SECONDS_PER_DAY, day_start - 1)
            out.month     = span(month_start, now)
            out.lmonth    = span(lmonth_start, month_start - 1)
            out.year      = span(year_start, now)
            overlap:close()
            Perf.log("  loadSummaryData: 5 spans", t_span)

            -- Pages read in each period, shown in brackets next to the time. Each session counts its stable
            -- (reference) pages when it saved them, and its screens when it did not (sessions of books without
            -- reference pages, or saved before they existed). A session belongs to the period where it started.
            local t_pages = Perf.start()
            pcall(function()
                local has_ref = false
                local info = conn:prepare("PRAGMA table_info(wpm_stat_data)")
                local col = {}
                while info:step(col) do
                    if tostring(col[2]) == "ref_pages" then has_ref = true end
                end
                info:close()
                local expr = has_ref
                    and "CASE WHEN ref_pages IS NOT NULL THEN ref_pages ELSE COALESCE(total_pages, 0) END"
                    or "COALESCE(total_pages, 0)"
                local stmt = conn:prepare("SELECT COALESCE(SUM(" .. expr
                    .. "), 0) FROM wpm_stat_data WHERE start_time >= ? AND start_time <= ?")
                local function pages(from, to)
                    local row = stmt:bind(from, to):step()
                    local n = tonumber(row[1]) or 0
                    stmt:clearbind():reset()
                    return n
                end
                out.pages = {
                    today     = pages(day_start, now),
                    yesterday = pages(day_start - SECONDS_PER_DAY, day_start - 1),
                    week      = pages(week_start, now),
                    month     = pages(month_start, now),
                    lmonth    = pages(lmonth_start, month_start - 1),
                    year      = pages(year_start, now),
                }
                stmt:close()
            end)
            Perf.log("  loadSummaryData: pages", t_pages)

            -- Per-page statistics (reading stats module); optional
            local t_page = Perf.start()
            pcall(function()
                local stmt = conn:prepare([[
                    SELECT COALESCE(SUM(duration), 0),
                           COUNT(DISTINCT (id_book || ':' || page))
                    FROM page_stat_data WHERE start_time >= ?]])
                local row = stmt:bind(day_start):step()
                out.page_secs  = tonumber(row[1]) or 0
                out.page_count = tonumber(row[2]) or 0
                stmt:clearbind():reset()
                row = stmt:bind(week_start):step()
                out.week = tonumber(row[1]) or 0
                stmt:close()
            end)
            Perf.log("  loadSummaryData: page_stat_data", t_page)
        end)
        conn:close()
        if not ok_q then error(err_q, 0) end
    end)
    if not ok then
        logger.warn("longest sessions: summary query failed:", err)
        return nil
    end
    Perf.log("loadSummaryData TOTAL", t0)
    return out
end

-- Time of the current session and on the open book (nil outside the reader)
local function getSessionInfo()
    local ui = getReaderUI()
    local topbar = ui and ui.view and ui.view.topbar
    if not topbar or not topbar.start_session_time then return nil end
    local session = math.max(0, os.time() - topbar.start_session_time)
    return session, session + (topbar.initial_total_time_book or 0)
end

-- ── Cards ────────────────────────────────────────────────────────────────────

local CARD_PAD = SPACE.xl
local CARD_RADIUS = Screen:scaleBySize(10)

local function cardInnerWidth(card_w)
    return card_w - 2 * (CARD_PAD + Size.border.thin)
end

-- Gap between two cards side by side (the columns of a row)
local CARD_GAP = Screen:scaleBySize(12)

-- Outlined card on the white window (no grey fill). `min_h` makes it at least
-- that tall (the content is centered), so two cards of a row can match.
local function makeCard(card_w, content, min_h)
    local h = math.max(content:getSize().h, min_h or 0)
    return FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        color = COLOR_BAR,
        bordersize = Screen:scaleBySize(2),
        radius = CARD_RADIUS,
        padding = CARD_PAD,
        margin = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = cardInnerWidth(card_w), h = h },
            content,
        },
    }
end

-- Width of the two columns of a row: the left one gets `left_ratio` of it
local function columnWidths(w_width, left_ratio)
    local usable = w_width - CARD_GAP
    local left = math.floor(usable * (left_ratio or 0.5))
    return left, usable - left
end

-- A column of rows: the caption on the left, the value (bold) on the right,
-- a thin line between rows. rows = { { value, caption, pages }, ... }
-- `pages` (optional text) goes in brackets after the value, small and muted.
local function buildStatRows(inner_w, rows)
    local vg = VerticalGroup:new{ align = "left" }
    local pad = SPACE.m
    -- the values and the pages of all the rows go in two columns of the same width, so they line up
    local values, extras = {}, {}
    local value_w, extra_w = 0, 0
    for i, r in ipairs(rows) do
        values[i] = TextWidget:new{
            text = r[1], face = getFace(FONT_BIG - 4), bold = true, fgcolor = COLOR_TEXT,
            max_width = math.floor(inner_w * 0.55),
        }
        value_w = math.max(value_w, values[i]:getSize().w)
        if r[3] then
            extras[i] = TextWidget:new{
                text = "(" .. r[3] .. ")", face = getFace(FONT_SUMMARY), fgcolor = COLOR_MUTED,
            }
            extra_w = math.max(extra_w, extras[i]:getSize().w)
        end
    end
    local right_w = value_w + (extra_w > 0 and (SPACE.s + extra_w) or 0)
    for i, r in ipairs(rows) do
        local value = values[i]
        local vh = value:getSize().h
        local right
        if extra_w > 0 then
            right = HorizontalGroup:new{
                align = "bottom",
                RightContainer:new{ dimen = Geom:new{ w = value_w, h = vh }, value },
                HorizontalSpan:new{ width = SPACE.s },
                RightContainer:new{
                    dimen = Geom:new{ w = extra_w, h = vh },
                    extras[i] or HorizontalSpan:new{ width = 0 },
                },
            }
        else
            right = RightContainer:new{ dimen = Geom:new{ w = value_w, h = vh }, value }
        end
        local caption = TextWidget:new{
            text = r[2], face = getFace(FONT_SUMMARY), fgcolor = COLOR_MUTED,
            max_width = inner_w - right_w - SPACE.m, ellipsis = true,
        }
        local h = math.max(vh, caption:getSize().h)
        if i > 1 then
            vg[#vg + 1] = VerticalSpan:new{ width = pad }
            vg[#vg + 1] = LineWidget:new{
                background = COLOR_TRACK,
                dimen = Geom:new{ w = inner_w, h = Size.line.thin },
            }
            vg[#vg + 1] = VerticalSpan:new{ width = pad }
        end
        vg[#vg + 1] = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = inner_w - right_w, h = h }, caption },
            right,
        }
    end
    return vg
end

-- Two cards side by side (same height, a gap between them)
local function buildCardRow(w_width, left_ratio, build_left, build_right)
    local lw, rw = columnWidths(w_width, left_ratio)
    local lc, rc = build_left(lw), build_right(rw)
    -- the taller content sets the height of both cards
    local h = math.max(lc[1].dimen.h, rc[1].dimen.h)
    -- free the measuring pass (it holds a scaled copy of the cover)
    pcall(function() lc:free() end)
    pcall(function() rc:free() end)
    lc, rc = build_left(lw, h), build_right(rw, h)
    return HorizontalGroup:new{
        align = "top",
        lc,
        HorizontalSpan:new{ width = CARD_GAP },
        rc,
    }
end

-- The biggest size (down to min_size) at which every text fits in max_w.
local function fitSize(texts, max_size, min_size, max_w, bold)
    local best = max_size
    for _i, text in ipairs(texts) do
        local size = max_size
        while size > min_size do
            local tw = TextWidget:new{ text = text, face = getFace(size), bold = bold }
            local w = tw:getSize().w
            tw:free()
            if w <= max_w then break end
            size = size - 1
        end
        best = math.min(best, size)
    end
    return best
end

-- Equal columns, each a value and a caption: cols = { { value, caption }, ... }
local function buildColumns(inner_w, cols, caption_on_top)
    local col_w = math.floor(inner_w / #cols)
    local avail = col_w - SPACE.m
    local values, captions = {}, {}
    for i, c in ipairs(cols) do values[i], captions[i] = c[1], c[2] end
    local value_size = fitSize(values, FONT_BIG, FONT_SMALL, avail, true)
    local caption_size = fitSize(captions, FONT_SUMMARY, FONT_CAPTION_MIN, avail, false)

    local groups, max_h = {}, 0
    for i, c in ipairs(cols) do
        local value = TextWidget:new{
            text = c[1], face = getFace(value_size), bold = true,
            fgcolor = COLOR_TEXT, max_width = avail,
        }
        local caption = TextWidget:new{
            text = c[2], face = getFace(caption_size),
            fgcolor = COLOR_MUTED, max_width = avail,
        }
        local gap = VerticalSpan:new{ width = SPACE.xs }
        local vg = VerticalGroup:new{ align = "center" }
        if caption_on_top then
            vg[1], vg[2], vg[3] = caption, gap, value
        else
            vg[1], vg[2], vg[3] = value, gap, caption
        end
        groups[i] = vg
        max_h = math.max(max_h, vg:getSize().h)
    end
    local row = HorizontalGroup:new{ align = "top" }
    for i, vg in ipairs(groups) do
        row[i] = CenterContainer:new{ dimen = Geom:new{ w = col_w, h = max_h }, vg }
    end
    return row
end

-- Two columns: differential (ΔL), today and yesterday on the left; this week,
-- month, last month and year on the right.
local function buildBreakdownCard(w_width, data)
    local pace = readPace()
    local delta = math.ceil((data.year / 3600) - (data.yday * pace))
    -- pages read in each period, in brackets (nil when they could not be read)
    local pg = data.pages or {}
    local function pagesText(n) return n and tostring(math.floor(n + 0.5)) or nil end
    local left_rows = {
        { (delta > 0 and "+" or "") .. tostring(delta), DELTA_L .. " " .. formatPace(pace) },
        { secondsToShortHM(data.today),                  _("Today"),      pagesText(pg.today) },
        { secondsToBreakdownTime(data.yesterday),        _("Yesterday"),  pagesText(pg.yesterday) },
    }
    local right_rows = {
        { data.week and secondsToStatsTime(data.week) or "-", _("This week"), pagesText(pg.week) },
        { secondsToBreakdownTime(data.month),            _("Month"),      pagesText(pg.month) },
        { secondsToBreakdownTime(data.lmonth),           _("Last month"), pagesText(pg.lmonth) },
        { secondsToBreakdownTime(data.year),             _("Year"),       pagesText(pg.year) },
    }
    return buildCardRow(w_width, 0.5,
        function(w, h) return makeCard(w, buildStatRows(cardInnerWidth(w), left_rows), h) end,
        function(w, h) return makeCard(w, buildStatRows(cardInnerWidth(w), right_rows), h) end)
end

-- Reading speed: words per minute and pages of the current session. Read from
-- the JSON the statistics plugin writes on every page turn; 0 and 0 when the
-- file is missing, invalid or older than 5 minutes (as the wpm_session module).
local WPM_STALE_S = 300

local function readWpmSession()
    local f = io.open(DataStorage:getSettingsDir() .. "/wpm_session.json", "r")
    if not f then return 0, 0 end
    local raw = f:read("*a")
    f:close()
    if not raw or raw == "" then return 0, 0 end
    local wpm     = tonumber(raw:match('"wpm"%s*:%s*(%d+)'))
    local pages   = tonumber(raw:lower():match('"pages[%w_]*"%s*:%s*(%d+)'))
    local updated = tonumber(raw:match('"updated"%s*:%s*(%d+)'))
    if not wpm or not updated then return 0, 0 end
    if os.time() - updated > WPM_STALE_S then return 0, 0 end
    return wpm, pages or 0
end

-- Pages read in the session in progress: the distinct pages of
-- page_stat_data since the session started (the window already saved the
-- session, see onShowLongestSessions). If that gives nothing, the pages of
-- wpm_session.json are used (only valid while that file is recent).
local function getSessionPages(session_start)
    local ui = getReaderUI()
    local stats = ui and ui.statistics
    -- the statistics plugin's own start of the session may be earlier
    local from = tonumber(stats and stats.start_current_period) or 0
    if from <= 0 or (session_start and session_start < from) then from = session_start end
    from = math.floor(from)

    -- 1. saved pages (page_stat_data); all the books, since `from`
    local db_pages = 0
    local rows = queryAll(string.format([[
        SELECT COUNT(DISTINCT (id_book || ':' || page))
        FROM page_stat_data WHERE start_time >= %d
    ]], from), function(row) return tonumber(row[1]) or 0 end)
    if rows and rows[1] then db_pages = rows[1] end

    -- 2. pages still in the statistics plugin's memory (not saved yet)
    local mem_pages = 0
    if stats and type(stats.page_stat) == "table" then
        for _page, list in pairs(stats.page_stat) do
            for _i, tuple in ipairs(list) do
                if (tonumber(tuple[1]) or 0) >= from and (tonumber(tuple[2]) or 0) > 0 then
                    mem_pages = mem_pages + 1
                    break
                end
            end
        end
    end

    -- 3. the json of the wpm module
    local _wpm, json_pages = readWpmSession()
    local pages = math.max(db_pages, mem_pages, json_pages or 0)
    logger.info(string.format("longest sessions: session pages db=%d mem=%d json=%s from=%d",
        db_pages, mem_pages, tostring(json_pages), from))
    return pages
end

-- Date (as text, dd/mm/yyyy) from which wpm and pages/day have data; set by loadReadingStats
local exact_since_text = nil

-- Figures over ALL the reading (not just the session in progress):
--   * total sessions: the number of rows of wpm_stat_data
--   * total read: the sum of their durations (seconds)
--   * words per minute: all the words read over all the minutes read
--   * pages per day: the reference pages of each session (ref_pages, saved with it: the reference page where the
--     session ends minus the one where it starts, as the reader numbers them) divided by the days with at least
--     MIN_DAY_SECONDS of reading
-- Total sessions and total read use every session. Words per minute and pages per day use only the sessions that
-- saved their exact figures (words, read_secs, ref_pages), no estimates: the older sessions are left out.
-- Returns total_sessions, total_seconds, avg_wpm, pages_per_day (0 when there is no data).
local function loadReadingStats()
    local total_sessions, total_secs, avg_wpm, pages_per_day = 0, 0, 0, 0
    exact_since_text = nil

    local t = queryAll("SELECT COUNT(*), COALESCE(SUM(duration), 0) FROM wpm_stat_data", function(row)
        return { count = tonumber(row[1]) or 0, secs = tonumber(row[2]) or 0 }
    end)
    if t and t[1] then total_sessions, total_secs = t[1].count, t[1].secs end

    -- the exact columns may not be in the database yet
    local found = 0
    local cols = queryAll("PRAGMA table_info(wpm_stat_data)", function(row) return tostring(row[2]) end)
    for _i, name in ipairs(cols or {}) do
        if name == "words" or name == "read_secs" or name == "ref_pages" then
            found = found + 1
        end
    end
    if found < 3 then return total_sessions, total_secs, avg_wpm, pages_per_day end

    local exact = [[words IS NOT NULL AND read_secs > 0 AND ref_pages IS NOT NULL AND start_time > 0]]

    local w = queryAll("SELECT COALESCE(SUM(words), 0), COALESCE(SUM(read_secs), 0), COALESCE(MIN(start_time), 0) FROM wpm_stat_data WHERE " .. exact,
        function(row)
            return { words = tonumber(row[1]) or 0, secs = tonumber(row[2]) or 0, first = tonumber(row[3]) or 0 }
        end)
    if w and w[1] then
        if w[1].secs > 0 then avg_wpm = w[1].words / (w[1].secs / 60) end
        if w[1].first > 0 then exact_since_text = os.date("%d/%m/%Y", w[1].first) end
    end

    local d = queryAll(string.format([[
        SELECT COUNT(*), COALESCE(SUM(pages), 0) FROM (
            SELECT SUM(ref_pages) AS pages
            FROM wpm_stat_data
            WHERE %s
            GROUP BY strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime')
            HAVING SUM(read_secs) >= %d
        )
    ]], exact, MIN_DAY_SECONDS), function(row)
        return { days = tonumber(row[1]) or 0, pages = tonumber(row[2]) or 0 }
    end)
    if d and d[1] and d[1].days > 0 then
        pages_per_day = d[1].pages / d[1].days
    end
    return total_sessions, total_secs, avg_wpm, pages_per_day
end

-- Whole number from 10 up, one decimal below ("7.4"), "0" for nothing
local function formatAverage(v)
    v = tonumber(v) or 0
    if v <= 0 then return "0" end
    if v >= 10 then return tostring(math.floor(v + 0.5)) end
    return string.format("%.1f", v)
end

-- Page counts (reference pages are whole numbers): "5", not "5.0"; a decimal only if the value has one
local function formatPages(v)
    v = tonumber(v) or 0
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.1f", v)
end

-- Cleans a top bar text: drops its leading bullet, [b] tags and the object
-- replacement character.
local function cleanTopBarText(s)
    s = tostring(s or ""):gsub("^%s*\xE2\x8B\x85%s*", ""):gsub("%[/?b%]", ""):gsub("\xEF\xBF\xBC", "")
    return (s:match("^%s*(.-)%s*$"))
end

-- ── Exact sessions: summary and list for the explain window ──────────────────
-- Only the sessions that saved their exact figures (words, read_secs, ref_pages) are listed and summed here: they
-- are the ones that feed avg wpm and pages/day, so the numbers of the window agree with the card.

-- The list is built as widgets and painted in an off-screen buffer as tall as itself, so it is kept bounded
local MAX_LISTED_SESSIONS = 5
local MAX_TOP_SESSIONS = 3  -- the longest sessions listed above the newest ones

local EXACT_WHERE = "words IS NOT NULL AND read_secs > 0 AND ref_pages IS NOT NULL AND start_time > 0"

-- 1234567 -> "1,234,567"
local function groupThousands(n)
    local s = tostring(math.floor((tonumber(n) or 0) + 0.5))
    local k
    repeat
        s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
    until k == 0
    return s
end

-- 45 min / 2h 05m
local function formatReadMinutes(secs)
    local m = math.floor((tonumber(secs) or 0) / 60 + 0.5)
    if m < 60 then return string.format("%d min", m) end
    return string.format("%dh %02dm", math.floor(m / 60), m % 60)
end

-- Everything the window needs in ONE connection and four statements (opening the database once per query was the
-- slow part): totals over all the sessions with exact data (not only the ones listed) and the newest `limit` of
-- them. Same rules as loadReadingStats: pages/day counts only the days with at least MIN_DAY_SECONDS of reading.
-- If the exact columns are not in the database yet, the exact figures stay at zero. Raises if it cannot be read.
local function loadExactData(limit, top_limit)
    local SQ3 = require("lua-ljsqlite3/init")
    local s = {
        total_sessions = 0, exact = 0, words = 0, secs = 0, ref_pages = 0, first = 0,
        wpm_min = 0, wpm_max = 0, days = 0, day_pages = 0,
    }
    local list, top = {}, {}
    local conn = SQ3.open(getStatsDbPath())
    local ok, err = pcall(function()
        local function run(sql, each)
            local stmt = conn:prepare(sql)
            local row = {}
            while stmt:step(row) do each(row) end
            stmt:close()
        end

        run("SELECT COUNT(*) FROM wpm_stat_data", function(row)
            s.total_sessions = tonumber(row[1]) or 0
        end)

        -- a missing exact column makes the first statement fail: no exact data yet
        local has_exact = pcall(function()
            run(string.format([[
                SELECT COUNT(*), COALESCE(SUM(words), 0), COALESCE(SUM(read_secs), 0), COALESCE(SUM(ref_pages), 0),
                       COALESCE(MIN(start_time), 0), COALESCE(MIN(words * 60.0 / read_secs), 0),
                       COALESCE(MAX(words * 60.0 / read_secs), 0)
                FROM wpm_stat_data
                WHERE %s
            ]], EXACT_WHERE), function(row)
                s.exact, s.words, s.secs = tonumber(row[1]) or 0, tonumber(row[2]) or 0, tonumber(row[3]) or 0
                s.ref_pages, s.first = tonumber(row[4]) or 0, tonumber(row[5]) or 0
                s.wpm_min, s.wpm_max = tonumber(row[6]) or 0, tonumber(row[7]) or 0
            end)
        end)
        if not has_exact or s.exact <= 0 then return end

        run(string.format([[
            SELECT COUNT(*), COALESCE(SUM(pages), 0) FROM (
                SELECT SUM(ref_pages) AS pages
                FROM wpm_stat_data
                WHERE %s
                GROUP BY strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime')
                HAVING SUM(read_secs) >= %d
            )
        ]], EXACT_WHERE, MIN_DAY_SECONDS), function(row)
            s.days, s.day_pages = tonumber(row[1]) or 0, tonumber(row[2]) or 0
        end)

        -- ref_start, ref_end, pct_start and pct_end are added by hand to the database: select only the ones that exist
        local have = {}
        run("PRAGMA table_info(wpm_stat_data)", function(row)
            have[tostring(row[2])] = true
        end)
        local function col(name) return have[name] and ("w." .. name) or "NULL" end

        -- The sessions with exact data in the given order: the newest, or the longest (most reading time)
        local function fetch(order_by, n, into)
            run(string.format([[
                SELECT w.start_time, w.duration, w.total_pages, w.words, w.read_secs, w.ref_pages, COALESCE(b.title, ''),
                       %s, %s, %s, %s
                FROM wpm_stat_data w
                LEFT JOIN book b ON w.id_book = b.id
                WHERE w.words IS NOT NULL AND w.read_secs > 0 AND w.ref_pages IS NOT NULL AND w.start_time > 0
                ORDER BY %s
                LIMIT %d
            ]], col("ref_start"), col("ref_end"), col("pct_start"), col("pct_end"), order_by, n), function(row)
                into[#into + 1] = {
                    start = tonumber(row[1]) or 0, duration = tonumber(row[2]) or 0, screens = tonumber(row[3]) or 0,
                    words = tonumber(row[4]) or 0, secs = tonumber(row[5]) or 0, ref_pages = tonumber(row[6]) or 0,
                    title = tostring(row[7] or ""),
                    -- nil for the sessions saved before these columns existed
                    ref_start = tonumber(row[8]), ref_end = tonumber(row[9]),
                    pct_start = tonumber(row[10]), pct_end = tonumber(row[11]),
                }
            end)
        end
        fetch("w.start_time DESC", limit, list)
        fetch("w.read_secs DESC, w.start_time DESC", top_limit or 0, top)
    end)
    conn:close()
    if not ok then error(err, 0) end
    return s, list, top
end

-- The summary as { title, text } items, with the real figures
local function buildSummaryItems(s)
    if s.exact <= 0 then
        return { { _("No exact data yet"), _("The sessions read from now on will be listed here with their words, time and reference pages") } }
    end
    local since = os.date("%d/%m/%Y", s.first)
    local avg_wpm = s.words / (s.secs / 60)
    local items = {}
    items[#items + 1] = {
        string.format(_("avg wpm  %s"), formatAverage(avg_wpm)),
        string.format(_("%s words over %s of reading"), groupThousands(s.words), formatReadMinutes(s.secs)),
    }
    if s.days > 0 then
        items[#items + 1] = {
            string.format(_("pages/day  %s"), formatAverage(s.day_pages / s.days)),
            string.format(_("%s reference pages over %s with at least %d minutes of reading"),
                formatPages(s.day_pages), s.days == 1 and _("1 day") or string.format(_("%d days"), s.days),
                math.floor(MIN_DAY_SECONDS / 60)),
        }
    else
        items[#items + 1] = {
            _("pages/day  0"),
            string.format(_("no day has reached %d minutes of reading yet"), math.floor(MIN_DAY_SECONDS / 60)),
        }
    end
    items[#items + 1] = {
        _("Sessions"),
        string.format(_("%d with exact data, since %s, of %d saved in total"), s.exact, since, s.total_sessions),
    }
    items[#items + 1] = {
        _("Per session"),
        string.format(_("%s of reading and %s reference pages on average, from %d to %d wpm"),
            formatReadMinutes(s.secs / s.exact), formatAverage(s.ref_pages / s.exact),
            math.floor(s.wpm_min + 0.5), math.floor(s.wpm_max + 0.5)),
    }
    return items
end

-- One { title, text } item per session: when and what book, then the figures
local function buildSessionItems(list)
    local items = {}
    for _i, s in ipairs(list) do
        local head = formatDateTime(s.start)
        if s.title ~= "" then head = head .. TITLE_SEPARATOR .. s.title end
        local first = { string.format(_("%s read"), formatReadMinutes(s.secs)) }
        if s.screens > 0 then
            first[#first + 1] = string.format(_("%d screens"), s.screens)
            first[#first + 1] = string.format(_("%d s/screen"), math.floor(s.secs / s.screens + 0.5))
        end
        local pages_text = string.format(_("%s pages (stable)"), formatPages(s.ref_pages))
        if s.ref_start then
            -- from the reference page where the session started to the one where it ended
            pages_text = pages_text .. string.format(" (%d \xE2\x86\x92 %d)", s.ref_start, s.ref_end or (s.ref_start + s.ref_pages))
        end
        local second = {
            string.format(_("%s words"), groupThousands(s.words)),
            string.format(_("%d wpm"), math.floor(s.words / (s.secs / 60) + 0.5)),
            pages_text,
        }
        if s.ref_pages > 0 then
            -- reading pace in stable (reference) pages: seconds of reading for each one
            second[#second + 1] = string.format(_("%d s/stable page"), math.floor(s.secs / s.ref_pages + 0.5))
        end
        if s.pct_start and s.pct_end then
            -- progress of the book where the session started and where it ended
            second[#second + 1] = string.format("%.1f%% \xE2\x86\x92 %.1f%%", s.pct_start, s.pct_end)
        end
        items[#items + 1] = {
            head,
            table.concat(first, SUMMARY_SEPARATOR) .. "\n" .. table.concat(second, SUMMARY_SEPARATOR),
        }
    end
    return items
end

-- Small window with the same look as the summary (white, rounded, outlined) that explains the figures of the
-- book card: the legend of each figure, a summary with the real numbers and the sessions with exact data, which
-- scroll when they do not fit. A tap (or Back) closes it. From the summary it shows the totals; while reading, how the
-- figures of the session are worked out.
local explain_window_open = false
local ExplainWindow = InputContainer:extend{
    modal = true,
    name = "longest_sessions_explain",
}

function ExplainWindow:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local w = math.floor(sw * 0.86)
    local border = Screen:scaleBySize(2)
    local inner_w = w - 2 * (CARD_PAD + border)
    -- the body leaves room for the scrollbar, so it is the same width whether it scrolls or not
    local body_w = inner_w - ScrollableContainer:getScrollbarWidth()

    local title_widget = TextWidget:new{
        text = self.title, face = getFace(FONT_TITLE), bold = true,
        fgcolor = COLOR_TEXT, max_width = inner_w,
    }

    local body = VerticalGroup:new{ align = "left" }
    -- a figure or a session: a rule, its name in bold and its text below
    local function addItem(item)
        body[#body + 1] = VerticalSpan:new{ width = SPACE.m }
        body[#body + 1] = LineWidget:new{
            background = COLOR_TRACK, dimen = Geom:new{ w = body_w, h = Size.line.thin },
        }
        body[#body + 1] = VerticalSpan:new{ width = SPACE.m }
        body[#body + 1] = TextWidget:new{
            text = item[1], face = getFace(FONT_TEXT), bold = true,
            fgcolor = COLOR_TEXT, max_width = body_w,
        }
        body[#body + 1] = VerticalSpan:new{ width = SPACE.s }
        body[#body + 1] = TextBoxWidget:new{
            text = item[2], face = getFace(FONT_SUMMARY), fgcolor = COLOR_MUTED, width = body_w,
        }
    end
    -- a section: a heavier rule and a bigger heading
    local function addHeader(text)
        body[#body + 1] = VerticalSpan:new{ width = SPACE.xl }
        body[#body + 1] = LineWidget:new{
            background = COLOR_ACCENT, dimen = Geom:new{ w = body_w, h = Size.line.medium },
        }
        body[#body + 1] = VerticalSpan:new{ width = SPACE.m }
        body[#body + 1] = TextWidget:new{
            text = text, face = getFace(FONT_SUBTITLE), bold = true,
            fgcolor = COLOR_TEXT, max_width = body_w,
        }
    end

    for _i, item in ipairs(self.items or {}) do addItem(item) end
    if self.summary and #self.summary > 0 then
        -- the title already says "Summary" unless a legend comes first
        if self.items and #self.items > 0 then addHeader(_("Summary")) end
        for _i, item in ipairs(self.summary) do addItem(item) end
    end
    if self.top_sessions and #self.top_sessions > 0 then
        addHeader(self.top_title or _("Longest sessions"))
        for _i, item in ipairs(self.top_sessions) do addItem(item) end
    end
    if self.sessions and #self.sessions > 0 then
        addHeader(self.sessions_title or _("Sessions"))
        for _i, item in ipairs(self.sessions) do addItem(item) end
    end

    local vg = VerticalGroup:new{ align = "left", title_widget }
    -- up to 90% of the screen: when the body is taller it scrolls (a swipe up or down), a horizontal swipe or a
    -- tap still closes the window
    local max_body_h = math.floor(sh * 0.9) - 2 * (CARD_PAD + border) - title_widget:getSize().h
    if body:getSize().h > max_body_h then
        vg[#vg + 1] = SwipePassthroughScrollable:new{
            dimen = Geom:new{ w = inner_w, h = max_body_h },
            show_parent = self,
            body,
        }
    else
        vg[#vg + 1] = body
    end
    local frame = FrameContainer:new{
        radius = Screen:scaleBySize(28),
        bordersize = border,
        padding = CARD_PAD,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        vg,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self[1] = CenterContainer:new{ dimen = self.dimen, frame }
    self.frame = frame
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = { GestureRange:new{ ges = "tap", range = self.dimen } }
        self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }
    end
end

function ExplainWindow:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame.dimen end)
    return true
end

function ExplainWindow:onClose()
    explain_window_open = false
    UIManager:close(self, "ui", self.frame.dimen)
    return true
end
ExplainWindow.onTapClose = ExplainWindow.onClose
function ExplainWindow:onSwipe() return self:onClose() end

-- The book card of the summary on screen (a row of two cards), for the hold that explains it
local summary_book_card = nil
local summary_book_reading = false  -- true: the card shows the session in progress; false: the totals

-- Reference pages read in the session in progress, as the reader numbers them. Same figure that is saved as ref_pages
-- when the session ends: the reference page the reader is on minus the one where the session started (provisional
-- until the session is valid). Always a whole number: 0 while there is no start yet (nothing counted as read) or
-- when the reader is before the start. nil when the session does not use reference pages or the page cannot be read.
local function getStablePages()
    local ui = getReaderUI()
    if not ui then return nil end
    -- this session does not use reference pages (see ReaderStatistics:decideSessionRefMode): nothing to show
    local allowed = false
    pcall(function() allowed = ui.statistics:refPagesAllowed() end)
    if not allowed then return nil end
    local start, current
    pcall(function() start = tonumber(ui.statistics._session_start_ref or ui.statistics._pending_start_ref) end)
    pcall(function() current = ui.statistics:getCurrentRefPage() end)
    if not current then return nil end
    if not start then return 0 end
    return math.max(0, current - start)
end

-- Caption of the "pages (stable)" row while reading: with the reference page where the session started (the one
-- saved as ref_start). Until the session is valid it is the provisional one.
local function getStablePagesCaption()
    local caption = _("pages (stable)")
    local ui = getReaderUI()
    local start
    pcall(function() start = tonumber(ui.statistics._session_start_ref or ui.statistics._pending_start_ref) end)
    if start then
        caption = caption .. TITLE_SEPARATOR .. start
    end
    return caption
end

-- ── Cover behind the title ───────────────────────────────────────────────────
-- The cover of the open book fills the left card of the book card and the title, series and year go on a white band
-- over it, so the text is readable whatever the cover looks like.

-- debug: true logs the cover's sizes and types ([LS-COVER] in crash.log) and saves the cover as KOReader
-- gives it as ls_cover_1_raw.png in the settings folder.
-- In this one table: the file is at Lua's limit of 200 top-level locals, so no new local can be added.
local cover_cache = { file = nil, bb = nil, debug = false }

-- The cover of the open book (a buffer kept for the next builds), or nil when there is none
local function getOpenBookCover()
    local ui = getReaderUI()
    local doc = ui and ui.document
    if not doc then return nil end
    if cover_cache.bb and cover_cache.file == doc.file then return cover_cache.bb end
    local ok, bb = pcall(function()
        return require("apps/filemanager/filemanagerbookinfo"):getCoverImage(doc)
    end)
    if not ok or not bb then return nil end
    local w, h = bb:getWidth(), bb:getHeight()
    if cover_cache.debug then
        logger.info(string.format("[LS-COVER] %s: raw %dx%d type %s rotation %s inverse %s, screen type %s",
            tostring(doc.file), w, h, tostring(bb:getType()), tostring(bb:getRotation()),
            tostring(bb:getInverse()), tostring(Screen.bb:getType())))
        pcall(function() bb:writePNG(DataStorage:getSettingsDir() .. "/ls_cover_1_raw.png") end)
    end
    local copy
    local ok_copy = pcall(function()
        if w <= 0 or h <= 0 then error("empty cover") end
        -- a private copy: the one given back can be freed or reused by whoever made it
        copy = bb:copy()
    end)
    pcall(function() bb:free() end)
    if not ok_copy or not copy then return nil end
    if cover_cache.bb then cover_cache.bb:free() end
    cover_cache.file, cover_cache.bb = doc.file, copy
    return copy
end

local CoverBanner = Widget:extend{
    width = 0,
    height = 0,
    cover = nil,      -- buffer of the cover (not freed here)
    content = nil,    -- the text widget that goes on the band
    pad = 0,          -- space between the text and the edge of the band
}

function CoverBanner:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    -- The whole cover is stretched to exactly the area: nothing is cropped (top and bottom of the cover stay visible).
    -- KOReader's own ImageWidget does the scaling and the transparency (the same code that draws the covers of the file browser).
    local bw, bh = self.cover:getWidth(), self.cover:getHeight()
    local scale = 0 -- only shown in the debug log: a stretch has no single factor
    self.image = require("ui/widget/imagewidget"):new{
        image = self.cover,
        image_disposable = false,   -- the cached cover is not ours to free
        width = self.width,
        height = self.height,
        scale_factor = nil,         -- nil with width + height: stretched to exactly that size
        alpha = true,               -- covers with transparency are blended, not blitted raw
    }
    if cover_cache.debug then
        local ok_sz, sz = pcall(function() return self.image:getSize() end)
        logger.info(string.format("[LS-COVER] cached %dx%d type %s, area %dx%d, scale %.3f, image %s",
            bw, bh, tostring(self.cover:getType()), self.width, self.height, scale,
            ok_sz and sz and string.format("%dx%d", sz.w, sz.h) or "?"))
    end
end

function CoverBanner:getSize()
    return self.dimen
end

function CoverBanner:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    -- white first, so a cover smaller than the area never leaves what was under the window showing through
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    local isz = self.image:getSize()
    self.image:paintTo(bb, x + math.floor((self.width - isz.w) / 2), y + math.floor((self.height - isz.h) / 2))
    local cs = self.content:getSize()
    local band_h = cs.h + 2 * self.pad
    -- the text goes over the TOP of the cover, moved down by bottom_gap (the same margin) so the card's
    -- border and rounded corners never cut it
    local by = y + (self.bottom_gap or 0)
    local tx, ty = x + math.floor((self.width - cs.w) / 2), by + self.pad
    -- black box behind the text (just around it), so the white text reads on any cover
    local box_px = Screen:scaleBySize(6)
    local box_py = Screen:scaleBySize(2)
    bb:paintRect(tx - box_px, ty - box_py, cs.w + 2 * box_px + math.max(1, Screen:scaleBySize(1)), cs.h + 2 * box_py,
        Blitbuffer.COLOR_BLACK)
    -- painted twice, the second one a pixel to the right: thicker strokes than plain bold
    local extra = math.max(1, Screen:scaleBySize(1))
    self.content:paintTo(bb, tx, ty)
    self.content:paintTo(bb, tx + extra, ty)
end

function CoverBanner:free()
    if self.image then
        self.image:free()
        self.image = nil
    end
    if self.content and self.content.free then self.content:free() end
end

-- Two columns. Left: title, series, words and publication year of the open
-- book. Right: totals and averages of all the reading: total time read, total
-- number of sessions, wpm of the sessions and pages per day read.
local function buildBookCard(w_width, session, book)
    local right_rows
    summary_book_reading = session ~= nil
    if session then
        -- reading: this book, the session in progress, its wpm and its pages
        local wpm, pages = readWpmSession()
        -- the json may be stale or lack the pages: count them in the database
        pages = math.max(pages, getSessionPages(os.time() - session))
        right_rows = {
            { book and secondsToShortHM(book) or "-",       _("This book") },
            { secondsToShortHM(session),                    _("Session") },
            { tostring(wpm),                                _("wpm") },
            { tostring(pages),                              _("pages (screen)") },
        }
        -- "pages (stable)" only when the book has reference pages; otherwise the row is left out
        local stable = getStablePages()
        if stable then
            right_rows[#right_rows + 1] = {
                formatPages(stable),
                getStablePagesCaption(),
            }
        end
    else
        -- not reading: totals of all the reading
        local total_sessions, total_secs, avg_wpm, pages_per_day = loadReadingStats()
        right_rows = {
            { string.format("%.1fd", total_secs / SECONDS_PER_DAY), _("Total read") },
            { tostring(total_sessions),                     _("Total sessions") },
            { formatAverage(avg_wpm),                       _("avg wpm") },
            { formatAverage(pages_per_day),                 _("pages/day") },
        }
    end

    local function leftContent(inner_w, min_h)
        local ui = getReaderUI()
        local topbar = ui and ui.view and ui.view.topbar
        local title = topbar and topbar.title or ""
        if title == "" then
            return TextWidget:new{
                text = _("Not reading"), face = getFace(FONT_BIG),
                fgcolor = COLOR_MUTED, max_width = inner_w,
            }
        end
        local words = tonumber(topbar.total_words) or 0
        local parts = {}
        if words > 0 then
            parts[#parts + 1] = (words >= 1000 and string.format("%dk", math.floor(words / 1000)) or tostring(words)) .. "w"
        end
        local pub = tostring(topbar.pub_date or "")
        if pub ~= "" then parts[#parts + 1] = pub end

        -- with a cover the text sits on a band, a bit narrower than the card
        local cover = getOpenBookCover()
        local band_pad = SPACE.l
        local text_w = cover and (inner_w - 2 * band_pad) or inner_w

        -- Only the words and the publication year (no title, no series, no author).
        -- The title is shown only when neither is known, so the card is never empty.
        local vg = VerticalGroup:new{ align = "center" }
        if #parts > 0 then
            vg[#vg + 1] = TextWidget:new{
                -- over the cover: bigger, bold and white so it can be read on the picture
                -- (without a cover it stays as before: gray on the white card)
                text = table.concat(parts, SUMMARY_SEPARATOR),
                face = getFace(cover and (FONT_BIG - 2) or FONT_SUMMARY), bold = cover and true or nil,
                fgcolor = cover and Blitbuffer.COLOR_WHITE or COLOR_MUTED, max_width = text_w, ellipsis = true,
            }
        else
            vg[#vg + 1] = TextWidget:new{
                text = cleanTopBarText(title), face = getFace(FONT_BIG - 2), bold = true,
                fgcolor = COLOR_TEXT, max_width = text_w, ellipsis = true,
            }
        end
        if cover then
            -- room above and below the band, so the cover shows
            local margin = Screen:scaleBySize(16)
            local height = math.max(min_h or 0, vg:getSize().h + 2 * band_pad + 2 * margin)
            return CoverBanner:new{
                width = inner_w, height = height, cover = cover, content = vg, pad = band_pad,
                bottom_gap = margin,   -- the text sits this far from the top edge of the cover
            }
        end
        return vg
    end

    local row = buildCardRow(w_width, 0.5,
        function(w, h)
            local inner_w = cardInnerWidth(w)
            local c = leftContent(inner_w, h)
            return makeCard(w, CenterContainer:new{
                dimen = Geom:new{ w = inner_w, h = c:getSize().h }, c,
            }, h)
        end,
        function(w, h) return makeCard(w, buildStatRows(cardInnerWidth(w), right_rows), h) end)
    summary_book_card = row
    return row
end

-- ── Tappable zones of the summary ────────────────────────────────────────────
-- A tap closes the window, except on a zone that does something first.
-- Zones are { card, ncols, col, row_h, callback }: column `col` of the row
-- of `ncols` equal columns at the bottom of `card`.
local summary_tap_zones = {}

local function hitSummaryZone(pos)
    for _i, z in ipairs(summary_tap_zones) do
        local d = z.card.dimen
        if d and d.w and d.w > 0 and pos.x >= d.x and pos.x < d.x + d.w then
            local edge = CARD_PAD + Size.border.thin
            local col_w = math.floor((d.w - 2 * edge) / z.ncols)
            local col = math.floor((pos.x - (d.x + edge)) / col_w) + 1
            local row_bottom = d.y + d.h - edge
            if pos.y >= row_bottom - z.row_h and pos.y < row_bottom and col == z.col then
                return z
            end
        end
    end
end

-- Names a chip can have for each status (the finished books are "complete"
-- in the sidecar files and "Finished" on the shelf).
local STATUS_CHIP_NAMES = {
    tbr      = { "tbr" },
    mbr      = { "mbr" },
    finished = { "finished", "complete" },
}

-- The id of the Bookshelf chip that shows the books of a status ("tbr",
-- "mbr", "finished"): the one whose id or label is one of its names (glyphs
-- and case ignored), or whose filter has that status. nil when there is none
-- (or when the chip model is not loaded yet).
local function findStatusChipKey(status)
    local names = STATUS_CHIP_NAMES[status] or { status }
    local ok, TabModel = pcall(require, "lib/bookshelf_tab_model")
    if not ok or not TabModel or not TabModel.getActive then return nil end
    for _i, tab in ipairs(TabModel.getActive()) do
        local label = tostring(tab.label or ""):lower():gsub("[^%w]", "")
        local f = tab.filter
        for _j, name in ipairs(names) do
            local by_filter = type(f) == "table" and type(f.statuses) == "table" and f.statuses[name]
            if tab.id == name or label == name or by_filter then
                return tab.id
            end
        end
    end
    logger.info("longest sessions: no chip for status " .. status .. " found in Bookshelf")
end

-- Makes `key` the active chip of a Bookshelf widget that is NOT showing, with
-- the state changes of its _selectChip but without the rebuild and the
-- repaint: the overlay that opens Bookshelf rebuilds the whole widget right
-- after showing it, so it comes up on this chip with a single paint.
local function presetChip(widget, key)
    pcall(function()
        if widget._markOpdsNav then widget:_markOpdsNav() end
        widget._opds_fail_url, widget._opds_fail_err = nil, nil
        if widget._clearDpadFocus then widget:_clearDpadFocus() end
        widget._drilldown_path = {}
        widget.chip = key
        widget._cursor = 1
        if widget._syncPageFromCursor then widget:_syncPageFromCursor() end
        widget._switching_shelf = true
    end)
end

-- Saves the active chip, so a Bookshelf widget created later starts on it.
local function saveActiveChip(key)
    pcall(function()
        local Store = require("lib/bookshelf_settings_store")
        local save = Store.saveDeferred or Store.save
        save("active_chip", key)
    end)
end

-- Opens Bookshelf parked over the open book (the ParkAndShowBookshelf event of
-- the bookshelf overlay patch) already on the chip of a status ("tbr", "mbr",
-- "finished"). The chip is set BEFORE showing, so there is no second change
-- on screen. If Bookshelf is already showing parked, it only changes the chip.
local function openBookshelfOnStatus(status)
    local rui = getReaderUI()
    local host = rui
    if not host then
        local ok_fm, FM = pcall(require, "apps/filemanager/filemanager")
        host = ok_fm and FM and FM.instance
    end
    local plugin = host and host.bookshelf
    if not plugin then return end

    local key = findStatusChipKey(status)
    local ok_park, Park = pcall(require, "lib/bookshelf_reader_park")
    local parked = ok_park and Park and Park.isParked()

    if parked then
        -- Bookshelf is on screen: change the chip the normal way (repaints)
        local widget = plugin._widget
        if key and widget and widget._selectChip then widget:_selectChip(key) end
        return
    end

    if key then
        if plugin._widget then
            presetChip(plugin._widget, key)   -- hidden widget: state only
        end
        saveActiveChip(key)                    -- a new widget reads this
    end

    if rui then
        local Event = require("ui/event")
        UIManager:sendEvent(Event:new("ParkAndShowBookshelf"))
    end

    if not key then
        -- The chip model was not loaded before; it is now that Bookshelf shows
        UIManager:nextTick(function()
            local late_key = findStatusChipKey(status)
            local widget = plugin._widget
            if late_key and widget and widget._selectChip then widget:_selectChip(late_key) end
        end)
    end
end

-- Shelf size: books in the library by status (from _G.all_files)
local SHELF_STATUS = {
    { "reading", _("Reading") }, { "tbr", _("TBR") }, { "mbr", _("MBR") },
    { "finished", _("Finished") }, { "unread", _("Unread") },
}

local function getShelfCounts()
    local t0 = Perf.start()
    local total = 0
    local counts = { reading = 0, tbr = 0, mbr = 0, finished = 0, unread = 0 }
    local all_files = rawget(_G, "all_files")
    if type(all_files) == "table" then
        for _file, info in pairs(all_files) do
            total = total + 1
            local status = type(info) == "table" and info.status or nil
            local bucket = (status == "complete" and "finished")
                or ((status == "reading" or status == "tbr" or status == "mbr") and status)
                or "unread"
            counts[bucket] = counts[bucket] + 1
        end
    end
    Perf.log("  getShelfCounts (" .. total .. " files)", t0)
    return total, counts
end

local function buildShelfCard(card_w)
    local inner_w = cardInnerWidth(card_w)
    local total, counts = getShelfCounts()
    local cols = {}
    for i, st in ipairs(SHELF_STATUS) do
        cols[i] = { tostring(counts[st[1]]), st[2] }
    end
    local header = HorizontalGroup:new{
        align = "bottom",
        TextWidget:new{ text = tostring(total), face = getFace(FONT_HERO), bold = true, fgcolor = COLOR_TEXT },
        HorizontalSpan:new{ width = SPACE.xl },
        TextWidget:new{ text = _("Books"), face = getFace(FONT_SUBTITLE), bold = true, fgcolor = COLOR_MUTED },
    }
    local row = buildColumns(inner_w, cols, true)
    local vg = VerticalGroup:new{
        align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = header:getSize().h }, header },
        VerticalSpan:new{ width = SPACE.m },
        row,
    }
    local card = makeCard(card_w, vg)
    -- columns that open Bookshelf on their chip when tapped
    for i, st in ipairs(SHELF_STATUS) do
        local status = st[1]
        if STATUS_CHIP_NAMES[status] then
            summary_tap_zones[#summary_tap_zones + 1] = {
                card = card, ncols = #SHELF_STATUS, col = i,
                row_h = row:getSize().h,
                callback = function() openBookshelfOnStatus(status) end,
            }
        end
    end
    return card
end

-- The whole screen: the cards, in a scrollable list when they do not fit.
local function buildSummaryView(w_width, parent)
    local t_all = Perf.start()
    local data = loadSummaryData()
    if not data then return nil, _("Could not read the statistics database") end
    local t_sess = Perf.start()
    local session, book = getSessionInfo()
    Perf.log("  getSessionInfo", t_sess)

    local function buildCards(card_w)
        local t_cards = Perf.start()
        summary_tap_zones = {}
        local cards = VerticalGroup:new{ align = "center" }

        local t = Perf.start()
        local shelf = buildShelfCard(card_w)
        Perf.log("  buildShelfCard", t)
        t = Perf.start()
        local breakdown = buildBreakdownCard(card_w, data)
        Perf.log("  buildBreakdownCard", t)
        t = Perf.start()
        local book_card = buildBookCard(card_w, session, book)
        Perf.log("  buildBookCard", t)

        local list = { shelf, breakdown, book_card }
        for i, card in ipairs(list) do
            if i > 1 then cards[#cards + 1] = VerticalSpan:new{ width = SPACE.m } end
            cards[#cards + 1] = card
        end
        Perf.log("  buildCards TOTAL", t_cards)
        return cards
    end

    local cards = buildCards(w_width)
    local max_h = math.floor(Screen:getHeight() * 0.7)
    if cards:getSize().h <= max_h then
        Perf.log("buildSummaryView TOTAL", t_all)
        return { cards }
    end

    if DEBUG_PERF then logger.info("[LS-PERF] summary does not fit: rebuilding with scroll") end
    cards:free()
    cards = buildCards(w_width - ScrollableContainer:getScrollbarWidth())
    Perf.log("buildSummaryView TOTAL (rebuilt)", t_all)
    return { SwipePassthroughScrollable:new{
        dimen = Geom:new{ w = w_width, h = max_h },
        show_parent = parent,
        cards,
    } }
end

-- ── Finished books ───────────────────────────────────────────────────────────
-- The statistics database does not know which books are finished: that lives
-- in each book's sidecar file ("summary" status). So the books of the reading
-- history are checked, and the ones marked "complete" are matched to the
-- statistics database by their partial MD5 or, failing that, by title.

local BOOK_RANK_W = Screen:scaleBySize(30)

-- What the last search for finished books found, for the "empty" message
local finished_info = ""

-- Adds to `files` the books that have a sidecar folder (book.sdr) under `root`
local function findBooksWithSidecar(root, files, seen)
    local lfs = require("libs/libkoreader-lfs")
    local budget = 20000  -- directory entries to look at, at most
    local function walk(dir, depth)
        if depth > 5 or budget <= 0 then return end
        pcall(function()
            for name in lfs.dir(dir) do
                if name:sub(1, 1) ~= "." then
                    budget = budget - 1
                    local path = dir .. "/" .. name
                    if name:match("%.sdr$") then
                        for fname in lfs.dir(path) do
                            local ext = fname:match("^metadata%.(.+)%.lua$")
                            if ext then
                                local book = path:sub(1, -5) .. "." .. ext
                                if not seen[book] then
                                    seen[book] = true
                                    files[#files + 1] = book
                                end
                            end
                        end
                    elseif lfs.attributes(path, "mode") == "directory" then
                        walk(path, depth + 1)
                    end
                end
            end
        end)
    end
    walk(root, 0)
end

-- Opening every sidecar (and walking the home folder to find them) is slow,
-- so when _G.all_files exists it is used to know which books were finished
-- this year, and only the sidecars of those few books are opened (to get
-- their MD5 and title, which match them to the statistics database).

-- Status that _G.all_files gives to a finished book (change it if yours differs)
local ALL_FILES_FINISHED_STATUS = "complete"

-- Returns the files finished in `year` according to _G.all_files, or nil when
-- it cannot be used (no such table, empty, or entries without a status), so
-- the caller falls back to the sidecar search.
local function getFinishedFilesFromAllFiles(year)
    local all_files = rawget(_G, "all_files")
    if type(all_files) ~= "table" then return nil end

    local files, has_status = {}, false
    for file, entry in pairs(all_files) do
        if type(entry) == "table" and entry.status ~= nil then
            has_status = true
            if entry.status == ALL_FILES_FINISHED_STATUS
                    and tonumber(entry.last_modified_year) == year then
                files[#files + 1] = file
            end
        end
    end
    if not has_status then return nil end
    return files
end

-- Returns the SQL condition that selects the finished books, or "0" if none
local function getFinishedBooksFilter()
    local t0 = Perf.start()
    local DocSettings = require("docsettings")
    local ReadHistory = require("readhistory")
    local util = require("util")
    local md5s, titles = {}, {}
    local finished = 0

    local function addTitle(title)
        if type(title) == "string" and title ~= "" then
            titles[title:lower():gsub("^%s+", ""):gsub("%s+$", "")] = true
        end
    end

    -- Fast path: the books finished this year, straight from _G.all_files
    local files = getFinishedFilesFromAllFiles(os.date("*t").year)
    local from_all_files = files ~= nil

    if not files then
        -- Books to check: the reading history, plus every book with a sidecar
        -- folder in the home folder (finished books may be gone from the history)
        local seen
        files, seen = {}, {}
        for _i, item in ipairs(ReadHistory.hist or {}) do
            if item.file and not seen[item.file] then
                seen[item.file] = true
                files[#files + 1] = item.file
            end
        end
        pcall(function()
            local root = G_reader_settings:readSetting("home_dir") or Device.home_dir
            if root then findBooksWithSidecar(root, files, seen) end
        end)
    end

    for _i, file in ipairs(files) do
        pcall(function()
            local doc_settings = DocSettings:open(file)
            local summary = doc_settings:readSetting("summary")
            if not (summary and summary.status == "complete") then return end
            finished = finished + 1
            local md5 = doc_settings:readSetting("partial_md5_checksum")
            if not md5 then
                local ok, sum = pcall(util.partialMD5, file)
                md5 = ok and sum or nil
            end
            if md5 and md5:match("^%x+$") then md5s[md5] = true end
            local props = doc_settings:readSetting("doc_props")
            addTitle(props and props.title)
            -- the statistics use the file name when the book has no title
            local _path, name = util.splitFilePathName(file)
            addTitle((util.splitFileNameSuffix(name)))
        end)
    end
    finished_info = string.format("%d finished of %d books checked%s",
        finished, #files, from_all_files and " (all_files)" or "")
    logger.info("longest sessions: " .. finished_info)

    local conditions = {}
    local list = {}
    for md5 in pairs(md5s) do list[#list + 1] = "'" .. md5 .. "'" end
    if #list > 0 then
        conditions[#conditions + 1] = "book.md5 IN (" .. table.concat(list, ",") .. ")"
    end
    list = {}
    for title in pairs(titles) do list[#list + 1] = "'" .. title:gsub("'", "''") .. "'" end
    if #list > 0 then
        conditions[#conditions + 1] = "lower(trim(book.title)) IN (" .. table.concat(list, ",") .. ")"
    end
    Perf.log("getFinishedBooksFilter (" .. finished_info .. ")", t0)
    if #conditions == 0 then return "0" end
    return "(" .. table.concat(conditions, " OR ") .. ")"
end

-- ── Today (hourly chart) ─────────────────────────────────────────────────────
-- When you read today: a stacked bar chart with one bar per hour (minutes read
-- in it), split in segments per book; above it the total, when you started
-- and stopped, the longest session and the best hour; below, the books of the
-- day with their rank number, which is also drawn in the chart's segments.
-- The sessions come from the statistics database (wpm_stat_data), plus the
-- session in progress (see getLiveSessionRow), which may not be saved yet.

local TODAY_MAX_BOOKS = 5       -- books listed under the chart
local TODAY_SESSION_GAP = 120   -- seconds: readings closer than this are one session

local TODAY_COLORS = { "red", "orange", "yellow", "green", "olive", "cyan", "blue", "purple" }

-- Look of the book with the given rank. Colour screens: one colour per rank.
-- Black and white: solid dark with white text, or white with a thick black
-- outline, alternating. The rank number is always drawn, so books can be told
-- apart without colour. Returns text colour, fill colour and border width.
local function todayRankStyle(rank)
    if Screen.isColorEnabled and Screen:isColorEnabled() then
        local ok, c = pcall(Blitbuffer.colorFromName, TODAY_COLORS[(rank - 1) % #TODAY_COLORS + 1])
        if ok and c then return Blitbuffer.COLOR_BLACK, c, Size.border.thin end
    end
    if rank % 2 == 1 then
        return Blitbuffer.COLOR_WHITE, gray(48), Size.border.thin
    end
    return Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE, Screen:scaleBySize(2)
end

-- The reading session in progress as a row like the ones of wpm_stat_data
-- ({ book, title, start, duration }), or nil outside the reader or when nothing
-- is left to add. The part of it that is already in the database (the rows of
-- this book that start or end inside the session) is not counted twice: only
-- the time after the last saved moment is added.
local function getLiveSessionRow(rows, now)
    local ui = getReaderUI()
    if not ui then return nil end
    local topbar = ui.view and ui.view.topbar
    local stats = ui.statistics
    -- start of the session: topbar if it has it, else the statistics plugin
    local live_start = (topbar and topbar.start_session_time)
        or (stats and tonumber(stats.start_current_period))
    if not live_start or live_start <= 0 then return nil end
    -- book: the one of the statistics plugin, else the one of the rows with
    -- the same title, else a placeholder so the time is still counted
    local book = stats and tonumber(stats.id_curr_book)
    local cur_title = (stats and stats.data and stats.data.title)
        or (topbar and cleanTopBarText(topbar.title))
        or (ui.doc_settings and ui.doc_settings.data and ui.doc_settings.data.doc_props
            and ui.doc_settings.data.doc_props.title)
    if not book or book <= 0 then
        for _i, r in ipairs(rows) do
            if cur_title and r.title == cur_title then book = r.book break end
        end
        book = book or -1
    end

    local covered_until = live_start
    local title
    for _i, r in ipairs(rows) do
        if r.book == book then
            title = title or r.title
            if r.start + r.duration > live_start then
                covered_until = math.max(covered_until, r.start + r.duration)
            end
        end
    end
    local duration = now - covered_until
    if duration < 5 then return nil end
    title = title or cur_title or _("Unknown")
    return { book = book, title = title, start = covered_until, duration = duration }
end

-- Message of loadTodayData when nothing was read today (the Today views show an empty state for it)
local TODAY_EMPTY = _("No reading today")

-- Reads today's sessions. Returns a table
--   { total, first, last, books = { {rank, title, seconds}... }, hours = { [1..24] = { [rank] = seconds } },
--     best_hour, best_secs, longest, longest_start }
-- (times in seconds from midnight), or nil and a message.
local function loadTodayData(day_t)
    -- day_t: any moment of the day to read (nil = today)
    local now = os.time()
    local t = os.date("*t", day_t or now)
    local day_start = os.time{ year = t.year, month = t.month, day = t.day, hour = 0, min = 0, sec = 0 }
    local day_end = os.time{ year = t.year, month = t.month, day = t.day + 1, hour = 0, min = 0, sec = 0 }

    local rows, err = queryAll(string.format([[
        SELECT wpm_stat_data.id_book, book.title, wpm_stat_data.start_time, wpm_stat_data.duration
        FROM wpm_stat_data
        INNER JOIN book ON wpm_stat_data.id_book = book.id
        WHERE wpm_stat_data.start_time + wpm_stat_data.duration > %d AND wpm_stat_data.start_time < %d
        ORDER BY wpm_stat_data.start_time
    ]], day_start, day_end), function(row)
        return {
            book = tonumber(row[1]), title = row[2] or _("Unknown"),
            start = tonumber(row[3]) or 0, duration = tonumber(row[4]) or 0,
        }
    end)
    if not rows then return nil, err end

    -- the session in progress only belongs to today
    local is_today = day_start <= now and now < day_end
    local live = is_today and getLiveSessionRow(rows, now) or nil
    if live then
        rows[#rows + 1] = live
        table.sort(rows, function(x, y) return x.start < y.start end)
    end

    -- sessions clipped to today, and the time of each book
    local periods, by_book = {}, {}
    for _i, r in ipairs(rows) do
        local s = math.max(r.start, day_start) - day_start
        local f = math.min(r.start + r.duration, day_end) - day_start
        if f > s then
            periods[#periods + 1] = { book = r.book, s = s, f = f }
            local b = by_book[r.book]
            if not b then
                b = { id = r.book, title = r.title, seconds = 0 }
                by_book[r.book] = b
            end
            b.seconds = b.seconds + (f - s)
        end
    end
    if #periods == 0 then return nil, TODAY_EMPTY end

    -- books ranked by time (1 = the longest)
    local books = {}
    for _id, b in pairs(by_book) do books[#books + 1] = b end
    table.sort(books, function(a, b)
        if a.seconds ~= b.seconds then return a.seconds > b.seconds end
        return a.id < b.id
    end)
    local rank_of, total = {}, 0
    for i, b in ipairs(books) do
        b.rank = i
        rank_of[b.id] = i
        total = total + b.seconds
    end

    -- minutes per hour and book, first and last moment, longest session
    local out = { total = total, books = books, hours = {} }
    for h = 1, 24 do out.hours[h] = {} end
    local hour_total = {}
    local cur_s, cur_f
    out.longest, out.longest_start = 0, 0
    for _i, p in ipairs(periods) do
        if not out.first or p.s < out.first then out.first = p.s end
        if not out.last or p.f > out.last then out.last = p.f end
        local rank = rank_of[p.book]
        for h = math.floor(p.s / 3600), math.floor((p.f - 1) / 3600) do
            if h >= 0 and h < 24 then
                local sec = math.min(p.f, (h + 1) * 3600) - math.max(p.s, h * 3600)
                if sec > 0 then
                    out.hours[h + 1][rank] = (out.hours[h + 1][rank] or 0) + sec
                    hour_total[h] = (hour_total[h] or 0) + sec
                end
            end
        end
        -- readings less than TODAY_SESSION_GAP apart count as one session
        if cur_f and p.s - cur_f <= TODAY_SESSION_GAP then
            cur_f = math.max(cur_f, p.f)
        else
            cur_s, cur_f = p.s, p.f
        end
        if cur_f - cur_s > out.longest then
            out.longest, out.longest_start = cur_f - cur_s, cur_s
        end
    end
    out.best_hour, out.best_secs = 0, 0
    for h, sec in pairs(hour_total) do
        if sec > out.best_secs then out.best_hour, out.best_secs = h, sec end
    end
    out.day_start = day_start
    out.current_hour = is_today and (os.date("*t", now)).hour + 1 or nil   -- no "now" on another day

    -- the stretches read inside each hour (seconds from the start of the hour), readings that touch merged
    out.hour_segments = {}
    for h = 1, 24 do out.hour_segments[h] = {} end
    for _i, p in ipairs(periods) do
        for h = math.floor(p.s / 3600), math.floor((p.f - 1) / 3600) do
            if h >= 0 and h < 24 then
                local a = math.max(p.s, h * 3600) - h * 3600
                local b = math.min(p.f, (h + 1) * 3600) - h * 3600
                if b > a then
                    local list = out.hour_segments[h + 1]
                    list[#list + 1] = { a, b }
                end
            end
        end
    end
    for h = 1, 24 do
        local list = out.hour_segments[h]
        table.sort(list, function(x, y) return x[1] < y[1] end)
        local merged = {}
        for _i, seg in ipairs(list) do
            local last = merged[#merged]
            if last and seg[1] <= last[2] + TODAY_SESSION_GAP / 4 then
                last[2] = math.max(last[2], seg[2])
            else
                merged[#merged + 1] = { seg[1], seg[2] }
            end
        end
        out.hour_segments[h] = merged
    end
    return out
end

-- Stacked bar chart of the day: one bar per hour, as tall as the minutes read
-- in it, split in a segment per book (bottom: book 1).
local TodayChart = Widget:extend{
    width = 0,
    height = 0,
    hours = nil,        -- hours[1..24] = { [rank] = seconds }
    ranks = nil,        -- ranks to stack, in order
    current = nil,      -- index (1..24) of the current hour
    font_size = FONT_CAPTION,
}

function TodayChart:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local face = getFace(self.font_size)
    self.totals = {}
    local max_total = 0
    for h = 1, 24 do
        local t = 0
        for _r, sec in pairs(self.hours[h]) do t = t + sec end
        self.totals[h] = t
        if t > max_total then max_total = t end
    end
    local max_min = max_total / 60
    -- axis maximum in minutes: 15, 30, 60, or a multiple of 60
    self.y_max = (max_min <= 15 and 15) or (max_min <= 30 and 30) or (math.ceil(max_min / 60) * 60)

    self.value_widgets, self.hour_widgets, self.tick_widgets = {}, {}, {}
    for h = 1, 24 do
        if self.totals[h] >= 30 then
            self.value_widgets[h] = TextWidget:new{
                text = tostring(math.floor(self.totals[h] / 60 + 0.5)), face = face, fgcolor = COLOR_TEXT,
            }
        end
        if (h - 1) % 3 == 0 or h == self.current then
            self.hour_widgets[h] = TextWidget:new{
                text = string.format("%02d", h - 1), face = face,
                bold = (h == self.current),
                fgcolor = (h == self.current) and COLOR_TEXT or COLOR_MUTED,
            }
        end
    end
    for i = 0, 2 do
        self.tick_widgets[i + 1] = TextWidget:new{
            text = string.format("%d", self.y_max * i / 2), face = face, fgcolor = COLOR_MUTED,
        }
    end
    self.text_h = self.tick_widgets[1]:getSize().h
    self.axis_w = self.tick_widgets[3]:getSize().w + SPACE.l
end

function TodayChart:getSize()
    return self.dimen
end

function TodayChart:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local top_pad = self.text_h + SPACE.s                      -- room for the value labels
    local plot_top = y + top_pad
    local plot_h = self.height - top_pad - self.text_h - SPACE.l
    local plot_x = x + self.axis_w
    local plot_w = self.width - self.axis_w
    local base = plot_top + plot_h
    local slot = plot_w / 24
    local bar_w = math.max(2, math.floor(slot * 0.74))

    -- grid: 0, half and full scale, with their labels
    for i = 0, 2 do
        local gy = base - math.floor(plot_h * i / 2)
        bb:paintRect(plot_x, gy, plot_w, Size.line.thin, i == 0 and COLOR_BAR or COLOR_TRACK)
        local tw = self.tick_widgets[i + 1]
        local ts = tw:getSize()
        tw:paintTo(bb, plot_x - SPACE.l - ts.w, gy - math.floor(ts.h / 2))
    end

    for h = 1, 24 do
        local cx = plot_x + math.floor((h - 0.5) * slot)
        local bx = cx - math.floor(bar_w / 2)
        if h == self.current then
            -- soft column behind the current hour
            bb:paintRect(plot_x + math.floor((h - 1) * slot), plot_top - SPACE.s,
                math.ceil(slot), plot_h + SPACE.s, COLOR_SOFT)
        end
        local cursor = base
        for _i, rank in ipairs(self.ranks) do
            local sec = self.hours[h][rank]
            if sec and sec > 0 then
                local sh = math.max(2, math.floor(plot_h * (sec / 60) / self.y_max + 0.5))
                local _fg, fill, border = todayRankStyle(rank)
                local sy = cursor - sh
                local b = math.min(border, math.floor(bar_w / 2), math.floor(sh / 2))
                bb:paintRect(bx, sy, bar_w, sh, Blitbuffer.COLOR_BLACK)
                if b > 0 and sh - 2 * b > 0 then
                    bb:paintRect(bx + b, sy + b, bar_w - 2 * b, sh - 2 * b, fill)
                end
                cursor = sy
            end
        end
        local vw = self.value_widgets[h]
        if vw and cursor < base then
            local vs = vw:getSize()
            vw:paintTo(bb, cx - math.floor(vs.w / 2), cursor - vs.h - SPACE.xs)
        end
        local hw = self.hour_widgets[h]
        if hw then
            local hs = hw:getSize()
            hw:paintTo(bb, cx - math.floor(hs.w / 2), base + SPACE.l)
        end
    end
end

function TodayChart:free()
    for _i, list in ipairs({ self.value_widgets, self.hour_widgets, self.tick_widgets }) do
        for _k, w in pairs(list) do w:free() end
    end
end

-- A book of the list: its rank in a badge (same look as its chart segments),
-- the title with a bar (share of the longest book), and its time on the right.
local function buildTodayBookRow(w_width, book, longest)
    local fg, fill, border = todayRankStyle(book.rank)
    local face = getFace(FONT_TEXT)
    local gap = SPACE.xl
    local badge_size = TextWidget:new{ text = "0", face = face, bold = true }:getSize().h + SPACE.m
    local time_w = Screen:scaleBySize(70)
    local text_w = w_width - badge_size - time_w - 2 * gap
    local badge = FrameContainer:new{
        width = badge_size, height = badge_size,
        margin = 0, padding = 0,
        bordersize = border, radius = Screen:scaleBySize(6),
        background = fill,
        CenterContainer:new{
            dimen = Geom:new{ w = badge_size - 2 * border, h = badge_size - 2 * border },
            TextWidget:new{ text = tostring(book.rank), face = face, bold = true, fgcolor = fg },
        },
    }
    local left = VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = cleanTopBarText and cleanTopBarText(book.title) or book.title,
            face = face, max_width = text_w, ellipsis = true },
        VerticalSpan:new{ width = SPACE.s },
        ProgressTrack:new{
            width = text_w, height = SPACE.m,
            ratio = longest > 0 and book.seconds / longest or 0,
            color = COLOR_ACCENT,
        },
    }
    local row_h = left:getSize().h + SPACE.m
    return HorizontalGroup:new{
        align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = badge_size, h = row_h }, badge },
        HorizontalSpan:new{ width = gap },
        LeftContainer:new{ dimen = Geom:new{ w = text_w, h = row_h }, left },
        HorizontalSpan:new{ width = gap },
        RightContainer:new{
            dimen = Geom:new{ w = time_w, h = row_h },
            TextWidget:new{ text = secondsToShortHM(book.seconds), face = face, bold = true },
        },
    }
end

local function buildTodayDayView(w_width, day_t)
    local data, err = loadTodayData(day_t)
    if not data then return nil, err end

    local function clock(secs) return os.date("%H:%M", data.day_start + secs) end

    -- total of the day, big, and how many books
    local hero = HorizontalGroup:new{
        align = "bottom",
        TextWidget:new{
            text = secondsToHM(data.total), face = getFace(FONT_HERO), bold = true, fgcolor = COLOR_TEXT,
        },
        HorizontalSpan:new{ width = SPACE.xl },
        TextWidget:new{
            text = string.format("%d %s", #data.books, #data.books == 1 and _("book") or _("books")),
            face = getFace(FONT_SUBTITLE), bold = true, fgcolor = COLOR_MUTED,
        },
    }

    local stats = buildColumns(w_width, {
        { clock(data.first),                         _("Started") },
        { clock(data.last),                          _("Last read") },
        { secondsToShortHM(data.longest),            _("Longest") .. " " .. clock(data.longest_start) },
        { secondsToShortHM(data.best_secs),          _("Best hour") .. string.format(" %02d", data.best_hour) },
    }, false)

    -- time of the session in progress (nil outside the reader)
    local session_line
    local session = (not day_t) and getSessionInfo() or nil   -- another day: no session in progress
    if not session and not day_t then
        local ui = getReaderUI()
        local st = ui and ui.statistics and tonumber(ui.statistics.start_current_period)
        if st and st > 0 then session = math.max(0, os.time() - st) end
    end
    if session then
        -- pages of the session: the stable (reference) ones, or the screens read when the book has none
        local pages_text
        local stable = getStablePages()
        if stable then
            pages_text = formatPages(stable) .. " " .. _("pages (stable)")
        else
            pages_text = tostring(getSessionPages(os.time() - session)) .. " " .. _("screens")
        end
        local session_text = _("Current session") .. "  " .. secondsToShortHM(session)
            .. SUMMARY_SEPARATOR .. pages_text
        session_line = CenterContainer:new{
            dimen = Geom:new{ w = w_width, h = Screen:scaleBySize(26) },
            TextWidget:new{
                text = session_text,
                face = getFace(FONT_SUBTITLE), bold = true, fgcolor = COLOR_MUTED,
            },
        }
    end

    local ranks = {}
    for i = 1, #data.books do ranks[i] = i end
    local chart = TodayChart:new{
        width = w_width,
        height = math.min(Screen:scaleBySize(240), math.floor(Screen:getHeight() * 0.3)),
        hours = data.hours,
        ranks = ranks,
        current = data.current_hour,
    }

    local widgets = {
        CenterContainer:new{ dimen = Geom:new{ w = w_width, h = hero:getSize().h }, hero },
    }
    if session_line then widgets[#widgets + 1] = session_line end
    for _i, w in ipairs{
        makeVerticalSpacing(SPACE.l),
        stats,
        makeVerticalSpacing(SPACE.xl),
        chart,
        makeVerticalSpacing(SPACE.xl),
    } do widgets[#widgets + 1] = w end
    local longest = data.books[1].seconds
    for i = 1, math.min(#data.books, TODAY_MAX_BOOKS) do
        if i > 1 then widgets[#widgets + 1] = makeSeparator(w_width) end
        widgets[#widgets + 1] = buildTodayBookRow(w_width, data.books[i], longest)
    end
    if #data.books > TODAY_MAX_BOOKS then
        widgets[#widgets + 1] = makeVerticalSpacing(SPACE.m)
        widgets[#widgets + 1] = makeSummaryLine(w_width,
            string.format("+ %d %s", #data.books - TODAY_MAX_BOOKS, _("more")))
    end
    return widgets
end

-- ── Reading hours ────────────────────────────────────────────────────────────
-- The Today view can also show the reading by hour, in the same window (see buildTodayView): the design of the
-- Today view on its side, in green, one horizontal bar per hour with reading (the hours without it are skipped; it
-- scrolls when long). With the reading of today, or with the time of ALL the saved sessions (wpm_stat_data).

-- Longest part of a session counted (a book left open for a night would fill the whole ring)
local HOURS_MAX_SESSION_SECONDS = 12 * 3600
-- An hour with less reading than this is not listed in the bars look
local HOURS_MIN_LISTED_SECONDS = 30

local DAY_PERIODS = {
    { name = _("Morning"),   from = 5,  to = 12, phrase = _("in the morning"),   sun = true },
    { name = _("Afternoon"), from = 12, to = 17, phrase = _("in the afternoon"), sun = true },
    { name = _("Evening"),   from = 17, to = 22, phrase = _("in the evening"),   sun = false },
    { name = _("Night"),     from = 22, to = 5,  phrase = _("at night"),         sun = false },  -- wraps midnight
}

local function periodOfHour(hour)
    for i, p in ipairs(DAY_PERIODS) do
        if p.from < p.to then
            if hour >= p.from and hour < p.to then return i end
        elseif hour >= p.from or hour < p.to then
            return i
        end
    end
    return 1
end

-- Seconds read in each hour of the day (local time), from every saved session. A session that crosses an hour
-- counts in each hour it touches. Returns { hours = { [1..24] = seconds }, total, sessions }, or nil and a message.
local function loadHourlyData()
    local rows, err = queryAll([[
        SELECT start_time, duration FROM wpm_stat_data WHERE start_time > 0 AND duration > 0
    ]], function(row)
        return { tonumber(row[1]) or 0, tonumber(row[2]) or 0 }
    end)
    if not rows then return nil, err end
    if #rows == 0 then return nil, _("No reading data found") end

    local hours = {}
    for h = 1, 24 do hours[h] = 0 end
    local total = 0
    for _i, r in ipairs(rows) do
        local t = r[1]
        local finish = t + math.min(r[2], HOURS_MAX_SESSION_SECONDS)
        while t < finish do
            local d = os.date("*t", t)
            local left = 3600 - (d.min * 60 + d.sec)
            local take = math.max(1, math.min(left, finish - t))
            hours[d.hour + 1] = hours[d.hour + 1] + take
            total = total + take
            t = t + take
        end
    end
    if total <= 0 then return nil, _("No reading data found") end
    return { hours = hours, total = total, sessions = #rows }
end

-- Look of the bars of the hours chart: green on a color screen, dark gray on black and white
local function hoursBarFill()
    if Screen.isColorEnabled and Screen:isColorEnabled() then
        local ok, c = pcall(Blitbuffer.colorFromName, "green")
        if ok and c then return c end
    end
    return gray(90)
end

-- The hourly chart of the Today view turned on its side: one row per hour with reading (the hours without it are
-- skipped), a bar as long as the time read in that hour over ALL the sessions, a light grid with its axis in hours
-- on top, the hour on the left and the time on the right. The current hour has a soft band behind it.
local HoursBarsChart = Widget:extend{
    width = 0,
    hours = nil,       -- hours[1..24] = seconds
    current = nil,     -- hour (1..24) to highlight
    minutes = false,   -- true: the axis is in minutes (one day); false: in hours (all the reading)
    segments = nil,    -- segments[1..24] = { { from, to }, ... } seconds inside the hour: draws each stretch read
    font_size = FONT_CAPTION,
}

function HoursBarsChart:init()
    local face = getFace(self.font_size)
    self.rows = {}
    local max_secs = 0
    for h = 1, 24 do
        local v = self.hours[h]
        if v >= HOURS_MIN_LISTED_SECONDS then
            self.rows[#self.rows + 1] = { hour = h, secs = v }
            if v > max_secs then max_secs = v end
        end
    end
    if #self.rows == 0 then  -- very little reading: list every hour that has some
        for h = 1, 24 do
            local v = self.hours[h]
            if v > 0 then
                self.rows[#self.rows + 1] = { hour = h, secs = v }
                if v > max_secs then max_secs = v end
            end
        end
    end
    self.max_secs = max_secs
    if self.segments then
        self.y_max = 60  -- the bar is the hour itself, in minutes
    elseif self.minutes then
        -- axis maximum in minutes: 15, 30, 60, or a multiple of 60 (as the chart of the Today view)
        local max_min = max_secs / 60
        self.y_max = (max_min <= 15 and 15) or (max_min <= 30 and 30) or (math.ceil(max_min / 60) * 60)
    else
        self.y_max = niceCeil(max_secs / 3600)  -- axis maximum in hours
    end
    self.unit_secs = self.minutes and 60 or 3600

    local peak
    for _i, row in ipairs(self.rows) do
        if row.secs == max_secs then peak = row.hour end
        row.label_widget = TextWidget:new{
            text = string.format("%02d", row.hour - 1), face = face,
            bold = (row.hour == self.current or row.hour == peak),
            fgcolor = (row.hour == self.current) and COLOR_TEXT or COLOR_MUTED,
        }
        row.value_widget = TextWidget:new{ text = secondsToShortHM(row.secs), face = face, fgcolor = COLOR_TEXT }
    end
    self.peak = peak
    self.tick_widgets = {}
    for i = 0, 2 do
        self.tick_widgets[i + 1] = TextWidget:new{
            text = self.minutes and string.format("%d", self.y_max * i / 2) or formatHours(self.y_max * i / 2),
            face = face, fgcolor = COLOR_MUTED,
        }
    end

    self.label_w, self.value_w = 0, 0
    for _i, row in ipairs(self.rows) do
        self.label_w = math.max(self.label_w, row.label_widget:getSize().w)
        self.value_w = math.max(self.value_w, row.value_widget:getSize().w)
    end
    self.label_w = self.label_w + SPACE.l
    self.value_w = self.value_w + SPACE.l
    self.text_h = self.tick_widgets[1]:getSize().h
    self.head_h = self.text_h + SPACE.s
    self.row_h = math.max(Screen:scaleBySize(26), self.text_h + SPACE.m)
    self.fill = hoursBarFill()
    self.dimen = Geom:new{ w = self.width, h = self.head_h + #self.rows * self.row_h + SPACE.s }
end

function HoursBarsChart:getSize()
    return self.dimen
end

function HoursBarsChart:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local plot_x = x + self.label_w
    local plot_w = self.width - self.label_w - self.value_w
    local top = y + self.head_h
    local rows_h = #self.rows * self.row_h

    -- soft band behind the current hour
    for i, row in ipairs(self.rows) do
        if row.hour == self.current then
            bb:paintRect(x, top + (i - 1) * self.row_h, self.width, self.row_h, COLOR_SOFT)
        end
    end

    -- grid: 0, half and full scale, with the axis on top
    for i = 0, 2 do
        local gx = plot_x + math.floor(plot_w * i / 2)
        bb:paintRect(gx, top, Size.line.thin, rows_h, i == 0 and COLOR_BAR or COLOR_TRACK)
        local tw = self.tick_widgets[i + 1]
        local ts = tw:getSize()
        local tx = gx - math.floor(ts.w / 2)
        tx = math.max(x, math.min(tx, x + self.width - ts.w))
        tw:paintTo(bb, tx, y)
    end

    local bar_h = math.floor(self.row_h * 0.62)
    local border = Size.border.thin
    for i, row in ipairs(self.rows) do
        local ry = top + (i - 1) * self.row_h
        local by = ry + math.floor((self.row_h - bar_h) / 2)
        if self.segments then
            -- the hour as a light track, with each stretch read where it happened inside the hour
            bb:paintRect(plot_x, by, plot_w, bar_h, COLOR_TRACK)
            for _k, seg in ipairs(self.segments[row.hour] or {}) do
                local sx = plot_x + math.floor(plot_w * seg[1] / 3600)
                local sw = math.max(3, math.floor(plot_w * (seg[2] - seg[1]) / 3600 + 0.5))
                sw = math.min(sw, plot_x + plot_w - sx)
                bb:paintRect(sx, by, sw, bar_h, Blitbuffer.COLOR_BLACK)
                if sw - 2 * border > 0 and bar_h - 2 * border > 0 then
                    bb:paintRect(sx + border, by + border, sw - 2 * border, bar_h - 2 * border, self.fill)
                end
            end
        else
            local bw = math.max(3, math.floor(plot_w * (row.secs / self.unit_secs) / self.y_max + 0.5))
            bb:paintRect(plot_x, by, bw, bar_h, Blitbuffer.COLOR_BLACK)
            if bw - border > 0 and bar_h - 2 * border > 0 then
                bb:paintRect(plot_x, by + border, bw - border, bar_h - 2 * border, self.fill)
            end
        end
        local ls, vs = row.label_widget:getSize(), row.value_widget:getSize()
        row.label_widget:paintTo(bb, x + self.label_w - SPACE.l - ls.w, ry + math.floor((self.row_h - ls.h) / 2))
        row.value_widget:paintTo(bb, x + self.width - vs.w, ry + math.floor((self.row_h - vs.h) / 2))
    end
end

function HoursBarsChart:free()
    for _i, row in ipairs(self.rows) do
        row.label_widget:free()
        row.value_widget:free()
    end
    for _k, w in ipairs(self.tick_widgets) do w:free() end
end

-- The widgets of the bars look: the Today view on its side, in green, with the time of ALL the sessions in each hour.
-- Total and sessions on top (like Today), the share of morning, afternoon, evening and night, and the
-- chart; when its rows do not fit they scroll.
local function buildHoursBarsWidgets(w_width, data, parent)
    local sh = Screen:getHeight()
    local sums = { 0, 0, 0, 0 }
    for h = 1, 24 do
        local p = periodOfHour(h - 1)
        sums[p] = sums[p] + data.hours[h]
    end

    local hero = HorizontalGroup:new{
        align = "bottom",
        TextWidget:new{ text = secondsToHM(data.total), face = getFace(FONT_HERO), bold = true, fgcolor = COLOR_TEXT },
        HorizontalSpan:new{ width = SPACE.xl },
        TextWidget:new{
            text = string.format("%d %s", data.sessions, data.sessions == 1 and _("session") or _("sessions")),
            face = getFace(FONT_SUBTITLE), bold = true, fgcolor = COLOR_MUTED,
        },
    }
    -- the share of each part of the day (the busiest hour is the longest bar of the chart)
    local cols = {}
    for i, p in ipairs(DAY_PERIODS) do
        cols[i] = { string.format("%d%%", math.floor(sums[i] * 100 / data.total + 0.5)), p.name }
    end
    local stats = buildColumns(w_width, cols, false)

    local chart = HoursBarsChart:new{
        width = w_width - ScrollableContainer:getScrollbarWidth(),
        hours = data.hours,
        current = (os.date("*t")).hour + 1,
    }
    local widgets = {
        CenterContainer:new{ dimen = Geom:new{ w = w_width, h = hero:getSize().h }, hero },
        makeVerticalSpacing(SPACE.l),
        stats,
        makeVerticalSpacing(SPACE.xl),
    }
    local max_h = math.floor(sh * 0.5)
    if chart:getSize().h > max_h then
        widgets[#widgets + 1] = SwipePassthroughScrollable:new{
            dimen = Geom:new{ w = w_width, h = max_h },
            show_parent = parent,
            chart,
        }
    else
        widgets[#widgets + 1] = chart
    end
    return widgets
end

-- The widgets of the look "today_hours": the Today view on its side, in green, with the reading of TODAY in each hour
-- (the session in progress included). The same top as the Today view: the total and the books, and four figures.
local function buildTodayHoursWidgets(w_width, data, parent)
    local sh = Screen:getHeight()
    local function clock(secs) return os.date("%H:%M", data.day_start + secs) end

    local hours = {}
    for h = 1, 24 do
        local sum = 0
        for _r, sec in pairs(data.hours[h]) do sum = sum + sec end
        hours[h] = sum
    end

    local hero = HorizontalGroup:new{
        align = "bottom",
        TextWidget:new{
            text = secondsToHM(data.total), face = getFace(FONT_HERO), bold = true, fgcolor = COLOR_TEXT,
        },
        HorizontalSpan:new{ width = SPACE.xl },
        TextWidget:new{
            text = string.format("%d %s", #data.books, #data.books == 1 and _("book") or _("books")),
            face = getFace(FONT_SUBTITLE), bold = true, fgcolor = COLOR_MUTED,
        },
    }
    local stats = buildColumns(w_width, {
        { clock(data.first),                         _("Started") },
        { clock(data.last),                          _("Last read") },
        { secondsToShortHM(data.longest),            _("Longest") .. " " .. clock(data.longest_start) },
        { secondsToShortHM(data.best_secs),          _("Best hour") .. string.format(" %02d", data.best_hour) },
    }, false)

    local chart = HoursBarsChart:new{
        width = w_width - ScrollableContainer:getScrollbarWidth(),
        hours = hours,
        current = data.current_hour,
        minutes = true,
        segments = data.hour_segments,
    }
    local widgets = {
        CenterContainer:new{ dimen = Geom:new{ w = w_width, h = hero:getSize().h }, hero },
        makeVerticalSpacing(SPACE.l),
        stats,
        makeVerticalSpacing(SPACE.xl),
    }
    local max_h = math.floor(sh * 0.5)
    if chart:getSize().h > max_h then
        widgets[#widgets + 1] = SwipePassthroughScrollable:new{
            dimen = Geom:new{ w = w_width, h = max_h },
            show_parent = parent,
            chart,
        }
    else
        widgets[#widgets + 1] = chart
    end
    return widgets
end

-- The Today view. It is one window with three looks (parent.today_mode):
--   "today"        the hours of today (the stacked chart)
--   "today_hours"  the same design on its side, in green: the reading of today in each hour
--   "all_hours"    the same design on its side, in green: the time of ALL the sessions in each hour
-- A tap switches between "today" and "today_hours", a hold between "all_hours" and "today" (see
-- ShowLongestSessionsWindow).
local function buildTodayView(w_width, parent)
    local mode = parent and parent.today_mode or "today"
    local day_t = parent and parent.day_t   -- a day picked in the month view (nil = today)
    if mode == "all_hours" then
        local data, err = loadHourlyData()
        if not data then return nil, err end
        return buildHoursBarsWidgets(w_width, data, parent)
    end
    local widgets, err
    if mode == "today" then
        widgets, err = buildTodayDayView(w_width, day_t)
    else
        local data
        data, err = loadTodayData(day_t)
        if data then widgets, err = buildTodayHoursWidgets(w_width, data, parent) end
    end
    if widgets then return widgets end
    if err == TODAY_EMPTY then
        -- nothing read yet today: still open the window (a tap or hold can switch to the other views)
        return {
            CenterContainer:new{
                dimen = Geom:new{ w = w_width, h = Screen:scaleBySize(120) },
                TextWidget:new{
                    text = day_t and _("No reading this day") or TODAY_EMPTY, face = getFace(FONT_SUBTITLE), bold = true,
                    fgcolor = COLOR_MUTED, max_width = w_width,
                },
            },
        }
    end
    return nil, err
end


-- ── Books and pages per month ────────────────────────────────────────────────
-- The second look of the "Hours per Month" window (a tap on the window switches): a line chart with the books and the
-- pages of each month of the year, each on its own axis (books on the left, pages on the right), like a small
-- yearly report. A book counts in a month when it has at least a minute of reading in it (every session counts).
-- The pages are only the stable (reference) pages saved with the sessions (ref_pages): the sessions without them
-- add no pages.

local BOOK_MIN_SECONDS = 60

-- First letter (UTF-8) of a month name
local function firstLetter(text)
    return tostring(text):match("^[%z\1-\127\194-\244][\128-\191]*") or ""
end

-- Books and pages of every month of the current year. Returns
--   { books = { [1..12] }, pages = { [1..12] }, total_books, total_pages, month }, or nil and a message.
local function loadBooksPagesData()
    local now = os.date("*t")
    local year_start = os.time({ year = now.year, month = 1, day = 1, hour = 0 })

    local has_ref = false
    local cols = queryAll("PRAGMA table_info(wpm_stat_data)", function(row) return tostring(row[2]) end)
    for _i, name in ipairs(cols or {}) do
        if name == "ref_pages" then has_ref = true end
    end
    -- only the sessions that saved stable pages add pages
    local pages_expr = has_ref and "COALESCE(ref_pages, 0)" or "0"

    local rows, err = queryAll(string.format([[
        SELECT month, COUNT(*), COALESCE(SUM(pages), 0) FROM (
            SELECT CAST(strftime('%%m', start_time, 'unixepoch', 'localtime') AS INTEGER) AS month,
                   id_book, SUM(duration) AS secs, SUM(%s) AS pages
            FROM wpm_stat_data
            WHERE start_time >= %d
            GROUP BY month, id_book
            HAVING SUM(duration) >= %d
        )
        GROUP BY month
    ]], pages_expr, year_start, BOOK_MIN_SECONDS), function(row)
        return { month = tonumber(row[1]), books = tonumber(row[2]) or 0, pages = tonumber(row[3]) or 0 }
    end)
    if not rows then return nil, err end
    if #rows == 0 then return nil, _("No reading data found for this year") end

    local out = { books = {}, pages = {}, total_pages = 0, month = now.month }
    for m = 1, 12 do out.books[m], out.pages[m] = 0, 0 end
    for _i, r in ipairs(rows) do
        if r.month and r.month >= 1 and r.month <= 12 then
            out.books[r.month], out.pages[r.month] = r.books, r.pages
            out.total_pages = out.total_pages + r.pages
        end
    end

    -- books of the whole year (a book read in two months counts once)
    local t = queryAll(string.format([[
        SELECT COUNT(*) FROM (
            SELECT id_book FROM wpm_stat_data WHERE start_time >= %d
            GROUP BY id_book HAVING SUM(duration) >= %d
        )
    ]], year_start, BOOK_MIN_SECONDS), function(row) return tonumber(row[1]) or 0 end)
    out.total_books = (t and t[1]) or 0
    return out
end

-- Colors of the two lines: red and blue on a color screen, dark and light gray on black and white
local function booksPagesColors()
    if Screen.isColorEnabled and Screen:isColorEnabled() then
        local ok1, red = pcall(Blitbuffer.colorFromName, "red")
        local ok2, blue = pcall(Blitbuffer.colorFromName, "blue")
        if ok1 and ok2 and red and blue then return red, blue end
    end
    return COLOR_ACCENT, COLOR_BAR
end

-- A thick line between two points (the framebuffer has no line call: small squares along it)
local function paintThickLine(bb, x1, y1, x2, y2, thick, color)
    local dx, dy = x2 - x1, y2 - y1
    local steps = math.max(math.abs(dx), math.abs(dy), 1)
    local half = math.floor(thick / 2)
    for i = 0, steps do
        bb:paintRect(math.floor(x1 + dx * i / steps) - half, math.floor(y1 + dy * i / steps) - half,
            thick, thick, color)
    end
end

-- Two lines over the months, one axis on each side. Both axes have the same four steps, so one grid serves both.
local BooksPagesChart = Widget:extend{
    width = 0,
    height = 0,
    books = nil,       -- books[1..12]
    pages = nil,       -- pages[1..12]
    last = 12,         -- last month drawn (the months to come have no line)
    font_size = FONT_CAPTION,
}

function BooksPagesChart:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local face = getFace(self.font_size)

    local max_b, max_p = 0, 0
    for m = 1, 12 do
        max_b = math.max(max_b, self.books[m])
        max_p = math.max(max_p, self.pages[m])
    end
    self.b_max = math.max(4, math.ceil(max_b / 4) * 4)          -- 4, 8, 12, 16...
    self.p_step = niceCeil(math.max(max_p, 4) / 4)               -- 250, 500, 1000...
    self.p_max = self.p_step * 4

    self.left_ticks, self.right_ticks, self.month_widgets = {}, {}, {}
    self.left_w, self.right_w = 0, 0
    for i = 0, 4 do
        local l = TextWidget:new{ text = string.format("%d", self.b_max * i / 4), face = face, fgcolor = COLOR_MUTED }
        local r = TextWidget:new{ text = groupThousands(self.p_step * i), face = face, fgcolor = COLOR_MUTED }
        self.left_ticks[i + 1], self.right_ticks[i + 1] = l, r
        self.left_w = math.max(self.left_w, l:getSize().w)
        self.right_w = math.max(self.right_w, r:getSize().w)
    end
    self.left_w = self.left_w + SPACE.l
    self.right_w = self.right_w + SPACE.l
    for m = 1, 12 do
        self.month_widgets[m] = TextWidget:new{
            text = firstLetter(MONTH_NAMES[m]), face = face,
            bold = (m == self.last), fgcolor = (m == self.last) and COLOR_TEXT or COLOR_MUTED,
        }
    end
    self.text_h = self.left_ticks[1]:getSize().h
    self.color_books, self.color_pages = booksPagesColors()
end

function BooksPagesChart:getSize()
    return self.dimen
end

function BooksPagesChart:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local top = y + math.floor(self.text_h / 2) + SPACE.s
    local plot_h = self.height - (top - y) - self.text_h - SPACE.l - SPACE.s
    local base = top + plot_h
    local plot_x = x + self.left_w
    local plot_w = self.width - self.left_w - self.right_w
    local slot = plot_w / 12

    -- grid with the two axes
    for i = 0, 4 do
        local gy = base - math.floor(plot_h * i / 4)
        bb:paintRect(plot_x, gy, plot_w, Size.line.thin, i == 0 and COLOR_BAR or COLOR_TRACK)
        local lw, rw = self.left_ticks[i + 1], self.right_ticks[i + 1]
        lw:paintTo(bb, plot_x - SPACE.l - lw:getSize().w, gy - math.floor(lw:getSize().h / 2))
        rw:paintTo(bb, plot_x + plot_w + SPACE.l, gy - math.floor(rw:getSize().h / 2))
    end

    local function px(m) return plot_x + math.floor((m - 0.5) * slot) end
    local function drawSeries(values, vmax, color)
        local thick = Screen:scaleBySize(2)
        local r = Screen:scaleBySize(4)
        local pts = {}
        for m = 1, self.last do
            pts[m] = { px(m), base - math.floor(plot_h * values[m] / vmax + 0.5) }
        end
        for m = 2, self.last do
            paintThickLine(bb, pts[m - 1][1], pts[m - 1][2], pts[m][1], pts[m][2], thick, color)
        end
        for m = 1, self.last do
            local px_, py_ = pts[m][1], pts[m][2]
            if m == self.last then
                -- the current month: a bigger ring
                bb:paintRect(px_ - r - 1, py_ - r - 1, 2 * r + 2, 2 * r + 2, color)
                bb:paintRect(px_ - r + 1, py_ - r + 1, 2 * r - 2, 2 * r - 2, Blitbuffer.COLOR_WHITE)
                bb:paintRect(px_ - 1, py_ - 1, 3, 3, color)
            else
                bb:paintRect(px_ - r + 1, py_ - r + 1, 2 * r - 1, 2 * r - 1, color)
            end
        end
    end
    drawSeries(self.pages, self.p_max, self.color_pages)
    drawSeries(self.books, self.b_max, self.color_books)

    for m = 1, 12 do
        local mw = self.month_widgets[m]
        local ms = mw:getSize()
        mw:paintTo(bb, px(m) - math.floor(ms.w / 2), base + SPACE.l)
    end
end

function BooksPagesChart:free()
    for _i, list in ipairs({ self.left_ticks, self.right_ticks, self.month_widgets }) do
        for _k, w in pairs(list) do w:free() end
    end
end

-- The widgets of the look "books": the totals of the year on top (each one with the color of its line), the chart
-- and a short line that says what is counted.
local function buildBooksPagesView(w_width)
    local data, err = loadBooksPagesData()
    if not data then return nil, err end
    local color_books, color_pages = booksPagesColors()

    local function legendItem(color, text)
        local dot = Screen:scaleBySize(12)
        return HorizontalGroup:new{
            align = "center",
            PillBar:new{ width = dot, height = dot, color = color },
            HorizontalSpan:new{ width = SPACE.m },
            TextWidget:new{ text = text, face = getFace(FONT_SUBTITLE), bold = true, fgcolor = COLOR_TEXT },
        }
    end
    local legend = HorizontalGroup:new{
        align = "center",
        legendItem(color_books, string.format("%d %s", data.total_books, data.total_books == 1 and _("book") or _("books"))),
        HorizontalSpan:new{ width = SPACE.xl * 2 },
        legendItem(color_pages, string.format("%s %s", groupThousands(data.total_pages), _("pages"))),
    }
    local chart = BooksPagesChart:new{
        width = w_width,
        height = math.min(Screen:scaleBySize(250), math.floor(Screen:getHeight() * 0.4)),
        books = data.books,
        pages = data.pages,
        last = data.month,
    }
    return {
        CenterContainer:new{ dimen = Geom:new{ w = w_width, h = legend:getSize().h }, legend },
        makeVerticalSpacing(SPACE.xl),
        chart,
        makeVerticalSpacing(SPACE.l),
        makeSummaryLine(w_width, _("Books and stable pages read, per month")),
    }
end

-- The "Hours per Month" window has two looks (parent.month_mode): the hours of each month, or the books and pages.
-- A tap on the window switches between them (see ShowLongestSessionsWindow:onTapClose).
local function buildMonthlyChartView(w_width, parent)
    if parent and parent.month_mode == "books" then return buildBooksPagesView(w_width) end
    return buildMonthlyHoursView(w_width)
end

-- ── View definitions ─────────────────────────────────────────────────────────

-- One line of text on the left: the item's `field`, cut with "…" if too long.
local function textLabel(field)
    return function(item, ctx)
        return TextWidget:new{
            text = item[field],
            face = getFace(FONT_TEXT),
            max_width = ctx.max_width,
            ellipsis = true,
        }
    end
end

-- A title with the current year: "Hours per Month · 2026"
local function yearTitle(name)
    return function()
        return string.format("%s" .. TITLE_SEPARATOR .. "%d", name, os.date("*t").year)
    end
end

local WINDOW_WIDTH_FACTOR = 0.85  -- window width, as a share of the screen width

local VIEWS = {
    {
        -- not a list: it builds its own widgets (the start-menu modules as cards)
        title = _("Reading Summary"),
        build = buildSummaryView,
        width_factor = 0.65,  -- narrower than the other views (they use WINDOW_WIDTH_FACTOR)
    },
    {
        -- not a list: it builds its own widgets (hourly chart of today, or of all the reading: see buildTodayView)
        title = function(win)
            local mode = win and win.today_mode or "today"
            if win and win.day_t and mode ~= "all_hours" then
                local day = os.date("%d %B %Y", win.day_t)
                return mode == "today_hours" and (day .. TITLE_SEPARATOR .. _("by hour")) or day
            end
            if mode == "today_hours" then return _("Today by hour") end
            if mode == "all_hours" then return _("Reading by hour") end
            return _("Today")
        end,
        build = buildTodayView,
    },
    {
        -- not a list: it builds its own widgets (a tap on a day shows that day as the Today view)
        title = function(win)
            local now = os.date("*t")
            local y = win and win.month_y or now.year
            local m = win and win.month_m or now.month
            return string.format("%s" .. TITLE_SEPARATOR .. "%s %d", _("Reading Days"),
                os.date("%B", os.time({ year = y, month = m, day = 1, hour = 12 })), y)
        end,
        build = buildMonthView,
    },
    {
        -- not a list: it builds its own widgets
        title = function(win)
            if win and win.month_mode == "books" then
                return string.format("%s" .. TITLE_SEPARATOR .. "%d", _("Books and Pages"), os.date("*t").year)
            end
            return yearTitle(_("Hours per Month"))()
        end,
        build = buildMonthlyChartView,
    },
    {
        -- not a list: it builds its own widgets
        title = function(win)
            if win and win.days_mode == "weekdays" then return _("Reading by Weekday") end
            return _("Days Read per Year")
        end,
        build = buildDaysReadChartView,
    },
    {
        -- not a list: it builds its own widgets
        title = _("Days per Year"),
        build = buildDaysPerYearView,
    },
    {
        -- not a list: it builds its own widgets
        title = function()
            local year = os.date("*t").year
            return string.format("%s" .. TITLE_SEPARATOR .. "%d-%d", _("Reading Heatmap"), year - HEATMAP_YEARS + 1, year)
        end,
        build = buildHeatmapView,
    },
    {
        -- finished books read this year, most time first
        title = yearTitle(_("Books Finished")),
        -- says what was found, to tell if the problem is detecting finished books
        empty = function()
            return string.format(_("No finished books read this year (%s)"), finished_info)
        end,
        row_height = ROW_HEIGHT_TALL,
        bar_indent = BOOK_RANK_W,
        -- number of books and the time spent on them
        summary = function(items)
            local total = 0
            for _i, item in ipairs(items) do total = total + (item.duration or 0) end
            return string.format("%s %d %s" .. SUMMARY_SEPARATOR .. "%s",
                _("Total"), #items, _("books"), secondsToDH(total))
        end,
        sql = function()
            local year_start = os.time({ year = os.date("*t").year, month = 1, day = 1, hour = 0 })
            local filter = getFinishedBooksFilter()
            -- books with less than a minute are accidental openings
            return string.format([[
                SELECT book.title, SUM(wpm_stat_data.duration), COUNT(*), MAX(wpm_stat_data.start_time)
                FROM wpm_stat_data
                INNER JOIN book ON wpm_stat_data.id_book = book.id
                WHERE wpm_stat_data.start_time >= %d AND %s
                GROUP BY book.id
                HAVING SUM(wpm_stat_data.duration) >= 60
                ORDER BY SUM(wpm_stat_data.duration) DESC
                LIMIT 100
            ]], year_start, filter)
        end,
        map = function(row, n)
            return {
                rank = n,
                title = row[1] or _("Unknown"),
                duration = tonumber(row[2]),
                sessions = tonumber(row[3]) or 0,
                last = tonumber(row[4]) or 0,
            }
        end,
        -- rank number, then the title and "sessions · last read"
        left = function(item, ctx)
            return HorizontalGroup:new{
                align = "top",
                LeftContainer:new{
                    dimen = Geom:new{ w = BOOK_RANK_W, h = Screen:scaleBySize(22) },
                    TextWidget:new{
                        text = tostring(item.rank),
                        face = getFace(FONT_TEXT),
                        bold = true,
                        fgcolor = item.rank <= 3 and COLOR_TEXT or COLOR_MUTED,
                    },
                },
                VerticalGroup:new{
                    align = "left",
                    TextWidget:new{
                        text = item.title,
                        face = getFace(FONT_TEXT),
                        max_width = ctx.max_width - BOOK_RANK_W,
                        ellipsis = true,
                    },
                    TextWidget:new{
                        text = string.format("%d %s" .. SUMMARY_SEPARATOR .. "%s %s",
                            item.sessions, _("sessions"), _("last"), os.date("%d/%m", item.last)),
                        face = getFace(FONT_CAPTION),
                        fgcolor = COLOR_MUTED,
                    },
                },
            }
        end,
    },
    {
        title = _("Time per Month"),
        empty = _("No monthly data found"),
        row_height = ROW_HEIGHT_NORMAL,
        -- local time, as the dates of the sessions list (not UTC)
        sql = [[
            SELECT
                strftime('%Y', start_time, 'unixepoch', 'localtime') AS year,
                CAST(strftime('%m', start_time, 'unixepoch', 'localtime') AS INTEGER) AS month,
                SUM(duration) AS total_duration
            FROM wpm_stat_data
            WHERE start_time > 0
            GROUP BY year, month
            ORDER BY year DESC, month DESC
        ]],
        map = function(row)
            return {
                label = string.format("%s %d", row[1], tonumber(row[2])),
                duration = tonumber(row[3]),
            }
        end,
        left = textLabel("label"),
    },
    {
        title = _("Longest Reading Sessions"),
        empty = _("No session data found"),
        row_height = ROW_HEIGHT_TALL,
        sql = [[
            SELECT book.title, wpm_stat_data.duration, wpm_stat_data.start_time
            FROM wpm_stat_data
            INNER JOIN book ON wpm_stat_data.id_book = book.id
            WHERE wpm_stat_data.start_time > 0
            ORDER BY wpm_stat_data.duration DESC
            LIMIT 200;
        ]],
        map = function(row)
            return { title = row[1] or _("Unknown"), duration = tonumber(row[2]), start_time = tonumber(row[3]) }
        end,
        -- two lines: the book's title and the date
        left = function(item, ctx)
            return VerticalGroup:new{
                align = "left",
                TextWidget:new{
                    text = item.title,
                    face = getFace(FONT_TEXT),
                    max_width = ctx.max_width,
                    ellipsis = true,
                },
                TextWidget:new{
                    text = formatDateTime(item.start_time),
                    face = getFace(FONT_CAPTION),
                    fgcolor = COLOR_MUTED,
                },
            }
        end,
    },
    {
        title = _("Time per Device"),
        empty = _("No device data found"),
        row_height = ROW_HEIGHT_NORMAL,
        sql = [[
            SELECT id_device, SUM(duration) as total_duration
            FROM wpm_stat_data
            GROUP BY id_device
            ORDER BY total_duration DESC
        ]],
        map = function(row)
            local id = tonumber(row[1])
            return {
                name = DEVICE_NAMES[id] or string.format(_("Device %s"), tostring(id)),
                duration = tonumber(row[2]),
            }
        end,
        left = textLabel("name"),
    },
    {
        title = _("Time per Font"),
        empty = _("No font data found"),
        row_height = ROW_HEIGHT_NORMAL,
        sql = [[
            SELECT COALESCE(font_name, 'Unknown'), SUM(duration) as total_duration
            FROM wpm_stat_data
            GROUP BY font_name
            ORDER BY total_duration DESC
        ]],
        map = function(row)
            return { name = row[1], duration = tonumber(row[2]) }
        end,
        left = textLabel("name"),
    },
}

-- ── Main window ──────────────────────────────────────────────────────────────

function ShowLongestSessionsWindow:init()
    self.current_view = self.current_view or 1
    self:_buildUI()
end

function ShowLongestSessionsWindow:_buildUI()
    local t_ui = Perf.start()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local w_width = math.floor(screen_width * (VIEWS[self.current_view].width_factor or WINDOW_WIDTH_FACTOR))
    if screen_width > screen_height then
        w_width = math.floor(w_width * screen_height / screen_width)
    end

    local w_padding_internal = SPACE.xl
    local w_padding_external = Screen:scaleBySize(14)

    -- Nothing to show: tell the user why, and see showWindow.
    local function fail(message)
        UIManager:show(InfoMessage:new{ text = message or _("Unknown error") })
        self.failed = true
    end

    -- The widgets that go under the title: a list in a scrollable
    -- container, or whatever the view builds itself.
    local view_def = VIEWS[self.current_view]
    local body
    local t_body = Perf.start()
    if view_def.build then
        local widgets, err = view_def.build(w_width, self)
        if not widgets then return fail(err) end
        body = widgets
    else
        local rows, num_items, row_height, items = buildRows(view_def, w_width)
        -- on failure the second value is the message
        if not rows then return fail(num_items) end

        -- As many rows as fit in 70% of the screen, up to 12
        local effective_row_height = row_height + Size.line.thin
        local rows_fit = math.max(1, math.floor(screen_height * 0.7 / effective_row_height))
        local scrollable_height = math.min(num_items, rows_fit, 12) * effective_row_height
        body = {
            SwipePassthroughScrollable:new{
                dimen = Geom:new{ w = w_width, h = scrollable_height },
                show_parent = self,
                rows,
            },
        }
        -- a line under the list, for the views that have a summary
        if view_def.summary then
            body[#body + 1] = makeVerticalSpacing(w_padding_internal, 0.8)
            body[#body + 1] = makeSummaryLine(w_width, view_def.summary(items))
        end
    end
    Perf.log("view body (view " .. self.current_view .. ")", t_body)

    -- Title on the left, "n / total" on the right
    local title_text = type(view_def.title) == "function" and view_def.title(self) or view_def.title
    local counter_w = Screen:scaleBySize(56)
    local title_widget = TextWidget:new{
        text = title_text,
        face = getFace(FONT_TITLE),
        bold = true,
        fgcolor = COLOR_TEXT,
        max_width = w_width - counter_w - SPACE.xl,
        ellipsis = true,
    }
    local counter_widget = TextWidget:new{
        text = string.format("%d / %d", self.current_view, #VIEWS),
        face = getFace(FONT_CAPTION),
        fgcolor = COLOR_MUTED,
    }
    local title_h = title_widget:getSize().h
    local title_row = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = w_width - counter_w, h = title_h },
            title_widget,
        },
        RightContainer:new{
            dimen = Geom:new{ w = counter_w, h = title_h },
            counter_widget,
        },
    }

    local content = VerticalGroup:new{
        title_row,
        makeVerticalSpacing(w_padding_internal, 1.2),
    }
    for _i, widget in ipairs(body) do
        content[#content + 1] = widget
    end

    -- Page dots, so it is clear that the views can be swiped
    local dots = PagerDots:new{ count = #VIEWS, current = self.current_view }
    content[#content + 1] = makeVerticalSpacing(w_padding_internal, 1.2)
    content[#content + 1] = CenterContainer:new{
        dimen = Geom:new{ w = w_width, h = dots:getSize().h },
        dots,
    }

    local frame = FrameContainer:new{
        radius = Screen:scaleBySize(28),
        bordersize = Screen:scaleBySize(2),
        padding = w_padding_external,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }

    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        frame,
    }

    self.dimen = Geom:new{ x = 0, y = 0, w = screen_width, h = screen_height }

    if Device:hasDPad() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        }
        self.ges_events.Swipe = {
            GestureRange:new{ ges = "swipe", range = self.dimen },
        }
        self.ges_events.HoldExplain = {
            GestureRange:new{ ges = "hold", range = self.dimen },
        }
        -- month view: two-finger swipe left = previous month, right = next month
        self.ges_events.MonthSwipe = {
            GestureRange:new{ ges = "two_finger_swipe", range = self.dimen },
        }
        -- some devices only report the hold when the finger is lifted
        self.ges_events.HoldReleaseExplain = {
            GestureRange:new{ ges = "hold_release", range = self.dimen },
        }
    end
    Perf.log("_buildUI TOTAL (view " .. self.current_view .. ")", t_ui)
end

-- Builds the window for a view and shows it. Returns the window, or nil when
-- it could not be built (the user has been told why).
local function showWindow(current_view)
    local t_new = Perf.start()
    local widget = ShowLongestSessionsWindow:new{ current_view = current_view }
    Perf.log("ShowLongestSessionsWindow:new", t_new)
    if widget.failed then return nil end
    local t_show = Perf.start()
    UIManager:show(widget, "ui", widget.dimen)
    Perf.log("UIManager:show", t_show)
    return widget
end

function ShowLongestSessionsWindow:onSwipe(arg, ges)
    self.ignore_hold = nil  -- a new touch: the opening hold is over
    -- a swipe down closes the window
    if ges.direction == "south" then
        return self:onClose()
    end
    local BD = require("ui/bidi")
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    local next_view
    if direction == "west" then
        next_view = (self.current_view % #VIEWS) + 1
    elseif direction == "east" then
        next_view = ((self.current_view - 2) % #VIEWS) + 1
    else
        return false
    end
    -- the new view first: if it fails, this one stays
    Perf.open_t0 = Perf.start()  -- time of the view change, up to the first paint
    local widget = ShowLongestSessionsWindow:new{ current_view = next_view }
    if widget.failed then
        Perf.open_t0 = nil
        return true
    end
    UIManager:close(self)
    UIManager:show(widget, "ui", widget.dimen)
    return true
end

function ShowLongestSessionsWindow:onShow()
    -- dithered: the cover is a photo, without it e-ink shows banding
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen, true
    end)
    if DEBUG_PERF and Perf.open_t0 then
        local t0 = Perf.open_t0
        Perf.log("onShow (from start)", t0)
        -- the real paint happens in the next UIManager cycle
        UIManager:nextTick(function()
            Perf.log("FIRST PAINT (from start)", t0)
        end)
        Perf.open_t0 = nil
    end
    return true
end

function ShowLongestSessionsWindow:onClose()
    local frame_dimen = self[1] and self[1][1] and self[1][1].dimen
    UIManager:close(self, "ui", frame_dimen)
    -- Come back to where the window was opened from, if it says so (see
    -- PageTextInfo:showReadingSummary). Swiping between views does not come here.
    local back = ShowLongestSessionsWindow.on_close
    ShowLongestSessionsWindow.on_close = nil
    if back then UIManager:nextTick(back) end
    return true
end

-- The text of the window that a hold on the card explains while reading: how each figure of the card is worked out
-- (now, and how the stable pages were worked out before), and the real numbers of the session in progress.
local function buildReadingExplainItems()
    local ui = getReaderUI()
    local stats = ui and ui.statistics
    local min_pages = tonumber(stats and stats.min_pages_valid_session) or 3
    local min_mins = math.floor((tonumber(stats and stats.min_time_valid_session) or 180) / 60)
    local items = {}

    items[#items + 1] = {
        _("This book"),
        _("The total time you have read this book: the time of all the previous sessions plus the session in progress."),
    }
    items[#items + 1] = {
        _("Session"),
        string.format(_("The time since the session started, by the clock, pauses between page turns included. A session starts when the book is opened, when the device wakes up and at midnight. It is only saved if it is valid: at least %d pages and %d minutes read."),
            min_pages, min_mins),
    }
    items[#items + 1] = {
        _("wpm"),
        _("Words per minute of the session: the words of the pages counted as read, divided by the minutes of reading time. A page counts when you stay on it at least the minimum seconds and at most the maximum seconds set in the statistics settings (if you stay longer, it counts as the maximum). The reading time is the sum of those times, not the clock time, so a pause does not lower it. It is updated at every counted page turn, and it shows 0 if no page has been counted for 5 minutes. This is worked out as before."),
    }
    items[#items + 1] = {
        _("pages (screen)"),
        _("The screens (pages of the current layout) read in the session, so it changes with the font size and margins. It is the highest of three counts: the different pages saved in the statistics since the session started, the pages still in memory that are not saved yet, and the pages counted by the statistics plugin in this session. This is worked out as before."),
    }
    items[#items + 1] = {
        _("pages (stable)"),
        _("Reference pages: the pages of the print edition (the page numbers of the book's page map), so they do not change with the font size. The number after the dot is the reference page where the session started.\n\nNow: the reference page you are on minus the reference page where the session started. The start is taken at the first page turn counted as read and is provisional: if you jump more than 15 reference pages before the session is valid, it is forgotten and taken again where you resume reading. It is fixed when the session becomes valid (the pages and minutes above); from then on jumps do not move it. The same subtraction is what is saved as ref_pages, together with the start as ref_start. If you go back before the start, it shows 0.\n\nBefore: it was an estimate from the words, the words read in the session divided by the words of the book, times the reference pages of the book. It assumed every reference page has the same amount of text, so a short page or a chapter start moved it, and it did not know where you actually were in the book.\n\nIt only appears when the book has reference pages and the reader is using them when the session starts. Turning that option on or off during the session changes nothing: the session keeps the mode it started with. A session that starts without reference pages is saved without them (no ref_pages, no ref_start), even if you turn the option on later, so it is left out of avg wpm and pages/day. A session that starts with them keeps them even if you turn the option off later."),
    }

    items[#items + 1] = {
        _("Progress"),
        _("Besides the reference pages, every session saves the progress of the book (a percentage) where it started and where it ended (pct_start and pct_end), and the reference page where it ended (ref_end). The progress is saved even in books without reference pages. It follows the same rules as the start reference page: the start is provisional at the first page turn counted as read, it is taken again after a jump of more than 20 screens, and it is fixed when the session is valid. It is shown in the list of sessions, after the pages."),
    }

    -- the real numbers of the session in progress
    local live
    pcall(function()
        if not stats then return end
        if not stats:refPagesAllowed() then
            live = _("This session is not using reference pages, so there is no stable figure.")
            return
        end
        local start = tonumber(stats._session_start_ref)
        local pending = tonumber(stats._pending_start_ref)
        local current = stats:getCurrentRefPage()
        if start and current then
            live = string.format(_("Start %d (fixed), now %d: %d pages."), start, current, current - start)
        elseif pending and current then
            live = string.format(_("Start %d (provisional, it is fixed when the session is valid), now %d: %d pages."),
                pending, current, current - pending)
        else
            live = _("No start yet: it is taken at the first page turn counted as read.")
        end
    end)
    pcall(function()
        if not stats then return end
        local pct = stats:getCurrentProgress()
        local start_pct = tonumber(stats._session_start_pct or stats._pending_start_pct)
        if pct and start_pct then
            local text = string.format(_("Progress from %.1f%% to %.1f%%."), start_pct, pct)
            live = live and (live .. "\n" .. text) or text
        end
    end)
    if live then items[#items + 1] = { _("Right now"), live } end
    return items
end

-- Hold on the right card of the book card (bottom right of the summary): a window explaining its four figures.
-- A hold anywhere else on this window is swallowed, so it never reaches the reader underneath.
function ShowLongestSessionsWindow:onHoldExplain(arg, ges)
    -- the hold that opened this window is still going on: not a hold on it
    if self.ignore_hold then return true end
    -- a hold on the window of the Today view: the hours of all the reading (and back to today); outside it, nothing
    if VIEWS[self.current_view].build == buildTodayView then
        if self:isOnWindow(ges) then
            self:switchTodayMode(self.today_mode == "all_hours" and "today" or "all_hours")
        end
        return true
    end
    if VIEWS[self.current_view].build ~= buildSummaryView or not (ges and ges.pos) then
        return true
    end
    -- the hold and its release both arrive: only one window
    if explain_window_open then return true end
    local rc = summary_book_card and summary_book_card[3]
    local rd = rc and rc.dimen
    local pos = ges.pos
    logger.info(string.format("longest sessions: hold at %s,%s card %s", tostring(pos.x), tostring(pos.y),
        rd and string.format("%s,%s %sx%s", tostring(rd.x), tostring(rd.y), tostring(rd.w), tostring(rd.h)) or "nil"))
    if not (rd and rd.w and rd.w > 0) then return true end
    if pos.x < rd.x or pos.x >= rd.x + rd.w or pos.y < rd.y or pos.y >= rd.y + rd.h then
        return true
    end
    -- while reading the card shows the session in progress: the window explains how its figures are worked out
    if summary_book_reading then
        explain_window_open = true
        UIManager:show(ExplainWindow:new{ title = _("Session"), items = buildReadingExplainItems() }, "ui")
        return true
    end
    -- the summary with the real figures and the sessions with exact data
    local summary, sessions, sessions_title, top_sessions, top_title
    local ok_list, err_list = pcall(function()
        local s, list, top = loadExactData(MAX_LISTED_SESSIONS, MAX_TOP_SESSIONS)
        summary = buildSummaryItems(s)
        sessions = buildSessionItems(list)
        top_sessions = buildSessionItems(top)
        top_title = string.format(_("Longest sessions (top %d)"), #top)
        if s.exact > #list then
            sessions_title = string.format(_("Sessions (last %d of %d)"), #list, s.exact)
        else
            sessions_title = string.format(_("Sessions (%d)"), #list)
        end
    end)
    if not ok_list then
        logger.warn("longest sessions: could not build the session list:", err_list)
        summary, sessions = nil, nil
        summary = { { _("Statistics"), _("Could not read the statistics database") } }
    end
    explain_window_open = true
    UIManager:show(ExplainWindow:new{
        title = _("Summary"), summary = summary, sessions = sessions, sessions_title = sessions_title,
        top_sessions = top_sessions, top_title = top_title,
    }, "ui")
    return true
end

function ShowLongestSessionsWindow:onHoldReleaseExplain(arg, ges)
    -- the release of the hold that opened this window: swallow it, once
    if self.ignore_hold then
        self.ignore_hold = nil
        return true
    end
    -- on the Today view only the hold changes the look (its release must not change it again)
    if VIEWS[self.current_view].build == buildTodayView then
        return true
    end
    return self:onHoldExplain(arg, ges)
end

-- true when the gesture is on the window itself (its rounded frame), not on the empty screen around it
function ShowLongestSessionsWindow:isOnWindow(ges)
    local frame = self[1] and self[1][1]
    local d = frame and frame.dimen
    local pos = ges and ges.pos
    if not (d and d.w and d.w > 0 and pos) then return false end
    return pos.x >= d.x and pos.x < d.x + d.w and pos.y >= d.y and pos.y < d.y + d.h
end

-- Shows the Today view again in another look ("today", "today_hours" or "all_hours"), in a new window like when swiping
-- between views. If it cannot be built (the user has been told why) this window stays.
function ShowLongestSessionsWindow:switchTodayMode(mode)
    local widget = ShowLongestSessionsWindow:new{ current_view = self.current_view, today_mode = mode,
        day_t = self.day_t, back = self.back }
    if widget.failed then return end
    UIManager:close(self)
    UIManager:show(widget, "ui", widget.dimen)
end

-- Shows the "Hours per Month" view again in another look ("hours" or "books"), as switchTodayMode does
function ShowLongestSessionsWindow:switchMonthMode(mode)
    local widget = ShowLongestSessionsWindow:new{ current_view = self.current_view, month_mode = mode }
    if widget.failed then return end
    UIManager:close(self)
    UIManager:show(widget, "ui", widget.dimen)
end

-- Shows the "Days Read per Year" view again in another look ("years" or "weekdays")
function ShowLongestSessionsWindow:switchDaysMode(mode)
    local widget = ShowLongestSessionsWindow:new{ current_view = self.current_view, days_mode = mode }
    if widget.failed then return end
    UIManager:close(self)
    UIManager:show(widget, "ui", widget.dimen)
end

-- Replaces this window with another view (fields = what to give ShowLongestSessionsWindow:new). If the new one
-- cannot be built (the user has been told why) this window stays.
function ShowLongestSessionsWindow:replaceWith(fields)
    local widget = ShowLongestSessionsWindow:new(fields)
    if widget.failed then return end
    UIManager:close(self)
    UIManager:show(widget, "ui", widget.dimen)
end

-- Two-finger swipe left / right: in the Month view, previous / next month (not past the current month);
-- in the Today view (a day or its hours), previous / next day (not past today)
function ShowLongestSessionsWindow:onMonthSwipe(arg, ges)
    self.ignore_hold = nil
    local build = VIEWS[self.current_view].build
    if build ~= buildMonthView and build ~= buildTodayView then return false end
    local BD = require("ui/bidi")
    local direction = BD.flipDirectionIfMirroredUILayout(ges and ges.direction)
    local step = (direction == "west" and -1) or (direction == "east" and 1) or nil
    if not step then return true end
    local now = os.date("*t")
    if build == buildTodayView then
        if self.today_mode == "all_hours" then return true end   -- all the reading: no day to move
        local d = os.date("*t", self.day_t or os.time())
        local t = os.time{ year = d.year, month = d.month, day = d.day + step, hour = 12 }
        local nd = os.date("*t", t)
        if nd.year > now.year or (nd.year == now.year and nd.yday > now.yday) then return true end   -- no days to come
        local is_today = (nd.year == now.year and nd.yday == now.yday)
        self:replaceWith{ current_view = self.current_view, today_mode = self.today_mode,
            day_t = (not is_today) and t or nil, back = self.back }
        return true
    end
    local y = self.month_y or now.year
    local m = (self.month_m or now.month) + step
    if m < 1 then y, m = y - 1, 12 elseif m > 12 then y, m = y + 1, 1 end
    if y > now.year or (y == now.year and m > now.month) then return true end   -- no months to come
    self:replaceWith{ current_view = self.current_view, month_y = y, month_m = m }
    return true
end

function ShowLongestSessionsWindow:onTapClose(arg, ges)
    self.ignore_hold = nil  -- a new touch: the opening hold is over
    -- on the month view a tap on a day shows that day as the Today view (screen 2) does for today
    if VIEWS[self.current_view].build == buildMonthView and self:isOnWindow(ges) then
        local grid = self._month_grid
        local day = grid and grid:dayAt(ges.pos)
        if day then
            local today_view
            for i, v in ipairs(VIEWS) do
                if v.build == buildTodayView then today_view = i break end
            end
            if today_view then
                self:replaceWith{
                    current_view = today_view, today_mode = "today",
                    day_t = os.time{ year = grid.year, month = grid.month, day = day, hour = 12 },
                    -- where a tap outside goes back to: this month (and from it, where the month came from)
                    back = { current_view = self.current_view, month_y = grid.year, month_m = grid.month,
                        back = self.back },
                }
                return true
            end
        end
    end
    -- on the heatmap a tap on a month opens that month in the month view (screen 3); a tap outside it goes back
    if VIEWS[self.current_view].build == buildHeatmapView and self:isOnWindow(ges) then
        for _i, grid in ipairs(self._heat_grids or {}) do
            local month = grid:monthAt(ges.pos)
            if month then
                local month_view
                for i, v in ipairs(VIEWS) do
                    if v.build == buildMonthView then month_view = i break end
                end
                if month_view then
                    self:replaceWith{ current_view = month_view, month_y = grid.year, month_m = month,
                        back = { current_view = self.current_view } }
                    return true
                end
            end
        end
    end
    -- a day picked in the month view (or a month picked in the heatmap): a tap outside the window goes back
    -- to where it was picked instead of closing
    if self.back and not self:isOnWindow(ges) then
        self:replaceWith(self.back)
        return true
    end
    -- on the days read per year a tap on the window changes between the years and the days of the week
    if VIEWS[self.current_view].build == buildDaysReadChartView and self:isOnWindow(ges) then
        self:switchDaysMode(self.days_mode == "weekdays" and "years" or "weekdays")
        return true
    end
    -- on the monthly chart a tap on the window changes between the hours and the books and pages of each month; a tap
    -- outside the window closes it as always
    if VIEWS[self.current_view].build == buildMonthlyChartView and self:isOnWindow(ges) then
        self:switchMonthMode(self.month_mode == "books" and "hours" or "books")
        return true
    end
    -- on the Today view a tap on the window does not close it: it changes between today and the reading of today by
    -- hour (swipe down or Back close it). A tap outside the window closes it as always.
    if VIEWS[self.current_view].build == buildTodayView and self:isOnWindow(ges) then
        self:switchTodayMode(self.today_mode == "today_hours" and "today" or "today_hours")
        return true
    end
    -- on the summary, a tap on a zone (TBR, MBR, Finished) closes the window and then acts
    if VIEWS[self.current_view].build == buildSummaryView and ges and ges.pos then
        local zone = hitSummaryZone(ges.pos)
        if zone then
            -- leaving for Bookshelf: do not come back to where the window was opened from
            ShowLongestSessionsWindow.on_close = nil
            self:onClose()
            UIManager:nextTick(zone.callback)
            return true
        end
    end
    self:onClose()
    return true
end

-- ── Embedded Reading Summary (sleep screen) ─────────────────────────────────
-- The first screen of the window (Reading Summary) as a small widget for other code, e.g. the sleep screen
-- patch. It is built exactly as in the window, drawn in an off-screen buffer and shrunk by `scale`
-- (0.5 = half of its normal size). Returns an image widget, or nil and a message. It has no input handling:
-- the host widget paints it. Registered in package.loaded, so any code can use it once this module has loaded:
--     local ok, Embed = pcall(require, "reading_summary_embed")
--     local widget, err = Embed.build(0.5)

local function buildEmbeddedSummary(scale)
    scale = math.min(math.max(tonumber(scale) or 0.5, 0.1), 1)
    local view = VIEWS[1]
    local screen_width, screen_height = Screen:getWidth(), Screen:getHeight()
    local w_width = math.floor(screen_width * (view.width_factor or WINDOW_WIDTH_FACTOR))
    if screen_width > screen_height then
        w_width = math.floor(w_width * screen_height / screen_width)
    end

    -- show_parent is only used to refresh a scroll; there is nothing to refresh here
    local widgets, err = view.build(w_width, {})
    if not widgets then return nil, err end

    local content = VerticalGroup:new{
        TextWidget:new{
            text = type(view.title) == "function" and view.title() or view.title,
            face = getFace(FONT_TITLE), bold = true, fgcolor = COLOR_TEXT, max_width = w_width,
        },
        makeVerticalSpacing(SPACE.xl, 1.2),
    }
    for _i, w in ipairs(widgets) do content[#content + 1] = w end

    -- square corners: the buffer is white, so rounded ones would show white wedges over the wallpaper
    local frame = FrameContainer:new{
        radius = 0,
        bordersize = Screen:scaleBySize(2),
        padding = Screen:scaleBySize(14),
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
    local size = frame:getSize()
    local bb = Blitbuffer.new(size.w, size.h, Screen.bb:getType())
    bb:fill(Blitbuffer.COLOR_WHITE)
    frame:paintTo(bb, 0, 0)
    pcall(function() frame:free() end)

    local ImageWidget = require("ui/widget/imagewidget")
    return ImageWidget:new{
        image = bb,
        image_disposable = true,   -- the image widget frees the buffer
        width = math.max(1, math.floor(size.w * scale)),
        height = math.max(1, math.floor(size.h * scale)),
        scale_factor = 0,          -- exactly that size (same proportions, so no distortion)
    }
end

package.loaded["reading_summary_embed"] = { build = buildEmbeddedSummary }

-- ── Setup ────────────────────────────────────────────────────────────────────
-- This file is a module, loaded from the plugin's main.lua:
--
--     local setupLongestSessions = require("top_reading_sessions")
--     setupLongestSessions(PageTextInfo)
--
-- It must be required at the top level of main.lua (while the plugin loads),
-- because the plugin folder is only in package.path during that time.

return function(PageTextInfo)
    Dispatcher:registerAction("show_longest_sessions", {
        category = "none",
        event = "ShowLongestSessions",
        title = _("Show longest reading sessions"),
        general = true,
    })

    -- Name of the device that inserted the last session into the statistics
    -- database (id_device of the newest row of wpm_stat_data). Used by the title
    -- of the actions menu. Ordering by rowid is instant (no table scan).
    -- Returns nil when it cannot be read.
    function PageTextInfo:getLastSessionDeviceName()
        local rows = queryAll([[
            SELECT id_device FROM wpm_stat_data
            ORDER BY rowid DESC
            LIMIT 1
        ]], function(row) return tonumber(row[1]) end)
        if not rows or rows[1] == nil then return nil end
        local id = rows[1]
        return DEVICE_NAMES[id] or string.format(_("Device %s"), tostring(id))
    end

    -- Opens the Reading Summary like the ShowLongestSessions event and calls
    -- `on_close` when the user closes it (not when swiping between views, and not
    -- when a tap on TBR / MBR / Finished leaves for Bookshelf). The actions menu
    -- uses it to come back to the menu. Returns true if the window was shown.
    function PageTextInfo:showReadingSummary(on_close)
        Perf.open_t0 = Perf.start()
        -- save the session in progress first, so it is in the lists
        if self.ui and self.ui.statistics then
            self.ui.statistics:insertDB()
        end
        local widget = showWindow()
        if widget then
            ShowLongestSessionsWindow.on_close = on_close
            -- opened by a hold of the menu: the finger may still be down, so that
            -- hold and its release must not count as a hold on this window
            widget.ignore_hold = true
        end
        return widget ~= nil
    end

    -- Reader: the plugin receives the event
    function PageTextInfo:onShowLongestSessions()
        Perf.open_t0 = Perf.start()
        local t_total = Perf.open_t0
        -- save the session in progress first, so it is in the lists
        if self.ui and self.ui.statistics then
            local t_db = Perf.start()
            self.ui.statistics:insertDB()
            Perf.log("statistics:insertDB", t_db)
        end
        showWindow()
        Perf.log("onShowLongestSessions TOTAL (sync)", t_total)
        return true
    end

    -- File manager: the plugin may not be loaded there, so the event is
    -- handled by the file manager itself
    local FileManager = require("apps/filemanager/filemanager")
    function FileManager:onShowLongestSessions()
        Perf.open_t0 = Perf.start()
        local t_total = Perf.open_t0
        showWindow()
        Perf.log("onShowLongestSessions TOTAL (sync, FM)", t_total)
        return true
    end

    logger.info("Longest sessions module loaded")
end