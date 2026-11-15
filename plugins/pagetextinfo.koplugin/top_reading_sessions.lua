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
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local _ = require("gettext")

local DEVICE_NAMES = {
    [0]   = "Unknown device",
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
    [99]  = "Physical book",
    [100] = "Emulator",
}

local MONTH_NAMES = {
    _("Jan"), _("Feb"), _("Mar"), _("Apr"), _("May"), _("Jun"),
    _("Jul"), _("Aug"), _("Sep"), _("Oct"), _("Nov"), _("Dec"),
}

local ShowLongestSessionsWindow = InputContainer:extend({
    modal = true,
    name = "show_longest_sessions_window",
})

-- ── Palette ────────────────────────────────────────────────────────────────────
-- A small set of grays so every view looks the same.

local function gray(v) return Blitbuffer.Color8(v) end

local COLOR_TEXT      = Blitbuffer.COLOR_BLACK
local COLOR_MUTED     = gray(110)  -- secondary text
local COLOR_ACCENT    = gray(30)   -- highlighted bars and dots
local COLOR_BAR       = gray(150)  -- regular bars
local COLOR_TRACK     = gray(225)  -- grid lines and separators

-- ── Formatting helpers ─────────────────────────────────────────────────────────

local SECONDS_PER_DAY = 86400

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

-- ── Shared helpers ─────────────────────────────────────────────────────────────

local ROW_HEIGHT_TALL = Screen:scaleBySize(66)   -- sessions (title + date + bar)
local ROW_HEIGHT_NORMAL = Screen:scaleBySize(46) -- the rest of the views

local function makeVerticalSpacing(w_padding_internal, h)
    h = h or 1
    return VerticalSpan:new({ width = math.floor(w_padding_internal * h) })
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

-- Runs a query on the statistics database and returns its rows, each one
-- turned into an item by `map` (which gets the row table, reused between
-- rows, so it must copy what it needs; it also gets the row number). Returns nil and a message when the
-- database cannot be read; the connection is closed in every case.
local function queryAll(sql_stmt, map)
    local SQ3 = require("lua-ljsqlite3/init")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local items = {}
    local ok, err = pcall(function()
        local conn = SQ3.open(db_location)
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
        return nil, "Could not read the statistics database"
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

-- ── Small custom widgets ───────────────────────────────────────────────────────

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

-- The "page" dots at the bottom: the current view is a longer, darker pill.
local PagerDots = Widget:extend{
    count = 1,
    current = 1,
}

function PagerDots:init()
    self.dot = Screen:scaleBySize(6)
    self.gap = Screen:scaleBySize(6)
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
    font_face = "cfont",
    font_size = 12,
}

function BarChart:init()
    self.dimen = Geom:new{ w = self.width, h = self.height }
    self.count = #self.values
    local face = Font:getFace(self.font_face, self.font_size)

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
    self.gap = Screen:scaleBySize(6)
    self.axis_w = self.axis_w + self.gap
    self.label_h = self.month_widgets[1]:getSize().h
end

function BarChart:getSize()
    return self.dimen
end

function BarChart:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y

    local top_pad = self.label_h + Screen:scaleBySize(4)  -- room for the value labels
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
            vw:paintTo(bb, cx - math.floor(vs.w / 2), by - vs.h - Screen:scaleBySize(2))
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

-- ── View builder ───────────────────────────────────────────────────────────────
-- Most views are the same list: something on the left, the time on the right,
-- and a thin bar under the label showing the share of the longest item.
-- A view says its query (sql), how a row becomes an item (map), what to show
-- on the left (left) and how tall a row is; this builds the rows from that.
-- (A view with its own `build` function, like the heatmap, does not use it.)

local function buildRows(view, w_width, w_font_face, w_font_size_small)
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local padding = Screen:scaleBySize(10) * 2
    local time_widget_width = Screen:scaleBySize(90)
    local bar_max_width = w_width - scrollbar_width - padding - time_widget_width - Screen:scaleBySize(10)
    local bar_height = Screen:scaleBySize(4)
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

    local ctx = { font_face = w_font_face, font_size = w_font_size_small, max_width = bar_max_width }
    local row_height = view.row_height
    local rows = VerticalGroup:new({})

    for i, item in ipairs(items) do
        local ratio = longest > 0 and (item.duration or 0) / longest or 0
        local left = VerticalGroup:new({
            align = "left",
            view.left(item, ctx),
            VerticalSpan:new({ width = Screen:scaleBySize(4) }),
            HorizontalGroup:new({
                HorizontalSpan:new({ width = bar_indent }),
                PillBar:new({
                    width = math.max(bar_height, math.floor((bar_max_width - bar_indent) * ratio)),
                    height = bar_height,
                    color = (i == 1) and COLOR_ACCENT or COLOR_BAR,
                }),
            }),
        })

        local row_item = HorizontalGroup:new({
            align = "center",
            LeftContainer:new({
                dimen = Geom:new({ w = bar_max_width, h = row_height }),
                left,
            }),
            HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
            RightContainer:new({
                dimen = Geom:new({ w = time_widget_width, h = row_height }),
                TextWidget:new({
                    text = secondsToHMS(item.duration),
                    face = Font:getFace(w_font_face, w_font_size_small),
                    bold = true,
                }),
            }),
        })
        table.insert(rows, row_item)
        if i < #items then
            table.insert(rows, makeSeparator(w_width))
        end
    end

    return rows, #items, row_height, items
