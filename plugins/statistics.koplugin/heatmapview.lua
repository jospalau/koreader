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




local CalendarDay = InputContainer:extend{
    daynum = nil,
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
    elseif self.duration>= 2 then
        bg_color = Blitbuffer.COLOR_DARK_GRAY
    elseif self.duration>= 0.5 then
        bg_color = Blitbuffer.COLOR_GRAY
    end
    self[1] = FrameContainer:new{
        padding = 0,
        -- color = self.is_future and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE, -- And border color
        -- color = Blitbuffer.COLOR_BLACK,
        -- bordersize = self.border,
        -- bordersize = self.is_different_year and 0 or 1,
        color = self.is_today and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        -- bordersize = 1,
        paint_down = self.paint_down,
        paint_left = self.paint_left,
        width = self.width,
        height = self.height,
        background = bg_color,
        focusable = true,
        focus_border_color = Blitbuffer.COLOR_GRAY, -- And border color
        OverlapGroup:new{
            dimen = { w = inner_w },
            TextWidget:new{
                text = "", -- tostring(self.duration),
                face = Font:getFace("myfont3", Screen:scaleBySize(4)),
                fgcolor = self.is_future and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
                padding = 0,
                bold = true,
            }, -- Just write a text
        }
    }
end

function CalendarDay:onTap()
    if self.callback then
        self.callback()
    end
    return true
end

function CalendarDay:onHold()
    return self:onTap()
end


local CalendarWeek = InputContainer:extend{
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
end

function CalendarWeek:addDay(calday_widget)
    -- Add day widget to this week widget, and update the
    -- list of books read this week for later showing book
    -- spans, that may span multiple days.
    table.insert(self.calday_widgets, calday_widget)

    local prev_day_num = #self.days_books
    local prev_day_books = prev_day_num > 0 and self.days_books[#self.days_books]
    local this_day_num = prev_day_num + 1
    local this_day_books = {}
    table.insert(self.days_books, this_day_books)
end

-- Set of { Font color, background color }
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
    self.day_container = VerticalGroup:new{ -- Make columns instead of rows
        dimen = self.dimen:copy(),
    }
    for num, calday in ipairs(self.calday_widgets) do
        table.insert(self.day_container, calday)
        if num < #self.calday_widgets then
            table.insert(self.day_container, HorizontalSpan:new{ width = 10, }) -- No padding
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


-- Fetched from db, cached as local as it might be expensive
local MIN_MONTH = nil

local HeatmapView = FocusManager:extend{
    reader_statistics = nil,
    start_day_of_week = 2, -- 2 = Monday, 1-7 = Sunday-Saturday
    show_hourly_histogram = true,
    browse_future_months = false,
    nb_book_spans = 3,
    font_face = "xx_smallinfofont",
    title = "",
    width = nil,
    height = nil,
    cur_month = nil,
    weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }, -- in Lua wday order
    months_names = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"},
    months_days = {
        [1] = 31,
        [2] = 28,
        [3] = 31,
        [4] = 30,
        [5] = 31,
        [6] = 30,
        [7] = 31,
        [8] = 31,
        [9] = 30,
        [10] = 31,
        [11] = 30,
        [12] = 31,
        },
    mondays_months_2023 = {
        [1] = 5,
        [2] = 4,
        [3] = 4,
        [4] = 4,
        [5] = 5,
        [6] = 4,
        [7] = 5,
        [8] = 4,
        [9] = 4,
        [10] = 5,
        [11] = 4,
        },
    mondays_months_2024 = {
        [1] = 5,
        [2] = 4,
        [3] = 4,
        [4] = 5,
        [5] = 4,
        [6] = 4,
        [7] = 5,
        [8] = 4,
        [9] = 5,
        [10] = 4,
        [11] = 4,
        },
}


function HeatmapView:isLeapYear(year)
    if ((year % 4 == 0) and (year % 100 ~= 0)) or (year % 400 == 0) then
        return true
    end
    return false
end



function HeatmapView:getMonthMaxDays(month, year)
    if (self.months_days[month]) then
        if (month ~= 2 and not self:isLeapYear(year)) then
            return self.months_days[month]
        else
            return 29
        end
    end
    return false
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
        WHERE date NOT IN (select DATE(datetime(start_time,'unixepoch')) from wpm_stat_data)
        UNION SELECT DATE(datetime(start_time,'unixepoch')), ROUND(CAST(SUM(duration)/60 as real)/60,2) from wpm_stat_data
        WHERE strftime('%Y',DATE(datetime(start_time,'unixepoch'))) = ? group by(DATE(datetime(start_time,'unixepoch')))
        ORDER BY DATE(datetime(start_time,'unixepoch'));
        ]]

    local stmt = conn:prepare(sql_stmt:gsub("year",year))
    local res, nb = stmt:reset():bind(year):resultset()
    stmt:close()
    local dates = {}
    for i=1, nb do
        -- (We don't care about the duration, we just needed it
        -- to have the books in decreasing duration order)
        local day, duration = res[1][i], res[2][i]
        if not dates[i] then
            dates[i] = {}
        end
        table.insert(dates[i], { day, tonumber(duration) })
        -- table.insert(dates[day], { date_day = tonumber(day), time = tonumber(duration) })
    end


    local sql_stmt = [[
        SELECT ROUND(CAST(SUM(duration)/60 as real)/60,2) from wpm_stat_data
        GROUP BY strftime('%%Y',DATE(datetime(start_time,'unixepoch')))
        HAVING strftime('%%Y',DATE(datetime(start_time,'unixepoch')))='%d';
        ]]

        local hours = conn:rowexec(string.format(sql_stmt, year))

        conn:close()
        if hours == nil then
            hours = 0
        end
        hours = tonumber(hours)

    return dates, hours
