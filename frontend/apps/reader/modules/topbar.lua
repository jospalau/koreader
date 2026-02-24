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
local bottom_container = require("ui/widget/container/bottomcontainer")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local datetime = require("datetime")
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
    --is_enabled = G_reader_settings:isTrue("show_top_bar"),
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
    -- show_bar_in_top_bar = true,
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

    if self.ui and self.ui.document and self.start_session_time then
        read_this_year = read_this_year + (os.time() - self.start_session_time)
    end
    conn:close()
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

function TopBar:getDateAndVersion()
    local date_and_version_file_path = "./dateandversion"
    local date_and_version = io.open(date_and_version_file_path, "r")
    if date_and_version == nil then return "No dateandversion file" end

    local t = date_and_version:read("*line")
    return t
end

function TopBar:getTodayBookStats()
    local now_t = os.date("*t")
    local start_today_time = os.time{year=now_t.year, month=now_t.month, day=now_t.day, hour=0, min=0, sec=0}

    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT IFNULL(sum(duration), 0), IFNULL(sum(total_pages), 0)
        FROM   wpm_stat_data
        WHERE  start_time >= %d
    ]]
    local today_duration, today_pages =  conn:rowexec(string.format(sql_stmt, start_today_time))
    conn:close()
    if today_pages == nil then
        today_pages = 0
    end
    if today_duration == nil then
        today_duration = 0
    end
    today_duration = tonumber(today_duration)
    today_pages = tonumber(today_pages)

    return today_duration, today_pages
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
            opf_text = self.ui.document:getDocumentFileContent("OEBPS/volume.opf")
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
    if not self.settings then self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/topbar.lua") end
    -- This is done in readerui.lua because the topbar is started in ReaderView when the menu has not yet been started by ReaderUI
    -- if not self.fm then
    --     self.ui.menu:registerToMainMenu(self)
    -- end
    -- La inicialización del objeto ocurre una única vez pero el método init ocurre cada vez que abrimos el documento
    TopBar.is_enabled = self.settings:isTrue("show_top_bar")
    -- TopBar.show_bar_in_top_bar = true
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
        TopBar.show_bar_in_top_bar = TopBar.preserved_alt_bar
        TopBar.preserved_alt_bar = nil
        else
            TopBar.show_bar_in_top_bar = true
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

    self.daily_time_goal = self.settings:readSetting("daily_time_goal", 120)
    self.daily_pages_goal = self.settings:readSetting("daily_pages_goal", 120)

    self.space_after_alt_bar = self.settings:readSetting("space_after_alt_bar", 12)
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
        self.series = " ⋅ " .. TextWidget.PTF_BOLD_START .. self.series .. TextWidget.PTF_BOLD_END
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

    if duration_raw < self.ui.statistics.min_time_valid_session or self.ui.statistics._total_pages < self.ui.statistics.min_pages_valid_session then
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


    local font = "cfont"
    if self.settings:nilOrFalse("use_system_font") then
        if not self.settings:nilOrFalse("font_times_progress") then
            font = self.settings:readSetting("font_times_progress")
        else
            font = "myfont3"
        end
    end
    local font_size= self.settings:readSetting("font_size_times_progress")
    and self.settings:readSetting("font_size_times_progress") or 12
    self.progress_book_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local text_face = Font:getFace("NotoSans-Regular.ttf", font_size)
    local w = TextWidget:new{ text = "", face = text_face, }
    local forced_baseline = w:getBaseline()
    local forced_height = w:getSize().h
    w:free()

    self.current_page_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
    }

    self.chapter_pages_left_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
    }

    self.progress_chapter_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
    }

    self.times_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
        invert = false,
    }

    self.book_stats_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3", 12),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.typography_text = TextWidget:new{
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

    self.goal_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3", 12),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }


    font = "cfont"
    if self.settings:nilOrFalse("use_system_font") then
        if not self.settings:nilOrFalse("font_title") then
            font = self.settings:readSetting("font_title")
        else
            font = "myfont3"
        end
    end

    font_size = self.settings:readSetting("font_size_title")
    and self.settings:readSetting("font_size_title")
    or 14

    local noto_sans_text_face = Font:getFace("NotoSans-Regular.ttf", font_size)
    local w = TextWidget:new{ text = "", face = noto_sans_text_face, }
    local forced_baseline = w:getBaseline()
    local forced_height = w:getSize().h
    w:free()

    self.title_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
        -- forced_baseline = forced_baseline,
        -- forced_height = forced_height,
    }

    self.series_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size - 8),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
        -- forced_baseline = forced_baseline - 4,
        -- forced_height = forced_height,
    }

    self.chapter_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
    }

    -- self[1] = left_container:new{
    --     dimen = Geom:new{ w = self.wpm_text:getSize().w, self.wpm_text:getSize().h },
    --     self.wpm_text,
    -- }

    self.author_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont3", 8),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.light_widget_container = left_container:new{
        dimen = Geom:new(),
        self.test_light_text,
    }

    self.progress_widget_container = bottom_container:new{
        dimen = Geom:new{ w = self.progress_book_text:getSize().w, self.progress_book_text:getSize().h },
        self.progress_book_text,
    }

    self.current_page_widget_container = bottom_container:new{
        dimen = Geom:new{ w = self.current_page_text:getSize().w, self.current_page_text:getSize().h },
        self.current_page_text,
    }

    self.chapter_pages_left_widget = bottom_container:new{
        dimen = Geom:new{ w = self.chapter_pages_left_text:getSize().w, self.chapter_pages_left_text:getSize().h },
        self.chapter_pages_left_text,
    }

    self.goal_widget_container = bottom_container:new{
        dimen = Geom:new{ w = self.goal_text:getSize().w, self.goal_text:getSize().h },
        self.goal_text,
    }

    -- Most of the container widgets used in the topbar (in fact, all currently drawn ones) are bottom containers.
    -- These containers make their child widgets grow upwards from their y coordinate on the screen:
    -- When bottom containers are placed at the bottom of the screen (like progress_widget_container),
    -- they are anchored to the bottom
    -- When bottom containers are placed at the top of the screen, we anchor them by the height of the
    -- contained text widget down from the topbar, so they can fit properly

    -- The following widget is different:
    -- This widget has always worked like this with two text widgets wrapped
    -- in left and right containers which center their child vertically
    -- To make this work, the containers have been modified to accept a no_center_vertically parameter,
    -- which shifts the y coordinate by the amount of space where we want to start drawing.
    -- This is 0 when defined, but later adjusted with Screen:scaleBySize(self.space_after_alt_bar).
    -- We could have used separate text widgets, since text widgets grow upwards from its y coordinate (which means downwards on the screen).
    -- In any case, one text widget uses a font size 4px smaller than the other,
    -- and to compensate (so it aligns with the other), we add 4px to this widget's no_center_vertically parameter
    self.title_and_series_widget_container = HorizontalGroup:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = self.border_size,
        padding = 0,
        margin = 0,
        radius = self.is_popout and math.floor(self.dimen.w * (1/20)) or 0,
        right_container:new{
            dimen = Geom:new{ w = self.title_text:getSize().w, self.title_text:getSize().h },
            no_center_vertically = 0,
            self.title_text,
        },
        left_container:new{
            dimen = Geom:new{ w = self.series_text:getSize().w, self.series_text:getSize().h },
            no_center_vertically = 0,
            self.series_text,
        }
    }

    self.stats_times_widget_container = bottom_container:new{
        dimen = Geom:new(),
        self.times_text,
    }

    self.progress_book_widget_container = left_container:new{
        dimen = Geom:new{ w = self.book_stats_text:getSize().w, self.book_stats_text:getSize().h },
        self.book_stats_text,
    }

    self.chapter_widget_container = bottom_container:new{
        dimen = Geom:new(),
        self.chapter_text,
    }

    self.progress_chapter_widget_container = bottom_container:new{
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

    self.author_information_widget_container = bottom_container:new{
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

function TopBar:changeAllWidgetFaces()
    local font = "cfont"
    if self.settings:nilOrFalse("use_system_font") then
        if not self.settings:nilOrFalse("font_times_progress") then
            font = self.settings:readSetting("font_times_progress")
        else
            font = "myfont3"
        end
    end

    local font_size= self.settings:readSetting("font_size_times_progress")
    and self.settings:readSetting("font_size_times_progress") or 12
    self.progress_book_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local text_face = Font:getFace("NotoSans-Regular.ttf", font_size)
    local w = TextWidget:new{ text = "", face = text_face, }
    local forced_baseline = w:getBaseline()
    local forced_height = w:getSize().h
    w:free()

    self.current_page_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
    }

    self.progress_chapter_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
    }

    self.times_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
        invert = false,
    }

    self.progress_widget_container = bottom_container:new{
        dimen = Geom:new{ w = self.progress_book_text:getSize().w, self.progress_book_text:getSize().h },
        self.progress_book_text,
    }

    self.current_page_widget_container = bottom_container:new{
        dimen = Geom:new{ w = self.current_page_text:getSize().w, self.current_page_text:getSize().h },
        self.current_page_text,
    }

    self.progress_chapter_widget_container = bottom_container:new{
        dimen = Geom:new(),
        self.progress_chapter_text,
    }

    self.stats_times_widget_container = bottom_container:new{
        dimen = Geom:new(),
        self.times_text,
    }

    font = "cfont"
    if self.settings:nilOrFalse("use_system_font") then
        if not self.settings:nilOrFalse("font_title") then
            font = self.settings:readSetting("font_title")
        else
            font = "myfont3"
        end
    end

    font_size = self.settings:readSetting("font_size_title")
    and self.settings:readSetting("font_size_title")
    or 14

    local noto_sans_text_face = Font:getFace("NotoSans-Regular.ttf", font_size)
    local w = TextWidget:new{ text = "", face = noto_sans_text_face, }
    local forced_baseline = w:getBaseline()
    local forced_height = w:getSize().h
    w:free()

    self.title_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
    }

    self.series_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size - 8),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
    }

    self.chapter_text = TextWidget:new{
        text =  "",
        face = Font:getFace(font, font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
        bold = true,
        forced_baseline = forced_baseline,
        forced_height = forced_height,
    }
    self.title_and_series_widget_container = HorizontalGroup:new{
        -- align = "top",
        background = Blitbuffer.COLOR_WHITE,
        bordersize = self.border_size,
        padding = 0,
        margin = 0,
        radius = self.is_popout and math.floor(self.dimen.w * (1/20)) or 0,
        right_container:new{
            dimen = Geom:new{ w = self.title_text:getSize().w, self.title_text:getSize().h },
            no_center_vertically = 0,
            self.title_text,
        },
        left_container:new{
            dimen = Geom:new{ w = self.series_text:getSize().w, self.series_text:getSize().h },
            no_center_vertically = 0,
            self.series_text,
        }
    }
    self.chapter_widget_container = bottom_container:new{
        dimen = Geom:new(),
        self.chapter_text,
    }

    self:toggleBar()
    self.view.doublebar.title_text.face = Font:getFace(font, font_size)
    self.view.doublebar.chapter_text.face = Font:getFace(font, font_size)
    self.view.doublebar:toggleBar()
end
function TopBar:onToggleShowTopBar()
    local show_top_bar = self.settings:isTrue("show_top_bar")
    self.settings:saveSetting("show_top_bar", not show_top_bar)
    self.settings:flush()
    TopBar.is_enabled = not show_top_bar
    self:toggleBar()
end

function TopBar:showTopBar()
    self.settings:saveSetting("show_top_bar", true)
    self.settings:flush()
    TopBar.is_enabled = true
    self:toggleBar()
end

function TopBar:hideTopBar()
    self.settings:saveSetting("show_top_bar", false)
    self.settings:flush()
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
            return "ui",
            Geom:new{ w = Screen:getWidth(), h = self:getHeight(), y = 0}
        end)
        UIManager:setDirty(self, function()
            return "ui",
            Geom:new{ w = Screen:getWidth(),
            h = self:getBottomHeight(),
            y = Screen:getHeight() - self:getBottomHeight()}
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
    TopBar.preserved_alt_bar = self.show_bar_in_top_bar
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
        self.settings:saveSetting("show_top_bar", true)
        self.settings:flush()
        TopBar.is_enabled = true
        TopBar.show_bar_in_top_bar = true
        TopBar.alt_bar = true
        self.main_progress_bar.altbar_ticks_height = 5
        self.main_progress_bar.altbar_line_thickness = 9
        TopBar.option = 1
        self:toggleBar()

        UIManager:setDirty(self.view.dialog, function()
            return self.view.currently_scrolling and "fast" or "ui",
            Geom:new{ w = Screen:getWidth(), h = self:getHeight(true), y = 0}
        end)
        UIManager:setDirty(self.view.dialog, function()
            return self.view.currently_scrolling and "fast" or "ui",
            Geom:new{ w = Screen:getWidth(),
            h = self:getBottomHeight(),
            y = Screen:getHeight(true) - self:getBottomHeight()}
        end)
        return
    end
    if self.settings:isTrue("show_top_bar") then
        if TopBar.show_bar_in_top_bar then
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
                TopBar.show_bar_in_top_bar = false
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
            self.settings:saveSetting("show_top_bar", false)
            self.settings:flush()
            TopBar.is_enabled = false
            TopBar.show_bar_in_top_bar = true
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
            return self.view.currently_scrolling and "fast" or "ui",
            Geom:new{ w = Screen:getWidth(), h = self:getHeight(true), y = 0}
        end)
        UIManager:setDirty(self.view.dialog, function()
            return self.view.currently_scrolling and "fast" or "ui",
            Geom:new{ w = Screen:getWidth(),
            h = self:getBottomHeight(),
            y = Screen:getHeight(true) - self:getBottomHeight()}
        end)
    end
