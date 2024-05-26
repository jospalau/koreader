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

    local sql_stmt = [[
        SELECT sum(duration)
        FROM wpm_stat_data
            WHERE DATE(start_time,'unixepoch','localtime') = DATE('now', '0 day', 'localtime')
    ]]

    local read_today = conn:rowexec(string.format(sql_stmt))

    local sql_stmt = [[
        SELECT sum(duration)
        FROM wpm_stat_data
            WHERE DATE(start_time, 'unixepoch', 'localtime') >= DATE('now', 'localtime', 'start of month')
    ]]



    local read_month = conn:rowexec(sql_stmt)

    local sql_stmt ="SELECT avg(wpm) FROM wpm_stat_data where wpm > 0"
    local avg_wpm = conn:rowexec(sql_stmt)

    if avg_wpm == nil then
        avg_wpm = 0
    end

    if title:match("'") then title = title:gsub("'", "''") end

    local conn = SQ3.open(db_location)
    local sql_stmt = "SELECT id FROM book where title like '%tp%'"

    local id_book = conn:rowexec(sql_stmt:gsub("tp",title))


    if id_book == nil then
        id_book = 0
    end
    id_book = tonumber(id_book)

    local conn = SQ3.open(db_location)
    local sql_stmt ="SELECT SUM(duration) FROM wpm_stat_data where id_book = ibp"


    local total_time_book = conn:rowexec(sql_stmt:gsub("ibp",id_book))

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



end

function TopBar:onReaderReady()

    self.title = self.ui.document._document:getDocumentProps().title
    if self.title:find('%[%d?.%d]') then
        self.title = self.title:sub(self.title:find('%]') + 2, self.title:len())
    end
    if self.initial_read_today == nil and self.initial_read_month == nil and self.initial_total_time_book == nil then
        self.initial_read_today, self.initial_read_month, self.initial_total_time_book, self.avg_wpm = self:getReadTodayThisMonth(self.title)
    end

    if self.start_session_time == nil then
        self.start_session_time = os.time()
    end

    local duration_raw = math.floor((os.time() - self.start_session_time))

    if duration_raw < 360 or self.ui.statistics._total_pages < 6 then
        self.start_session_time = os.time()
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


    self[1] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.test_light,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 1,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    self[2] = left_container:new{
        dimen = Geom:new{ w = self.progress_text:getSize().w, self.progress_text:getSize().h },
        self.progress_text,
    }


    self[3] = left_container:new{
        dimen = Geom:new{ w = self.title_text:getSize().w, self.title_text:getSize().h },
        self.title_text,
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

end
function TopBar:onToggleShowTopBar()
    local show_top_bar = G_reader_settings:isTrue("show_top_bar")
    G_reader_settings	:saveSetting("show_top_bar", not show_top_bar)
    TopBar.is_enabled = not show_top_bar
    self:toggleBar()
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
    self.initial_read_today, self.initial_read_month, self.initial_total_time_book, self.avg_wpm = self:getReadTodayThisMonth(self.title)
    self.start_session_time = os.time()
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


function TopBar:toggleBar()
    if TopBar.is_enabled then
        local now_t = os.date("*t")
        local daysdiff = now_t.day - os.date("*t",self.start_session_time).day
        if daysdiff > 0 then
            self.ui.statistics:insertDBSessionStats()
            self.initial_read_today, self.initial_read_month, self.initial_total_time_book, self.avg_wpm  = self:getReadTodayThisMonth(self.title)
            self.start_session_time = os.time()
        end


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



        self.progress_text:setText(("%d de %d"):format(self.view.footer.pageno, self.view.footer.pages))


        -- self.times_text:setText(session_time .. "|" .. read_today .. "|" .. read_month)
        self.times_text_text = session_time .. "|" .. read_today .. "|" .. read_month



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
            self.book_progress:setText(tostring(progress) .. "%|" .. read_book)
            words = title:match("([0-9,]+w)"):gsub("w",""):gsub(",","") .. "w"
            title = title:sub(1, title:find('%(')-2, title:len())
        end
        title = TextWidget.PTF_BOLD_START .. title .. " with " .. words .. TextWidget.PTF_BOLD_END
        self.title_text:setText(title)


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
            self.progress_bar2.show_percentage = true
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
            self.progress_bar2.time_spent_book =  math.floor(self.view.footer.pageno / self.view.footer.pages*1000)/10 .. "%"
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
            if powerd:isFrontlightOn() then
                self.frontlight = " ☼"
            else
                self.frontlight = ""
            end
        end
        if self.option == 1 or self.option == 2 or self.option == 3 then
            if Device:isAndroid() then
                if configurable.h_page_margins[1] == 20 and configurable.t_page_margin == self.space_after_alt_bar + 9 + 6 and configurable.h_page_margins[2] == 20 and configurable.b_page_margin == 12 then
                    self.test_light:setText(" ● " .. self.frontlight)
                else
                    self.test_light:setText(" ○ " .. self.frontlight)
                end
            else
                if configurable.h_page_margins[1] == 12 and configurable.t_page_margin == self.space_after_alt_bar + 9 + 6 and configurable.h_page_margins[2] == 12 and configurable.b_page_margin == 12 then
                    self.test_light:setText(" ● " .. self.frontlight)
                else
                    self.test_light:setText(" ○ " .. self.frontlight)
                end
            end
        elseif self.option == 4 then
            if Device:isAndroid() then
                if configurable.h_page_margins[1] == 20 and configurable.t_page_margin == 9 + 6 and configurable.h_page_margins[2] == 20 and configurable.b_page_margin == 12 then
                    self.test_light:setText(" ● " .. self.frontlight)
                else
                    self.test_light:setText(" ○ " .. self.frontlight)
                end
            else
                if configurable.h_page_margins[1] == 12 and configurable.t_page_margin == 9 + 6 and configurable.h_page_margins[2] == 12 and configurable.b_page_margin == 12 then
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
        self.chapter_text:setText("")
        self.progress_chapter_text:setText("")
        self.book_progress:setText("")
        self.progress_bar.width = 0
        self.progress_bar2.width = 0
        self.progress_chapter_bar.width = 0
        self.times_text_text = ""
        self.time_battery_text_text = ""
    end
end

function TopBar:onPageUpdate()
    self:toggleBar()

end

function TopBar:paintTo(bb, x, y)
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

        -- Top center

        self[3]:paintTo(bb, x + Screen:getWidth()/2 - self[3][1]:getSize().w/2, y + TopBar.MARGIN_TOP)
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

        local time_battery_text_text = time .. "|" .. batt_lvl .. "%|" ..  last_file

        times_text:setText(time_battery_text_text:reverse())
        times_text:paintTo(bb, x - times_text:getSize().w - TopBar.MARGIN_BOTTOM - Screen:scaleBySize(12), y)


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

        local ok, stats = pcall(dofile, G_reader_settings:readSetting("home_dir") .. "/stats.lua")

        -- local execute = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub' | wc -l" )
        -- local execute2 = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub.lua' -exec ls {} + | wc -l")
        -- books_information[1][1]:setText("TB: " .. execute:read('*a') .. "TBC: " .. execute2:read('*a'))
        books_information[1][1]:setText("B: " .. stats["total_books"] .. ", BF: " .. stats["total_books_finished"] .. ", BFTM: "
        .. stats["total_books_finished_this_month"] .. ", BFTY: " .. stats["total_books_finished_this_year"]
        .. ", BFLY: " .. stats["total_books_finished_last_year"] .. ", BMBR: " .. stats["total_books_mbr"] .. ", BTBR: " .. stats["total_books_tbr"])
        books_information:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)
    end
