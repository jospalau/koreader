local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local datetime = require("datetime")
local _ = require("gettext")
local Screen = Device.screen

local LINE_COLOR = Blitbuffer.COLOR_GRAY_9
local BG_COLOR = Blitbuffer.COLOR_LIGHT_GRAY

-- Oh, hey, this one actually *is* an InputContainer!
local TopReadingSessions = InputContainer:extend{
    padding = Size.padding.fullscreen,
}



function TopReadingSessions:getStats(sessions)
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day

    local SQ3 = require("lua-ljsqlite3/init")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

    local conn = SQ3.open(db_location)
    local sql_stmt = [[
         SELECT avg(wpm), sum(duration)
         FROM  wpm_stat_data
				 WHERE wpm is not 0 -- will not take into account entries I migrated
     ]]
		local stmt = conn:prepare(sql_stmt)
		local execution = stmt:step()
		local avg_wpm = math.floor(execution[1])
		local sum_time = datetime.secondsToClockDuration("letters", tonumber(execution[2]))
		print("Total time reading since new stats table: " .. tostring(sum_time))
		print("Avg Wpm: " .. tostring(avg_wpm) .. "wpm")

    sql_stmt = [[SELECT sum(sum_duration)
        FROM   (
                    SELECT sum(duration)    AS sum_duration
                    FROM   wpm_stat_data
                WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-7 day','localtime'),'localtime')
                GROUP BY DATE(start_time,'unixepoch','localtime'));"
                );
    ]]

	local avg_last_seven_days = conn:rowexec(sql_stmt)
	local avg_last_seven_days = math.floor(tonumber(avg_last_seven_days)/7/60/60 * 100)/100

    sql_stmt = [[SELECT sum((sum_duration))
        FROM   (
                    SELECT sum(duration)    AS sum_duration
                    FROM   wpm_stat_data
                WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-30 day','localtime'),'localtime')
                GROUP BY DATE(start_time,'unixepoch','localtime'));"
                );
    ]]
    local avg_last_thirty_days = conn:rowexec(sql_stmt)
	local avg_last_thirty_days = math.floor(tonumber(avg_last_thirty_days)/30/60/60 * 100)/100


    print("Average time read last 7 days: " .. avg_last_seven_days .. "h")
    print("Average time read last 30 days: " .. avg_last_thirty_days .. "h")

    sql_stmt = [[
				SELECT book.title,wpm_stat_data.*,avg(wpm),sum(duration)
				FROM  wpm_stat_data
				INNER JOIN book ON wpm_stat_data.id_book=book.id
				WHERE wpm is not 0  -- will not take into account entries I migrated
				GROUP BY id_device
				ORDER by start_time
    ]]
		print("\nInfo per device: ")
    stmt = conn:prepare(sql_stmt)
	  --local row, names = stmt:step({}, {})
		local row = {}
		while stmt:step(row) do
			local duration = datetime.secondsToClockDuration("letters", tonumber(row[10]), true)
			print(self.devices[tonumber(row[7])] .. ": " .. duration .. ", " .. tostring(math.floor(tonumber(row[9]))) .. "wpm")
			--print(unpack(row))
		end

     sql_stmt = [[
        -- SELECT book.title,duration,strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime')
        SELECT book.title,duration,strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime')
        FROM  wpm_stat_data
        INNER JOIN book ON wpm_stat_data.id_book=book.id
        ORDER by duration desc LIMIT sessions;
    ]]


    print("\nTop 5 duration sessions: ")
    stmt = conn:prepare(sql_stmt:gsub("sessions",sessions))
    --local row, names = stmt:step({}, {})
    row = {}
    local i = 0
    while stmt:step(row) do
        i = i + 1
        local duration = datetime.secondsToClockDuration("letters", tonumber(row[2]), true)
			local font_name = row[8]
		    if font_name == nil then
				font_name = "Unknown font"
			end
            -- table.insert(self.sessions,{i, {row[1], tonumber(row[2]), row[3]}})
            table.insert(self.sessions,{row[1], tonumber(row[2]), row[3]})
			print(row[1] .. " " .. duration .. " " .. row[3] .. " " .. font_name)
      --print(unpack(row))
    end

	  print("\n")
    conn:close()
    return
end