end

function TopBar:quickToggleOnOff(put_off)
    self.settings:saveSetting("show_top_bar", put_off)
    self.settings:flush()
    TopBar.is_enabled = put_off
    self:toggleBar()
    UIManager:setDirty(self.view.dialog, function()
        return self.view.currently_scrolling and "fast" or "ui",
        Geom:new{ w = Screen:getWidth(), h = self:getHeight(), y = 0}
    end)
    UIManager:setDirty(self.view.dialog, function()
        return self.view.currently_scrolling and "fast" or "ui",
        Geom:new{ w = Screen:getWidth(),
        h = self:getBottomHeight(),
        y = Screen:getHeight() - self:getBottomHeight()}
    end)
end

function TopBar:getHeight(max_height)
   if TopBar.show_bar_in_top_bar or max_height then
        return Screen:scaleBySize(self.space_after_alt_bar)
        + self.progress_bar_widget_container:getSize().h
        + self.title_and_series_widget_container[1][1]._height
    else
       return self.title_and_series_widget_container[1][1]._height
    end
end

function TopBar:getBottomHeight()
    return self.chapter_widget_container[1]:getSize().h
end

function TopBar:resetSession()
    self.initial_read_today, self.initial_read_month, self.initial_total_time_book, self.avg_wpm, self.sessions_current_book, self.initial_read_last_month, self.initial_read_year = self:getReadTodayThisMonth(self.title)
    local now_ts = os.time()
    self.start_session_time = now_ts
    self.init_page = nil
    self.init_page_screens = nil
    self:toggleBar()
