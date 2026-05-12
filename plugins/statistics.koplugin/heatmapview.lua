local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckMark = require("ui/widget/checkmark")
local Device = require("device")
local FocusManager = require("ui/widget/focusmanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Math = require("optmath")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local datetime = require("datetime")
local Input = Device.input
local Screen = Device.screen
local _ = require("gettext")
local T = require("ffi/util").template

-- How many years back to display (including current year)
local NUM_YEARS = 4


local CalendarWeek = FocusManager:extend{
    width = nil,
    height = nil,
    day_width = 0,
    day_padding = 0,
    day_border = 0,
    nb_book_spans = 0,
    histo_shown = nil,
    span_height = nil,
    font_size = 0,
    font_face = "xx_smallinfofont",
}

function CalendarWeek:init()
    self.calday_widgets = {}
    self.days_books = {}
    self.focusable = true
end

function CalendarWeek:addDay(calday_widget)
    table.insert(self.calday_widgets, calday_widget)
    local prev_day_num = #self.days_books
    local this_day_books = {}
    table.insert(self.days_books, this_day_books)
end

local CalendarDay = InputContainer:extend{
    ratio_per_hour = nil,
    filler = false,
    width = nil,
    height = nil,
    border = 0,
    is_future = false,
    is_today = false,
    paint_down = false,
    paint_left = false,
    is_different_year = false,
    font_face = "xx_smallinfofont",
    font_size = nil,
    show_histo = true,
    histo_height = nil,
}

function CalendarDay:init()
    self.dimen = Geom:new{w = self.width, h = self.height}
    if self.filler then
        return
    end
    self.ges_events.Tap = {
        GestureRange:new{
            ges = "tap",
            range = self.dimen,
        }
    }
    self.ges_events.Hold = {
        GestureRange:new{
            ges = "hold",
            range = self.dimen,
        }
    }

    local inner_w = self.width - 2*self.border
    local inner_h = self.height - 2*self.border

    local bg_color = Blitbuffer.COLOR_WHITE
    if self.duration >= 4 then
        bg_color = Blitbuffer.COLOR_BLACK
    elseif self.duration >= 2 then
        bg_color = Blitbuffer.COLOR_DARK_GRAY
    elseif self.duration >= 0.5 then
        bg_color = Blitbuffer.COLOR_GRAY
    end

    self[1] = FrameContainer:new{
        padding = 0,
        color = self.is_today and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        paint_down = self.paint_down,
        paint_left = self.paint_left,
        width = self.width,
        height = self.height,
        background = bg_color,
        focusable = true,
        focus_border_color = Blitbuffer.COLOR_GRAY,
        OverlapGroup:new{
            dimen = { w = inner_w },
            TextWidget:new{
                text = "",
                face = Font:getFace("myfont3", Screen:scaleBySize(4)),
                fgcolor = self.is_future and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
                padding = 0,
                bold = true,
            },
        }
    }
end

function CalendarDay:onTap()
    if self.callback then
        self.callback(self.show_parent, self.cur_month)
    end
    return true
end

function CalendarDay:onHold()
    return self:onTap()
end


local SPAN_COLORS = {
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE },
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_GRAY_E },
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_GRAY_D },
    { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_GRAY_B },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_9 },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_7 },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_5 },
    { Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_GRAY_3 },
}

function CalendarWeek:update()
    self.dimen = Geom:new{w = self.width, h = self.height}
    self.day_container = VerticalGroup:new{
        dimen = self.dimen:copy(),
    }
    for num, calday in ipairs(self.calday_widgets) do
        table.insert(self.day_container, calday)
        if num < #self.calday_widgets then
            table.insert(self.day_container, HorizontalSpan:new{ width = 10 })
        end
    end

    local overlaps = OverlapGroup:new{
        self.day_container,
    }

    self[1] = LeftContainer:new{
        dimen = self.dimen:copy(),
        overlaps,
    }
end


local MIN_MONTH = nil

