local Widget = require("ui/widget/widget")
local LineWidget = require("ui/widget/linewidget")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local T = require("ffi/util").template
local _ = require("gettext")
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local Blitbuffer = require("ffi/blitbuffer")
local left_container = require("ui/widget/container/leftcontainer")
local right_container = require("ui/widget/container/rightcontainer")
local center_container = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local datetime = require("datetime")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local SQ3 = require("lua-ljsqlite3/init")
local ProgressWidget = require("ui/widget/progresswidget")
local Device = require("device")
local Size = require("ui/size")


-- self[4] = self.topbar in readerview.lua

local TopBar = WidgetContainer:extend{
    name = "Topbar",
    is_enabled = G_reader_settings:isTrue("show_top_bar"),
    -- start_session_time = os.time(),
    -- initial_read_today = getReadToday(),
    -- initial_read_month = getReadThisMonth(),

    MARGIN_SIDES = Screen:scaleBySize(10),
    -- El margen de las pantallas, flushed o recessed no es perfecto. La pantalla suele empezar un poco más arriba en casi todos los dispositivos estando un poco por debajo del bezel
    -- Al menos los Kobos y el Boox Palma
    -- Podemos cambiar los márgenes
    -- Para verlo en detalle, es mejor no poner ningún estilo en las barras de progreso
    MARGIN_TOP = Screen:scaleBySize(9),
    MARGIN_BOTTOM = Screen:scaleBySize(9),
    -- show_top_bar = true,
}




function TopBar:getReadToday()
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    -- best to e it to letters, to get '2m' ?
    -- user_duration_format = "letters"

    local conn = SQ3.open(db_location)



    local sql_stmt = [[
        SELECT sum(sum_duration)
        FROM    (
                     SELECT sum(duration)    AS sum_duration
                     FROM   page_stat
                     WHERE  DATE(start_time,'unixepoch','localtime') = DATE('now', '0 day', 'localtime')
                     GROUP  BY id_book, page
                );
    ]]

    local read_today = conn:rowexec(string.format(sql_stmt))

    conn:close()

    if read_today == nil then
        read_today = 0
    end
    read_today = tonumber(read_today)


    return read_today
end

function TopBar:getReadTodayThisMonth(title)
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    -- best to e it to letters, to get '2m' ?
    -- user_duration_format = "letters"

    local conn = SQ3.open(db_location)

    local sql_stmt = ""

    -- For some reason, in the PocketBook platform when date is transformed to localtime, the time is 27 seconds behind
    -- $ date -d @1717016400
    -- Wed May 29 23:59:33 +03 2024
    -- It is not big deal, but it has been fixed for time read today to have accurate time
    if Device:isPocketBook() then
        sql_stmt = [[
            SELECT sum(duration)
            FROM wpm_stat_data
                WHERE DATE(start_time + 27, 'unixepoch', 'localtime') = DATE('now', '0 day', 'localtime')
        ]]
    else
        sql_stmt = [[
            SELECT sum(duration)
            FROM wpm_stat_data
                WHERE DATE(start_time, 'unixepoch', 'localtime') = DATE('now', '0 day', 'localtime')
        ]]
    end

    local read_today = conn:rowexec(string.format(sql_stmt))

    local sql_stmt = [[
        SELECT sum(duration)
        FROM wpm_stat_data
            WHERE DATE(start_time, 'unixepoch', 'localtime') >= DATE('now', 'localtime', 'start of month')
    ]]



    local read_month = conn:rowexec(sql_stmt)

    sql_stmt ="SELECT avg(wpm) FROM wpm_stat_data where wpm > 0"
    local avg_wpm = conn:rowexec(sql_stmt)

    if avg_wpm == nil then
        avg_wpm = 0
    end

    if title:match("'") then title = title:gsub("'", "''") end

    conn = SQ3.open(db_location)
    sql_stmt = "SELECT id FROM book where title like 'titles' order by id desc LIMIT 1;"
    local id_book = conn:rowexec(sql_stmt:gsub("titles", title))


    if id_book == nil then
        id_book = 0
    end
    id_book = tonumber(id_book)

    sql_stmt ="SELECT SUM(duration) FROM wpm_stat_data where id_book = ibp"


    local total_time_book = conn:rowexec(sql_stmt:gsub("ibp", id_book))

    if total_time_book == nil then
        total_time_book = 0
    end

    conn:close()

    if read_today == nil then
        read_today = 0
    end
    read_today = tonumber(read_today)

    if read_month == nil then
        read_month = 0
    end
    read_month = tonumber(read_month)

    return read_today, read_month, total_time_book, avg_wpm
end

function TopBar:getReadThisYearSoFar()
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    -- best to e it to letters, to get '2m' ?
    -- user_duration_format = "letters"

    local conn = SQ3.open(db_location)



    local sql_stmt = "SELECT name FROM sqlite_master WHERE type='table' AND name='wpm_stat_data'"
    local exists_table = conn:rowexec(sql_stmt)
    local stats_table = {}
    if exists_table == nil then
        return 0
    end

    sql_stmt = [[
        SELECT sum(duration) AS sum_duration
        FROM   wpm_stat_data
        WHERE  DATE(start_time,'unixepoch','localtime') >= DATE('now', '-%d day','localtime');
    ]]

    local read_this_year = conn:rowexec(string.format(sql_stmt, os.date("*t").yday))

    if read_this_year == nil then
        read_this_year = 0
    end
    read_this_year = tonumber(read_this_year)


    conn:close()
    local Math = require("optmath")
    return math.ceil((read_this_year / 60 / 60) - (os.date("*t").yday * 2))

