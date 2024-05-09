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

    self.daynum_w = TextWidget:new{
        text = "" .. tostring(self.daynum),
        face = Font:getFace(self.font_face, self.font_size),
        fgcolor = self.is_future and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
        padding = 0,
        bold = true,
    }
    self.nb_not_shown_w = TextWidget:new{
        text = " ",-- self.day, -- Show day
        face = Font:getFace(self.font_face, self.font_size - 1),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        overlap_align = "right",
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
            -- self.daynum_w, -- Kust write a text
            self.nb_not_shown_w,
            self.histo_w, -- nil if not show_histo
        }
    }
end

function CalendarDay:updateNbNotShown(nb)
    self.nb_not_shown_w:setText(string.format("+ %d ", nb))
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

    -- if not calday_widget.read_books then
    --     calday_widget.read_books = {}
    -- end
    -- local nb_books_read = #calday_widget.read_books
    -- if nb_books_read > self.nb_book_spans then
    --     calday_widget:updateNbNotShown(nb_books_read - self.nb_book_spans)
    -- end
    -- for i=1, self.nb_book_spans do
    --     if calday_widget.read_books[i] then
    --         this_day_books[i] = calday_widget.read_books[i] -- brings id & title keys
    --         this_day_books[i].span_days = 1
    --         this_day_books[i].start_day = this_day_num
    --         this_day_books[i].fixed = false
    --     else
    --         this_day_books[i] = false
    --     end
    -- end

    -- if prev_day_books then
    --     -- See if continuation from previous day, and re-order them if needed
    --     for pn=1, #prev_day_books do
    --         local prev_book = prev_day_books[pn]
    --         if prev_book then
    --             for tn=1, #this_day_books do
    --                 local this_book = this_day_books[tn]
    --                 if this_book and this_book.id == prev_book.id then
    --                     this_book.start_day = prev_book.start_day
    --                     this_book.fixed = true
    --                     this_book.span_days = prev_book.span_days + 1
    --                     -- Update span_days in all previous books
    --                     for bk = 1, prev_book.span_days do
    --                         self.days_books[this_day_num-bk][pn].span_days = this_book.span_days
    --                     end
    --                     if tn ~= pn then -- swap it with the one at previous day position
    --                         this_day_books[tn], this_day_books[pn] = this_day_books[pn], this_day_books[tn]
    --                     end
    --                     break
    --                 end
    --             end
    --         end
    --     end
    -- end
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
    weekdays = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" } -- in Lua wday order
        -- (These do not need translations: they are the keys into the datetime module translations)
}



function HeatmapView:getDates(year)
    local SQ3 = require("lua-ljsqlite3/init")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
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
    local conn = SQ3.open(db_location)
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
            face = Font:getFace("xx_smallinfofont", Screen:scaleBySize(4)),
            -- bold = true,
        }
        table.insert(self.day_names, FrameContainer:new{
            padding = 0,
            bordersize = 0,
            padding_right = 20,
            CenterContainer:new{
                dimen = Geom:new{ w = 25, h = 25 },
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

    local main_content2023 = HorizontalGroup:new{} -- With a vertical group, draws everything down
    self.dates, self.hours = self:getDates('2023')
    self:_populateItems(main_content2023)

    self.title_bar_2023 = TitleBar:new{
        fullscreen = self.covers_fullscreen,
        width = self.dimen.w,
        bottom_v_padding = 20,
        align = "left",
        title = "2023 (" .. self.hours .. "h )",
        title_h_padding = self.outer_padding, -- have month name aligned with calendar left edge
        -- close_callback = function() self:onClose() end,
        -- show_parent = self,
    }


    self.dates, self.hours = self:getDates('2024')
    local main_content2024 = HorizontalGroup:new{}
    self:_populateItems(main_content2024)


    self.title_bar_2024 = TitleBar:new{
        fullscreen = self.covers_fullscreen,
        bottom_v_padding = 20,
        width = self.dimen.w,
        align = "left",
        title = "2024 (" .. self.hours .. "h )",
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

function HeatmapView:_populateItems(main_content)
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
    for i = 1, #self.dates do
        print(self.dates[i][1][1])

        local pattern = "(%d+)-(%d+)-(%d+)"
        local ryear, rmonth, rday = self.dates[i][1][1]:match(pattern)
        local date = os.time({year=ryear, month=rmonth, day=rday})
        local weekday = os.date("*t", date).wday - 1

        last_weekday = weekday
        if weekday == 0 then
            weekday = 7
        end
        local weekx = tonumber(os.date("%V", date))
        local yearx = tonumber(os.date("%Y", date))
        local monthx = tonumber(os.date("%d", date))
        print(weekday)
        rday = tonumber(rday)
        -- if dayc % 8 == 0 then
        if i == 1 and weekx == 52 then
            cur_week = CalendarWeek:new{
                height = 25,
                width = 25,
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
                    height = 25,
                    width = 25,
                    show_parent = self,
                    duration = 0,
                }
                cur_week:addDay(calendar_day)
                table.insert(layout_week, calendar_day)
            end
        else
            if weekday == 1 then
                cur_week = CalendarWeek:new{
                    height = 25,
                    width = 25,
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
                height = 25,
                width = 25,
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
                height = 20,
                width = 20,
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
    UIManager:broadcastEvent(Event:new("SetRotationMode", 0))
    UIManager:broadcastEvent(Event:new("GenerateCover", 0))
    -- Remove ghosting
    UIManager:setDirty(nil, "full")
    return true
end

return HeatmapView