local HeatmapView = FocusManager:extend{
    reader_statistics = nil,
    start_day_of_week = 2,
    show_hourly_histogram = true,
    browse_future_months = false,
    nb_book_spans = 3,
    font_face = "xx_smallinfofont",
    title = "",
    width = nil,
    height = nil,
    cur_month = nil,
    weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" },
    months_names = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"},
    months_days = {
        [1] = 31, [2] = 28, [3] = 31, [4] = 30,
        [5] = 31, [6] = 30, [7] = 31, [8] = 31,
        [9] = 30, [10] = 31, [11] = 30, [12] = 31,
    },
}

-- Returns true if the given year is a leap year
function HeatmapView:isLeapYear(year)
    year = tonumber(year)
    return ((year % 4 == 0) and (year % 100 ~= 0)) or (year % 400 == 0)
end

-- Returns max days for a given month/year
function HeatmapView:getMonthMaxDays(month, year)
    if not self.months_days[month] then return false end
    if month == 2 and self:isLeapYear(year) then
        return 29
    end
    return self.months_days[month]
end

-- Computes the number of ISO weeks whose Monday falls in each month of a given year.
-- This is used to correctly size the month label spacing in the header row.
function HeatmapView:computeMondaysPerMonth(year)
    year = tonumber(year)
    local counts = {}
    for m = 1, 12 do
        counts[m] = 0
    end
    -- Iterate over every day of the year and count Mondays per month
    for m = 1, 12 do
        local max_day = self:getMonthMaxDays(m, year)
        for d = 1, max_day do
            local t = os.time({year=year, month=m, day=d})
            local wday = os.date("*t", t).wday  -- 1=Sun .. 7=Sat
            if wday == 2 then  -- Monday
                counts[m] = counts[m] + 1
            end
        end
    end
    return counts
end

function HeatmapView:getDates(year)
    local SQ3 = require("lua-ljsqlite3/init")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local conn = SQ3.open(db_location)

    local sql_stmt = [[
        WITH RECURSIVE dates(date) AS (
            VALUES('year-01-01')
            UNION ALL
            SELECT date(date, '+1 day')
            FROM dates
            WHERE date < 'year-12-31'
        )
        SELECT date, 0 FROM dates
        WHERE date NOT IN (select DATE(datetime(start_time,'unixepoch','localtime')) from wpm_stat_data)
        UNION SELECT DATE(datetime(start_time,'unixepoch','localtime')), ROUND(CAST(SUM(duration)/60 as real)/60,2) from wpm_stat_data
        WHERE strftime('%Y',DATE(datetime(start_time,'unixepoch','localtime'))) = ? group by(DATE(datetime(start_time,'unixepoch','localtime')))
        ORDER BY DATE(datetime(start_time,'unixepoch','localtime'));
        ]]

    local stmt = conn:prepare(sql_stmt:gsub("year", tostring(year)))
    local res, nb = stmt:reset():bind(tostring(year)):resultset()
    stmt:close()

    local dates = {}
    for i = 1, nb do
        local day, duration = res[1][i], res[2][i]
        if not dates[i] then dates[i] = {} end
        table.insert(dates[i], { day, tonumber(duration) })
    end

    local sql_stmt2 = [[
        SELECT ROUND(CAST(SUM(duration)/60 as real)/60,2) from wpm_stat_data
        GROUP BY strftime('%%Y',DATE(datetime(start_time,'unixepoch','localtime')))
        HAVING strftime('%%Y',DATE(datetime(start_time,'unixepoch','localtime')))='%d';
        ]]
    local hours = conn:rowexec(string.format(sql_stmt2, year))
    conn:close()

    hours = tonumber(hours) or 0
    return dates, hours
end

function HeatmapView:getReadMonth(year, month)
    local SQ3 = require("lua-ljsqlite3/init")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local conn = SQ3.open(db_location)

    local sql_stmt = [[
        SELECT ROUND(CAST(SUM(duration)/60 as real)/60,2),
        strftime('%%Y',DATE(datetime(start_time,'unixepoch','localtime'))),
        strftime('%%m',DATE(datetime(start_time,'unixepoch','localtime')))
        FROM wpm_stat_data GROUP BY strftime('%%Y',DATE(datetime(start_time,'unixepoch','localtime'))), strftime('%%m',DATE(datetime(start_time,'unixepoch','localtime')))
        HAVING CAST(strftime('%%Y',DATE(datetime(start_time,'unixepoch','localtime'))) as decimal) ='%d'
        AND CAST(strftime('%%m',DATE(datetime(start_time,'unixepoch','localtime'))) as decimal) ='%d';
        ]]
    local hours = conn:rowexec(string.format(sql_stmt, year, month))
    conn:close()

    return tonumber(hours) or 0