end

-- ── Chart views ────────────────────────────────────────────────────────────────
-- Shared body of the chart views: the chart and a one-line summary under it.

local function chartBody(w_width, w_font_face, w_font_size_small, chart_args, summary_text)
    chart_args.width = w_width
    chart_args.height = math.min(Screen:scaleBySize(250), math.floor(Screen:getHeight() * 0.4))
    chart_args.font_face = w_font_face
    chart_args.font_size = w_font_size_small - 2
    return {
        BarChart:new(chart_args),
        makeVerticalSpacing(Screen:scaleBySize(8)),
        TextWidget:new{
            text = summary_text,
            face = Font:getFace(w_font_face, w_font_size_small - 1),
            fgcolor = COLOR_MUTED,
            max_width = w_width,
        },
    }
end

-- Bar chart of the hours read in each month of the current year.
local function buildMonthlyChartView(w_width, w_font_face, w_font_size_small)
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
    if #items == 0 then return nil, "No reading data found for this year" end

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

    local summary = string.format("%s %s  \xC2\xB7  %s %s (%s)",
        _("Total"), secondsToDH(total),
        _("Best:"), MONTH_NAMES[best], secondsToDH(values[best] * 3600))
    return chartBody(w_width, w_font_face, w_font_size_small, {
        values = values,
        labels = MONTH_NAMES,
        current = now.month,
    }, summary)
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

-- Days read per year, one row per year (newest first): the year, a track
-- filled with the share of the year's days that had reading, and the count.
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
local function buildYearRows(w_width, w_font_face, w_font_size_small, entries, summary_text)
    local now = os.date("*t")
    local gap = Screen:scaleBySize(10)
    local row_h = Screen:scaleBySize(48)
    local year_w = Screen:scaleBySize(54)
    local count_w = Screen:scaleBySize(84)
    local track_w = w_width - year_w - count_w - 2 * gap
    local face = Font:getFace(w_font_face, w_font_size_small + 1)
    local face_small = Font:getFace(w_font_face, w_font_size_small - 3)

    local rows = VerticalGroup:new({})
    for _i, e in ipairs(entries) do
        local is_current = (e.year == now.year)
        rows[#rows + 1] = HorizontalGroup:new({
            align = "center",
            LeftContainer:new({
                dimen = Geom:new({ w = year_w, h = row_h }),
                TextWidget:new({
                    text = tostring(e.year),
                    face = face,
                    bold = true,
                    fgcolor = is_current and COLOR_TEXT or COLOR_MUTED,
                }),
            }),
            ProgressTrack:new({
                width = track_w,
                height = Screen:scaleBySize(14),
                ratio = e.ratio,
                color = is_current and COLOR_ACCENT or COLOR_BAR,
            }),
            HorizontalSpan:new({ width = gap }),
            RightContainer:new({
                dimen = Geom:new({ w = count_w, h = row_h }),
                VerticalGroup:new({
                    align = "right",
                    TextWidget:new({ text = e.main, face = face, bold = true }),
                    TextWidget:new({ text = e.sub, face = face_small, fgcolor = COLOR_MUTED }),
                }),
            }),
        })
    end

    return {
        rows,
        makeVerticalSpacing(Screen:scaleBySize(8)),
        TextWidget:new{
            text = summary_text,
            face = Font:getFace(w_font_face, w_font_size_small - 1),
            fgcolor = COLOR_MUTED,
            max_width = w_width,
        },
    }
end

-- Days per year: the share of the year's days that had reading.
local function buildDaysPerYearView(w_width, w_font_face, w_font_size_small)
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
    if #items == 0 then return nil, "No reading data found" end

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
    local summary = string.format("%s %d %s  \xC2\xB7  %s %d (%d)",
        _("Total"), total, _("days"), _("Best:"), best.year, best.days)
    return buildYearRows(w_width, w_font_face, w_font_size_small, entries, summary)
end

-- Days read per year: all the reading time of each year added up and shown
-- in days (24 hours each). The track is relative to the best year.
local function buildDaysReadPerYearView(w_width, w_font_face, w_font_size_small)
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
    if #items == 0 then return nil, "No reading data found" end

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
    local summary = string.format("%s %s  \xC2\xB7  %s %d (%s)",
        _("Total"), secondsToDH(total), _("Best:"), best.year, secondsToDH(best.seconds))
    return buildYearRows(w_width, w_font_face, w_font_size_small, entries, summary)