end

function TopBar:onAdjustMarginsTopbar()
    local Event = require("ui/event")
    -- local configurable = self.ui.document.configurable
    -- local margins = { TopBar.MARGIN_SIDES, TopBar.MARGIN_TOP, TopBar.MARGIN_SIDES, TopBar.MARGIN_BOTTOM}
    -- local margins_lr = { TopBar.MARGIN_SIDES, TopBar.MARGIN_SIDES}
    -- self.ui.document:onSetPageTopAndBottomMargin(margins_tb)
    -- self.ui:handleEvent(Event:new("SetPageTopMargin",  TopBar.MARGIN_TOP))
    -- self.ui:handleEvent(Event:new("SetPageBottomMargin",  TopBar.MARGIN_BOTTOM))


    -- Adjust margin values to the topbar. Values are in pixels
    -- We add a little bit more, 12 pixels hardcoded since side margins are 10 and bottom margin 9, always. Top margin value is 9 if not alternative status bar
    -- Exceptions are Android in which side margins are set to 20
    -- And top margin when alternative status bar is on. Value is set to self.space_after_alt_bar (fixed to 15) + 9, adding a little bit more too, 6 more pixels

    self.ui.document.configurable.b_page_margin = 12
    if Device:isAndroid() then
        self.ui.document.configurable.h_page_margins[1] = 20
        self.ui.document.configurable.h_page_margins[2] = 20
    else
        self.ui.document.configurable.h_page_margins[1] = 12
        self.ui.document.configurable.h_page_margins[2] = 12
    end

    local margins = {}
    if self.show_top_bar then
        if Device:isAndroid() then
            margins = { 20, self.space_after_alt_bar + 9 + 6, 20, 12}
        else
            margins = { 12, self.space_after_alt_bar + 9 + 6, 12, 12}
        end
        self.ui.document.configurable.t_page_margin = self.space_after_alt_bar + 9 + 6
    else
        if Device:isAndroid() then
            margins = { 20, 9 + 6, 20, 12}
        else
            margins = { 12, 9 + 6, 12, 12}
        end
        self.ui.document.configurable.t_page_margin = 9 + 6
    end

    self.ui:handleEvent(Event:new("SetPageMargins", margins))

    --self.ui:saveSettings()

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