end

function TopBar:classifyLeading(lf, x_height, ascender, descender)
    if not x_height or x_height == 0 then return "invalid" end
    local safe_min = (ascender + descender) / x_height
    -- print("Ascender: " .. ascender)
    -- print("Descender: " .. descender)
    -- print("X-height: " .. x_height)
    -- print("Safe min: " .. safe_min)
    if lf < safe_min then return "collision"
    elseif lf < safe_min + 0.15 then return "compact"
    elseif lf < safe_min + 0.4 then return "balanced"
    elseif lf < safe_min + 0.6 then return "airy"
    else return "very airy"
    end                     -- Excessive spacing, feels like children's books or UI
end

function TopBar:getXHeightRangeLabel(size_pt, xh_mm)
    local perfect_min = 1.7     -- A partir de aquí empieza a ser cómodo
    local perfect_max = 1.85    -- Más allá empieza a parecer visualmente grande
    local label

    if xh_mm < perfect_min then
      label = "low"
    elseif xh_mm <= perfect_max then
      label = "perfect"
    else
      label = "too big"
    end

    return string.format("fS: %.2fpt, xH: %.2fmm (%.2f–%.2f) [%s]", size_pt, xh_mm, perfect_min, perfect_max, label)
end

function TopBar:toggleBar(light_on)
    if self.init_page == nil and self.ui.pagemap:wantsPageLabels() then
        self.init_page = self.ui.pagemap:getCurrentPageLabel(true)
    end

    if self.init_page_screens == nil then
        self.init_page_screens = self.view.footer.pageno
    end

    if TopBar.is_enabled then
        local user_duration_format = "modern"
        local session_time = datetime.secondsToClockDuration(user_duration_format, os.time() - self.start_session_time, false)

        local duration_raw =  math.floor((os.time() - self.start_session_time))
        if self.ui.statistics and self.ui.statistics._total_words then
            self.wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        end
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
           self.current_page_text:setText(("%d"):format(self.ui.pagemap:getCurrentPageLabel(true)))
        else
           self.progress_book_text:setText(("%d de %d"):format(self.view.footer.pageno, self.view.footer.pages))
           self.current_page_text:setText(("%d"):format(self.view.footer.pageno))
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


        local font_face = self.ui.document._document:getFontFace()
        local current_face = font_face:gsub("%s+", "") .. "-Regular"
        local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
        local size_px = (display_dpi * self.ui.document.configurable.font_size)/72
        local size_pt = (size_px/display_dpi) * 72
        local face_base = Font:getFace(current_face, size_px, 0, false);
        local x_height = 0
        local x_height_mm = 0
        local x_height_with_range = "N/A"
        local line_height = 0
        local leading_factor_text = "N/A"
        if face_base ~= nil then
            x_height = Math.round(face_base.ftsize:getXHeight() * size_px)
            x_height_mm = Math.round((x_height * (25.4 / display_dpi) * 100)) / 100
            x_height_with_range = self:getXHeightRangeLabel(size_pt, x_height_mm)
            local line_spacing_factor = self.ui.document.configurable.line_spacing / 100
            local x_height2, ascender, descender = face_base.ftsize:getAscDesc()
            -- How many times the x_height fits in the line height
            -- The line height is the distance from one baseline line to the other
            local leading_factor = math.floor(((1.2 * size_px * line_spacing_factor) / x_height ) * 100) / 100 -- 1.2em hardcoded as it is in all books in Calibre
            leading_factor_text = leading_factor .. " (" .. self:classifyLeading(leading_factor, x_height2, ascender, descender) .. ")"
        end


        local hours_to_read = tonumber(self.total_words)/(self.avg_wpm * 60)
        local progress =  math.floor(100/hours_to_read * 10)/10
        self.total_wordsk = tostring(math.floor(self.total_words/1000))
        self.book_stats_text:setText(self.total_wordsk .. "kw|"
        .. tostring(self.sessions_current_book) .. "s|" .. tostring(progress) .. "%|"
        .. read_book)

        self.typography_text:setText(x_height_with_range .. ", lF: " .. leading_factor_text)
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
                self.author_text:setText(self.ui.document._document:getDocumentProps().authors .. " - " ..  self.pub_date .. " - "  ..  self.origin_book .. " - " .. self.book_stats_text.text .. " - " .. self.typography_text.text)
            else
                self.author_text:setText(self.ui.document._document:getDocumentProps().authors .. " - " ..  self.pub_date .. " - " .. self.book_stats_text.text .. " - " .. self.typography_text.text)
            end
        else
            self.author_text:setText("")
        end


        local left = self.ui.toc:getChapterPagesLeft(self.view.footer.pageno) or self.ui.document:getTotalPagesLeft(self.view.footer.pageno)
        local left_time = (self.ui.statistics and self.ui.statistics:getTimeForPages(left) or _("N/A"))

        self.progress_chapter = self.view.footer:getChapterProgress(false)
        self.progress_chapter_text:setText(self.progress_chapter) -- .. " " .. left_time)
       local text_widget_container = TextWidget:new{
            text = self.chapter_widget_container[1].text:gsub(" ", "\u{00A0}"), -- no-break-space
            max_width = Screen:getWidth() * 40 * (1/100),
            face = Font:getFace(self.settings:readSetting("font_title") and self.settings:readSetting("font_title") or "Consolas-Regular.ttf",
            self.settings:readSetting("font_size_title") and self.settings:readSetting("font_size_title") or 14),

            bold = true,
        }
        local fitted_text, __ = text_widget_container:getFittedText()
        self.chapter_widget_container[1].text = fitted_text
        text_widget_container:free()

        --self.progress_chapter_text:setText(self.series)

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

        -- How far we want the tile and series widget. There is a menu entry to set it up, default 12px
        -- self.space_after_alt_bar = 12
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
        local time_spent_book = nil
        if self.ui.statistics and self.ui.statistics.id_curr_book then
            time_spent_book = self.ui.statistics:getBookStat(self.ui.statistics.id_curr_book)
        end

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
            -- If page text info plugin highlight_all_words_vocabulary_builder_and_notes setting is true, then self.ui.gestures.ignore_hold_corners will be true so the corner words can be double tapped
            if self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
                self.ignore_corners = "\u{F0F6}"
            else
                self.ignore_corners = "🔒"
            end
        else
            self.ignore_corners = ""
            -- if self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
            --     self.ignore_corners = "\u{F0F6}"
            -- else
            --     self.ignore_corners = ""
            -- end
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
        local side_margins = 15
        if Device:isAndroid() then
            side_margins = 20
        end
        if configurable.h_page_margins[1] == side_margins and configurable.t_page_margin == Screen:unscaleBySize(self:getHeight())
            and configurable.h_page_margins[2] == side_margins and configurable.b_page_margin == Screen:unscaleBySize(self:getBottomHeight()) then
            self.test_light_text:setText(" ● " .. self.frontlight)
        else
            self.test_light_text:setText(" ○ " .. self.frontlight)
        end


        local face_big = Font:getFace(
            self.settings:readSetting("font_title") or "Consolas-Regular.ttf",
            self.settings:readSetting("font_size_title") or 14
        )

        local face_small = Font:getFace(
            self.settings:readSetting("font_title") or "Consolas-Regular.ttf",
            (self.settings:readSetting("font_size_title") or 14) - 8
        )

        -- BIG
        local w = TextWidget:new{ text = "A", face = face_big }  -- usa una letra que tenga ascender
        local baseline_big = w:getBaseline()
        local height_big = w:getSize().h
        w:free()

        -- SMALL  ← AQUÍ ESTABA TU ERROR
        w = TextWidget:new{ text = "A", face = face_small }
        local baseline_small = w:getBaseline()
        local height_small = w:getSize().h
        w:free()

        local size_big = self.settings:readSetting("font_size_title") or 14
        local size_small = size_big - 8

        local x_height_big = face_big.ftsize:getXHeight() * size_big
        local x_height_small = face_small.ftsize:getXHeight() * size_small
        local baseline_diff = baseline_big - baseline_small - math.floor(x_height_big - x_height_small + 0.5) -- Same baseline for both texts and then center x-heights
        -- local baseline_diff = baseline_big - baseline_small - math.floor(x_height_big)
        if TopBar.show_bar_in_top_bar then
            TopBar.MARGIN_TOP = Screen:scaleBySize(9) + Screen:scaleBySize(self.space_after_alt_bar)
            self.title_and_series_widget_container[1].no_center_vertically = Screen:scaleBySize(self.space_after_alt_bar)
            self.title_and_series_widget_container[2].no_center_vertically = Screen:scaleBySize(self.space_after_alt_bar) + baseline_diff -- compensation
        else
            TopBar.MARGIN_TOP = Screen:scaleBySize(9)
            self.title_and_series_widget_container[1].no_center_vertically = 0
            self.title_and_series_widget_container[2].no_center_vertically = baseline_diff
        end

    else
        self.session_time_text:setText("")
        self.progress_book_text:setText("")
        self.current_page_text:setText("")
        self.chapter_pages_left_text:setText("")
        self.goal_text:setText("")
        self.times_text:setText("")
        self.time_battery_text:setText("")
        self.title_text:setText("")
        self.series_text:setText("")
        self.chapter_text:setText("")
        self.progress_chapter_text:setText("")
        self.book_stats_text:setText("")
        self.typography_text:setText("")
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
        if not self.status_bar then
            if self.ui.pagemap:wantsPageLabels() then
                self.current_page_text:setText(("%d"):format(self.ui.pagemap:getCurrentPageLabel(true)))
            else
                self.current_page_text:setText(("%d"):format(self.view.footer.pageno))
            end

            local today_duration, __ = self:getTodayBookStats()
            today_duration = today_duration + os.time() - self.start_session_time
            local today_duration_number = math.ceil(today_duration / 60)
            local text = (self.daily_time_goal - today_duration_number) .. "m"

            if today_duration_number >= self.daily_time_goal then
                text = "⚑ " .. (today_duration_number - self.daily_time_goal) .. "m"
            end
            self.goal_text:setText(text)
            local chapter_pages_left = self.ui.toc:getChapterPagesLeft(self.view.footer.pageno) or self.ui.document:getTotalPagesLeft(self.view.footer.pageno)
            self.chapter_pages_left_text:setText("\u{200A}" .. chapter_pages_left)
        end
        if self.ui.gestures.ignore_hold_corners then
            -- If page text info plugin highlight_all_words_vocabulary_builder_and_notes setting is true, then self.ui.gestures.ignore_hold_corners will be true so the corner words can be double tapped
            if self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
                self.ignore_corners = "\u{F0F6}"
            else
                self.ignore_corners = "🔒"
            end
        else
            self.ignore_corners = ""
            -- if self.ui.pagetextinfo and self.ui.pagetextinfo.settings:isTrue("highlight_all_words_vocabulary_builder_and_notes") then
            --     self.ignore_corners = "\u{F0F6}"
            -- else
            --     self.ignore_corners = ""
            -- end
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
        if self.view.footer.settings.bar_top or self.view.dogear_visible then
            if Device:isAndroid() then
                self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(20), Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            else
                self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(2), Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            end
        else
            if Device:isAndroid() then
                self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(20), y + Screen:scaleBySize(6))
            else
                self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(2), y + Screen:scaleBySize(6))
            end
        end
        if self.view.footer.settings.bar_top then
            -- self.stats_times_widget_container:paintTo(bb, x + Screen:scaleBySize(4), Screen:getHeight() -  Screen:scaleBySize(6))
            self.author_information_widget_container:paintTo(bb, x + self.author_information_widget_container[1]:getSize().w/2 + Screen:scaleBySize(4), y + Screen:getHeight())


            if Device:isAndroid() then
                self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(20), Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            else
                self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(2), Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            end
            if self.settings:isTrue("show_battery_and_memory_info") then
                battery_frame_diff:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
                battery_frame:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
                mem_frame_diff:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
                mem_frame:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - mem_frame[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
            end
            if self.ui.gestures.ignore_hold_corners and self.ui.gestures.ignore_hold_corners == false and self.settings:isTrue("show_battery_and_memory_info") then
                battery_frame_diff:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w, Screen:getHeight() - Screen:scaleBySize(8))
                battery_frame:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w, Screen:getHeight() - Screen:scaleBySize(8))
                mem_frame_diff:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
                mem_frame:paintTo(bb, x + Screen:getWidth() - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - mem_frame[1]:getSize().w - Screen:scaleBySize(6), Screen:getHeight() - Screen:scaleBySize(8))
            end
        else
            self.author_information_widget_container:paintTo(bb, x + self.author_information_widget_container[1]:getSize().w/2 + Screen:scaleBySize(4), y + self.author_information_widget_container[1]._height)
            if self.settings:isTrue("show_battery_and_memory_info") then
                battery_frame_diff:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6), y + Screen:scaleBySize(9))
                battery_frame:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6), y + Screen:scaleBySize(9))
                mem_frame_diff:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6), y + Screen:scaleBySize(9))
                mem_frame:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - battery_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - battery_frame[1]:getSize().w - Screen:scaleBySize(6) - mem_frame_diff[1]:getSize().w - Screen:scaleBySize(6) - mem_frame[1]:getSize().w - Screen:scaleBySize(6), y + Screen:scaleBySize(9))
            end
            if self.ui.gestures.ignore_hold_corners and self.ui.gestures.ignore_hold_corners == false and self.settings:isTrue("show_battery_and_memory_info") then
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
        if TopBar.show_bar_in_top_bar then
            if self.main_progress_bar.altbar then
                self.progress_bar_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, y + Screen:scaleBySize(12))
            else
                self.progress_bar_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, y + Screen:scaleBySize(9))
                -- self.progress_bar_widget_container:paintTo(bb, x, Screen:getHeight() - Screen:scaleBySize(12))
            end
        end
        self.light_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)

        -- self[21].dimen = Geom:new{ w = self[21][1]:getSize().w, self[21][1]:getSize().h }
        self.author_information_widget_container:paintTo(bb, x + self.author_information_widget_container[1]:getSize().w/2 + Screen:scaleBySize(4), y + self.author_information_widget_container[1]._height)

        -- Top center
        self.title_and_series_widget_container[1][1]:updateSize()
        self.title_and_series_widget_container:paintTo(bb, x + Screen:getWidth()/2 + self.title_and_series_widget_container[1][1]:getSize().w/2 - self.title_and_series_widget_container[2][1]:getSize().w/2,
        y + TopBar.MARGIN_TOP) -- + self.title_and_series_widget_container[1][1]._baseline_h * 0.3) -- Visually compensates for excess internal top spacing
        -- self.title_and_series_widget_container:paintTo(bb, x + Screen:getWidth()/2, y + 20)

        if self.settings:isTrue("show_topbar_separators") then
            LineWidget = require("ui/widget/linewidget")
            local topbar_height = self:getHeight()
            local separator_line1 = LineWidget:new{
                dimen = Geom:new{
                    w = Screen:getWidth(),
                    h = Size.line.thick,
                }
            }
            separator_line1:paintTo(bb, x, y + topbar_height)
            separator_line1:paintTo(bb, x, (y + Screen:scaleBySize(self.space_after_alt_bar) - y + topbar_height) / 2)
            separator_line1:paintTo(bb, x, y + Screen:scaleBySize(self.space_after_alt_bar))
        end

        -- Top right
        -- Commented the text, using progress bar
        -- if not TopBar.show_bar_in_top_bar then
        --     self.progress_bar_book_widget_container:paintTo(bb, x + Screen:getWidth() - self.progress_bar_book_widget_container[1][1]:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- end

        self.ignore_corners_widget_container[1]:setText(self.ignore_corners)
        if self.view.dogear_visible then
            if Device:isAndroid() then
                self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(20), Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            else
                self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(2), Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            end
        else
            if Device:isAndroid() then
                self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(20), y + Screen:scaleBySize(6))
            else
                self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(2), y + Screen:scaleBySize(6))
            end
        end

        self.progress_widget_container.dimen = Geom:new{ w = self.progress_widget_container[1]:getSize().w, self.progress_widget_container[1]:getSize().h } -- The text width change and we need to adjust the container dimensions to be able to align it on the right

        if self.option == 1 or self.option == 2 or self.option == 3 then
            self.progress_widget_container:paintTo(bb, Screen:getWidth() - self.progress_widget_container:getSize().w - TopBar.MARGIN_SIDES, y +  self.progress_widget_container[1]._height + Screen:scaleBySize(12))
        else
            self.progress_widget_container:paintTo(bb, Screen:getWidth() - self.progress_widget_container:getSize().w - TopBar.MARGIN_SIDES, y +  self.progress_widget_container[1]._height)
        end

        -- if TopBar.show_bar_in_top_bar then
        --     self.progress_widget_container:paintTo(bb, Screen:getWidth() - self.progress_widget_container:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- end

        -- Si no se muestra la barra de progreso de arriba, se muestra la de arriba a la derecha
        -- Y si se muestra la de arriba a la derecha, queremos mover el texto unos pocos píxeles a la izquierda
        -- if not TopBar.show_bar_in_top_bar then
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
        self.stats_times_widget_container:paintTo(bb, x + math.floor(self.stats_times_widget_container[1]:getSize().w / 2) + TopBar.MARGIN_SIDES, Screen:getHeight())
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
            -- self.chapter_widget_container:paintTo(bb, x + Screen:getWidth()/2 - self.chapter_widget_container[1]:getSize().w/2, Screen:getHeight() - TopBar.MARGIN_BOTTOM)
            if self.stats_times_widget_container[1]:getSize().w  + TopBar.MARGIN_SIDES > math.floor(Screen:getWidth() / 2) then
                self.chapter_widget_container:paintTo(bb, x + self.stats_times_widget_container[1]:getSize().w + math.floor(self.chapter_widget_container[1]:getSize().w / 2) + TopBar.MARGIN_SIDES + 3, Screen:getHeight())
            else
                self.chapter_widget_container:paintTo(bb, x + math.floor(Screen:getWidth() / 2) + math.floor(self.chapter_widget_container[1]:getSize().w / 2), Screen:getHeight())
            end
            -- end
        end

        -- Bottom right
        -- Use progress bar
        -- self.progress_chapter_bar_chapter_widget_container:paintTo(bb, x + Screen:getWidth() - self.progress_chapter_bar_chapter_widget_container[1][1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)
        self.progress_chapter_widget_container:paintTo(bb, x + Screen:getWidth() - math.floor(self.progress_chapter_widget_container[1]:getSize().w / 2) - TopBar.MARGIN_SIDES, Screen:getHeight())
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
        local collate_widget_container = bottom_container:new{
            dimen = Geom:new(),
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont3", 12),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        }
        local reverse_collate_widget_container = bottom_container:new{
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
               elseif sort_by_mode == "finished" then
                    collate_symbol = "F"
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
            collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w / 2 - TopBar.MARGIN_SIDES, Screen:getHeight())
            local reverse_collate_mode = G_reader_settings:readSetting("reverse_collate")
            if reverse_collate_mode == nil then
                reverse_collate_widget_container[1]:setText("")
            elseif not reverse_collate_mode then
                reverse_collate_widget_container[1]:setText("↓")
            else
                reverse_collate_widget_container[1]:setText("↑")
            end
                -- collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1][1]:getSize().w - TopBar.MARGIN_SIDES, y + Screen:scaleBySize(6))
                reverse_collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w - reverse_collate_widget_container[1]:getSize().w / 2 - TopBar.MARGIN_SIDES, Screen:getHeight())

            else
                collate_widget_container[1]:setText("?")
                collate_widget_container:paintTo(bb, x + Screen:getWidth() - TopBar.MARGIN_SIDES, Screen:getHeight())
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


            local books_information_widget_container = bottom_container:new{
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

            if ffiUtil.realpath(require("datastorage"):getSettingsDir() .. "/stats.lua") then
                local ok, stats = pcall(dofile, require("datastorage"):getSettingsDir() .. "/stats.lua")
                local last_days = ""
                for k, v in pairs(stats["stats_last_days"]) do
                    last_days = v > 0 and last_days .. " ● " or last_days .. " ○ "
                end
                -- local execute = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub' | wc -l" )
                -- local execute2 = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub.lua' -exec ls {} + | wc -l")
                -- books_information_widget_container[1]:setText("TB: " .. execute:read('*a') .. "TBC: " .. execute2:read('*a'))

                books_information_widget_container[1]:setText("T:" .. stats["total_books"]
                .. "·F:" .. stats["total_books_finished"]
                .. "·FTM:" .. stats["total_books_finished_this_month"]
                .. "·FTY:" .. stats["total_books_finished_this_year"]
                .. "·FLY:" .. stats["total_books_finished_last_year"]
                .. "·MR:" .. stats["total_books_mbr"]
                .. "·TR:" .. stats["total_books_tbr"])
                -- .. ", LD:" .. last_days
                -- .. stats_year)
            else
                books_information_widget_container[1]:setText("No stats.lua file in home dir")
            end
            books_information_widget_container:paintTo(bb, x + books_information_widget_container[1]:getSize().w / 2 + TopBar.MARGIN_SIDES, Screen:getHeight() - 10)


            local times_widget_container =
            bottom_container:new{
                dimen = Geom:new(),
                TextWidget:new{
                    text =  "",
                    face = Font:getFace("myfont3", 12),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            }

            local stats_year = TopBar:getReadThisYearSoFar()
            if stats_year > 0 then
                stats_year = "+" .. stats_year
            end
            -- times[1]:setText(time .. "|" .. batt_lvl .. "%")
            -- times_widget_container[1]:setText("BDB: " .. TopBar:getBooksOpened() .. ", TR: " .. TopBar:getTotalRead() .. "d" .. " ΔL " .. stats_year .. "h")
            -- times.dimen = Geom:new{ w = times[1]:getSize().w, h = times[1].face.size }
            -- times_widget_container:paintTo(bb, x + times_widget_container[1]:getSize().w / 2 + TopBar.MARGIN_SIDES,
            -- Screen:getHeight() - books_information_widget_container[1]:getSize().h)

            local version_widget_container =
            bottom_container:new{
                dimen = Geom:new(),
                TextWidget:new{
                    text =  "aa",
                    face = Font:getFace("myfont3", 12),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            }
            version_widget_container[1]:setText(TopBar:getDateAndVersion() .. ". BDB:" .. TopBar:getBooksOpened() .. "·TR:" .. TopBar:getTotalRead() .. "d" .. "·ΔL:" .. stats_year .. "h")
            version_widget_container:paintTo(bb, x + version_widget_container[1]:getSize().w / 2 + TopBar.MARGIN_SIDES,
            Screen:getHeight()
            - books_information_widget_container[1]:getSize().h - 10)
            -- - times_widget_container[1]:getSize().h)

            if self.fm and not self.history then
                if ffiUtil.realpath(DataStorage:getSettingsDir() .. "/calibre.lua") then
                    local sort_by_mode = G_reader_settings:readSetting("collate")
                    local collate_symbol = ""
                    if sort_by_mode == "strcoll" then
                        collate_symbol = "Name"
                    elseif sort_by_mode == "finished" then
                        collate_symbol = "F"
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
                    collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w / 2- TopBar.MARGIN_SIDES, Screen:getHeight())

                    local reverse_collate_mode = G_reader_settings:readSetting("reverse_collate")
                    if reverse_collate_mode then
                        reverse_collate_widget_container[1]:setText("↓")
                    else
                        reverse_collate_widget_container[1]:setText("↑")
                    end
                    -- collate:paintTo(bb, x + Screen:getWidth() - collate[1]:getSize().w - TopBar.MARGIN_SIDES, y + Screen:scaleBySize(6))
                    reverse_collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w - reverse_collate_widget_container[1]:getSize().w /2 - TopBar.MARGIN_SIDES, Screen:getHeight())

                else
                    collate_widget_container[1]:setText("?")
                    collate_widget_container:paintTo(bb, x + Screen:getWidth() - collate_widget_container[1]:getSize().w / 2- TopBar.MARGIN_SIDES, Screen:getHeight())
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
    if (self.status_bar and self.status_bar == true and self.view.footer.settings.bar_top) or self.view.dogear_visible then
        if Device:isAndroid() then
            self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(20), Screen:getHeight() - TopBar.MARGIN_BOTTOM)
        else
            self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(2), Screen:getHeight() - TopBar.MARGIN_BOTTOM)
        end
    else
        if Device:isAndroid() then
            self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(20), y + Screen:scaleBySize(6))
        else
            self.ignore_corners_widget_container:paintTo(bb, x + Screen:getWidth() - self.ignore_corners_widget_container[1]:getSize().w - Screen:scaleBySize(2), y + Screen:scaleBySize(6))
        end
    end

    self.goal_widget_container:paintTo(bb, x + TopBar.MARGIN_SIDES + self.goal_widget_container[1]:getSize().w / 2, Screen:getHeight())
    self.current_page_widget_container:paintTo(bb, x + math.floor(Screen:getWidth() / 2), Screen:getHeight())-- - TopBar.MARGIN_BOTTOM_CURRENT_PAGE)

    local font = "cfont"
    if self.settings:nilOrFalse("use_system_font") then
        font = self.settings:readSetting("font_times_progress") or "myfont3"
    end

    local font_size = self.settings:readSetting("font_size_times_progress")
    and self.settings:readSetting("font_size_times_progress") or 12


    local face_big = Font:getFace(
        font,
        font_size
    )

    local face_small = Font:getFace(
        font,
        font_size - 6
    )

    local size_big = font_size
    local size_small = size_big - 6

    local function get_metrics_px(face)
        local xh, asc, desc = face.ftsize:getAscDesc()
        local px = face.size -- tamaño real en píxeles
        return
            xh  * px,
            asc * px,
            desc * px
    end

    local xh_big, asc_big = get_metrics_px(face_big)
    local xh_small, asc_small = get_metrics_px(face_small)

    local center_big = asc_big - xh_big / 2
    local center_small = asc_small - xh_small / 2

    local center_offset = math.floor(center_big - center_small + 0.5)

    -- self.chapter_pages_left_text = TextWidget:new{
    --     text = self.chapter_pages_left_text.text,
    --     face = Font:getFace(font, size_small),
    --     fgcolor = Blitbuffer.COLOR_BLACK,
    --     -- forced_baseline = self.current_page_widget_container[1].forced_baseline - size_big,
    --     -- forced_baseline = self.current_page_widget_container[1].forced_baseline + size_small,
    --     -- forced_baseline = self.current_page_widget_container[1].forced_baseline - center_offset,
    --     forced_baseline = self.current_page_widget_container[1].forced_baseline,
    --     forced_height = self.current_page_widget_container[1].forced_height,
    -- }


    self.chapter_pages_left_text.face = Font:getFace(font, size_small)
    -- self.chapter_pages_left_text.forced_baseline = self.current_page_widget_container[1].forced_baseline - size_big
    -- self.chapter_pages_left_text.forced_baseline = self.current_page_widget_container[1].forced_baseline + size_small
    -- self.chapter_pages_left_text.forced_baseline = self.current_page_widget_container[1].forced_baseline - center_offset
    self.chapter_pages_left_text.forced_baseline = self.current_page_widget_container[1].forced_baseline
    self.chapter_pages_left_text.forced_height = self.current_page_widget_container[1].forced_height

    -- self.chapter_pages_left_widget = bottom_container:new{
    --     dimen = Geom:new(),
    --         self.chapter_pages_left_text,
    -- }

    local parent_width =  math.floor(self.current_page_widget_container[1]:getSize().w / 2)
    local parent_x = x + math.floor(Screen:getWidth() / 2)
    local x_pos = parent_x + parent_width + math.floor(self.chapter_pages_left_widget[1]:getSize().w / 2)
    local y_pos = Screen:getHeight()

    self.chapter_pages_left_widget:paintTo(bb, x_pos, y_pos)