end

-- ── Reading heatmap ────────────────────────────────────────────────────────────
-- Calendar heatmap drawn with the same look as the charts: rounded cells,
-- the same grays, month names on top and a light legend. One column per week,
-- one row per weekday. It shows the whole current year, from January 1st to today.

local HEATMAP_WEEK_STARTS_ON_SUNDAY = false

-- No reading, then 0-25%, 25-50%, 50-75% and 75-100% of the busiest day
local HEAT_COLORS = { gray(238), gray(200), gray(155), gray(100), COLOR_ACCENT }
local DAY_LETTERS = { _("S"), _("M"), _("T"), _("W"), _("T"), _("F"), _("S") } -- Sunday first

local function heatLevel(seconds, max_seconds)
    if seconds <= 0 or max_seconds <= 0 then return 1 end
    local r = seconds / max_seconds
    return (r <= 0.25 and 2) or (r <= 0.5 and 3) or (r <= 0.75 and 4) or 5
end

local HeatmapGrid = Widget:extend{
    width = 0,
    daily = nil,       -- seconds read per day, keyed by "YYYY-MM-DD"
    start_t = 0,       -- first day shown (noon timestamp)
    end_t = 0,         -- last day shown (noon timestamp)
    font_face = "cfont",
    font_size = 12,
}