end


function HeatmapView:getReadMonth(year, month)
    local SQ3 = require("lua-ljsqlite3/init")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT ROUND(CAST(SUM(duration)/60 as real)/60,2),
        strftime('%%Y',DATE(datetime(start_time,'unixepoch'))),
        strftime('%%m',DATE(datetime(start_time,'unixepoch')))
        FROM wpm_stat_data GROUP BY strftime('%%Y',DATE(datetime(start_time,'unixepoch'))), strftime('%%m',DATE(datetime(start_time,'unixepoch')))
        HAVING CAST(strftime('%%Y',DATE(datetime(start_time,'unixepoch'))) as decimal) ='%d'
        AND CAST(strftime('%%m',DATE(datetime(start_time,'unixepoch'))) as decimal) ='%d';
        ]]

        local hours = conn:rowexec(string.format(sql_stmt, year, month))
        conn:close()
        if hours == nil then
            hours = 0
        end
        hours = tonumber(hours)

    return hours
end


function deep_copy(obj, seen)
	-- Handle non-tables and previously-seen tables.
	if type(obj) ~= 'table' then return obj end
	if seen and seen[obj] then return seen[obj] end

	-- New table; mark it as seen an copy recursively.
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
        self.covers_fullscreen = true -- hint for UIManager:_repaint()
    end

    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
        self.key_events.NextMonth = { { Input.group.PgFwd } }
        self.key_events.PrevMonth = { { Input.group.PgBack } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = self.dimen,
            }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new{
                ges = "multiswipe",
                range = self.dimen,
            }
        }
    end

    self.outer_padding = Size.padding.large
    self.inner_padding = Size.padding.small

    -- 7 days in a week
    self.day_width = math.floor((self.dimen.w - 2*self.outer_padding - 6*self.inner_padding) * (1/7))
    -- Put back the possible 7px lost in rounding into outer_padding
    self.outer_padding = math.floor((self.dimen.w - 7*self.day_width - 6*self.inner_padding) * (1/2))

    self.content_width = self.dimen.w - 2*self.outer_padding


    self.title_bar = TitleBar:new{
        fullscreen = self.covers_fullscreen,
        width = self.dimen.w,
        align = "left",
        title = "2023",
        title_h_padding = self.outer_padding, -- have month name aligned with calendar left edge
        -- close_callback = function() self:onClose() end,
        -- show_parent = self,
    }

    -- week days names header
    self.day_names = VerticalGroup:new{}
    table.insert(self.day_names, HorizontalSpan:new{ width = self.outer_padding })
    for i = 0, 6 do
        local dayname = TextWidget:new{
            text = datetime.shortDayOfWeekTranslation[self.weekdays[(self.start_day_of_week-1+i)%7 + 1]],
            face = Font:getFace("myfont3", Screen:scaleBySize(4)),
            -- bold = true,
        }
        table.insert(self.day_names, FrameContainer:new{
            padding = 0,
            bordersize = 0,
            padding_right = 20,
            CenterContainer:new{
                dimen = Geom:new{ w = Screen:scaleBySize(12), h = Screen:scaleBySize(12) },
                dayname,
            }
        })
        if i < 6 then
            table.insert(self.day_names, HorizontalSpan:new{ width = self.inner_padding, })
        end
    end



    -- At most 6 weeks in a month
    local available_height = self.dimen.h - self.title_bar:getHeight() - self.day_names:getSize().h
    self.week_height = math.floor((available_height - 7*self.inner_padding) * (1/6))
    self.day_border = Size.border.default
    if self.show_hourly_histogram then
        -- day num + nb_book_spans + histogram: ceil() as histogram rarely
        -- reaches 100% and is stuck to bottom
        self.span_height = math.ceil((self.week_height - 2*self.day_border) / (self.nb_book_spans+2))
    else
        -- day num + nb_book_span: floor() to get some room for bottom padding
        self.span_height = math.floor((self.week_height - 2*self.day_border) / (self.nb_book_spans+1))
    end
    -- Limit font size to 1/3 of available height, and so that
    -- the day number and the +nb-not-shown do not overlap
    local text_height = math.min(self.span_height, self.week_height/3)
    self.span_font_size = TextBoxWidget:getFontSizeToFitHeight(text_height, 1, 0.3)
    local day_inner_width = self.day_width - 2*self.day_border -2*self.inner_padding



    self.months = HorizontalGroup:new{}
    table.insert(self.months, VerticalSpan:new{ width = Screen:scaleBySize(20) })

    -- table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(40) })
    local dateFirstDayYear = os.time({year=2023, month=1, day=1})

    if tonumber(os.date("%V", dateFirstDayYear)) == 52 then
        table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(40) })
    else
        table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(28) })
    end




    local main_content2023 = HorizontalGroup:new{} -- With a vertical group, draws everything down
    self.dates, self.hours = self:getDates('2023')
    self:_populateItems(main_content2023, '2023')
    self.months_2023 = deep_copy(self.months)
    self.months = HorizontalGroup:new{}
    table.insert(self.months, VerticalSpan:new{ width = Screen:scaleBySize(20) })



    -- table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(40) })

    local dateFirstDayYear = os.time({year=2024, month=1, day=1})

    if tonumber(os.date("%V", dateFirstDayYear)) == 52 then
        table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(40) })
    else
        table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(30) })
    end



    self.title_bar_2023 = TitleBar:new{
        fullscreen = self.covers_fullscreen,
        title_face_fullscreen = Font:getFace("myfont3", Screen:scaleBySize(8)),
        width = self.dimen.w,
        bottom_v_padding = 20,
        align = "left",
        title = "2023 (" ..  string.format("%.2fd)",self.hours / 24),
        title_h_padding = self.outer_padding, -- have month name aligned with calendar left edge
        -- close_callback = function() self:onClose() end,
        -- show_parent = self,
    }


    self.dates, self.hours = self:getDates('2024')
    local main_content2024 = HorizontalGroup:new{}
    self:_populateItems(main_content2024, '2024')
    self.months_2024 = self.months

    self.title_bar_2024 = TitleBar:new{
        fullscreen = self.covers_fullscreen,
        title_face_fullscreen = Font:getFace("myfont3", Screen:scaleBySize(8)),
        bottom_v_padding = 20,
        width = self.dimen.w,
        align = "left",
        title = "2024 (" .. string.format("%.2fd)",self.hours / 24),
        title_h_padding = self.outer_padding, -- have month name aligned with calendar left edge
        -- close_callback = function() self:onClose() end,
        -- show_parent = self,
    }

    local content = OverlapGroup:new{
        dimen = Geom:new{
            w = self.dimen.w,
            h = self.dimen.h,
        },
        allow_mirroring = false,
        VerticalGroup:new{
            align = "left",
            self.title_bar_2023,
            self.months_2023,
            HorizontalGroup:new{
                HorizontalSpan:new{ width = self.outer_padding },
                self.day_names,
                main_content2023,
            },
            FrameContainer:new{
                padding = 0,
                bordersize = 0,
                padding_bottom = 60,
                HorizontalSpan:new{ width = self.outer_padding },
            },
            -- VerticalSpan:new{ width = 60 }, -- We need the main_content to go a little bit down
            self.title_bar_2024,
            self.months_2024,
            HorizontalGroup:new{
                HorizontalSpan:new{ width = self.outer_padding },
                self.day_names,
                main_content2024,
            },
        },
    }
    -- assemble page
    self[1] = FrameContainer:new{
        width = self.dimen.w,
        height = self.dimen.h,
        padding = 0,
        margin = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        content
    }