end

local function deep_copy(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
    local s = seen or {}
    local res = {}
    s[obj] = res
    for k, v in next, obj do res[deep_copy(k, s)] = deep_copy(v, s) end
    return setmetatable(res, getmetatable(obj))
end

function HeatmapView:init()
    self.dimen = Geom:new{
        w = self.width or Screen:getWidth(),
        h = self.height or Screen:getHeight(),
    }

    if self.dimen.w == Screen:getWidth() and self.dimen.h == Screen:getHeight() then
        self.covers_fullscreen = true
    end

    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
        self.key_events.NextMonth = { { Input.group.PgFwd } }
        self.key_events.PrevMonth = { { Input.group.PgBack } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{ ges = "swipe", range = self.dimen }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new{ ges = "multiswipe", range = self.dimen }
        }
    end

    self.outer_padding = Size.padding.large
    self.inner_padding = Size.padding.small

    self.day_width = math.floor((self.dimen.w - 2*self.outer_padding - 6*self.inner_padding) * (1/7))
    self.outer_padding = math.floor((self.dimen.w - 7*self.day_width - 6*self.inner_padding) * (1/2))
    self.content_width = self.dimen.w - 2*self.outer_padding

    self.title_bar = TitleBar:new{
        fullscreen = self.covers_fullscreen,
        width = self.dimen.w,
        align = "left",
        title = "Reading Heatmap",
        title_h_padding = self.outer_padding,
    }

    self.size_tile = Screen:getWidth() / (12 * 5)

    -- Build shared day names header
    self.day_names = VerticalGroup:new{}
    table.insert(self.day_names, HorizontalSpan:new{ width = self.outer_padding })
    for i = 0, 6 do
        local dayname = TextWidget:new{
            text = datetime.shortDayOfWeekTranslation[self.weekdays[(self.start_day_of_week-1+i)%7 + 1]],
            face = Font:getFace("myfont3", Screen:scaleBySize(4)),
        }
        table.insert(self.day_names, FrameContainer:new{
            padding = 0,
            bordersize = 0,
            padding_right = 20,
            CenterContainer:new{
                dimen = Geom:new{ w = self.size_tile, h = self.size_tile },
                dayname,
            }
        })
        if i < 6 then
            table.insert(self.day_names, HorizontalSpan:new{ width = self.inner_padding })
        end
    end

    local available_height = self.dimen.h - self.title_bar:getHeight() - self.day_names:getSize().h
    self.week_height = math.floor((available_height - 7*self.inner_padding) * (1/6))
    self.day_border = Size.border.default
    if self.show_hourly_histogram then
        self.span_height = math.ceil((self.week_height - 2*self.day_border) / (self.nb_book_spans+2))
    else
        self.span_height = math.floor((self.week_height - 2*self.day_border) / (self.nb_book_spans+1))
    end
    local text_height = math.min(self.span_height, self.week_height/3)
    self.span_font_size = TextBoxWidget:getFontSizeToFitHeight(text_height, 1, 0.3)

    -- Determine the range of years to show: last NUM_YEARS years
    local current_year = tonumber(os.date("%Y"))
    local start_year = current_year - NUM_YEARS + 1

    -- Build per-year data and widgets, then assemble into a single VerticalGroup
    local year_blocks = {}  -- list of {title_bar, months_group, main_content}

    for y = start_year, current_year do
        local year_str = tostring(y)

        -- Precompute mondays-per-month for this year (generic, no hardcoded table)
        local mondays_months = self:computeMondaysPerMonth(y)

        -- Reset months group for this year
        self.months = HorizontalGroup:new{}
        table.insert(self.months, VerticalSpan:new{ width = Screen:scaleBySize(20) })

        -- Leading offset: depends on whether Jan 1 is in ISO week 52 or week 1
        local dateFirstDayYear = os.time({year=y, month=1, day=1})
        if tonumber(os.date("%V", dateFirstDayYear)) == 52 then
            table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(40) })
        else
            table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(28) })
        end

        self.dates, self.hours = self:getDates(year_str)
        local main_content = HorizontalGroup:new{}
        self:_populateItems(main_content, year_str, mondays_months)

        local months_group = deep_copy(self.months)

        local title_bar = TitleBar:new{
            fullscreen = self.covers_fullscreen,
            title_face_fullscreen = Font:getFace("myfont3", Screen:scaleBySize(8)),
            bottom_v_padding = 20,
            width = self.dimen.w,
            align = "left",
            title = year_str .. " (" .. string.format("%.2fd)", self.hours / 24),
            title_h_padding = self.outer_padding,
        }

        table.insert(year_blocks, {
            title_bar = title_bar,
            months_group = months_group,
            main_content = main_content,
        })
    end

    -- Assemble all year blocks into a single vertical layout
    local vgroup = VerticalGroup:new{ align = "left" }
    for idx, block in ipairs(year_blocks) do
        table.insert(vgroup, block.title_bar)
        table.insert(vgroup, block.months_group)
        table.insert(vgroup, HorizontalGroup:new{
            HorizontalSpan:new{ width = self.outer_padding },
            self.day_names,
            block.main_content,
        })
        -- Add spacing between years (but not after the last one)
        if idx < #year_blocks then
            table.insert(vgroup, FrameContainer:new{
                padding = 0,
                bordersize = 0,
                padding_bottom = 60,
                HorizontalSpan:new{ width = self.outer_padding },
            })
        end
    end

    local content = OverlapGroup:new{
        dimen = Geom:new{ w = self.dimen.w, h = self.dimen.h },
        allow_mirroring = false,
        vgroup,
    }

    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content,
    }