function TopReadingSessions:getReadingPast()
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    -- best to e it to letters, to get '2m' ?
    user_duration_format = "letters"


    local SQ3 = require("lua-ljsqlite3/init")
    local DataStorage = require("datastorage")
    local conn = SQ3.open(db_location)
    local sql_stmt ="SELECT count(id_book) AS sessions FROM wpm_stat_data"
    local sessions = conn:rowexec(sql_stmt)
    local sql_stmt ="SELECT avg(wpm) FROM wpm_stat_data where wpm > 0"
    local avg_wpm = conn:rowexec(sql_stmt)

    sql_stmt = [[SELECT SUM(sum_duration)
        FROM   (
                    SELECT sum(duration)    AS sum_duration
                    FROM   wpm_stat_data
                WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-7 day','localtime'),'localtime')
                GROUP BY DATE(start_time,'unixepoch','localtime'));"
                );
    ]]
    local avg_last_seven_days = conn:rowexec(sql_stmt)

    sql_stmt = [[SELECT SUM(sum_duration)
    FROM   (
                SELECT sum(duration)    AS sum_duration
                FROM   wpm_stat_data
            WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-30 day','localtime'),'localtime')
            GROUP BY DATE(start_time,'unixepoch','localtime'));"
            );
    ]]
    local avg_last_thirty_days = conn:rowexec(sql_stmt)


    sql_stmt = [[SELECT SUM(sum_duration)
    FROM   (
                SELECT sum(duration)    AS sum_duration
                FROM   wpm_stat_data
            WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-60 day','localtime'),'localtime')
            GROUP BY DATE(start_time,'unixepoch','localtime'));"
            );
    ]]
    local avg_last_sixty_days = conn:rowexec(sql_stmt)

    sql_stmt = [[SELECT SUM(sum_duration)
    FROM   (
                SELECT sum(duration)    AS sum_duration
                FROM   wpm_stat_data
            WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-90 day','localtime'),'localtime')
            GROUP BY DATE(start_time,'unixepoch','localtime'));"
            );
    ]]
    local avg_last_ninety_days = conn:rowexec(sql_stmt)

    sql_stmt = [[SELECT SUM(sum_duration)
    FROM   (
                SELECT sum(duration)    AS sum_duration
                FROM   wpm_stat_data
            WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-6 month','localtime'),'localtime')
            GROUP BY DATE(start_time,'unixepoch','localtime'));"
            );
    ]]
    local avg_last_six_months = conn:rowexec(sql_stmt)


    sql_stmt = [[SELECT SUM(sum_duration)
    FROM   (
                SELECT sum(duration)    AS sum_duration
                FROM   wpm_stat_data
            WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-1 year','localtime'),'localtime')
            GROUP BY DATE(start_time,'unixepoch','localtime'));"
            );
    ]]
    local avg_last_year = conn:rowexec(sql_stmt)


    conn:close()
    if sessions == nil then
        sessions = 0
    end
    sessions = tonumber(sessions)

    if avg_wpm == nil then
        avg_wpm = 0
    end

    avg_wpm = tonumber(avg_wpm)
    if avg_last_seven_days == nil then
        avg_last_seven_days = 0
    end

    if avg_last_thirty_days == nil then
        avg_last_thirty_days = 0
    end

    if avg_last_sixty_days == nil then
        avg_last_sixty_days = 0
    end

    if avg_last_ninety_days == nil then
        avg_last_ninety_days = 0
    end

    if avg_last_six_months == nil then
        avg_last_six_months = 0
    end

    if avg_last_year == nil then
        avg_last_year = 0
    end

    avg_last_seven_days = math.floor(tonumber(avg_last_seven_days)/7/60/60 * 100)/100
    avg_last_thirty_days = math.floor(tonumber(avg_last_thirty_days)/30/60/60 * 100)/100
    avg_last_sixty_days = math.floor(tonumber(avg_last_sixty_days)/60/60/60 * 100)/100
    avg_last_ninety_days = math.floor(tonumber(avg_last_ninety_days)/90/60/60 * 100)/100
    avg_last_six_months = math.floor(tonumber(avg_last_six_months)/180/60/60 * 100)/100
    avg_last_year = math.floor(tonumber(avg_last_year)/365/60/60 * 100)/100

    table.insert(self.sessions,{7, avg_last_seven_days})
    table.insert(self.sessions,{30, avg_last_thirty_days})
    table.insert(self.sessions,{60, avg_last_sixty_days})
    table.insert(self.sessions,{90, avg_last_ninety_days})
    table.insert(self.sessions,{180, avg_last_six_months})
    table.insert(self.sessions,{365, avg_last_year})
    return

end