end

function HeatmapView:_populateItems(main_content, year)
    self.layout = {}
    main_content:clear()


    table.insert(main_content, VerticalSpan:new{ width = self.inner_padding })
    self.weeks = {}
    local today_s = os.date("%Y-%m-%d", os.time())
    local cur_ts = month_start_ts
    local cur_date = os.date("*t", cur_ts)
    local this_month = cur_date.month
    local cur_week
    local layout_week
    local last_weekday = ""
    local last_month = nil


    for i = 0, 11 do
        local hours = self:getReadMonth(year, i + 1)
        local month_name = TextWidget:new{
            text = self.months_names[(i)%12 + 1] .. " " .. hours,
            face = Font:getFace("myfont3", Screen:scaleBySize(4)),
            bold = true,
        }
        local fc =  FrameContainer:new{
            padding = 0,
            bordersize = 0,
            padding_right = 0,
            LeftContainer:new{
                dimen = Geom:new{w = month_name:getSize().w, h = month_name:getSize().h },
                month_name,
            }
        }
        table.insert(self.months, fc)
        if i < 11 then
            -- table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(12) * self.mondays_months_2024[i + 1] - month_name:getSize().w})
            -- table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(12) * self:getMonthMaxDays(i + 1, year) / 7 - month_name:getSize().w}) -- Number of whole weeks in a month times the square size
            -- table.insert(self.months, HorizontalSpan:new{ width = (Screen:scaleBySize(12) * self.months_weeks_2023[i + 1] ) - month_name:getSize().w })--  Screen:scaleBySize(fc[1][1]:getSize().w) })
            if year == '2023' then
                table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(12) * self.mondays_months_2023[i + 1] - month_name:getSize().w})
            else
                table.insert(self.months, HorizontalSpan:new{ width = Screen:scaleBySize(12) * self.mondays_months_2024[i + 1] - month_name:getSize().w})
            end

        end
    end
    table.insert(self.months, VerticalSpan:new{ width = Screen:scaleBySize(20) })


    for i = 1, #self.dates do
        -- print(self.dates[i][1][1])

        local pattern = "(%d+)-(%d+)-(%d+)"
        local ryear, rmonth, rday = self.dates[i][1][1]:match(pattern)
        local date = os.time({year=ryear, month=rmonth, day=rday})
        local weekday = os.date("*t", date).wday - 1


        local hours = 0
        if rmonth ~= last_month then
            hours = self:getReadMonth(ryear, rmonth)
            print(hours)
        end
        last_month = rmonth

        last_weekday = weekday
        if weekday == 0 then
            weekday = 7
        end
        local weekx = tonumber(os.date("%V", date))
        local yearx = tonumber(os.date("%Y", date))
        local monthx = tonumber(os.date("%d", date))
        -- print(weekday)
        rday = tonumber(rday)
        -- if dayc % 8 == 0 then
        if i == 1 and weekx == 52 then
            cur_week = CalendarWeek:new{
                height = Screen:scaleBySize(12),
                width = Screen:scaleBySize(12),
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
                local paint_down = false
                local paint_left = false
                if j >= weekday then
                    paint_down = true
                end

                if j >= weekday and (rday == 1 or rday == 2 or rday == 3 or rday == 4 or rday == 5 or rday == 6 or rday == 7) then
                    paint_left = true
                end

                local calendar_day = CalendarDay:new{
                    is_different_year = j < weekday and true or false,
                    day = j < weekday and "" or i,
                    font_face = self.font_face,
                    font_size = self.span_font_size,
                    border = self.day_border,
                    daynum = cur_date.day,
                    paint_down = paint_down,
                    paint_left = paint_left,
                    height = Screen:scaleBySize(12),
                    width = Screen:scaleBySize(12),
                    show_parent = self,
                    duration = 0,
                }
                cur_week:addDay(calendar_day)
                table.insert(layout_week, calendar_day)
            end
        else
            if weekday == 1 then
                cur_week = CalendarWeek:new{
                    height = Screen:scaleBySize(12),
                    width = Screen:scaleBySize(12),
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
            local day_ts = os.time({
                year = cur_date.year,
                month = cur_date.month,
                day = cur_date.day,
                hour = 0,
            })

            local is_today = os.date("%Y-%m-%d") == self.dates[i][1][1]
            local is_future = day_s > today_s
            local calendar_day = CalendarDay:new{
                font_face = self.font_face,
                font_size = self.span_font_size,
                -- border = is_future and 0 or 1,
                is_different_year = false,
                paint_down = (monthx == 1 and true or false),
                paint_left = ((rday == 1 or rday == 2 or rday == 3 or rday == 4 or rday == 5 or rday == 6 or rday == 7) and true or false),
                day = i,
                is_today = is_today,
                daynum = cur_date.day,
                height = Screen:scaleBySize(12),
                width = Screen:scaleBySize(12),
                show_parent = self,
                duration = self.dates[i][1][2],
            }

            cur_week:addDay(calendar_day)
            table.insert(layout_week, calendar_day)
        end
    end
    if last_weekday > 1 then
        for j = last_weekday, 6 do
            local calendar_day = CalendarDay:new{
                is_different_year = true,
                day = "",
                font_face = self.font_face,
                font_size = self.span_font_size,
                border = self.day_border,
                daynum = cur_date.day,
                height = Screen:scaleBySize(12),
                width = Screen:scaleBySize(12),
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
    -- trigger full refresh
    UIManager:setDirty(nil, "full")
    -- a long diagonal swipe may also be used for taking a screenshot,
    -- so let it propagate
    return false
end

function HeatmapView:onMultiSwipe(arg, ges_ev)
    -- For consistency with other fullscreen widgets where swipe south can't be
    -- used to close and where we then allow any multiswipe to close, allow any
    -- multiswipe to close this widget too.
    self:onClose()
    return true
end

function HeatmapView:onClose()
    UIManager:close(self)
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("SetRotationMode", 0, true))
    UIManager:broadcastEvent(Event:new("GenerateCover", 0))
    -- Remove ghosting
    UIManager:setDirty(nil, "full")
    return true
end

return HeatmapView