function HeatmapGrid:init()
    local face = Font:getFace(self.font_face, self.font_size)
    local week_start = HEATMAP_WEEK_STARTS_ON_SUNDAY and 0 or 1
    self.week_start = week_start

    -- Align the grid to the start of the week. Timestamps are taken at noon
    -- so daylight saving changes never move a day.
    local first = os.date("*t", self.start_t)
    local offset = (first.wday - 1 - week_start) % 7
    local ts = self.start_t - offset * SECONDS_PER_DAY

    self.cells, self.month_widgets, self.day_widgets = {}, {}, {}
    self.total, self.active = 0, 0
    local max_seconds, index = 0, 0
    while ts <= self.end_t do
        if ts >= self.start_t then
            local d = os.date("*t", ts)
            local seconds = self.daily[os.date("%Y-%m-%d", ts)] or 0
            local col = math.floor(index / 7)
            self.cells[#self.cells + 1] = { col = col, row = index % 7, seconds = seconds }
            if seconds > 0 then
                self.total = self.total + seconds
                self.active = self.active + 1
                max_seconds = math.max(max_seconds, seconds)
            end
            -- a month name over the column where the month starts
            if d.day == 1 then
                self.month_widgets[#self.month_widgets + 1] = {
                    col = col,
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
    self.cell = math.min(math.floor((self.width - self.label_w) / self.cols), Screen:scaleBySize(30))
    -- thinner gaps when the cells are small (a whole year is ~53 columns)
    self.gap = self.cell < 12 and 1 or math.max(2, math.floor(self.cell * 0.14))
    self.text_h = self.less_widget:getSize().h
    self.head_h = self.text_h + Screen:scaleBySize(4)
    self.legend_gap = Screen:scaleBySize(10)
    self.dimen = Geom:new{
        w = self.width,
        h = self.head_h + 7 * self.cell + self.legend_gap + self.text_h,
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
        bb:paintRoundedRect(grid_x + cell.col * self.cell, grid_y + cell.row * self.cell,
            size, size, HEAT_COLORS[cell.level], radius)
    end

    -- Legend, aligned to the right: Less [] [] [] [] [] More
    local sq = math.floor(self.text_h * 0.8)
    local pad = Screen:scaleBySize(6)
    local legend_w = self.less_widget:getSize().w + pad + 5 * (sq + pad) + self.more_widget:getSize().w
    local lx = x + self.width - legend_w
    local ly = grid_y + 7 * self.cell + self.legend_gap
    self.less_widget:paintTo(bb, lx, ly)
    lx = lx + self.less_widget:getSize().w + pad
    for i = 1, 5 do
        bb:paintRoundedRect(lx, ly + math.floor((self.text_h - sq) / 2), sq, sq, HEAT_COLORS[i], math.floor(sq / 4))
        lx = lx + sq + pad
    end
    self.more_widget:paintTo(bb, lx, ly)
end

function HeatmapGrid:free()
    for _i, mark in ipairs(self.month_widgets) do mark.widget:free() end
    for _r, w in pairs(self.day_widgets) do w:free() end
    self.less_widget:free()
    self.more_widget:free()
end

-- The widgets of the heatmap view (the window puts them under its title).
local function buildHeatmapView(w_width, w_font_face, w_font_size_small)
    local now = os.date("*t")
    -- the period starts on January 1st of this year
    local start_t = os.time({ year = now.year, month = 1, day = 1, hour = 12 })
    local end_t = os.time({ year = now.year, month = now.month, day = now.day, hour = 12 })

    -- seconds read on each day of the period (sessions, by local date)
    local items, err = queryAll(string.format([[
        SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS day, SUM(duration)
        FROM wpm_stat_data
        WHERE start_time >= %d
        GROUP BY day
    ]], start_t - 2 * SECONDS_PER_DAY), function(row)
        return { day = row[1], seconds = tonumber(row[2]) or 0 }
    end)
    if not items then return nil, err end
    if #items == 0 then return nil, "No reading data found" end

    local daily_map = {}
    for _i, item in ipairs(items) do daily_map[item.day] = item.seconds end

    local grid = HeatmapGrid:new{
        width = w_width,
        daily = daily_map,
        start_t = start_t,
        end_t = end_t,
        font_face = w_font_face,
        font_size = w_font_size_small - 4,  -- small text: the cells are tight
    }

    return {
        grid,
        makeVerticalSpacing(Screen:scaleBySize(8)),
        TextWidget:new{
            text = string.format("%s %s  \xC2\xB7  %d %s", _("Total"), secondsToHM(grid.total), grid.active, _("active days")),
            face = Font:getFace(w_font_face, w_font_size_small - 1),
            fgcolor = COLOR_MUTED,
            max_width = w_width,
        },
    }
end

-- ── Reading summary (first screen) ─────────────────────────────────────────────
-- The start-menu modules as stacked cards (shelf size, reading time with differential, book
-- info with session time and reading speed), like the start menu.
-- The reading figures come from one read-only connection to the statistics database.
-- No open-session time is added: showing this window already saved the
-- session in progress (see onShowLongestSessions), so it is in the database.

local DELTA_PACE_KEY = "micromodule_reading_delta_pace"  -- same key as the module
local DEFAULT_PACE = 2                                    -- hours per day

-- The pace is a setting of the reading differential module. This plugin may
-- not be able to load that module's settings store; then the default is used.
local function readPace()
    local loaders = {
        function() return require("lib/bookshelf_settings_store") end,
        function() return dofile("plugins/bookshelf.koplugin/lib/bookshelf_settings_store.lua") end,
    }
    for _i, load in ipairs(loaders) do
        local ok, Store = pcall(load)
        if ok and type(Store) == "table" and Store.read then
            local ok_read, v = pcall(Store.read, DELTA_PACE_KEY)
            v = ok_read and tonumber(v) or nil
            if v and v > 0 then return v end
        end
    end
    return DEFAULT_PACE
end

local function fmtPace(h)
    if h == math.floor(h) then return string.format("%dh/d", h) end
    return string.format("%.1fh/d", h)
end

-- "1h 8m" / "25m"
local function fmtHM(secs)
    secs = math.max(0, math.floor(tonumber(secs) or 0))
    local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
    if h > 0 then return string.format("%dh %dm", h, m) end
    return string.format("%dm", m)
end

-- "2h" for a whole hour, otherwise as fmtHM (reading stats module)
local function fmtStats(secs)
    secs = math.max(0, math.floor(tonumber(secs) or 0))
    local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
    if h > 0 and m == 0 then return string.format("%dh", h) end
    return fmtHM(secs)
end

-- "12.5h" / "1.2d" / "40m" (reading time module)
local function fmtBreakdown(secs)
    secs = tonumber(secs) or 0
    local h = secs / 3600
    if h >= 24 then return string.format("%.1fd", h / 24) end
    if h >= 1 then return string.format("%.1fh", h) end
    return string.format("%dm", math.floor(secs / 60))
end

-- Reads every figure of the summary. Returns nil when the database cannot be read.
local function loadSummaryData()
    local lfs = require("libs/libkoreader-lfs")
    local path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
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
            out.today     = span(day_start, now)
            out.yesterday = span(day_start - SECONDS_PER_DAY, day_start - 1)
            out.month     = span(month_start, now)
            out.lmonth    = span(lmonth_start, month_start - 1)
            out.year      = span(year_start, now)
            overlap:close()

            -- Per-page statistics (reading stats module); optional
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
        end)
        conn:close()
        if not ok_q then error(err_q, 0) end
    end)
    if not ok then
        logger.warn("longest sessions: summary query failed:", err)
        return nil
    end
    return out
end

-- Time of the current session and on the open book (nil outside the reader)
local function getSessionInfo()
    local ok, ui = pcall(function() return require("apps/reader/readerui").instance end)
    if not ok or not ui then return nil end
    local topbar = ui.view and ui.view.topbar
    if not topbar or not topbar.start_session_time then return nil end
    local session = math.max(0, os.time() - topbar.start_session_time)
    return session, session + (topbar.initial_total_time_book or 0)
end

-- ── Cards ──
local CARD_BG = gray(238)
local CARD_PAD = Screen:scaleBySize(10)

local function cardInnerWidth(card_w)
    return card_w - 2 * (CARD_PAD + Size.border.thin)
end

local function makeCard(card_w, content)
    return FrameContainer:new({
        background = CARD_BG,
        color = COLOR_BAR,
        bordersize = Size.border.thin,
        radius = Screen:scaleBySize(10),
        padding = CARD_PAD,
        margin = 0,
        CenterContainer:new({
            dimen = Geom:new({ w = cardInnerWidth(card_w), h = content:getSize().h }),
            content,
        }),
    })
end

-- The biggest size (down to min_size) at which every text fits in max_w.
local function fitSize(texts, max_size, min_size, max_w, bold)
    local best = max_size
    for _i, text in ipairs(texts) do
        local size = max_size
        while size > min_size do
            local tw = TextWidget:new({ text = text, face = Font:getFace("cfont", size), bold = bold })
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
    local avail = col_w - Screen:scaleBySize(6)
    local values, captions = {}, {}
    for i, c in ipairs(cols) do values[i], captions[i] = c[1], c[2] end
    local vsize = fitSize(values, 24, 12, avail, true)
    local csize = fitSize(captions, 14, 9, avail, false)

    local groups, max_h = {}, 0
    for i, c in ipairs(cols) do
        local value = TextWidget:new({
            text = c[1], face = Font:getFace("cfont", vsize), bold = true,
            fgcolor = COLOR_TEXT, max_width = avail,
        })
        local caption = TextWidget:new({
            text = c[2], face = Font:getFace("cfont", csize),
            fgcolor = COLOR_MUTED, max_width = avail,
        })
        local gap = VerticalSpan:new({ width = Screen:scaleBySize(2) })
        local vg = VerticalGroup:new({ align = "center" })
        if caption_on_top then
            vg[1], vg[2], vg[3] = caption, gap, value
        else
            vg[1], vg[2], vg[3] = value, gap, caption
        end
        groups[i] = vg
        max_h = math.max(max_h, vg:getSize().h)
    end
    local row = HorizontalGroup:new({ align = "top" })
    for i, vg in ipairs(groups) do
        row[i] = CenterContainer:new({ dimen = Geom:new({ w = col_w, h = max_h }), vg })
    end
    return row
end

-- First row: differential (ΔL), today, yesterday, this week, month, last month, year
local function buildBreakdownCard(card_w, data)
    local pace = readPace()
    local delta = math.ceil((data.year / 3600) - (data.yday * pace))
    return makeCard(card_w, buildColumns(cardInnerWidth(card_w), {
        { (delta > 0 and "+" or "") .. tostring(delta), "\xCE\x94L " .. fmtPace(pace) },
        { fmtHM(data.today),            _("Today") },
        { fmtBreakdown(data.yesterday), _("Yesterday") },
        { data.week and fmtStats(data.week) or "-", _("This week") },
        { fmtBreakdown(data.month),     _("Month") },
        { fmtBreakdown(data.lmonth),    _("Last month") },
        { fmtBreakdown(data.year),      _("Year") },
    }, true))
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
    local pages   = tonumber(raw:match('"Pages"%s*:%s*(%d+)'))
    local updated = tonumber(raw:match('"updated"%s*:%s*(%d+)'))
    if not wpm or not updated then return 0, 0 end
    if os.time() - updated > WPM_STALE_S then return 0, 0 end
    return wpm, pages or 0
end

-- Title, series, words and publication year of the open book
local function buildBookCard(card_w, session, book)
    local full_w = cardInnerWidth(card_w)
    local right_w = math.floor(full_w * 0.58)
    local gap = Screen:scaleBySize(10)
    local inner_w = full_w - right_w - gap  -- width of the title block

    -- Right block, next to the title: time on this book, then the session
    -- time, wpm and pages of the session
    local wpm, pages = readWpmSession()
    local right = buildColumns(right_w, {
        { book and fmtHM(book) or "-",       _("This book") },
        { session and fmtHM(session) or "-", _("Session") },
        { tostring(wpm),                      _("wpm") },
        { tostring(pages),                    _("pages") },
    }, false)
    local function withRight(left)
        local h = math.max(left:getSize().h, right:getSize().h)
        return makeCard(card_w, HorizontalGroup:new({
            align = "top",
            CenterContainer:new({ dimen = Geom:new({ w = inner_w, h = h }), left }),
            HorizontalSpan:new({ width = gap }),
            CenterContainer:new({ dimen = Geom:new({ w = right_w, h = h }), right }),
        }))
    end

    local ok, ui = pcall(function() return require("apps/reader/readerui").instance end)
    local topbar = ok and ui and ui.view and ui.view.topbar
    local title = topbar and topbar.title or ""
    if title == "" then
        return withRight(TextWidget:new({
            text = _("Not reading"), face = Font:getFace("cfont", 22),
            fgcolor = COLOR_MUTED, max_width = inner_w,
        }))
    end
    local function clean(s)
        s = tostring(s or ""):gsub("^%s*\xE2\x8B\x85%s*", ""):gsub("%[/?b%]", ""):gsub("\xEF\xBF\xBC", "")
        return (s:match("^%s*(.-)%s*$"))
    end
    local words = tonumber(topbar.total_words) or 0
    local parts = {}
    if words > 0 then
        parts[#parts + 1] = (words >= 1000 and string.format("%dk", math.floor(words / 1000)) or tostring(words)) .. "w"
    end
    local pub = tostring(topbar.pub_date or "")
    if pub ~= "" then parts[#parts + 1] = pub end

    local vg = VerticalGroup:new({ align = "center" })
    vg[#vg + 1] = TextWidget:new({
        text = clean(title), face = Font:getFace("cfont", 24), bold = true,
        fgcolor = COLOR_TEXT, max_width = inner_w, ellipsis = true,
    })
    local series = clean(topbar.series)
    if series ~= "" then
        vg[#vg + 1] = VerticalSpan:new({ width = Screen:scaleBySize(4) })
        vg[#vg + 1] = TextWidget:new({
            text = series, face = Font:getFace("cfont", 18),
            fgcolor = COLOR_MUTED, max_width = inner_w, ellipsis = true,
        })
    end
    if #parts > 0 then
        vg[#vg + 1] = VerticalSpan:new({ width = Screen:scaleBySize(4) })
        vg[#vg + 1] = TextWidget:new({
            text = table.concat(parts, "  \xC2\xB7  "), face = Font:getFace("cfont", 18),
            fgcolor = COLOR_MUTED, max_width = inner_w, ellipsis = true,
        })
    end
    return withRight(vg)
end

-- ── Tappable zones of the summary ──
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
    local ok_ui, ReaderUI = pcall(require, "apps/reader/readerui")
    local rui = ok_ui and ReaderUI and ReaderUI.instance
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
    return total, counts
end

local function buildShelfCard(card_w)
    local inner_w = cardInnerWidth(card_w)
    local total, counts = getShelfCounts()
    local cols = {}
    for i, st in ipairs(SHELF_STATUS) do
        cols[i] = { tostring(counts[st[1]]), st[2] }
    end
    local header = HorizontalGroup:new({
        align = "bottom",
        TextWidget:new({ text = tostring(total), face = Font:getFace("cfont", 34), bold = true, fgcolor = COLOR_TEXT }),
        HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
        TextWidget:new({ text = _("Books"), face = Font:getFace("cfont", 18), bold = true, fgcolor = COLOR_MUTED }),
    })
    local row = buildColumns(inner_w, cols, true)
    local vg = VerticalGroup:new({
        align = "center",
        CenterContainer:new({ dimen = Geom:new({ w = inner_w, h = header:getSize().h }), header }),
        VerticalSpan:new({ width = Screen:scaleBySize(6) }),
        row,
    })
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
local function buildSummaryView(w_width, w_font_face, w_font_size_small, parent)
    local data = loadSummaryData()
    if not data then return nil, "Could not read the statistics database" end
    local session, book = getSessionInfo()

    local function buildCards(card_w)
        summary_tap_zones = {}
        local cards = VerticalGroup:new({ align = "center" })
        local list = {
            buildShelfCard(card_w),
            buildBreakdownCard(card_w, data),
            buildBookCard(card_w, session, book),
        }
        for i, card in ipairs(list) do
            if i > 1 then table.insert(cards, VerticalSpan:new({ width = Screen:scaleBySize(6) })) end
            table.insert(cards, card)
        end
        return cards
    end

    local cards = buildCards(w_width)
    local max_h = math.floor(Screen:getHeight() * 0.7)
    if cards:getSize().h <= max_h then return { cards } end

    cards:free()
    cards = buildCards(w_width - ScrollableContainer:getScrollbarWidth())
    return { SwipePassthroughScrollable:new({
        dimen = Geom:new({ w = w_width, h = max_h }),
        show_parent = parent,
        cards,
    }) }
end

-- ── View definitions ───────────────────────────────────────────────────────────

-- One line of text on the left: the item's `field`, cut with "…" if too long.
local function textLabel(field)
    return function(item, ctx)
        return TextWidget:new({
            text = item[field],
            face = Font:getFace(ctx.font_face, ctx.font_size),
            max_width = ctx.max_width,
            ellipsis = true,
        })
    end
end

-- ── Finished books ─────────────────────────────────────────────────────────────
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
    if #conditions == 0 then return "0" end
    return "(" .. table.concat(conditions, " OR ") .. ")"
end

local VIEWS = {
    {
        -- not a list: it builds its own widgets (the start-menu modules as cards)
        title = "Reading Summary",
        build = buildSummaryView,
    },
    {
        -- not a list: it builds its own widgets
        title = function() return string.format("Hours per Month \xC2\xB7 %d", os.date("*t").year) end,
        build = buildMonthlyChartView,
    },
    {
        -- not a list: it builds its own widgets
        title = "Days Read per Year",
        build = buildDaysReadPerYearView,
    },
    {
        -- not a list: it builds its own widgets
        title = "Days per Year",
        build = buildDaysPerYearView,
    },
    {
        -- not a list: it builds its own widgets
        title = function() return string.format("Reading Heatmap \xC2\xB7 %d", os.date("*t").year) end,
        build = buildHeatmapView,
    },
    {
        -- finished books read this year, most time first
        title = function() return string.format("Books Finished \xC2\xB7 %d", os.date("*t").year) end,
        -- says what was found, to tell if the problem is detecting finished books
        empty = function() return "No finished books read this year (" .. finished_info .. ")" end,
        row_height = ROW_HEIGHT_TALL,
        bar_indent = BOOK_RANK_W,
        -- number of books and the time spent on them
        summary = function(items)
            local total = 0
            for _i, item in ipairs(items) do total = total + (item.duration or 0) end
            return string.format("%s %d %s  \xC2\xB7  %s", _("Total"), #items, _("books"), secondsToDH(total))
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
                title = row[1] or "Unknown",
                duration = tonumber(row[2]),
                sessions = tonumber(row[3]) or 0,
                last = tonumber(row[4]) or 0,
            }
        end,
        -- rank number, then the title and "sessions · last read"
        left = function(item, ctx)
            return HorizontalGroup:new({
                align = "top",
                LeftContainer:new({
                    dimen = Geom:new({ w = BOOK_RANK_W, h = Screen:scaleBySize(22) }),
                    TextWidget:new({
                        text = tostring(item.rank),
                        face = Font:getFace(ctx.font_face, ctx.font_size),
                        bold = true,
                        fgcolor = item.rank <= 3 and COLOR_TEXT or COLOR_MUTED,
                    }),
                }),
                VerticalGroup:new({
                    align = "left",
                    TextWidget:new({
                        text = item.title,
                        face = Font:getFace(ctx.font_face, ctx.font_size),
                        max_width = ctx.max_width - BOOK_RANK_W,
                        ellipsis = true,
                    }),
                    TextWidget:new({
                        text = string.format("%d %s  \xC2\xB7  %s %s", item.sessions, _("sessions"),
                            _("last"), os.date("%d/%m", item.last)),
                        face = Font:getFace(ctx.font_face, ctx.font_size - 2),
                        fgcolor = COLOR_MUTED,
                    }),
                }),
            })
        end,
    },
    {
        title = "Time per Month",
        empty = "No monthly data found",
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
        title = "Longest Reading Sessions",
        empty = "No session data found",
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
            return { title = row[1] or "Unknown", duration = tonumber(row[2]), start_time = tonumber(row[3]) }
        end,
        -- two lines: the book's title and the date
        left = function(item, ctx)
            return VerticalGroup:new({
                align = "left",
                TextWidget:new({
                    text = item.title,
                    face = Font:getFace(ctx.font_face, ctx.font_size),
                    max_width = ctx.max_width,
                    ellipsis = true,
                }),
                TextWidget:new({
                    text = formatDateTime(item.start_time),
                    face = Font:getFace(ctx.font_face, ctx.font_size - 2),
                    fgcolor = COLOR_MUTED,
                }),
            })
        end,
    },
    {
        title = "Time per Device",
        empty = "No device data found",
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
                name = DEVICE_NAMES[id] or ("Device " .. tostring(id)),
                duration = tonumber(row[2]),
            }
        end,
        left = textLabel("name"),
    },
    {
        title = "Time per Font",
        empty = "No font data found",
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

-- ── Main window ────────────────────────────────────────────────────────────────

function ShowLongestSessionsWindow:init()
    self.current_view = self.current_view or 1
    self:_buildUI()
end

function ShowLongestSessionsWindow:_buildUI()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local w_width = math.floor(screen_width * 0.85)
    if screen_width > screen_height then
        w_width = math.floor(w_width * screen_height / screen_width)
    end

    local w_font_face = "cfont"
    local w_font_size_med = 20
    local w_font_size_small = 15
    local w_padding_internal = Screen:scaleBySize(10)
    local w_padding_external = Screen:scaleBySize(14)

    -- Nothing to show: tell the user why, and see showWindow.
    local function fail(message)
        UIManager:show(InfoMessage:new({ text = _(message or "Unknown error") }))
        self.failed = true
    end

    -- The widgets that go under the title: a list in a scrollable
    -- container, or whatever the view builds itself.
    local view_def = VIEWS[self.current_view]
    local body
    if view_def.build then
        local widgets, err = view_def.build(w_width, w_font_face, w_font_size_small, self)
        if not widgets then return fail(err) end
        body = widgets
    else
        local rows, num_items, row_height, items = buildRows(view_def, w_width, w_font_face, w_font_size_small)
        -- on failure the second value is the message
        if not rows then return fail(num_items) end

        -- As many rows as fit in 70% of the screen, up to 12
        local effective_row_height = row_height + Size.line.thin
        local rows_fit = math.max(1, math.floor(screen_height * 0.7 / effective_row_height))
        local scrollable_height = math.min(num_items, rows_fit, 12) * effective_row_height
        body = {
            SwipePassthroughScrollable:new({
                dimen = Geom:new({ w = w_width, h = scrollable_height }),
                show_parent = self,
                rows,
            }),
        }
        -- a line under the list, for the views that have a summary
        if view_def.summary then
            table.insert(body, makeVerticalSpacing(w_padding_internal, 0.8))
            table.insert(body, TextWidget:new({
                text = view_def.summary(items),
                face = Font:getFace(w_font_face, w_font_size_small - 1),
                fgcolor = COLOR_MUTED,
                max_width = w_width,
            }))
        end
    end

    -- Title on the left, "n / total" on the right
    local title_text = type(view_def.title) == "function" and view_def.title() or view_def.title
    local counter_w = Screen:scaleBySize(56)
    local title_widget = TextWidget:new({
        text = title_text,
        face = Font:getFace(w_font_face, w_font_size_med),
        bold = true,
        fgcolor = COLOR_TEXT,
        max_width = w_width - counter_w - Screen:scaleBySize(10),
        ellipsis = true,
    })
    local counter_widget = TextWidget:new({
        text = string.format("%d / %d", self.current_view, #VIEWS),
        face = Font:getFace(w_font_face, w_font_size_small - 2),
        fgcolor = COLOR_MUTED,
    })
    local title_h = title_widget:getSize().h
    local title_row = HorizontalGroup:new({
        align = "center",
        LeftContainer:new({
            dimen = Geom:new({ w = w_width - counter_w, h = title_h }),
            title_widget,
        }),
        RightContainer:new({
            dimen = Geom:new({ w = counter_w, h = title_h }),
            counter_widget,
        }),
    })

    local content = VerticalGroup:new({
        title_row,
        makeVerticalSpacing(w_padding_internal, 1.2),
    })
    for _i, widget in ipairs(body) do
        table.insert(content, widget)
    end

    -- Page dots, so it is clear that the views can be swiped
    local dots = PagerDots:new({ count = #VIEWS, current = self.current_view })
    table.insert(content, makeVerticalSpacing(w_padding_internal, 1.2))
    table.insert(content, CenterContainer:new({
        dimen = Geom:new({ w = w_width, h = dots:getSize().h }),
        dots,
    }))

    local frame = FrameContainer:new({
        radius = Screen:scaleBySize(28),
        bordersize = Screen:scaleBySize(2),
        padding = w_padding_external,
        background = Blitbuffer.COLOR_WHITE,
        content,
    })

    self[1] = CenterContainer:new({
        dimen = Screen:getSize(),
        frame,
    })

    self.dimen = Geom:new({ x = 0, y = 0, w = screen_width, h = screen_height })

    if Device:hasDPad() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new({ ges = "tap", range = self.dimen }),
        }
        self.ges_events.Swipe = {
            GestureRange:new({ ges = "swipe", range = self.dimen }),
        }
    end
end

-- Builds the window for a view and shows it. Returns the window, or nil when
-- it could not be built (the user has been told why).
local function showWindow(current_view)
    local widget = ShowLongestSessionsWindow:new({ current_view = current_view })
    if widget.failed then return nil end
    UIManager:show(widget, "ui", widget.dimen)
    return widget
end

function ShowLongestSessionsWindow:onSwipe(arg, ges)
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
    local widget = ShowLongestSessionsWindow:new({ current_view = next_view })
    if widget.failed then return true end
    UIManager:close(self)
    UIManager:show(widget, "ui", widget.dimen)
    return true
end

function ShowLongestSessionsWindow:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
    return true
end

function ShowLongestSessionsWindow:onClose()
    UIManager:close(self)
    return true
end

function ShowLongestSessionsWindow:onTapClose(arg, ges)
    -- on the summary, a tap on a zone (TBR, MBR, Finished) closes the window and then acts
    if VIEWS[self.current_view].build == buildSummaryView and ges and ges.pos then
        local zone = hitSummaryZone(ges.pos)
        if zone then
            self:onClose()
            UIManager:nextTick(zone.callback)
            return true
        end
    end
    self:onClose()
    return true
end

-- ── Setup ──────────────────────────────────────────────────────────────────────
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

    -- Reader: the plugin receives the event
    function PageTextInfo:onShowLongestSessions()
        -- save the session in progress first, so it is in the lists
        if self.ui and self.ui.statistics then
            self.ui.statistics:insertDB()
        end
        showWindow()
        return true
    end

    -- File manager: the plugin may not be loaded there, so the event is
    -- handled by the file manager itself
    local FileManager = require("apps/filemanager/filemanager")
    function FileManager:onShowLongestSessions()
        showWindow()
        return true
    end

    logger.info("Longest sessions module loaded")
end
