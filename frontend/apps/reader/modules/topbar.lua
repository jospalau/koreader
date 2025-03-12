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
local Math = require("optmath")
local SQ3 = require("lua-ljsqlite3/init")
local ProgressWidget = require("ui/widget/progresswidget")
local Device = require("device")
local Size = require("ui/size")
local ffiUtil = require("ffi/util")


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

    total_time_book = tonumber(total_time_book)

    sql_stmt ="SELECT COUNT(id_book) FROM wpm_stat_data where id_book = ibp"


    local sessions_current_book = conn:rowexec(sql_stmt:gsub("ibp", id_book))

    if sessions_current_book == nil then
        sessions_current_book = 0
    end

    sessions_current_book = tonumber(sessions_current_book)



    local sql_stmt = [[
        SELECT sum(duration)
        FROM wpm_stat_data
            WHERE DATE(start_time, 'unixepoch', 'localtime')
            BETWEEN DATE('now', 'localtime', 'start of month', "-1 month")
            AND DATE('now', 'localtime', 'start of month')
    ]]

    local read_last_month = conn:rowexec(sql_stmt)

    if read_last_month == nil then
        read_last_month = 0
    end
    read_last_month = tonumber(read_last_month)


    local sql_stmt = [[
        SELECT sum(duration)
        FROM wpm_stat_data
            WHERE strftime('%Y',DATE(datetime(start_time,'unixepoch'))) = 'year'
    ]]


    local read_year = conn:rowexec(sql_stmt:gsub("year", os.date("*t").year))

    if read_year == nil then
        read_year = 0
    end
    read_year = tonumber(read_year)

    conn:close()
    if read_today == nil then
        read_today = 0
    end
    read_today = tonumber(read_today)

    if read_month == nil then
        read_month = 0
    end
    read_month = tonumber(read_month)

    return read_today, read_month, total_time_book, avg_wpm, sessions_current_book, read_last_month, read_year
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

    local sql_stmt = "SELECT name FROM sqlite_master WHERE type='table' AND name='wpm_stat_data'"
    local exists_table = conn:rowexec(sql_stmt)
    local stats_table = {}
    if exists_table == nil then
        return 0
    end

    local sql_stmt = [[
        SELECT sum(duration)
        FROM page_stat_data
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

    local sql_stmt = "SELECT name FROM sqlite_master WHERE type='table' AND name='wpm_stat_data'"
    local exists_table = conn:rowexec(sql_stmt)
    local stats_table = {}
    if exists_table == nil then
        return 0
    end

    sql_stmt = [[
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

function TopBar:getPublicationDateBook()
    if not self.ui then return end
    local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")
    if file_type == "epub" then
        local css_text = self.ui.document:getDocumentFileContent("OPS/styles/stylesheet.css")
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("stylesheet.css")
        end
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("OEBPS/css/style.css")
        end

        -- $ bsdtar tf arthur-conan-doyle_the-hound-of-the-baskervilles.epub | grep -i css
        -- epub/css/
        -- epub/css/core.css
        -- epub/css/se.css
        -- epub/css/local.css
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("epub/css/core.css")
        end

        local opf_text = self.ui.document:getDocumentFileContent("OPS/Miscellaneous/content.opf")
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("content.opf")
        end

        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OPS/volume.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("volume.opf")
        end

        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OEBPS/Miscellaneous/content.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OEBPS/content.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("content.opf")
        end

        -- $ bsdtar tf arthur-conan-doyle_the-hound-of-the-baskervilles.epub | grep -i content
        -- epub/content.opf
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("epub/content.opf")
        end

        if opf_text == nil or not string.gmatch(opf_text, "<dc:date>(.-)</dc:date>")(1) then
            return ""
        else
            return string.gmatch(opf_text, "<dc:date>(.-)</dc:date>")(1):sub(1, 4)
        end
    end
end

function TopBar:getOriginBook()
    if not self.ui then return end
    local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")
    if file_type == "epub" then
        local css_text = self.ui.document:getDocumentFileContent("OPS/styles/stylesheet.css")
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("stylesheet.css")
        end
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("OEBPS/css/style.css")
        end

        -- $ bsdtar tf arthur-conan-doyle_the-hound-of-the-baskervilles.epub | grep -i css
        -- epub/css/
        -- epub/css/core.css
        -- epub/css/se.css
        -- epub/css/local.css
        if css_text == nil then
            css_text = self.ui.document:getDocumentFileContent("epub/css/core.css")
        end

        local opf_text = self.ui.document:getDocumentFileContent("OPS/Miscellaneous/content.opf")
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("content.opf")
        end

        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OPS/volume.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("volume.opf")
        end

        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OEBPS/Miscellaneous/content.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("OEBPS/content.opf")
        end
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("content.opf")
        end

        -- $ bsdtar tf arthur-conan-doyle_the-hound-of-the-baskervilles.epub | grep -i content
        -- epub/content.opf
        if opf_text == nil then
            opf_text = self.ui.document:getDocumentFileContent("epub/content.opf")
        end

        local origin = string.match(opf_text, "<opf:meta property=\"calibre:user_metadata\">(.-)</opf:meta>")
        if origin ~= nil then
            origin = string.match(origin, "\"#origin\": {(.-)}")
            if origin ~= nil then
                origin = string.match(origin, " \"#value#\": \".-\"")
                origin = string.match(origin, ": .*")
                origin = origin:sub(4,origin:len() - 1)
            end
        end
        return origin
    end
end

function TopBar:init()
    if self.fm then return end
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

    if TopBar.preserved_initial_read_last_month then
        self.initial_read_last_month = TopBar.preserved_initial_read_last_month
        TopBar.preserved_initial_read_last_month = nil
    end

    if TopBar.preserved_initial_read_year then
        self.initial_read_year = TopBar.preserved_initial_read_year
        TopBar.preserved_initial_read_year = nil
    end

    if TopBar.preserved_initial_total_time_book then
        self.initial_total_time_book = TopBar.preserved_initial_total_time_book
        TopBar.preserved_initial_total_time_book = nil
    end

    if TopBar.preserved_avg_wpm ~= nil then
        self.avg_wpm = TopBar.preserved_avg_wpm
        TopBar.preserved_avg_wpm = nil
    end

    if TopBar.preserved_sessions_current_book ~= nil then
        self.sessions_current_book = TopBar.preserved_sessions_current_book
        TopBar.preserved_sessions_current_book = nil
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
        TopBar.altbar_line_thickness = TopBar.preserved_altbar_line_thickness
        TopBar.preserved_altbar_line_thickness = nil
    else
        TopBar.altbar_line_thickness = 9
    end

    if TopBar.preserved_altbar_ticks_height ~= nil then
        TopBar.altbar_ticks_height = TopBar.preserved_altbar_ticks_height
        TopBar.preserved_altbar_ticks_height = nil
    else
        TopBar.altbar_ticks_height = 7
    end

    if TopBar.preserved_option ~= nil then
        TopBar.option = TopBar.preserved_option
        TopBar.preserved_option = nil
    else
        TopBar.option = 1
    end

    if TopBar.preserved_init_page ~= nil then
        self.init_page = TopBar.preserved_init_page
        TopBar.preserved_init_page = nil
    else
        self.init_page = nil
    end

    if TopBar.preserved_init_page_screens ~= nil then
        self.init_page_screens = TopBar.preserved_init_page_screens
        TopBar.preserved_init_page_screens = nil
    else
        self.init_page_screens = nil
    end

    if TopBar.preserved_initial_battery_lvl then
        self.initial_battery_lvl = TopBar.preserved_initial_battery_lvl
        TopBar.preserved_initial_battery_lvl = nil
    end

    self.ui:registerPostReaderReadyCallback(function()
        self.ui.menu:registerToMainMenu(self)
        if os.time() - self.start_session_time < 5 then
            self.start_session_time = os.time()
        end

        self:toggleBar()
        UIManager:nextTick(function()
            self.onPageUpdate = function(this, pageno)
                self:toggleBar()
                return
            end
            -- self:toggleBar()
        end)
    end)
end

local getMem = function()
    -- local cmd = "cat /proc/$(pgrep luajit | head -1)/statm | awk '{ print $2 }'"
    -- local std_out = io.popen(cmd, "r")
    -- if std_out then
    --     local output = std_out:read("*all")
    --     std_out:close()
    --     return true, output
    -- end
    local stat = io.open("/proc/self/stat", "r")
    if stat == nil then return end

    local util = require("util")
    local t = util.splitToArray(stat:read("*line"), " ")
    stat:close()

    if #t == 0 then return 0 end

    return Math.round(tonumber(t[24]) / 256)
end

function TopBar:onReaderReady()
    self.initial_memory = getMem()

    local powerd = Device:getPowerDevice()
    if self.initial_battery_lvl == nil then
        self.initial_battery_lvl = powerd:getCapacity()
    end


    self:onSetDimensions()
    self.title = self.ui.document._document:getDocumentProps().title
    self.series = self.ui.document._document:getDocumentProps().series
    if self.series ~= "" then
        self.series = "(" .. TextWidget.PTF_BOLD_START .. self.series .. TextWidget.PTF_BOLD_END .. ")"
    end

    -- if self.title:find('%[%d?.%d]') then
    --     self.series = self.title:sub(1, self.title:find('%[') - 2)
    --     self.series = "(" .. TextWidget.PTF_BOLD_START .. self.series .. " " ..  tonumber(self.ui.document._document:getDocumentProps().title:match("%b[]"):sub(2, self.ui.document._document:getDocumentProps().title:match("%b[]"):len() - 1)) .. TextWidget.PTF_BOLD_END .. ")"
    --     self.title = self.title:sub(self.title:find('%]') + 2, self.title:len())
    -- end
    if self.initial_read_today == nil and self.initial_read_month == nil and self.initial_total_time_book == nil and self.sessions_current_book == nil and self.read_last_month == nil and self.initial_read_year == nil then
        self.initial_read_today, self.initial_read_month, self.initial_total_time_book, self.avg_wpm, self.sessions_current_book, self.initial_read_last_month, self.initial_read_year = self:getReadTodayThisMonth(self.ui.document._document:getDocumentProps().title)
    end

    if self.start_session_time == nil then
        self.start_session_time = os.time()
    end

    local duration_raw = math.floor((os.time() - self.start_session_time))

    if duration_raw < 360 or self.ui.statistics._total_pages < 6 then
        self.start_session_time = os.time()
        self.init_page = nil
        self.init_page_screens = nil
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

    self.test_light_text = TextWidget:new{
        text = "",
        face = Font:getFace("myfont3"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.progress_book_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.times_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3", 12),
        fgcolor = Blitbuffer.COLOR_BLACK,
        invert = false,
    }

    self.book_stats_text = TextWidget:new{
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
        face = Font:getFace("myfont3", 14),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
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

    self.light_widget_container = left_container:new{
        dimen = Geom:new(),
        self.test_light_text,
    }

    self.progress_widget_container = left_container:new{
        dimen = Geom:new{ w = self.progress_book_text:getSize().w, self.progress_book_text:getSize().h },
        self.progress_book_text,
    }

    self.title_and_series_widget_container = HorizontalGroup:new{
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

    self.stats_times_widget_container = left_container:new{
        dimen = Geom:new(),
        self.times_text,
    }

    self.progress_book_widget_container = left_container:new{
        dimen = Geom:new{ w = self.book_stats_text:getSize().w, self.book_stats_text:getSize().h },
        self.book_stats_text,
    }

    self.chapter_widget_container = left_container:new{
        dimen = Geom:new(),
        self.chapter_text,
    }

    self.progress_chapter_widget_container = left_container:new{
        dimen = Geom:new(),
        self.progress_chapter_text,
    }

    self.progress_bar_book = ProgressWidget:new{
        width = 200,
        height = 5,
        percentage = 0,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }

    self.progress_bar_book_widget_container = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_bar_book,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
    }

    self.author_information_widget_container = left_container:new{
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

    self.progress_chapter_bar_chapter_widget_container = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_chapter_bar,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
    }

    -- self.main_progress_bar  = ProgressWidget:new{
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

    self.main_progress_bar  = ProgressWidget:new{
        width = Screen:getSize().w,
        height = 0,
        percentage = 0,
        -- bordercolor = Blitbuffer.COLOR_GRAY,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
        altbar_line_thickness = TopBar.altbar_line_thickness, -- Initial value, it is used in alternative
        -- factor = 1,
        altbar_ticks_height = TopBar.altbar_ticks_height,
        -- bordercolor = Blitbuffer.COLOR_WHITE,
    }

    self.progress_bar_widget_container = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.main_progress_bar,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
    }

    -- self.bottom_frame = FrameContainer:new{
    --     -- background = Blitbuffer.COLOR_WHITE,
    --     padding_bottom = 20,
    --     bordersize = 0,
    --     VerticalGroup:new{
    --         -- self.progress_book_text,
    --         self.progress_book_text,
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

    self.battery_widget_container = left_container:new{
        dimen = Geom:new(),
        self.time_battery_text,
    }

    self.ignore_corners_widget_container = left_container:new{
        dimen = Geom:new(),
        TextWidget:new{
            text =  "",
            face = Font:getFace("symbols", 12),
            fgcolor = Blitbuffer.COLOR_BLACK,
        },
    }
    if Device:isAndroid() then
        TopBar.MARGIN_SIDES =  Screen:scaleBySize(20)
    end
    self.status_bar = self.view.footer_visible
    self.pub_date = self:getPublicationDateBook()
    self.total_words = select(2, self.ui.document:getBookCharactersCount())
    self.origin_book = self:getOriginBook()

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

function TopBar:onFrontlightStateChanged()
    local top_widget_container = UIManager:getTopmostVisibleWidget() or {}
    if not Device.screen_saver_mode and top_widget_container.name == "ReaderUI" then
        self:toggleBar()
        -- local Screen = require("device").screen
        -- self:paintTo(Screen.bb, 0, 0)
        -- UIManager:setDirty(self, "ui")
        UIManager:widgetRepaint(self, 0, 0)
        UIManager:setDirty(self, function()
            return "ui"
        end)
    end
end

function TopBar:onSetDimensions()
    self.width = Screen:getWidth()
end


function TopBar:onResume()
    self.initial_read_today, self.initial_read_month, self.initial_total_time_book, self.avg_wpm, self.sessions_current_book, self.initial_read_last_month, self.initial_read_year = self:getReadTodayThisMonth(self.ui.document._document:getDocumentProps().title)
    self.start_session_time = os.time()
    self.init_page = nil
    self.init_page_screens = nil
    local powerd = Device:getPowerDevice()
    self.initial_battery_lvl = powerd:getCapacity()
    self:toggleBar()
end


function TopBar:onPreserveCurrentSession()
    -- Can be called before ReaderUI:reloadDocument() to not reset the current session
    TopBar.preserved_start_session_time = self.start_session_time
    TopBar.preserved_initial_read_today = self.initial_read_today
    TopBar.preserved_initial_read_month = self.initial_read_month
    TopBar.preserved_initial_read_last_month = self.initial_read_last_month
    TopBar.preserved_initial_read_year = self.initial_read_year
    TopBar.preserved_initial_total_time_book = self.initial_total_time_book
    TopBar.preserved_avg_wpm = self.avg_wpm
    TopBar.preserved_sessions_current_book = self.sessions_current_book
    TopBar.preserved_alt_bar = self.show_top_bar
    TopBar.preserved_show_alt_bar = self.alt_bar
    TopBar.preserved_altbar_line_thickness = self.main_progress_bar.altbar_line_thickness
    TopBar.preserved_altbar_ticks_height = self.main_progress_bar.altbar_ticks_height
    TopBar.preserved_option = self.option
    TopBar.preserved_init_page = self.init_page
    TopBar.preserved_init_page_screens = self.init_page_screens
    TopBar.preserved_initial_battery_lvl = self.initial_battery_lvl
end


function TopBar:onSwitchTopBar()
    if not TopBar.is_enabled then
        G_reader_settings:saveSetting("show_top_bar", true)
        TopBar.is_enabled = true
        TopBar.show_top_bar = true
        TopBar.alt_bar = true
        self.main_progress_bar.altbar_ticks_height = 5
        self.main_progress_bar.altbar_line_thickness = 9
        TopBar.option = 1
        self:toggleBar()

        UIManager:setDirty(self.view.dialog, function()
            return self.view.currently_scrolling and "fast" or "ui"
        end)
        return
    end
    if G_reader_settings:isTrue("show_top_bar") then
        if TopBar.show_top_bar then
            if TopBar.option == 1 then
                self.main_progress_bar.altbar_ticks_height = 16
                self.main_progress_bar.altbar_line_thickness = 6
                TopBar.option = 2
                -- self.main_progress_bar.factor = 3
            elseif TopBar.option == 2 then
                self.main_progress_bar.altbar_ticks_height = -1
                self.main_progress_bar.altbar_line_thickness = -1
                -- self.main_progress_bar.factor = -1
                TopBar.alt_bar = false
                TopBar.option = 3
            elseif TopBar.option == 3 then
                self.main_progress_bar.altbar_ticks_height = 5
                self.main_progress_bar.altbar_line_thickness = 9
                -- self.main_progress_bar.factor = 1
                TopBar.show_top_bar = false
                TopBar.option = 4
            end
        -- We don't want to cycle disabling/enabling the topbar
        -- since there is a swipe gesture in the page text info plugin
        -- to toggle it on and off
        -- elseif TopBar.is_enabled then
        --     TopBar.is_enabled = false
        -- Although we do it here. First we disable it and then
        -- we let it ready to start from the beginning
        else
            G_reader_settings:saveSetting("show_top_bar", false)
            TopBar.is_enabled = false
            TopBar.show_top_bar = true
            TopBar.alt_bar = true
            self.main_progress_bar.altbar_ticks_height = 5
            self.main_progress_bar.altbar_line_thickness = 9
            TopBar.option = 1
        end
        self:toggleBar()

        -- TopBar.is_enabled = not TopBar.is_enabled
        -- self:toggleBar()
        -- UIManager:setDirty("all", "partial")
        UIManager:setDirty(self.view.dialog, function()
            return self.view.currently_scrolling and "fast" or "ui"
        end)
    end
end

function TopBar:quickToggleOnOff(put_off)
    G_reader_settings:saveSetting("show_top_bar", put_off)
    TopBar.is_enabled = put_off
    self:toggleBar()
    UIManager:setDirty(self.view.dialog, function()
        return self.view.currently_scrolling and "fast" or "ui"
    end)
end

function TopBar:resetSession()
    self.initial_read_today, self.initial_read_month, self.initial_total_time_book, self.avg_wpm, self.sessions_current_book, self.initial_read_last_month, self.initial_read_year = self:getReadTodayThisMonth(self.title)
    local now_ts = os.time()
    self.start_session_time = now_ts
    self.init_page = nil
    self.init_page_screens = nil
end

function TopBar:toggleBar(light_on)
    if TopBar.is_enabled then
        local user_duration_format = "modern"
        local session_time = datetime.secondsToClockDuration(user_duration_format, os.time() - self.start_session_time, false)

        local duration_raw =  math.floor((os.time() - self.start_session_time))
        self.wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        self.wpm_text:setText(self.wpm_session .. "wpm")

        local read_today = self.initial_read_today + (os.time() - self.start_session_time)
        read_today = read_today > 86400 and math.floor(read_today/60/60/24 * 100)/100 .. "d" or datetime.secondsToClockDuration(user_duration_format, read_today, false)

        local read_month = self.initial_read_month + (os.time() - self.start_session_time)
        read_month = read_month > 86400 and math.floor(read_month/60/60/24 * 100)/100 .. "d" or datetime.secondsToClockDuration(user_duration_format, read_month, false)

        local read_last_month = self.initial_read_last_month + (os.time() - self.start_session_time)
        read_last_month = read_last_month > 86400 and math.floor(read_last_month/60/60/24 * 100)/100 .. "d" or datetime.secondsToClockDuration(user_duration_format, read_last_month, false)

        local read_year = self.initial_read_year + (os.time() - self.start_session_time)
        read_year = read_year > 86400 and math.floor(read_year/60/60/24 * 100)/100 .. "d" or datetime.secondsToClockDuration(user_duration_format, read_year, false)

        local read_book = self.initial_total_time_book + (os.time() - self.start_session_time)
        read_book = read_book > 86400 and math.floor(read_book/60/60/24 * 100)/100 .. "d" or datetime.secondsToClockDuration(user_duration_format, read_book, false)


        self.session_time_text:setText(datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")))


        if self.ui.pagemap:wantsPageLabels() then
           self.progress_book_text:setText(("%d de %d"):format(self.ui.pagemap:getCurrentPageLabel(true), self.ui.pagemap:getLastPageLabel(true)))
        else
           self.progress_book_text:setText(("%d de %d"):format(self.view.footer.pageno, self.view.footer.pages))
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
            -- self.times_text:setText("RTS: " .. session_time ..  "(" .. pages_session .. "p), RT: " .. read_today .. ", RTM: " .. read_month .. ", RLM: " .. read_last_month .. ", RTY: " .. read_year)
            -- self.times_text_text = "RTS: " .. session_time ..  "(" .. pages_session .. "p), RT: " .. read_today .. ", RTM: " .. read_month .. ", RLM: " .. read_last_month .. ", RTY: " .. read_year
            self.times_text:setText(session_time ..  "(" .. pages_session .. "p)," .. read_today .. "," .. read_month .. "," .. read_last_month .. "," .. read_year)
            self.times_text_text = session_time ..  "(" .. pages_session .. "p)," .. read_today .. "," .. read_month .. "," .. read_last_month .. "," .. read_year
        else
            init_page = self.init_page_screens
            pages_session = self.view.footer.pageno - init_page
            -- self.times_text:setText("RTS: " .. session_time .. ", RT: " .. read_today .. ", RTM: " .. read_month .. ", RLM: " .. read_last_month .. ", RTY: " .. read_year)
            -- self.times_text_text = "RTS: " .. session_time .. ", RT: " .. read_today .. ", RTM: " .. read_month .. ", RLM: " .. read_last_month .. ", RTY: " .. read_year
            self.times_text:setText(session_time .. "," .. read_today .. "," .. read_month .. "," .. read_last_month .. "," .. read_year)
            self.times_text_text = session_time .. "," .. read_today .. "," .. read_month .. "," .. read_last_month .. "," .. read_year
        end


        local powerd = Device:getPowerDevice()
        local batt_lvl = tostring(powerd:getCapacity())


        local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
        self.time_battery_text_text = time .. "|" .. batt_lvl .. "%"

        local words = "?w"
        local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")

        local title = self.title
        -- if (title:find("([0-9,]+w)") ~= nil) then
        --     words = self.title:match("([0-9,]+w)"):gsub("w",""):gsub(",","")
        --     local hours_to_read = tonumber(words)/(self.avg_wpm * 60)
        --     local progress =  math.floor(100/hours_to_read * 10)/10
        --     words = title:match("([0-9,]+w)"):gsub("w",""):gsub(",","") .. "w"
        --     self.book_stats_text:setText(words .. "|" .. tostring(progress) .. "%|" .. read_book)
        --     title = title:sub(1, title:find('%(')-2, title:len())
        -- end
        -- title = TextWidget.PTF_BOLD_START .. title .. " with " .. words .. TextWidget.PTF_BOLD_END
        -- if self.series == "" then
        --     title = TextWidget.PTF_BOLD_START .. title .. TextWidget.PTF_BOLD_END
        -- else
        --     title = TextWidget.PTF_BOLD_START .. title .. " (" .. self.series .. ")" .. TextWidget.PTF_BOLD_END
        -- end

        local hours_to_read = tonumber(self.total_words)/(self.avg_wpm * 60)
        local progress =  math.floor(100/hours_to_read * 10)/10
        self.total_wordsk = tostring(math.floor(self.total_words/1000))
        self.book_stats_text:setText(self.total_wordsk .. "kw|" .. tostring(self.sessions_current_book) .. "s|" .. tostring(progress) .. "%|" .. read_book)
        title = TextWidget.PTF_BOLD_START .. title .. TextWidget.PTF_BOLD_END
        self.title_text:setText(title)
        self.series_text:setText(self.series)


        local chapter = self.ui.toc:getTocTitleByPage(self.view.footer.pageno) ~= ""
        and TextWidget.PTF_BOLD_START .. self.ui.toc:getTocTitleByPage(self.view.footer.pageno) .. TextWidget.PTF_BOLD_END or ""


        -- self.separator_line.dimen.w = self.main_progress_bar.width
        -- -- progress bars size slightly bigger than the font size
        -- self.progress_bar_book.height = Font:getFace("myfont4").size + 10
        -- self.progress_chapter_bar.height = Font:getFace("myfont4").size + 10

        -- self.progress_bar_book.height = self.title_text:getSize().h
        -- self.progress_chapter_bar.height = self.title_text:getSize().h

        self.progress_bar_book.height = self.progress_book_text.face.size
        self.progress_chapter_bar.height = self.chapter_text.face.size

        if Device:isAndroid() then
            self.progress_bar_book.width = 150
            self.progress_chapter_bar.width = 150
        else
            self.progress_bar_book.width = 250
            self.progress_chapter_bar.width = 250
        end

        self.progress_bar_book.width = self.progress_book_text:getSize().w
        -- if chapter:len() <= 30 then
        --     self.chapter_text:setText(chapter)
        -- else
        --     self.chapter_text:setText(chapter:gsub(1, 30) .. "…")
        -- end
        self.chapter_text:setText(chapter)
        if self.option == 1 then
            if self.origin_book and  self.origin_book ~= "" then
                self.author_text:setText(self.ui.document._document:getDocumentProps().authors .. " - " ..  self.pub_date .. " - "  ..  self.origin_book .. " - " .. self.book_stats_text.text)
            else
                self.author_text:setText(self.ui.document._document:getDocumentProps().authors .. " - " ..  self.pub_date .. " - " .. self.book_stats_text.text)
            end
        else
            self.author_text:setText("")
        end


        local left = self.ui.toc:getChapterPagesLeft(self.view.footer.pageno) or self.ui.document:getTotalPagesLeft(self.view.footer.pageno)
        local left_time = self.view.footer:getDataFromStatistics("", left)

        self.progress_chapter_text:setText(self.view.footer:getChapterProgress(false)) -- .. " " .. left_time)


        -- -- Option 1 for the three bars
        -- self.progress_bar_book:updateStyle(false, nil)


        -- self.progress_chapter_bar:updateStyle(false, nil)

        -- With or without white bordercolor
        -- self.main_progress_bar:updateStyle(false, nil)
        -- self.main_progress_bar.bordercolor = Blitbuffer.COLOR_WHITE


        -- -- Option 2 for the three bars
        -- self.main_progress_bar:updateStyle(false, 10) -- Optionally the size
        -- self.progress_bar_book.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_bar_book.fillcolor = Blitbuffer.COLOR_BLACK


        -- self.progress_chapter_bar.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_chapter_bar.fillcolor = Blitbuffer.COLOR_BLACK

        -- -- With or without white bordercolor
        -- self.main_progress_bar.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.main_progress_bar.fillcolor = Blitbuffer.COLOR_BLACK
        -- self.main_progress_bar.bordercolor = Blitbuffer.COLOR_WHITE


        -- -- Other options just for top bar
        -- self.main_progress_bar:updateStyle(false, 5)
        -- self.main_progress_bar.bgcolor = Blitbuffer.COLOR_BLACK
        -- self.main_progress_bar.bordercolor = Blitbuffer.COLOR_WHITE
        -- self.main_progress_bar.fillcolor = Blitbuffer.COLOR_DARK_GRAY

        -- Same inverted. I like this one
        -- self.main_progress_bar:updateStyle(false, 5)
        -- self.main_progress_bar.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.main_progress_bar.fillcolor = Blitbuffer.COLOR_BLACK
        -- self.main_progress_bar.bordercolor = Blitbuffer.COLOR_WHITE


        -- self.main_progress_bar:updateStyle(false, 1)
        -- self.main_progress_bar.bgcolor = Blitbuffer.COLOR_WHITE
        -- self.main_progress_bar.fillcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.main_progress_bar.bordercolor = Blitbuffer.COLOR_BLACK


        self.main_progress_bar.width = self.width - 2 * TopBar.MARGIN_SIDES
        -- No scaled because margins are saved not scaled even though they are scaled
        -- when set (see onSetPageMargins() in readertypeset.lua)
        self.space_after_alt_bar = 15
        if self.alt_bar then
            -- Begin alternative progress bar
            -- This last configuration goes with the separation line. Everything is hardcoded because it is difficult to make it proportional
            self.main_progress_bar:updateStyle(false, 1)
            self.main_progress_bar.bgcolor = Blitbuffer.COLOR_WHITE
            self.main_progress_bar.bordercolor = Blitbuffer.COLOR_BLACK
            self.main_progress_bar.fillcolor = Blitbuffer.COLOR_BLACK
            self.main_progress_bar.altbar = true
            self.main_progress_bar.show_percentage = self.option == 2
            self.main_progress_bar.ui = self.ui
            -- Multiple of 3 onwards because we want the line to be a third in the middle of the progress thick line
            -- self.main_progress_bar.altbar_line_thickness = 3
            -- self.main_progress_bar.altbar_line_thickness = 6


            -- self.main_progress_bar.altbar_line_thickness is the line height (thickness) of the progress bar line
            -- self.main_progress_bar.altbar_line_thickness/3 is the line height (thickness) of the fixed static bar line calculated in the widget
            -- We need a minimum tick height of self.main_progress_bar.altbar_line_thickness/3
            -- And then we add a little bit more, an even number, to have the same tick size up and down the line
            -- self.main_progress_bar.altbar_ticks_height = (self.main_progress_bar.altbar_line_thickness/3) + 4 -- Line size, not progress line

            -- Factor variable is not used. I finally hardcoded the value of altbar_ticks_height and altbar_line_thickness
            -- for the only two configurations I like
            -- Both parameteres are initialized when creating progress_bar2 and onSwitchTopBar() changes

            -- self.main_progress_bar.factor = 3
            -- The factor plays well with any value which final product is even (3, 9, 15, 21). So even values. More size, higher ticks. I am using a value of 3 with altbar_line_thickness 3 and 6
            -- A factor of 1 also works and we can alternate it
            -- factor 1 with altbar_line_thickness 3 and factor 3 with altbar_line_thickness 6
            self.main_progress_bar.tick_width = 2 -- Not scaled, we want 2px size for ticks width
            -- End alternative progress bar
        else
            self.main_progress_bar.altbar = false
            -- self.main_progress_bar.height = 20 -- Not scaled
            self.main_progress_bar:setHeight(10)
            -- self.main_progress_bar:updateStyle(false, 10)
            -- self.main_progress_bar.bgcolor = Blitbuffer.COLOR_DARK_GRAY
            -- self.main_progress_bar.fillcolor = Blitbuffer.COLOR_BLACK
            -- self.main_progress_bar.bordercolor = Blitbuffer.COLOR_WHITE
            self.main_progress_bar.bgcolor = Blitbuffer.COLOR_WHITE
            self.main_progress_bar.fillcolor = Blitbuffer.COLOR_DARK_GRAY
            self.main_progress_bar.bordercolor = Blitbuffer.COLOR_BLACK
            self.main_progress_bar.bordersize = Screen:scaleBySize(1)
        end
        local time_spent_book = self.ui.statistics:getBookStat(self.ui.statistics.id_curr_book)

        if time_spent_book == nil then
            self.main_progress_bar.time_spent_book = ""
        else
            -- self.main_progress_bar.time_spent_book = time_spent_book[4][2]
            -- self.main_progress_bar.time_spent_book =  math.floor(self.view.footer.pageno / self.view.footer.pages*1000)/10 .. "%"
            self.main_progress_bar.time_spent_book =  tostring(left)
        end


        self.progress_bar_book.last = self.pages or self.ui.document:getPageCount()
        -- self.progress_bar_book.ticks = self.ui.toc:getTocTicksFlattened()
        self.main_progress_bar.last = self.pages or self.ui.document:getPageCount()
        self.main_progress_bar.ticks = self.ui.toc:getTocTicksFlattened()
        self.progress_bar_book:setPercentage(self.view.footer.pageno / self.view.footer.pages)
        self.main_progress_bar:setPercentage(self.view.footer.pageno / self.view.footer.pages)
        self.progress_chapter_bar:setPercentage(self.view.footer:getChapterProgress(true))
        -- self.progress_bar_book.height = self.title_text:getSize().h
        -- self.progress_chapter_bar.height = self.title_text:getSize().h

        if self.ui.gestures.ignore_hold_corners then
            if self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
                self.ignore_corners = "\u{F0F6} 🔒"
            else
                self.ignore_corners = "🔒"
            end
        else
            if self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
                self.ignore_corners = "\u{F0F6}"
            else
                self.ignore_corners = ""
            end
        end

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
                    self.test_light_text:setText(" ● " .. self.frontlight)
                else
                    self.test_light_text:setText(" ○ " .. self.frontlight)
                end
            else
                if configurable.h_page_margins[1] == 15 and configurable.t_page_margin == self.space_after_alt_bar + 9 + 6 and configurable.h_page_margins[2] == 15 and configurable.b_page_margin == 15 then
                    self.test_light_text:setText(" ● " .. self.frontlight)
                else
                    self.test_light_text:setText(" ○ " .. self.frontlight)
                end
            end
        elseif self.option == 4 then
            if Device:isAndroid() then
                if configurable.h_page_margins[1] == 20 and configurable.t_page_margin == 9 + 6 and configurable.h_page_margins[2] == 20 and configurable.b_page_margin == 15 then
                    self.test_light_text:setText(" ● " .. self.frontlight)
                else
                    self.test_light_text:setText(" ○ " .. self.frontlight)
                end
            else
                if configurable.h_page_margins[1] == 15 and configurable.t_page_margin == 9 + 6 and configurable.h_page_margins[2] == 15 and configurable.b_page_margin == 15 then
                    self.test_light_text:setText(" ● " .. self.frontlight)
                else
                    self.test_light_text:setText(" ○ " .. self.frontlight)
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
        self.progress_book_text:setText("")
        self.times_text:setText("")
        self.time_battery_text:setText("")
        self.title_text:setText("")
        self.series_text:setText("")
        self.chapter_text:setText("")
        self.progress_chapter_text:setText("")
        self.book_stats_text:setText("")
        self.author_text:setText("")
        self.test_light_text:setText("")
        self.progress_bar_book.width = 0
        self.main_progress_bar.width = 0
        self.progress_chapter_bar.width = 0
        self.times_text_text = ""
        self.time_battery_text_text = ""
        local configurable = self.ui.document.configurable
        local powerd = Device:getPowerDevice()
        -- if self.last_frontlight ~= nil then
        --     self.frontlight = self.last_frontlight
        --     self.last_frontlight = nil
        -- else
        --     if light_on or powerd:isFrontlightOn() then
        --         self.frontlight = " ☼"
        --     else
        --         self.frontlight = ""
        --     end
        -- end
        -- if Device:isAndroid() then
        --     if configurable.h_page_margins[1] == 20 and configurable.t_page_margin == 9 + 6 and configurable.h_page_margins[2] == 20 and configurable.b_page_margin == 15 then
        --         self.test_light_text:setText(" ● " .. self.frontlight)
        --     else
        --         self.test_light_text:setText(" ○ " .. self.frontlight)
        --     end
        -- else
        --     if configurable.h_page_margins[1] == 15 and configurable.t_page_margin == 9 + 6 and configurable.h_page_margins[2] == 15 and configurable.b_page_margin == 15 then
        --         self.test_light_text:setText(" ● " .. self.frontlight)
        --     else
        --         self.test_light_text:setText(" ○ " .. self.frontlight)
        --     end
        -- end
        if self.ui.gestures.ignore_hold_corners then
            if self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
                self.ignore_corners = "\u{F0F6} 🔒"
            else
                self.ignore_corners = "🔒"
            end
        else
            if self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
                self.ignore_corners = "\u{F0F6}"
            else
                self.ignore_corners = ""
            end
        end
    end
end

-- Defined in the init() function using registerPostReaderReadyCallback() after nextTick()
-- so it is not called several times when opening the document by other sources using registerPostReaderReadyCallback()
-- function TopBar:onPageUpdate()
--     self:toggleBar()
-- end

function TopBar:onPosUpdate(new_pos)
    self:toggleBar()
end

function TopBar:paintTo(bb, x, y)
    if self.status_bar and self.status_bar == true then
        -- self.battery_widget_container[1]:setText(self.time_battery_text_text:reverse())
        -- self.battery_widget_container:paintTo(bb, x - self.battery_widget_container[1]:getSize().w - TopBar.MARGIN_BOTTOM - Screen:scaleBySize(12), y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))
        -- self.stats_times_widget_container[1]:setText(self.times_text_text:reverse())
        -- self.stats_times_widget_container:paintTo(bb, x - Screen:getHeight() + TopBar.MARGIN_BOTTOM + Screen:scaleBySize(12), y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))

        self.ignore_corners_widget_container[1]:setText(self.ignore_corners)
        local duration_raw =  math.floor(((os.time() - self.start_session_time)/60)* 100) / 100
        local wpm = 0
        if self.ui.statistics._total_words > 0 then
            wpm = math.floor(self.ui.statistics._total_words/duration_raw)
        end
        local wpm_frame = FrameContainer:new{
            left_container:new{
                dimen = Geom:new(),
                TextWidget:new{
                    text = wpm .. "wpm",
                    face = Font:getFace("myfont"),
                    fgcolor = Blitbuffer.COLOR_GRAY,
                }
            },
            -- background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
        }

        local mem = getMem()
        -- local result, mem_result = getMem("cat /proc/$(pgrep luajit | head -1)/statm | awk '{ print $2 }'")
        -- if result and mem_result then
        --     mem = Math.round(tonumber(mem_result) * 4 / 1024)
        -- end

        -- local mem = collectgarbage("count")
        -- mem = Math.round(tonumber(mem)/ 1024)

        local mem_frame = left_container:new{
            dimen = Geom:new(),
            TextWidget:new{
                text = mem .. "MB",
                face = Font:getFace("myfont"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            }
        }
        local mem_diff = math.abs(self.initial_memory - mem)
        local mem_frame_diff = left_container:new{
            dimen = Geom:new(),
            TextWidget:new{
                text = mem_diff .. "MB",
                face = Font:getFace("myfont"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            }
        }

        local powerd = Device:getPowerDevice()
        local battery_lvl = powerd:getCapacity()

        local battery_frame = left_container:new{
            dimen = Geom:new(),
            TextWidget:new{
                text = battery_lvl .. "%",
                face = Font:getFace("myfont"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            }
        }

        local battery_frame_diff = left_container:new{
            dimen = Geom:new(),
            TextWidget:new{
                text = (self.initial_battery_lvl - battery_lvl) .. "%",
                face = Font:getFace("myfont"),
                fgcolor = Blitbuffer.COLOR_GRAY,
            }
        }
        if self.view.footer.settings.bar_top then
            -- self.stats_times_widget_container:paintTo(bb, x + Screen:scaleBySize(4), Screen:getHeight() -  Screen:scaleBySize(6))
            self.author_information_widget_container:paintTo(bb, x + Screen:scaleBySize(4), Screen:getHeight() - Screen:scaleBySize(6))
            self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth()- self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(2), Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            battery_frame_diff:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
            battery_frame:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
            mem_frame_diff:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
            mem_frame:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - mem_frame[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
            if self.ui.gestures.ignore_hold_corners and self.ui.gestures.ignore_hold_corners == false then
                battery_frame_diff:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w, Screen:getHeight() - Screen:scaleBySize(8))
                battery_frame:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w, Screen:getHeight() - Screen:scaleBySize(8))
                mem_frame_diff:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
                mem_frame:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - mem_frame[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
            end
        else
            self.author_information_widget_container:paintTo(bb, x + Screen:scaleBySize(4), y + Screen:scaleBySize(6))
            self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(2), y + Screen:scaleBySize(6))
            battery_frame_diff:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6), y + Screen:scaleBySize(9))
            battery_frame:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6), y + Screen:scaleBySize(9))
            mem_frame_diff:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6), y + Screen:scaleBySize(9))
            mem_frame:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - mem_frame[1]:getSize().w - Screen:scaleBySize(6), y + Screen:scaleBySize(9))
            if self.ui.gestures.ignore_hold_corners and self.ui.gestures.ignore_hold_corners == false then
                battery_frame_diff:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w, y + Screen:scaleBySize(9))
                battery_frame:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w, y + Screen:scaleBySize(9))
                mem_frame_diff:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6), y + Screen:scaleBySize(9))
                mem_frame:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6) -  mem_frame[1]:getSize().w - Screen:scaleBySize(6), y + Screen:scaleBySize(9))
            end
        end
        return
    end
    if not self.fm then
        -- The alignment is good but there are things to take into account
        -- - Any screen side in any screen type, flushed or recessed are not aligned with the frame, they can be a little bit hidden. It depends on the devices
        -- - There are some fonts that are bigger than its em square so the aligment may be not right. For instance Bitter Pro descender overpass its bottom limits
        if TopBar.show_top_bar then
            if self.main_progress_bar.altbar then
                self.progress_bar_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, y + Screen:scaleBySize(12))
            else
                self.progress_bar_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, y + Screen:scaleBySize(9))
                -- self.progress_bar_widget_container:paintTo(bb, x, Screen:getHeight() - Screen:scaleBySize(12))
            end
        end
        self.light_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)

        -- self[21].dimen = Geom:new{ w = self[21][1]:getSize().w, self[21][1]:getSize().h }
        self.author_information_widget_container:paintTo(bb, x + Screen:scaleBySize(4), y + Screen:scaleBySize(6))

        -- Top center

        self.title_and_series_widget_container:paintTo(bb, x + Screen:getWidth()/2 + self.title_and_series_widget_container[1][1]:getSize().w/2 - self.title_and_series_widget_container[2][1]:getSize().w/2, y + TopBar.MARGIN_TOP)
        -- self.title_and_series_widget_container:paintTo(bb, x + Screen:getWidth()/2, y + 20)


        -- Top right
        -- Commented the text, using progress bar
        -- if not TopBar.show_top_bar then
        --     self.progress_bar_book_widget_container:paintTo(bb, x + Screen:getWidth() - self.progress_bar_book_widget_container[1][1]:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- end

        self.ignore_corners_widget_container[1]:setText(self.ignore_corners)
        self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - 2, y + Screen:scaleBySize(6))

        self.progress_widget_container.dimen = Geom:new{ w = self.progress_widget_container[1]:getSize().w, self.progress_widget_container[1]:getSize().h } -- The text width change and we need to adjust the container dimensions to be able to align it on the right
        self.progress_widget_container:paintTo(bb, Screen:getWidth() - self.progress_widget_container:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- if TopBar.show_top_bar then
        --     self.progress_widget_container:paintTo(bb, Screen:getWidth() - self.progress_widget_container:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- end

        -- Si no se muestra la barra de progreso de arriba, se muestra la de arriba a la derecha
        -- Y si se muestra la de arriba a la derecha, queremos mover el texto unos pocos píxeles a la izquierda
        -- if not TopBar.show_top_bar then
        --     self.progress_widget_container:paintTo(bb, Screen:getWidth() - self.progress_widget_container:getSize().w - TopBar.MARGIN_SIDES - 20, y + TopBar.MARGIN_TOP)
        -- else
        --     self.progress_widget_container:paintTo(bb, Screen:getWidth() - self.progress_widget_container:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- end



        -- For the bottom components it is better to use frame containers.
        -- It is better to position them without the dimensions simply passing x and y to the paintTo method
        -- Bottom left
        -- self.stats_times_widget_container.dimen.w = self.stats_times_widget_container[1]:getSize().w
        -- self.stats_times_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)


        -- Bottom left, commented for the moment, I put here times
        -- self.progress_book_widget_container.dimen.w = self.progress_book_widget_container[1]:getSize().w
        -- self.progress_book_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

        -- if self.option == 1 then
        self.stats_times_widget_container[1]:setText(self.times_text_text)
        self.stats_times_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)
        -- end

        -- -- Comment inverted info for the moment
        -- -- This is inverted to be shown in left margin
        -- self.stats_times_widget_container[1]:setText(self.times_text_text:reverse())
        -- -- When inverted, the text is positioned to the end of the screen
        -- -- So, we take that position as a reference to position it later
        -- -- Inverted aligned to side left center
        -- -- self.stats_times_widget_container:paintTo(bb, x - Screen:getHeight()/2 - self.stats_times_widget_container[1]:getSize().w/2, y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))

        -- -- Inverted aligned to side left top
        -- -- Remember to set invert = true for self.times_text_text
        -- self.stats_times_widget_container:paintTo(bb, x - Screen:getHeight() + TopBar.MARGIN_BOTTOM + Screen:scaleBySize(12), y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))



        -- print(string.byte(self.chapter_widget_container [1].text, 1,-1))
        -- Bottom center
         if self.chapter_widget_container[1].text ~= "" then
            -- if self.option == 2 then
            -- self.chapter_widget_container[1].face = Font:getFace("myfont3", 14)
            -- if self.chapter_widget_container[1]:getSize().w > Screen:getWidth()/3 then
            --     self.chapter_widget_container[1].face = Font:getFace("myfont3", 12)
            -- end
            local text_widget_container = TextWidget:new{
                text = self.chapter_widget_container[1].text:gsub(" ", "\u{00A0}"), -- no-break-space
                max_width = Screen:getWidth() * 40 * (1/100),
                face = Font:getFace("myfont3", 14),
                bold = true,
            }
            local fitted_text, add_ellipsis = text_widget_container:getFittedText()
            self.chapter_widget_container[1].text = fitted_text
            text_widget_container:free()

            -- self.chapter_widget_container:paintTo(bb, x + Screen:getWidth()/2 - self.chapter_widget_container[1]:getSize().w/2, Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            self.chapter_widget_container:paintTo(bb, x + Screen:getWidth()/2, Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            -- end
        end

        -- Bottom right
        -- Use progress bar
        -- self.progress_chapter_bar_chapter_widget_container:paintTo(bb, x + Screen:getWidth() - self.progress_chapter_bar_chapter_widget_container[1][1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)
        self.progress_chapter_widget_container:paintTo(bb, x + Screen:getWidth() - self.progress_chapter_widget_container[1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)


        -- Comment inverted info for the moment
        -- self.battery_widget_container[1]:setText(self.time_battery_text_text:reverse())


        -- -- Inverted aligned to side left bottom
        -- -- self.battery_widget_container:paintTo(bb, x - self.battery_widget_container[1]:getSize().w, y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))
        --self.battery_widget_container:paintTo(bb, x - self.battery_widget_container[1]:getSize().w - TopBar.MARGIN_BOTTOM - Screen:scaleBySize(12), y + TopBar.MARGIN_SIDES/2 + Screen:scaleBySize(3))


        -- self.progress_chapter_widget_container.dimen.w = self.progress_chapter_widget_container[1]:getSize().w
        -- -- La barra de progreso de abajo a la derecha se muestra siempre y queremos mover el texto unos pocos píxeles a la izquierda
        -- self.progress_chapter_widget_container:paintTo(bb, x + Screen:getWidth() - self.progress_chapter_widget_container:getSize().w - TopBar.MARGIN_SIDES - 20, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

        -- text_container2:paintTo(bb, x + Screen:getWidth() - text_container2:getSize().w - 20, y + 20)
        -- text_container2:paintTo(bb, x + Screen:getWidth()/2 - text_container2:getSize().w/2, y + 20)
    else
        local collate_widget_container = left_container:new{
            dimen = Geom:new(),
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont3", 12),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        }
        local reverse_collate_widget_container = left_container:new{
            dimen = Geom:new(),
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont3", 12),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        }
        if self.collection then
            if ffiUtil.realpath(DataStorage:getSettingsDir() .. "/calibre.lua") then
                local sort_by_mode = self.collection_collate
                local collate_symbol = ""
                if sort_by_mode == "strcoll" then
                    collate_symbol = "Name"
                elseif sort_by_mode == "publication_date" then
                    collate_symbol = "PD"
                elseif sort_by_mode == "word_count" then
                    collate_symbol = "WC"
                elseif sort_by_mode == "gr_rating" then
                    collate_symbol = "GRR"
                elseif sort_by_mode == "gr_votes" then
                    collate_symbol = "GRV"
                elseif sort_by_mode == "series" then
                    collate_symbol = "S"
                elseif sort_by_mode == "not_manual_sorting" then
                    collate_symbol = "Set manual sorting"
                elseif sort_by_mode == "manual_sorting" then
                    collate_symbol = "Set manual sorting"
                else
                    collate_symbol = "Sort"
                end

                collate_widget_container[1]:setText(collate_symbol)
                collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - collate_widget_container[1]:getSize().h )
                local reverse_collate_mode = G_reader_settings:readSetting("reverse_collate")
                if reverse_collate_mode == nil then
                    reverse_collate_widget_container[1]:setText("")
                elseif not reverse_collate_mode then
                    reverse_collate_widget_container[1]:setText("↓")
                else
                    reverse_collate_widget_container[1]:setText("↑")
                end
                -- collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1][1]:getSize().w - TopBar.MARGIN_SIDES, y + Screen:scaleBySize(6))
                reverse_collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w - reverse_collate_widget_container[1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - reverse_collate_widget_container[1]:getSize().h)
            else
                collate_widget_container[1]:setText("?")
                collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - collate_widget_container[1]:getSize().h )
            end
        else
            local times_text_widget_container = TextWidget:new{
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

            -- times_text_widget_container:setText(time_battery_text_text:reverse())
            -- times_text_widget_container:paintTo(bb, x - times_text_widget_container:getSize().w - TopBar.MARGIN_BOTTOM - Screen:scaleBySize(12), y)


            local books_information_widget_container = left_container:new{
                dimen = Geom:new(),
                TextWidget:new{
                    text =  "",
                    face = Font:getFace("myfont3", 12),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            }

            -- local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
            -- local _, files = self:getList("*.epub")
            -- books_information_widget_container[1]:setText("TF: " .. tostring(#files))

            if G_reader_settings:readSetting("home_dir") and ffiUtil.realpath(G_reader_settings:readSetting("home_dir") .. "/stats.lua") then
                local ok, stats = pcall(dofile, G_reader_settings:readSetting("home_dir") .. "/stats.lua")
                local last_days = ""
                for k, v in pairs(stats["stats_last_days"]) do
                    last_days = v > 0 and last_days .. " ● " or last_days .. " ○ "
                end
                -- local execute = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub' | wc -l" )
                -- local execute2 = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub.lua' -exec ls {} + | wc -l")
                -- books_information_widget_container[1]:setText("TB: " .. execute:read('*a') .. "TBC: " .. execute2:read('*a'))

                local stats_year = TopBar:getReadThisYearSoFar()
                if stats_year > 0 then
                    stats_year = "+" .. stats_year
                end
                books_information_widget_container[1]:setText("B: " .. stats["total_books"]
                .. ", BF:" .. stats["total_books_finished"]
                .. ", BFTM:" .. stats["total_books_finished_this_month"]
                .. ", BFTY:" .. stats["total_books_finished_this_year"]
                .. ", BFLY:" .. stats["total_books_finished_last_year"]
                .. ", BMBR:" .. stats["total_books_mbr"]
                .. ", BTBR:" .. stats["total_books_tbr"]
                .. ", LD:" .. last_days
                .. stats_year)
            else
                books_information_widget_container[1]:setText("No stats.lua file in home dir")
            end
            books_information_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)


            local times_widget_container =
            left_container:new{
                dimen = Geom:new(),
                TextWidget:new{
                    text =  "",
                    face = Font:getFace("myfont3", 12),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            }

            -- times[1]:setText(time .. "|" .. batt_lvl .. "%")
            times_widget_container[1]:setText("BDB: " .. TopBar:getBooksOpened() .. ", TR: " .. TopBar:getTotalRead() .. "d")
            -- times.dimen = Geom:new{ w = times[1]:getSize().w, h = times[1].face.size }
            times_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM - times_widget_container[1].face.size - 4)
            if self.fm and not self.history then
                if ffiUtil.realpath(DataStorage:getSettingsDir() .. "/calibre.lua") then
                    local sort_by_mode = G_reader_settings:readSetting("collate")
                    local collate_symbol = ""
                    if sort_by_mode == "strcoll" then
                        collate_symbol = "Name"
                    elseif sort_by_mode == "publication_date" then
                        collate_symbol = "PD"
                    elseif sort_by_mode == "word_count" then
                        collate_symbol = "WC"
                    elseif sort_by_mode == "gr_rating" then
                        collate_symbol = "GRR"
                    elseif sort_by_mode == "gr_votes" then
                        collate_symbol = "GRV"
                    elseif sort_by_mode == "series" then
                        collate_symbol = "S"
                    else
                        collate_symbol = "O"
                    end
                    collate_widget_container[1]:setText(collate_symbol)
                    -- collate:paintTo(bb, x + Screen:getWidth() - collate[1]:getSize().w - TopBar.MARGIN_SIDES, y + Screen:scaleBySize(6))
                    collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

                    local reverse_collate_mode = G_reader_settings:readSetting("reverse_collate")
                    if reverse_collate_mode then
                        reverse_collate_widget_container[1]:setText("↓")
                    else
                        reverse_collate_widget_container[1]:setText("↑")
                    end
                    -- collate:paintTo(bb, x + Screen:getWidth() - collate[1]:getSize().w - TopBar.MARGIN_SIDES, y + Screen:scaleBySize(6))
                    reverse_collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w - reverse_collate_widget_container[1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

                else
                    collate_widget_container[1]:setText("?")
                    collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)
                end
               local ignore_double_tap_frame_widget_container = left_container:new{
                    dimen = Geom:new(),
                    TextWidget:new{
                        text =  "",
                        face = Font:getFace("myfont3", 12),
                        fgcolor = Blitbuffer.COLOR_BLACK,
                    },
                }

                local fm = require("apps/filemanager/filemanager").instance
                if not fm.disable_double_tap then
                    ignore_double_tap_frame_widget_container[1]:setText("🔒")
                else
                    ignore_double_tap_frame_widget_container[1]:setText("")
                end
                ignore_double_tap_frame_widget_container:paintTo(bb, x + Screen:getWidth() - ignore_double_tap_frame_widget_container[1]:getSize().w - Screen:scaleBySize(2), Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            end
        end
    end
end

function TopBar:paintToDisabled(bb, x, y)
    self.ignore_corners_widget_container[1]:setText(self.ignore_corners)
    self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - 2, y + Screen:scaleBySize(6))
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
-- We do it in the init() function using a registerPostReaderReadyCallback() function
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

function TopBar:setCollectionCollate(collate)
    self.collection_collate = collate
end

function TopBar:getCollectionCollate()
    return self.collection_collate
end

return TopBar