end

function TopBar:getTotalRead()
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    -- best to e it to letters, to get '2m' ?
    -- user_duration_format = "letters"

    local conn = SQ3.open(db_location)



    local sql_stmt = [[
        SELECT sum(duration)
        FROM page_stat
    ]]

    local read_total = conn:rowexec(string.format(sql_stmt))

    conn:close()

    if read_total == nil then
        read_total = 0
    end
    read_total = tonumber(read_total)

    local Math = require("optmath")
    return Math.round(read_total / 60 / 60 / 24)
end

function TopBar:getBooksOpened()
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    -- best to e it to letters, to get '2m' ?
    -- user_duration_format = "letters"

    local conn = SQ3.open(db_location)



    local sql_stmt = [[
        SELECT count(id)
        FROM book
    ]]

    local total_books = conn:rowexec(string.format(sql_stmt))

    conn:close()

    if total_books == nil then
        total_books = 0
    end
    total_books = tonumber(total_books)

    return total_books
end



function TopBar:init()

    -- This is done in readerui.lua because the topbar is started in ReaderView when the menu has not yet been started by ReaderUI
    -- if not self.fm then
    --     self.ui.menu:registerToMainMenu(self)
    -- end
    -- La inicialización del objeto ocurre una única vez pero el método init ocurre cada vez que abrimos el documento
    TopBar.is_enabled = G_reader_settings:isTrue("show_top_bar")
    -- TopBar.show_top_bar = true
    -- TopBar.alt_bar = true
    if TopBar.preserved_start_session_time then
        self.start_session_time = TopBar.preserved_start_session_time
        TopBar.preserved_start_session_time = nil
    end

    if TopBar.preserved_initial_read_today then
        self.initial_read_today = TopBar.preserved_initial_read_today
        TopBar.preserved_initial_read_today = nil
    end

    if TopBar.preserved_initial_read_month then
        self.initial_read_month = TopBar.preserved_initial_read_month
        TopBar.preserved_initial_read_month = nil
    end

    if TopBar.preserved_initial_total_time_book then
        self.initial_total_time_book = TopBar.preserved_initial_total_time_book
        TopBar.preserved_initial_total_time_book = nil
    end

    if TopBar.preserved_avg_wpm ~= nil then
        self.avg_wpm = TopBar.preserved_avg_wpm
        TopBar.preserved_avg_wpm = nil
    end

    if TopBar.preserved_alt_bar ~= nil then
        TopBar.show_top_bar = TopBar.preserved_alt_bar
        TopBar.preserved_alt_bar = nil
    else
        TopBar.show_top_bar = true
    end

    if TopBar.preserved_show_alt_bar ~= nil then
        TopBar.alt_bar = TopBar.preserved_show_alt_bar
        TopBar.preserved_show_alt_bar = nil
    else
        TopBar.alt_bar = true
    end

    if TopBar.preserved_altbar_line_thickness ~= nil then
        TopBar.alt_bar = TopBar.preserved_altbar_line_thickness
        TopBar.preserved_altbar_line_thickness = nil
    end

    if TopBar.preserved_option ~= nil then
        TopBar.option = TopBar.preserved_option
        TopBar.preserved_option = nil
    else
        TopBar.option = 1
    end

    if TopBar.preserved_init_page ~= nil then
        TopBar.init_page = TopBar.preserved_init_page
        TopBar.preserved_init_page = nil
    else
        TopBar.init_page = nil
    end


    if TopBar.preserved_init_page_screens ~= nil then
        TopBar.init_page_screens = TopBar.preserved_init_page_screens
        TopBar.preserved_init_page_screens = nil
    else
        TopBar.init_page_screens = nil
    end

end