function TopReadingSessions:init()
    -- self.past_reading = self.past_reading
    self.small_font_face = Font:getFace("smallffont")
    self.medium_font_face = Font:getFace("ffont")
    self.large_font_face = Font:getFace("largeffont")
    self.screen_width = Screen:getWidth()
    self.screen_height = Screen:getHeight()
    -- self.header_span = Screen:scaleBySize(15)
    self.stats_span = Screen:scaleBySize(10)


    self.devices = {
        [0] = "Unknown",
        [1] = "Kobo Libra 2",
        [2] = "Kobo Sage",
        [3] = "Kobo Clara 2E",
        [4] = "Kindle",
        [5] = "Xiaomi",
        [6] = "Boox Palma",
        [7] = "PocketBook Era",
        [8] = "Physical book session"
    }

    self.height_session = Screen:scaleBySize(40)
    self.sessions = {}

    self.covers_fullscreen = true -- hint for UIManager:_repaint()
    self[1] = FrameContainer:new{
        width = self.screen_width,
        height = self.screen_height,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        self:getStatusContent(self.screen_width),
    }
    -- We're full-screen, and the widget is built in a funky way, ensure dimen actually matches the full-screen,
    -- instead of only the content's effective area...
    self.dimen = Geom:new{ x = 0, y = 0, w = self.screen_width, h = self.screen_height }

    if Device:hasKeys() then
        -- don't get locked in on non touch devices
        self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = function() return self.dimen end,
            }
        }
        self.ges_events.MultiSwipe = {
            GestureRange:new{
                ges = "multiswipe",
                range = function() return self.dimen end,
            }
        }
    end

    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)

end



function TopReadingSessions:getTotalStats(stats_day)
    local total_time = 0
    local total_pages = 0
    for i=1, stats_day do
        total_pages = total_pages + self.dates[i][1]
        total_time = total_time + self.dates[i][2]
    end
    return total_time, total_pages
end

function TopReadingSessions:getStatusContent(width)
    local title_bar = TitleBar:new{
        width = width,
        bottom_v_padding = 0,
        close_callback = not self.readonly and function() self:onClose() end,
        show_parent = self,
    }

    -- 1/3 of self.height_session for the title and 1/3 for the bar and a span between them
    local number_sessions = math.floor(Screen:getHeight()/ (((self.height_session / 3) * 2) + self.stats_span))

    return VerticalGroup:new{
        align = "left",
        -- title_bar,
        -- self:genSingleHeader(_("Top session books")),
        -- self:genSingleHeader(_(tostring(number_sessions) .. " Sessions")),
        -- self.past_reading and self:genSingleHeader(_("Stats over the last year")),
        self.past_reading and self:genLastReading() or self:genTopSessions(number_sessions) ,
    }
end

function TopReadingSessions:genSingleHeader(title)
    local header_title = TextWidget:new{
        text = title,
        face = self.medium_font_face,
        fgcolor = LINE_COLOR,
    }
    local padding_span = HorizontalSpan:new{ width = self.padding }
    local line_width = (self.screen_width - header_title:getSize().w) / 2 - self.padding * 2
    local line_container = LeftContainer:new{
        dimen = Geom:new{ w = line_width, h = self.screen_height * (1/25) },
        LineWidget:new{
            background = BG_COLOR,
            dimen = Geom:new{
                w = line_width,
                h = Size.line.thick,
            }
        }
    }

    return VerticalGroup:new{
        -- VerticalSpan:new{ width = Screen:scaleBySize(self.header_span), height = self.screen_height * (1/25) },
        HorizontalGroup:new{
            align = "center",
            padding_span,
            line_container,
            padding_span,
            header_title,
            padding_span,
            line_container,
            padding_span,
        },
        -- VerticalSpan:new{ width = Size.span.vertical_large, height = self.screen_height * (1/25) },
    }
end



function TopReadingSessions:genTopSessions(number_books)
    local select_day_time
    local user_duration_format = G_reader_settings:readSetting("duration_format")

    self.info = self:getStats(number_books)
    print(self.info)

    local statistics_container = CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width , h = self.height_session },
    }
    local statistics_group = VerticalGroup:new{ align = "left" }
    local max_session_time = -1
    local session_time
    for i=1, number_books do
        session_time = self.sessions[i][2]
        if session_time > max_session_time then max_session_time = session_time end
    end
    -- local top_padding_span = HorizontalSpan:new{ width = Screen:scaleBySize(15) }
    -- local top_span_group = HorizontalGroup:new{
    --     align = "center",
    --     LeftContainer:new{
    --         dimen = Geom:new{ h = Screen:scaleBySize(30) },
    --         top_padding_span
    --     },
    -- }
    -- table.insert(statistics_group, top_span_group)

    -- local padding_span = HorizontalSpan:new{ width = Screen:scaleBySize(15) }
    -- local span_group = HorizontalGroup:new{
    --     align = "center",
    --     LeftContainer:new{
    --         dimen = Geom:new{ h = Screen:scaleBySize(self.stats_span) },
    --         padding_span
    --     },
    -- }

    -- Lines have L/R self.padding. Make this section even more indented/padded inside the lines
    local inner_width = self.screen_width - 4*self.padding
    for i = 1, number_books do
        select_day_time = self.sessions[i][2]
        local total_group = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = inner_width , h = self.height_session * (1/3) },
                TextWidget:new{
                    padding = Size.padding.small,
                    text = self.sessions[i][1]  .. " — " .. self.sessions[i][3]  .. " — " ..  datetime.secondsToClockDuration(user_duration_format, select_day_time, true, true),
                    face = Font:getFace("smallffont",Screen:scaleBySize(6)),
                },
            },
        }
        local titles_group = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = inner_width , h = self.height_session * (1/3) },
                ProgressWidget:new{
                    width = math.floor(inner_width * select_day_time / max_session_time),
                    height = Screen:scaleBySize(8),
                    percentage = 1.0,
                    ticks = nil,
                    last = nil,
                    margin_h = 0,
                    margin_v = 0,
                }
            },
        }
        table.insert(statistics_group, total_group)
        table.insert(statistics_group, titles_group)
        -- table.insert(statistics_group, span_group)

        table.insert(statistics_group, VerticalSpan:new{ width = self.stats_span })
    end  --for i=1
    table.insert(statistics_container, statistics_group)
    return CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width, h = self.screen_height  },
        statistics_container,
    }