end

-- _populateItems now receives mondays_months as a parameter instead of using hardcoded tables
function HeatmapView:_populateItems(main_content, year, mondays_months)
    self.layout = {}
    main_content:clear()

    table.insert(main_content, VerticalSpan:new{ width = self.inner_padding })
    self.weeks = {}
    local today_s = os.date("%Y-%m-%d", os.time())
    local cur_ts = month_start_ts
    local cur_date = os.date("*t", cur_ts)
    local cur_week
    local layout_week
    local last_weekday = ""
    local last_month = nil

    -- Build month label header
    for i = 0, 11 do
        local hours = self:getReadMonth(year, i + 1)
        local month_name = TextWidget:new{
            text = self.months_names[(i)%12 + 1] .. " " .. hours,
            face = Font:getFace("myfont3", Screen:scaleBySize(3)),
            bold = true,
        }
        local fc = FrameContainer:new{
            padding = 0,
            bordersize = 0,
            padding_right = 0,
            padding_left = 0,
            LeftContainer:new{
                dimen = Geom:new{ w = month_name:getSize().w, h = month_name:getSize().h },
                month_name,
            }
        }
        table.insert(self.months, fc)
        if i < 11 then
            -- Use the computed mondays_months table passed in
            table.insert(self.months, HorizontalSpan:new{
                width = self.size_tile * mondays_months[i + 1] - month_name:getSize().w
            })
        end
    end
    table.insert(self.months, VerticalSpan:new{ width = Screen:scaleBySize(20) })

    -- Populate day cells
    for i = 1, #self.dates do
        local pattern = "(%d+)-(%d+)-(%d+)"
        local ryear, rmonth, rday = self.dates[i][1][1]:match(pattern)
        local date = os.time({year=ryear, month=rmonth, day=rday})
        local weekday = os.date("*t", date).wday - 1  -- 0=Sun..6=Sat

        last_month = rmonth
        last_weekday = weekday

        if weekday == 0 then weekday = 7 end

        local weekx = tonumber(os.date("%V", date))
        local monthx = tonumber(os.date("%d", date))
        rday = tonumber(rday)

        -- First day of year: handle partial first week
        if i == 1 and (weekx == 52 or weekx == 1) then
            cur_week = CalendarWeek:new{
                height = self.size_tile,
                width = self.size_tile,
                span_height = self.span_height,
                font_face = self.font_face,
                font_size = self.span_font_size,
                show_parent = self,
            }
            layout_week = {}
            table.insert(self.layout, layout_week)
            table.insert(self.weeks, cur_week)
            table.insert(main_content, cur_week)

            for j = 1, weekday do
                local paint_down = j >= weekday
                local paint_left = j >= weekday and rday <= 7
                local duration = (i == 1 and weekx == 1 and j >= weekday) and self.dates[i][1][2] or 0
                local calendar_day = CalendarDay:new{
                    is_different_year = j < weekday,
                    day = j < weekday and "" or i,
                    font_face = self.font_face,
                    font_size = self.span_font_size,
                    border = self.day_border,
                    paint_down = paint_down,
                    paint_left = paint_left,
                    height = self.size_tile,
                    width = self.size_tile,
                    show_parent = self,
                    duration = duration,
                }
                cur_week:addDay(calendar_day)
                table.insert(layout_week, calendar_day)
            end
        else
            -- Start a new week column on Monday
            if weekday == 1 then
                cur_week = CalendarWeek:new{
                    height = self.size_tile,
                    width = self.size_tile,
                    font_face = self.font_face,
                    font_size = self.span_font_size,
                    show_parent = self,
                }
                layout_week = {}
                table.insert(self.layout, layout_week)
                table.insert(self.weeks, cur_week)
                table.insert(main_content, cur_week)
            end

            local day_s = os.date("%Y-%m-%d", cur_ts)
            local is_today = os.date("%Y-%m-%d") == self.dates[i][1][1]
            local is_future = day_s > today_s

            local calendar_day = CalendarDay:new{
                font_face = self.font_face,
                font_size = self.span_font_size,
                is_different_year = false,
                paint_down = (monthx == 1),
                paint_left = (rday <= 7),
                day = i,
                is_today = is_today,
                cur_month = ryear .. "-" .. rmonth,
                height = self.size_tile,
                width = self.size_tile,
                show_parent = self,
                duration = self.dates[i][1][2],
                callback = function(parent, cur_month)
                    local HeatmapView = require("calendarview")
                    UIManager:show(HeatmapView:new{
                        cur_month = cur_month,
                        reader_statistics = parent.reader_statistics,
                        start_day_of_week = parent.reader_statistics.settings.calendar_start_day_of_week,
                        nb_book_spans = parent.reader_statistics.settings.calendar_nb_book_spans,
                        show_hourly_histogram = parent.reader_statistics.settings.calendar_show_histogram,
                        browse_future_months = parent.reader_statistics.settings.calendar_browse_future_months,
                    })
                end,
            }

            cur_week:addDay(calendar_day)
            table.insert(layout_week, calendar_day)
        end
    end

    -- Fill trailing empty days in last week
    if last_weekday > 1 then
        for j = last_weekday, 6 do
            local calendar_day = CalendarDay:new{
                is_different_year = true,
                day = "",
                font_face = self.font_face,
                font_size = self.span_font_size,
                border = self.day_border,
                height = self.size_tile,
                width = self.size_tile,
                show_parent = self,
                duration = 0,
            }
            cur_week:addDay(calendar_day)
            table.insert(layout_week, calendar_day)
        end
    end

    for _, week in ipairs(self.weeks) do
        week:update()
    end

    self:moveFocusTo(1, 1, FocusManager.NOT_UNFOCUS)
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end


function HeatmapView:onSwipe(arg, ges_ev)
    UIManager:setDirty(nil, "full")
    return false
end

function HeatmapView:onMultiSwipe(arg, ges_ev)
    self:onClose()
    return true
end

function HeatmapView:onClose()
    UIManager:close(self)
    UIManager:setDirty(nil, "full")
    return true
end

return HeatmapView