function TopBar:onReaderReady()

    self.title = self.ui.document._document:getDocumentProps().title
    self.series = ""
    if self.title:find('%[%d?.%d]') then
        self.series = self.title:sub(1, self.title:find('%[') - 2)
        self.series = "(" .. TextWidget.PTF_BOLD_START .. self.series .. TextWidget.PTF_BOLD_END .. ")"
        self.title = self.title:sub(self.title:find('%]') + 2, self.title:len())
    end
    if self.initial_read_today == nil and self.initial_read_month == nil and self.initial_total_time_book == nil then
        self.initial_read_today, self.initial_read_month, self.initial_total_time_book, self.avg_wpm = self:getReadTodayThisMonth(self.ui.document._document:getDocumentProps().title)
    end

    if self.start_session_time == nil then
        self.start_session_time = os.time()
    end

    local duration_raw = math.floor((os.time() - self.start_session_time))

    if duration_raw < 360 or self.ui.statistics._total_pages < 6 then
        self.start_session_time = os.time()
        TopBar.init_page = nil
        TopBar.init_page_screens = nil
    end

    self.wpm_session = 0
    if duration_raw > 0 and self.ui.statistics._total_words then
        self.wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
    end


    self.wpm_text = TextWidget:new{
        text = self.wpm_session .. "wpm",
        face = Font:getFace("myfont3"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")

    self.session_time_text = TextWidget:new{
        text = "",
        face = Font:getFace("myfont3"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }


    self.test_light = TextWidget:new{
        text = "",
        face = Font:getFace("myfont3"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.progress_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.times_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3", 12),
        fgcolor = Blitbuffer.COLOR_BLACK,
        invert = true,
    }


    self.book_progress = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3", 12),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.time_battery_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3", 12),
        fgcolor = Blitbuffer.COLOR_BLACK,
        invert = true,
    }


    self.title_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }


    self.series_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3", 10),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }


    self.chapter_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.progress_chapter_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    -- self[1] = left_container:new{
    --     dimen = Geom:new{ w = self.wpm_text:getSize().w, self.wpm_text:getSize().h },
    --     self.wpm_text,
    -- }



    self.author_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3", 8),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self[1] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.test_light,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    self[2] = left_container:new{
        dimen = Geom:new{ w = self.progress_text:getSize().w, self.progress_text:getSize().h },
        self.progress_text,
    }


    self[3] = HorizontalGroup:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = self.border_size,
        padding = 0,
        margin = 0,
        radius = self.is_popout and math.floor(self.dimen.w * (1/20)) or 0,
        right_container:new{
            dimen = Geom:new{ w = self.title_text:getSize().w, self.title_text:getSize().h },
            self.title_text,
        },
        left_container:new{
            dimen = Geom:new{ w = self.series_text:getSize().w, self.series_text:getSize().h },
            self.series_text,
        }
    }

    self[4] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.times_text,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    self[11] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new{ w = self.book_progress:getSize().w, self.book_progress:getSize().h },
            self.book_progress,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }



    self[5] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.chapter_text,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }
    self[6] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_chapter_text,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }


    self.progress_bar  = ProgressWidget:new{
        width = 200,
        height = 5,
        percentage = 0,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }

    self[7] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_bar,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }


    self.progress_barr  = ProgressWidget:new{
        width = 200,
        height = 5,
        percentage = 0,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }

    self[20] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_barr,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }


    self[21] = left_container:new{
        dimen = Geom:new{ w = self.author_text:getSize().w, self.author_text:getSize().h },
        self.author_text,
    }

    self.progress_chapter_bar = ProgressWidget:new{
        width = 200,
        height = 5,
        percentage = 0,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }


    self[8] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_chapter_bar,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }


    -- self.progress_bar2  = ProgressWidget:new{
    --     width = Screen:getSize().w,
    --     height = 5,
    --     percentage = 0,
    --     tick_width = Screen:scaleBySize(1),
    --     ticks = nil, -- ticks will be populated in self:updateFooterText
    --     last = nil, -- last will be initialized in self:updateFooterText
    --     altbar = true,
    --     altbar_position = 4,
    --     altbar_ticks_height = 12,
    --     altbar_line_thickness = 4,
    --     bordersize = 0,
    --     radius = 0,
    -- }

    self.progress_bar2  = ProgressWidget:new{
        width = Screen:getSize().w,
        height = 0,
        percentage = 0,
        -- bordercolor = Blitbuffer.COLOR_GRAY,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
        altbar_line_thickness = 3, -- Initial value, it is used in alternative
        -- factor = 1,
        altbar_ticks_height = 7,
        -- bordercolor = Blitbuffer.COLOR_WHITE,
    }

    self[9] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_bar2,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    -- self.bottom_frame = FrameContainer:new{
    --     -- background = Blitbuffer.COLOR_WHITE,
    --     padding_bottom = 20,
    --     bordersize = 0,
    --     VerticalGroup:new{
    --         -- self.progress_text,
    --         self.progress_text,
    --     },
    -- }

    -- self[4] = BottomContainer:new{
    --     dimen = Screen:getSize(),
    --     self.bottom_frame,
    -- }


    -- self.separator_line = LineWidget:new{
    --     background = Blitbuffer.COLOR_BLACK,
    --     style = "solid",
    --     dimen = Geom:new{
    --         w = Screen:getSize().w,
    --         h = Size.line.medium,
    --     }
    -- }


    self[10] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.time_battery_text,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    if Device:isAndroid() then
        TopBar.MARGIN_SIDES =  Screen:scaleBySize(20)
    end
    self.status_bar = self.view.footer_visible
end
function TopBar:onToggleShowTopBar()
    local show_top_bar = G_reader_settings:isTrue("show_top_bar")
    G_reader_settings	:saveSetting("show_top_bar", not show_top_bar)
    TopBar.is_enabled = not show_top_bar
    self:toggleBar()
end

function TopBar:showTopBar()
    G_reader_settings:saveSetting("show_top_bar", true)
    TopBar.is_enabled = true
    self:toggleBar()
end

function TopBar:hideTopBar()
    G_reader_settings:saveSetting("show_top_bar", false)
    TopBar.is_enabled = false
end

function TopBar:resetLayout()
    -- if self.wpm_text then
    --     self:toggleBar()
    -- end
end

function TopBar:onSuspend()
    -- local powerd = Device:getPowerDevice()
    -- if powerd:isFrontlightOn() then
    --     self.frontlight = " ☼"
    -- else
    --     self.frontlight = ""
    -- end
    -- self.afterSuspend = true
    self.last_frontlight = self.frontlight
end


function TopBar:onResume()
    self.initial_read_today, self.initial_read_month, self.initial_total_time_book, self.avg_wpm = self:getReadTodayThisMonth(self.ui.document._document:getDocumentProps().title)
    self.start_session_time = os.time()
    self.init_page = nil
    self.init_page_screens = nil
    self:toggleBar()
end


function TopBar:onPreserveCurrentSession()
    -- Can be called before ReaderUI:reloadDocument() to not reset the current session
    TopBar.preserved_start_session_time = self.start_session_time
    TopBar.preserved_initial_read_today = self.initial_read_today
    TopBar.preserved_initial_read_month = self.initial_read_month
    TopBar.preserved_initial_total_time_book = self.initial_total_time_book
    TopBar.preserved_avg_wpm = self.avg_wpm
    TopBar.preserved_alt_bar = self.show_top_bar
    TopBar.preserved_show_alt_bar = self.alt_bar
    TopBar.preserved_altbar_line_thickness= self.altbar_line_thickness
    TopBar.preserved_option= self.option
    TopBar.preserved_init_page= self.init_page
    TopBar.preserved_init_page_screens= self.init_page_screens