end

function TopBar:onAdjustMarginsTopbar()
    local Event = require("ui/event")
    if self.settings:isTrue("show_top_bar") and not self.status_bar then

        -- local configurable = self.ui.document.configurable
        -- local margins = { TopBar.MARGIN_SIDES, TopBar.MARGIN_TOP, TopBar.MARGIN_SIDES, TopBar.MARGIN_BOTTOM}
        -- local margins_lr = { TopBar.MARGIN_SIDES, TopBar.MARGIN_SIDES}
        -- self.ui.document:onSetPageTopAndBottomMargin(margins_tb)
        -- self.ui:handleEvent(Event:new("SetPageTopMargin",  TopBar.MARGIN_TOP))
        -- self.ui:handleEvent(Event:new("SetPageBottomMargin",  TopBar.MARGIN_BOTTOM))


        -- Adjust margin values to the topbar. Values are in pixels
        -- We add a little bit more, 12 (15, after revision) pixels hardcoded since side margins are 10 and bottom margin 9, always. Top margin value is 9 if not alternative status bar
        -- Exceptions are Android in which side margins are set to 20
        -- And top margin when alternative status bar is on. Value is set to self.space_after_alt_bar (fixed to 15) + 9, adding a little bit more too, 6 more pixels (variable TopBar.extra_pixels)

        local side_margins = {15, 15}
        if Device:isAndroid() then
            side_margins = {20, 20}
        end
        if self.ui.document.configurable.t_page_margin ~= Screen:unscaleBySize(self:getHeight()) or
            self.ui.document.configurable.b_page_margin ~= Screen:unscaleBySize(self:getBottomHeight()) or
            self.ui.document.configurable.h_page_margins[1] ~= side_margins[1] or
            self.ui.document.configurable.h_page_margins[2] ~= side_margins[2] then
                local margins = { side_margins[1], Screen:unscaleBySize(self:getHeight()), side_margins[2], Screen:unscaleBySize(self:getBottomHeight())}
                self.ui.document.configurable.t_page_margin = Screen:unscaleBySize(self:getHeight())
                self.ui.document.configurable.b_page_margin = Screen:unscaleBySize(self:getBottomHeight())
                self.ui.document.configurable.h_page_margins = side_margins
                UIManager:sendEvent(Event:new("SetPageHorizMargins", side_margins))
                UIManager:sendEvent(Event:new("SetPageTopMargin", Screen:unscaleBySize(self:getHeight())))
                UIManager:sendEvent(Event:new("SetPageBottomMargin", Screen:unscaleBySize(self:getBottomHeight())))
            else
                self.ui:showBookStatus()
            end
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
    local FontList = require("fontlist")
    local table_fonts = {}
    for _, font_path in ipairs(FontList:getFontList()) do
        if font_path:match("([^/]+%-Regular%.[ot]tf)$") then
            font_path = font_path:match("([^/]+%-Regular%.[ot]tf)$")
            table.insert(table_fonts, {
                text = font_path,
                checked_func = function()
                    return self.settings:readSetting("font_title") == font_path
                end,
                callback = function()
                    local face = Font:getFace(font_path, self.settings:readSetting("font_size_title")
                    and self.settings:readSetting("font_size_title") or 14)
                    local face_series = Font:getFace(font_path, self.settings:readSetting("font_size_title")
                    and self.settings:readSetting("font_size_title") - 8 or 6)
                    self.settings:saveSetting("font_title", font_path)
                    self:changeAllWidgetFaces()
                    UIManager:setDirty("all", "ui")
                    self.settings:flush()
                    return true
                end,
            })
        end
    end
    local table_fonts_times_progress = {}
    for _, font_path in ipairs(FontList:getFontList()) do
        if font_path:match("([^/]+%-Regular%.[ot]tf)$") then
            font_path = font_path:match("([^/]+%-Regular%.[ot]tf)$")
            table.insert(table_fonts_times_progress, {
                text = font_path,
                checked_func = function()
                    return self.settings:readSetting("font_times_progress") == font_path
                end,
                callback = function()
                    self.settings:saveSetting("font_times_progress", font_path)
                    self:changeAllWidgetFaces()
                    UIManager:setDirty("all", "ui")
                    self.settings:flush()
                    return true
                end,
            })
        end
    end
    menu_items.topbar = {
        text = _("Top bar"),
        sub_item_table = {
            {
                text = _("Show top bar"),
                checked_func = function() return self.settings:isTrue("show_top_bar") end,
                callback = function()
                    UIManager:broadcastEvent(Event:new("ToggleShowTopBar"))
                    UIManager:setDirty("all", "ui")
                    return true
                end,
           },
           {
                text_func = function()
                    return T(_("Space after alternative bar: %1"), self.space_after_alt_bar)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local InputDialog = require("ui/widget/inputdialog")
                    local space_after_alt_bar
                    space_after_alt_bar = InputDialog:new{
                        title = _("Set space after alternative bar"),
                        input = self.space_after_alt_bar,
                        input_type = "number",
                        input_hint = _("Pxs after alternative bar (default is 12px)"),
                        buttons =  {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(space_after_alt_bar)
                                    end,
                                },
                                {
                                    text = _("OK"),
                                    -- keep_menu_open = true,
                                    callback = function()
                                        local px = space_after_alt_bar:getInputValue()
                                        if not px or px < 0 or px > 140 then -- Max top margin value (creoptions.lua)
                                            px = 12
                                        end
                                        self.space_after_alt_bar = px
                                        self.settings:saveSetting("space_after_alt_bar", px)
                                        self.settings:flush()
                                        UIManager:close(space_after_alt_bar)
                                        touchmenu_instance:updateItems()
                                        self:toggleBar()
                                        UIManager:setDirty("all", "ui")
                                    end,
                                },
                            },
                        },
                    }
                    UIManager:show(space_after_alt_bar)
                    space_after_alt_bar:onShowKeyboard()
                end,
            },
            {
                text = _("Enable show separator lines"),
                checked_func = function()
                    return self.settings:isTrue("show_topbar_separators")
                end,
                    help_text = _([[Show space_after_alt_bar and top bar height separator lines]]),
                callback = function()
                    local show_topbar_separators = not self.settings:isTrue("show_topbar_separators")
                    self.settings:saveSetting("show_topbar_separators", show_topbar_separators)
                    self.settings:flush()
                    UIManager:setDirty("all", "ui")
                    return true
                end,
            },
            {
                text = _("Use system font"),
                checked_func = function()
                    return self.settings:isTrue("use_system_font")
                end,
                    help_text = _([[Use the select UI System font for the top bar widgets]]),
                callback = function()
                    local use_system_font = not self.settings:isTrue("use_system_font")
                    self.settings:saveSetting("use_system_font", use_system_font)
                    self:changeAllWidgetFaces()
                    UIManager:setDirty("all", "ui")
                    self.settings:flush()
                    return true
                end,
            },
           {
                text = _("Show battery and memory info"),
                checked_func = function() return self.settings:isTrue("show_battery_and_memory_info") end,
                callback = function()
                    local show_battery_and_memory_info = self.settings:isTrue("show_battery_and_memory_info")
                    self.settings:saveSetting("show_battery_and_memory_info", not show_battery_and_memory_info)
                    self.settings:flush()
                    self:toggleBar()
                    UIManager:setDirty("all", "ui")
                    return true
                end,
            },
            {
                text = _("Daily goal configuration"),
                sorting_hint = ("more_tools"),
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("Time goal: %1"), self.daily_time_goal)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local InputDialog = require("ui/widget/inputdialog")
                            local daily_time_goal
                            daily_time_goal = InputDialog:new{
                                title = _("Set time goal"),
                                input = self.daily_time_goal,
                                input_type = "number",
                                input_hint = _("Time goal (default is 120 minutes)"),
                                buttons =  {
                                    {
                                        {
                                            text = _("Cancel"),
                                            id = "close",
                                            callback = function()
                                                UIManager:close(daily_time_goal)
                                            end,
                                        },
                                        {
                                            text = _("OK"),
                                            -- keep_menu_open = true,
                                            callback = function()
                                                local goal = daily_time_goal:getInputValue()
                                                if goal and goal < 0 or goal > 10000 then
                                                    goal = 120
                                                end
                                                if not goal then
                                                    goal = goal
                                                end
                                                self.daily_time_goal = goal
                                                self.settings:saveSetting("daily_time_goal", goal)
                                                self.settings:flush()
                                                UIManager:close(daily_time_goal)
                                                touchmenu_instance:updateItems()
                                                self:toggleBar()
                                                UIManager:setDirty("all", "ui")
                                            end,
                                        },
                                    },
                                },
                            }
                            UIManager:show(daily_time_goal)
                            daily_time_goal:onShowKeyboard()
                        end,
                    },
                    {
                        text_func = function()
                            return T(_("Pages goal: %1"), self.daily_pages_goal)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local InputDialog = require("ui/widget/inputdialog")
                            local daily_pages_goal
                            daily_pages_goal = InputDialog:new{
                                title = _("Set pages goal"),
                                input = self.daily_pages_goal,
                                input_type = "number",
                                input_hint = _("Pages goal (default is 120 minutes)"),
                                buttons =  {
                                    {
                                        {
                                            text = _("Cancel"),
                                            id = "close",
                                            callback = function()
                                                UIManager:close(daily_pages_goal)
                                            end,
                                        },
                                        {
                                            text = _("OK"),
                                            -- keep_menu_open = true,
                                            callback = function()
                                                local goal = daily_pages_goal:getInputValue()
                                                if goal and goal < 0 or goal > 10000 then
                                                    goal = 120
                                                end
                                                if not goal then
                                                    goal = goal
                                                end
                                                self.daily_pages_goal = goal
                                                self.settings:saveSetting("daily_pages_goal", goal)
                                                self.settings:flush()
                                                UIManager:close(daily_pages_goal)
                                                touchmenu_instance:updateItems()
                                                self:toggleBar()
                                                UIManager:setDirty("all", "ui")
                                            end,
                                        },
                                    },
                                },
                            }
                            UIManager:show(daily_pages_goal)
                            daily_pages_goal:onShowKeyboard()
                        end,
                    }
                },
            },
            {
                text_func = function()
                    return T(_("Title and chapter font: %1"), self.settings:readSetting("font_title") and self.settings:readSetting("font_title") or "Default: Consolas-Regular.ttf")
                end,
                sub_item_table = table_fonts,
            },
            {
                text_func = function()
                    return T(_("Title and chapter font size: %1"), self.settings:readSetting("font_size_title") and self.settings:readSetting("font_size_title") or 12)
                end,
                text = _("Title and chapter font size"),
                sub_item_table = {
            {
                text_func = function()
                    return T(_("Item font size: %1"), self.settings:readSetting("font_size_title") and self.settings:readSetting("font_size_title") or 12)
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local items_font = SpinWidget:new{
                        title_text = _("Item font size"),
                        value = self.settings:readSetting("font_size_title")
                        and self.settings:readSetting("font_size_title")
                        or 12,
                        value_min = 8,
                        value_max = 36,
                        default_value = 12,
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            local new_font_size = spin.value
                            self.settings:saveSetting("font_size_title", new_font_size)
                            local face = Font:getFace(self.settings:readSetting("font_title")
                            and self.settings:readSetting("font_title") or "Consolas-Regular.ttf", new_font_size)
                            local face_series = Font:getFace(self.settings:readSetting("font_title")
                            and self.settings:readSetting("font_title") or "Consolas-Regular.ttf", new_font_size - 8)
                            self:changeAllWidgetFaces()
                            UIManager:setDirty("all", "ui")
                            self.settings:flush()
                            touchmenu_instance:updateItems()

                        end,
                    }
                    UIManager:show(items_font)
                end,
                keep_menu_open = true,
            },
            },
            },
            {
                text_func = function()
                    return T(_("Times and progress font: %1"), self.settings:readSetting("font_times_progress") and self.settings:readSetting("font_times_progress") or "Default: Consolas-Regular.ttf")
                end,
                sub_item_table = table_fonts_times_progress,
            },
            {
                text_func = function()
                    return T(_("Times and progress font size: %1"), self.settings:readSetting("font_size_times_progress") and self.settings:readSetting("font_size_times_progress") or 10)
                end,
                text = _("Times and progress font size"),
                sub_item_table = {
            {
                text_func = function()
                    return T(_("Item font size: %1"), self.settings:readSetting("font_size_times_progress") and self.settings:readSetting("font_size_times_progress") or 10)
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local items_font = SpinWidget:new{
                        title_text = _("Item font size"),
                        value = self.settings:readSetting("font_size_times_progress")
                        and self.settings:readSetting("font_size_times_progress")
                        or 10,
                        value_min = 6,
                        value_max = 18,
                        default_value = 10,
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings:saveSetting("font_size_times_progress", spin.value)
                            self:changeAllWidgetFaces()
                            UIManager:setDirty("all", "ui")
                            self.settings:flush()
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(items_font)
                end,
                keep_menu_open = true,
            },
            },
        }
        },
}
end

function TopBar:setCollectionCollate(collate)
    self.collection_collate = collate
end

function TopBar:getCollectionCollate()
    return self.collection_collate
end

return TopBar