end


function TopReadingSessions:genLastReading()
    local select_day_time
    local user_duration_format = G_reader_settings:readSetting("duration_format")

    self:getReadingPast()

    local statistics_container = CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width , h = self.height_session },
    }
    local statistics_group = VerticalGroup:new{ align = "left" }
    local max_session_time = -1
    local session_time
    for i=1, #self.sessions do
        session_time = self.sessions[i][2]
        if session_time > max_session_time then max_session_time = session_time end
    end
    -- local top_padding_span = HorizontalSpan:new{ width = Screen:scaleBySize(15) }
    -- local top_span_group = HorizontalGroup:new{
    --     align = "center",
    --     LeftContainer:new{
    --         dimen = Geom:new{ h = Screen:scaleBySize(30) },
    --         top_padding_span
    --     },
    -- }
    -- table.insert(statistics_group, top_span_group)

    -- local padding_span = HorizontalSpan:new{ width = Screen:scaleBySize(15) }
    -- local span_group = HorizontalGroup:new{
    --     align = "center",
    --     LeftContainer:new{
    --         dimen = Geom:new{ h = Screen:scaleBySize(self.stats_span) },
    --         padding_span
    --     },
    -- }

    -- Lines have L/R self.padding. Make this section even more indented/padded inside the lines
    local inner_width = self.screen_width - 4*self.padding
    for i = 1, #self.sessions do
        select_day_time = self.sessions[i][2]
        local total_group = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = inner_width , h = self.height_session * (1/3) },
                TextWidget:new{
                    padding = Size.padding.small,
                    text = self.sessions[i][1]  .. " days" .. " — " .. tonumber(self.sessions[i][2]) .. "h",
                    face = Font:getFace("smallffont",Screen:scaleBySize(6)),
                },
            },
        }
        local titles_group = HorizontalGroup:new{
            align = "center",
            LeftContainer:new{
                dimen = Geom:new{ w = inner_width , h = self.height_session * (1/3) },
                ProgressWidget:new{
                    width = math.floor(inner_width * select_day_time / max_session_time),
                    height = Screen:scaleBySize(8),
                    percentage = 1.0,
                    ticks = nil,
                    last = nil,
                    margin_h = 0,
                    margin_v = 0,
                }
            },
        }
        table.insert(statistics_group, total_group)
        table.insert(statistics_group, titles_group)
        -- table.insert(statistics_group, span_group)

        table.insert(statistics_group, VerticalSpan:new{ width = self.stats_span })
    end  --for i=1
    table.insert(statistics_container, statistics_group)
    return CenterContainer:new{
        dimen = Geom:new{ w = self.screen_width, h = self.height_session * 6  },
        statistics_container,
    }
end


function TopReadingSessions:onSwipe(arg, ges_ev)
    if ges_ev.direction == "south" then
        -- Allow easier closing with swipe up/down
        self:onClose()
    elseif ges_ev.direction == "east" or ges_ev.direction == "west" or ges_ev.direction == "north" then
        -- no use for now
        do end -- luacheck: ignore 541
    else -- diagonal swipe
        -- trigger full refresh
        UIManager:setDirty(nil, "full")
        -- a long diagonal swipe may also be used for taking a screenshot,
        -- so let it propagate
        return false
    end
end

function TopReadingSessions:onClose()
    UIManager:close(self)
    return true
end
TopReadingSessions.onAnyKeyPressed = TopReadingSessions.onClose
-- For consistency with other fullscreen widgets where swipe south can't be
-- used to close and where we then allow any multiswipe to close, allow any
-- multiswipe to close this widget too.
TopReadingSessions.onMultiSwipe = TopReadingSessions.onClose


return TopReadingSessions