end


function TopBar:onSwitchTopBar()
    if G_reader_settings:isTrue("show_top_bar") then
        if TopBar.show_top_bar then
            if self.progress_bar2.altbar_ticks_height == 7 then
                self.progress_bar2.altbar_ticks_height = 16
                self.progress_bar2.altbar_line_thickness = 6
                self.option = 2
                -- self.progress_bar2.factor = 3
            elseif self.progress_bar2.altbar_ticks_height == 16 then
                self.progress_bar2.altbar_ticks_height = -1
                self.progress_bar2.altbar_line_thickness = -1
                -- self.progress_bar2.factor = -1
                TopBar.alt_bar = false
                self.option = 3
            else
                self.progress_bar2.altbar_ticks_height = 7
                self.progress_bar2.altbar_line_thickness = 3
                -- self.progress_bar2.factor = 1
                TopBar.show_top_bar = false
                self.option = 4
            end
        elseif TopBar.is_enabled then
            TopBar.is_enabled = false
        else
            TopBar.is_enabled = true
            TopBar.show_top_bar = true
            TopBar.alt_bar = true
            self.option = 1
        end
        self:toggleBar()

        -- TopBar.is_enabled = not TopBar.is_enabled
        -- self:toggleBar()
        UIManager:setDirty("all", "partial")
    end
end


function TopBar:toggleBar(light_on)
    if TopBar.is_enabled then
        local user_duration_format = "modern"
        local session_time = datetime.secondsToClockDuration(user_duration_format, os.time() - self.start_session_time, false)

        local duration_raw =  math.floor((os.time() - self.start_session_time))
        self.wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        self.wpm_text:setText(self.wpm_session .. "wpm")

        local read_today = self.initial_read_today + (os.time() - self.start_session_time)
        read_today = datetime.secondsToClockDuration(user_duration_format, read_today, false)

        local read_month = self.initial_read_month + (os.time() - self.start_session_time)
        read_month = datetime.secondsToClockDuration(user_duration_format, read_month, false)

        local read_book = self.initial_total_time_book + (os.time() - self.start_session_time)
        read_book = datetime.secondsToClockDuration(user_duration_format, read_book, false)


        self.session_time_text:setText(datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")))


        if self.ui.pagemap:wantsPageLabels() then
           self.progress_text:setText(("%d de %d"):format(self.ui.pagemap:getCurrentPageLabel(true), self.ui.pagemap:getLastPageLabel(true)))
        else
           self.progress_text:setText(("%d de %d"):format(self.view.footer.pageno, self.view.footer.pages))
        end



        if self.init_page == nil then
            self.init_page = self.ui.pagemap:getCurrentPageLabel(true)
        end

        if self.init_page_screens == nil then
            self.init_page_screens = self.view.footer.pageno
        end

        local init_page = 0
        local pages_session = 0
        if self.ui.pagemap:wantsPageLabels() then
            init_page = self.init_page
            pages_session = self.ui.pagemap:getCurrentPageLabel(true) - init_page
            self.times_text:setText(session_time ..  "(" .. pages_session .. "p)|" .. read_today .. "|" .. read_month)
            self.times_text_text = session_time ..  "(" .. pages_session .. "p)|" .. read_today .. "|" .. read_month
        else
            init_page = self.init_page_screens
            pages_session = self.view.footer.pageno - init_page
            self.times_text:setText(session_time .. "|" .. read_today .. "|" .. read_month)
            self.times_text_text = session_time .. "|" .. read_today .. "|" .. read_month
        end


        local powerd = Device:getPowerDevice()
        local batt_lvl = tostring(powerd:getCapacity())


        local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
        self.time_battery_text_text = time .. "|" .. batt_lvl .. "%"

        local words = "?w"
        local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")

        local title = self.title
        if (title:find("([0-9,]+w)") ~= nil) then
            words = self.title:match("([0-9,]+w)"):gsub("w",""):gsub(",","")
            local hours_to_read = tonumber(words)/(self.avg_wpm * 60)
            local progress =  math.floor(100/hours_to_read * 10)/10
            words = title:match("([0-9,]+w)"):gsub("w",""):gsub(",","") .. "w"
            self.book_progress:setText(words .. "|" .. tostring(progress) .. "%|" .. read_book)
            title = title:sub(1, title:find('%(')-2, title:len())
        end
        -- title = TextWidget.PTF_BOLD_START .. title .. " with " .. words .. TextWidget.PTF_BOLD_END
        -- if self.series == "" then
        --     title = TextWidget.PTF_BOLD_START .. title .. TextWidget.PTF_BOLD_END
        -- else
        --     title = TextWidget.PTF_BOLD_START .. title .. " (" .. self.series .. ")" .. TextWidget.PTF_BOLD_END
        -- end
        title = TextWidget.PTF_BOLD_START .. title .. TextWidget.PTF_BOLD_END
        self.title_text:setText(title)
        self.series_text:setText(self.series)


        local chapter = self.ui.toc:getTocTitleByPage(self.view.footer.pageno) ~= ""
        and TextWidget.PTF_BOLD_START .. self.ui.toc:getTocTitleByPage(self.view.footer.pageno) .. TextWidget.PTF_BOLD_END or ""


        -- self.separator_line.dimen.w = self.progress_bar2.width
        -- -- progress bars size slightly bigger than the font size
        -- self.progress_bar.height = Font:getFace("myfont4").size + 10
        -- self.progress_chapter_bar.height = Font:getFace("myfont4").size + 10

        -- self.progress_bar.height = self.title_text:getSize().h
        -- self.progress_chapter_bar.height = self.title_text:getSize().h

        self.progress_bar.height = self.chapter_text.face.size
        self.progress_barr.height = 1

        self.progress_chapter_bar.height = self.title_text.face.size

        if Device:isAndroid() then
            self.progress_bar.width = 150
            self.progress_barr.width = 150
            self.progress_chapter_bar.width = 150
        else
            self.progress_bar.width = 250
            self.progress_barr.width = 250
            self.progress_chapter_bar.width = 250
        end

        self.chapter_text:setText(chapter)
        if self.option == 1 then
            self.author_text:setText(self.ui.document._document:getDocumentProps().authors)
        else
            self.author_text:setText("")
        end


        local left = self.ui.toc:getChapterPagesLeft(self.view.footer.pageno) or self.ui.document:getTotalPagesLeft(self.view.footer.pageno)
        local left_time = self.view.footer:getDataFromStatistics("", left)

        self.progress_chapter_text:setText(self.view.footer:getChapterProgress(false) .. " " .. left_time)


        -- -- Option 1 for the three bars
        -- self.progress_bar:updateStyle(false, nil)


        -- self.progress_chapter_bar:updateStyle(false, nil)

        -- With or without white bordercolor
        -- self.progress_bar2:updateStyle(false, nil)
        -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_WHITE


        -- -- Option 2 for the three bars
        -- self.progress_bar2:updateStyle(false, 10) -- Optionally the size
        -- self.progress_bar.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_bar.fillcolor = Blitbuffer.COLOR_BLACK


        -- self.progress_chapter_bar.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_chapter_bar.fillcolor = Blitbuffer.COLOR_BLACK

        -- -- With or without white bordercolor
        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_BLACK
        -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_WHITE


        -- -- Other options just for top bar
        -- self.progress_bar2:updateStyle(false, 5)
        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_BLACK
        -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_WHITE
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_DARK_GRAY

        -- Same inverted. I like this one
        -- self.progress_bar2:updateStyle(false, 5)
        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_BLACK
        -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_WHITE


        -- self.progress_bar2:updateStyle(false, 1)
        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_WHITE
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_BLACK


        self.progress_bar2.width = Screen:getSize().w - 2 * TopBar.MARGIN_SIDES
        self.space_after_alt_bar = 15
        if self.alt_bar then
            -- Begin alternative progress bar
            -- This last configuration goes with the separation line. Everything is hardcoded because it is difficult to make it proportional
            self.progress_bar2:updateStyle(false, 1)
            self.progress_bar2.bgcolor = Blitbuffer.COLOR_WHITE
            self.progress_bar2.bordercolor = Blitbuffer.COLOR_BLACK
            self.progress_bar2.fillcolor = Blitbuffer.COLOR_BLACK
            self.progress_bar2.altbar = true
            self.progress_bar2.show_percentage =  self.option == 2
            self.progress_bar2.ui = self.ui
            -- Multiple of 3 onwards because we want the line to be a third in the middle of the progress thick line
            -- Value initialized to 3 when init, possible to toggle
            -- self.progress_bar2.altbar_line_thickness = 3
            -- self.progress_bar2.altbar_line_thickness = 6
            -- self.progress_bar2.factor = 3
            -- The factor plays well with any value which final product is even (3, 9, 15, 21). So even values. More size, higher ticks. I am using a value of 3 with altbar_line_thickness 3 and 6
            -- A factor of 1 also works and we can alternate it
            -- factor 1 with altbar_line_thickness 3 and factor 3 with altbar_line_thickness 6
            -- Factor is not used, I finally hardcoded the value of altbar_ticks_height and altbar_line_thickness for the only two configurations I like
            -- Both parameteres initialized when creating progress_bar2 and onSwitchTopBar() changes
            self.progress_bar2.tick_width = 2
            -- End alternative progress bar
        else
            self.progress_bar2.altbar = false
            self.progress_bar2.height = 20
            -- self.progress_bar2:updateStyle(false, 10)
            -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_DARK_GRAY
            -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_BLACK
            -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_WHITE
            self.progress_bar2.bgcolor = Blitbuffer.COLOR_WHITE
            self.progress_bar2.fillcolor = Blitbuffer.COLOR_DARK_GRAY
            self.progress_bar2.bordercolor = Blitbuffer.COLOR_BLACK
            self.progress_bar2.bordersize = Screen:scaleBySize(1)
        end
        local time_spent_book = self.ui.statistics:getBookStat(self.ui.statistics.id_curr_book)

        if time_spent_book == nil then
            self.progress_bar2.time_spent_book = ""
        else
            -- self.progress_bar2.time_spent_book = time_spent_book[4][2]
            -- self.progress_bar2.time_spent_book =  math.floor(self.view.footer.pageno / self.view.footer.pages*1000)/10 .. "%"
            self.progress_bar2.time_spent_book =  tostring(left)
        end


        self.progress_bar.last = self.pages or self.ui.document:getPageCount()
        -- self.progress_bar.ticks = self.ui.toc:getTocTicksFlattened()
        self.progress_bar2.last = self.pages or self.ui.document:getPageCount()
        self.progress_bar2.ticks = self.ui.toc:getTocTicksFlattened()
        self.progress_bar:setPercentage(self.view.footer.pageno / self.view.footer.pages)
        self.progress_bar2:setPercentage(self.view.footer.pageno / self.view.footer.pages)
        self.progress_chapter_bar:setPercentage(self.view.footer:getChapterProgress(true))
        -- self.progress_bar.height = self.title_text:getSize().h
        -- self.progress_chapter_bar.height = self.title_text:getSize().h

        -- ○ ◎ ● ◐ ◑ ◒ ◓

        local configurable = self.ui.document.configurable
        local powerd = Device:getPowerDevice()

        if self.last_frontlight ~= nil then
            self.frontlight = self.last_frontlight
            self.last_frontlight = nil
        else
            if light_on or powerd:isFrontlightOn() then
                self.frontlight = " ☼"
            else
                self.frontlight = ""
            end
        end
        if self.option == 1 or self.option == 2 or self.option == 3 then
            if Device:isAndroid() then
                if configurable.h_page_margins[1] == 20 and configurable.t_page_margin == self.space_after_alt_bar + 9 + 6 and configurable.h_page_margins[2] == 20 and configurable.b_page_margin == 15 then
                    self.test_light:setText(" ● " .. self.frontlight)
                else
                    self.test_light:setText(" ○ " .. self.frontlight)
                end
            else
                if configurable.h_page_margins[1] == 15 and configurable.t_page_margin == self.space_after_alt_bar + 9 + 6 and configurable.h_page_margins[2] == 15 and configurable.b_page_margin == 15 then
                    self.test_light:setText(" ● " .. self.frontlight)
                else
                    self.test_light:setText(" ○ " .. self.frontlight)
                end
            end
        elseif self.option == 4 then
            if Device:isAndroid() then
                if configurable.h_page_margins[1] == 20 and configurable.t_page_margin == 9 + 6 and configurable.h_page_margins[2] == 20 and configurable.b_page_margin == 15 then
                    self.test_light:setText(" ● " .. self.frontlight)
                else
                    self.test_light:setText(" ○ " .. self.frontlight)
                end
            else
                if configurable.h_page_margins[1] == 15 and configurable.t_page_margin == 9 + 6 and configurable.h_page_margins[2] == 15 and configurable.b_page_margin == 15 then
                    self.test_light:setText(" ● " .. self.frontlight)
                else
                    self.test_light:setText(" ○ " .. self.frontlight)
                end
            end
        end
        if TopBar.show_top_bar then
            TopBar.MARGIN_TOP = Screen:scaleBySize(9) + Screen:scaleBySize(self.space_after_alt_bar)
        else
            TopBar.MARGIN_TOP = Screen:scaleBySize(9)
        end
    else
        self.session_time_text:setText("")
        self.progress_text:setText("")
        self.times_text:setText("")
        self.time_battery_text:setText("")
        self.title_text:setText("")
        self.series_text:setText("")
        self.chapter_text:setText("")
        self.progress_chapter_text:setText("")
        self.book_progress:setText("")
        self.author_text:setText("")
        self.progress_bar.width = 0
        self.progress_bar2.width = 0
        self.progress_chapter_bar.width = 0
        self.times_text_text = ""
        self.time_battery_text_text = ""
        local configurable = self.ui.document.configurable
        local powerd = Device:getPowerDevice()
        if self.last_frontlight ~= nil then
            self.frontlight = self.last_frontlight
            self.last_frontlight = nil
        else
            if light_on or powerd:isFrontlightOn() then
                self.frontlight = " ☼"
            else
                self.frontlight = ""
            end
        end
        if Device:isAndroid() then
            if configurable.h_page_margins[1] == 20 and configurable.t_page_margin == 9 + 6 and configurable.h_page_margins[2] == 20 and configurable.b_page_margin == 15 then
                self.test_light:setText(" ● " .. self.frontlight)
            else
                self.test_light:setText(" ○ " .. self.frontlight)
            end
        else
            if configurable.h_page_margins[1] == 15 and configurable.t_page_margin == 9 + 6 and configurable.h_page_margins[2] == 15 and configurable.b_page_margin == 15 then
                self.test_light:setText(" ● " .. self.frontlight)
            else
                self.test_light:setText(" ○ " .. self.frontlight)
            end
        end
    end
end

function TopBar:onPageUpdate()
    self:toggleBar()

end

function TopBar:paintTo(bb, x, y)
    if self.status_bar and self.status_bar == true then
        self[10][1][1]:setText(self.time_battery_text_text:reverse())
        self[10]:paintTo(bb, x - self[10][1][1]:getSize().w - TopBar.MARGIN_BOTTOM - Screen:scaleBySize(12), y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))
        self[4][1][1]:setText(self.times_text_text:reverse())
        self[4]:paintTo(bb, x - Screen:getHeight() + TopBar.MARGIN_BOTTOM + Screen:scaleBySize(12), y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))
        return
    end
    if not self.fm then
        -- The alighment is good but there are things to take into account
        -- - Any screen side in any screen type, flushed or recessed are not aligned with the frame, they can be a little bit hidden. It depends on the devices
        -- - There are some fonts that are bigger than its em square so the aligment may be not right. For instance Bitter Pro descender overpass its bottom limits
        if TopBar.show_top_bar then
            if self.progress_bar2.altbar then
                self[9]:paintTo(bb, x + TopBar.MARGIN_SIDES, y + Screen:scaleBySize(12))
            else
                self[9]:paintTo(bb, x + TopBar.MARGIN_SIDES, y + Screen:scaleBySize(9))
                -- self[9]:paintTo(bb, x, Screen:getHeight() - Screen:scaleBySize(12))
            end
        end
        self[1]:paintTo(bb, x + TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)

        self[21].dimen = Geom:new{ w = self[2][1]:getSize().w, self[2][1]:getSize().h } -- The text width change and we need to adjust the container dimensions to be able to align it on the right
        self[21]:paintTo(bb, x + Screen:scaleBySize(4), y + Screen:scaleBySize(6))

        -- Top center

        self[3]:paintTo(bb, x + Screen:getWidth()/2 + self[3][1][1]:getSize().w/2 - self[3][2][1]:getSize().w/2, y + TopBar.MARGIN_TOP)
        -- self[3]:paintTo(bb, x + Screen:getWidth()/2, y + 20)


        -- Top right
        -- Commented the text, using progress bar
        -- if not TopBar.show_top_bar then
        --     self[7]:paintTo(bb, x + Screen:getWidth() - self[7][1][1]:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        --     -- self[20]:paintTo(bb, x + Screen:getWidth() - self[20][1][1]:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- end

        self[2].dimen = Geom:new{ w = self[2][1]:getSize().w, self[2][1]:getSize().h } -- The text width change and we need to adjust the container dimensions to be able to align it on the right
        self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- if TopBar.show_top_bar then
        --     self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- end

        -- Si no se muestra la barra de progreso de arriba, se muestra la de arriba a la derecha
        -- Y si se muestra la de arriba a la derecha, queremos mover el texto unos pocos píxeles a la izquierda
        -- if not TopBar.show_top_bar then
        --     self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - TopBar.MARGIN_SIDES - 20, y + TopBar.MARGIN_TOP)
        -- else
        --     self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- end



        -- For the bottom components it is better to use frame containers.
        -- It is better to position them without the dimensions simply passing x and y to the paintTo method
        -- Bottom left
        -- self[4][1].dimen.w = self[4][1][1]:getSize().w
        -- self[4]:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

        self[11][1].dimen.w = self[11][1][1]:getSize().w
        self[11]:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

        -- This is inverted to be shown in left margin
        self[4][1][1]:setText(self.times_text_text:reverse())
        -- When inverted, the text is positioned to the end of the screen
        -- So, we take that position as a reference to position it later
        -- Inverted aligned to side left center
        -- self[4]:paintTo(bb, x - Screen:getHeight()/2 - self[4][1][1]:getSize().w/2, y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))

        -- Inverted aligned to side left top
        self[4]:paintTo(bb, x - Screen:getHeight() + TopBar.MARGIN_BOTTOM + Screen:scaleBySize(12), y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))



        -- print(string.byte(self[5][1][1].text, 1,-1))
        -- Bottom center
         if self[5][1][1].text ~= "" then
            self[5]:paintTo(bb, x + Screen:getWidth()/2 - self[5][1][1]:getSize().w/2, Screen:getHeight() - TopBar.MARGIN_BOTTOM)
        end

        -- Bottom right
        -- Use progress bar
        -- self[8]:paintTo(bb, x + Screen:getWidth() - self[8][1][1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)
        -- self[20]:paintTo(bb, x + Screen:getWidth() - self[20][1][1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

        self[6]:paintTo(bb, x + Screen:getWidth() - self[6][1][1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)


        self[10][1][1]:setText(self.time_battery_text_text:reverse())


        -- Inverted aligned to side left bottom
        -- self[10]:paintTo(bb, x - self[10][1][1]:getSize().w, y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))
        self[10]:paintTo(bb, x - self[10][1][1]:getSize().w - TopBar.MARGIN_BOTTOM - Screen:scaleBySize(12), y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))


        -- self[6][1].dimen.w = self[6][1][1]:getSize().w
        -- -- La barra de progreso de abajo a la derecha se muestra siempre y queremos mover el texto unos pocos píxeles a la izquierda
        -- self[6]:paintTo(bb, x + Screen:getWidth() - self[6][1]:getSize().w - TopBar.MARGIN_SIDES - 20, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

        -- text_container2:paintTo(bb, x + Screen:getWidth() - text_container2:getSize().w - 20, y + 20)
        -- text_container2:paintTo(bb, x + Screen:getWidth()/2 - text_container2:getSize().w/2, y + 20)
    else

        local times_text = TextWidget:new{
            text =  "",
            face = Font:getFace("myfont3", 12),
            fgcolor = Blitbuffer.COLOR_BLACK,
            invert = true,
        }

        local powerd = Device:getPowerDevice()
        local batt_lvl = tostring(powerd:getCapacity())



        local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

        local last_file = "None"
        if G_reader_settings:readSetting("lastfile") ~= nil then
            last_file = G_reader_settings:readSetting("lastfile")
        end


        -- local time_battery_text_text = time .. "|" .. batt_lvl .. "%|" ..  last_file

        -- times_text:setText(time_battery_text_text:reverse())
        -- times_text:paintTo(bb, x - times_text:getSize().w - TopBar.MARGIN_BOTTOM - Screen:scaleBySize(12), y)


        local books_information = FrameContainer:new{
            left_container:new{
                dimen = Geom:new(),
                TextWidget:new{
                    text =  "",
                    face = Font:getFace("myfont3", 12),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            },
            -- background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            padding_bottom = self.bottom_padding,
        }

        -- local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
        -- local _, files = self:getList("*.epub")
        -- books_information[1][1]:setText("TF: " .. tostring(#files))

        local ffiutil = require("ffi/util")
        if G_reader_settings:readSetting("home_dir") and ffiutil.realpath(G_reader_settings:readSetting("home_dir") .. "/stats.lua") then
            local ok, stats = pcall(dofile, G_reader_settings:readSetting("home_dir") .. "/stats.lua")
            local last_days = ""
            for k, v in pairs(stats["stats_last_days"]) do
                last_days = v > 0 and last_days .. " ● " or last_days .. " ○ "
            end
            -- local execute = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub' | wc -l" )
            -- local execute2 = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub.lua' -exec ls {} + | wc -l")
            -- books_information[1][1]:setText("TB: " .. execute:read('*a') .. "TBC: " .. execute2:read('*a'))

            local stats_year = TopBar:getReadThisYearSoFar()
            if stats_year > 0 then
                stats_year = "+" .. stats_year
            end
            books_information[1][1]:setText("B: " .. stats["total_books"]
            .. ", BF: " .. stats["total_books_finished"]
            .. ", BFTM: " .. stats["total_books_finished_this_month"]
            .. ", BFTY: " .. stats["total_books_finished_this_year"]
            .. ", BFLY: " .. stats["total_books_finished_last_year"]
            .. ", BMBR: " .. stats["total_books_mbr"]
            .. ", BTBR: " .. stats["total_books_tbr"]
            .. ", LD: " .. last_days
            .. " " .. stats_year)
        else
            books_information[1][1]:setText("No stats.lua file in home dir")
        end
        books_information:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)


        local times = FrameContainer:new{
            left_container:new{
                dimen = Geom:new(),
                TextWidget:new{
                    text =  "",
                    face = Font:getFace("myfont3", 12),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            },
            -- background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            padding_bottom = self.bottom_padding,
        }


        -- times[1][1]:setText(time .. "|" .. batt_lvl .. "%")

        local total_read = TopBar:getTotalRead()
        local total_books = TopBar:getBooksOpened()
        times[1][1]:setText("BDB: " .. total_books .. ", TR: " .. total_read .. "d")
        times:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM - times[1][1]:getSize().h )
    end
end

function TopBar:onAdjustMarginsTopbar()
    local Event = require("ui/event")
    if G_reader_settings:isTrue("show_top_bar") and not self.status_bar then

        -- local configurable = self.ui.document.configurable
        -- local margins = { TopBar.MARGIN_SIDES, TopBar.MARGIN_TOP, TopBar.MARGIN_SIDES, TopBar.MARGIN_BOTTOM}
        -- local margins_lr = { TopBar.MARGIN_SIDES, TopBar.MARGIN_SIDES}
        -- self.ui.document:onSetPageTopAndBottomMargin(margins_tb)
        -- self.ui:handleEvent(Event:new("SetPageTopMargin",  TopBar.MARGIN_TOP))
        -- self.ui:handleEvent(Event:new("SetPageBottomMargin",  TopBar.MARGIN_BOTTOM))


        -- Adjust margin values to the topbar. Values are in pixels
        -- We add a little bit more, 12 (15, after revision) pixels hardcoded since side margins are 10 and bottom margin 9, always. Top margin value is 9 if not alternative status bar
        -- Exceptions are Android in which side margins are set to 20
        -- And top margin when alternative status bar is on. Value is set to self.space_after_alt_bar (fixed to 15) + 9, adding a little bit more too, 6 more pixels

        self.ui.document.configurable.b_page_margin = 15
        if Device:isAndroid() then
            self.ui.document.configurable.h_page_margins[1] = 20
            self.ui.document.configurable.h_page_margins[2] = 20
        else
            self.ui.document.configurable.h_page_margins[1] = 15
            self.ui.document.configurable.h_page_margins[2] = 15
        end

        local margins = {}
        if self.show_top_bar then
            if Device:isAndroid() then
                margins = { 20, self.space_after_alt_bar + 9 + 6, 20, 15}
            else
                margins = { 15, self.space_after_alt_bar + 9 + 6, 15, 15}
            end
            self.ui.document.configurable.t_page_margin = self.space_after_alt_bar + 9 + 6
        else
            if Device:isAndroid() then
                margins = { 20, 9 + 6, 20, 15}
            else
                margins = { 15, 9 + 6, 15, 15}
            end
            self.ui.document.configurable.t_page_margin = 9 + 6
        end

        self.ui:handleEvent(Event:new("SetPageMargins", margins))

      --self.ui:saveSettings()
   end

end

-- In devicelistener.lua
-- function TopBar:onToggleFrontlight()
--     UIManager:scheduleIn(0.5, function()
--         self:toggleBar()
--         UIManager:setDirty("all", "full")
--     end)
-- end


-- This is called after self.ui.menu:registerToMainMenu(self) in the init method
-- But in this case registerToMainMenu() needs to be called in readerui.lua because the menu is still not available
function TopBar:addToMainMenu(menu_items)
    local Event = require("ui/event")
    -- menu_items.show_double_bar = {
    --     text = _("Show double bar"),
    --     checked_func = function() return G_reader_settings:isTrue("show_double_bar") end,
    --     enabled_func = function()
    --         local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")
    --         return file_type == "epub"
    --     end,
    --     callback = function()
    --         UIManager:broadcastEvent(Event:new("ToggleShowDoubleBar"))
    --     end
    -- }

    menu_items.show_top_bar = {
        text = _("Show top bar"),
        checked_func = function() return G_reader_settings:isTrue("show_top_bar") end,
        -- enabled_func = function()
        --     local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")
        --     return file_type == "epub"
        -- end,
        callback = function()
            UIManager:broadcastEvent(Event:new("ToggleShowTopBar"))
        end
    }
end


return TopBar
