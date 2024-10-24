local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local ProgressWidget = require("ui/widget/progresswidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local logger = require("logger")
local T = require("ffi/util").template
local _ = require("gettext")
local C_ = _.pgettext
local Screen = Device.screen
local SQ3 = require("lua-ljsqlite3/init")
local util = require("util")
local InfoMessage = require("ui/widget/infomessage")
local Notification = require("ui/widget/notification")


local MODE = {
    off = 0,
    page_progress = 1,
    pages_left_book = 2,
    time = 3,
    pages_left = 4,
    battery = 5,
    percentage = 6,
    book_time_to_read = 7,
    chapter_time_to_read = 8,
    frontlight = 9,
    mem_usage = 10,
    wifi_status = 11,
    book_title = 12,
    book_chapter = 13,
    bookmark_count = 14,
    chapter_progress = 15,
    frontlight_warmth = 16,
    custom_text = 17,
    book_author = 18,
    page_turning_inverted = 19, -- includes both page-turn-button and swipe-and-tap inversion
}

local WPP = 240

local symbol_prefix = {
    letters = {
        time = nil,
        pages_left_book = "->",
        pages_left = "=>",
        -- @translators This is the footer letter prefix for battery % remaining.
        battery = C_("FooterLetterPrefix", "B:"),
        -- @translators This is the footer letter prefix for the number of bookmarks (bookmark count).
        bookmark_count = C_("FooterLetterPrefix", "BM:"),
        -- @translators This is the footer letter prefix for percentage read.
        percentage = C_("FooterLetterPrefix", "R:"),
        -- @translators This is the footer letter prefix for book time to read.
        book_time_to_read = C_("FooterLetterPrefix", "TB:"),
        -- @translators This is the footer letter prefix for chapter time to read.
        chapter_time_to_read = C_("FooterLetterPrefix", "TC:"),
        -- @translators This is the footer letter prefix for frontlight level.
        frontlight = C_("FooterLetterPrefix", "L:"),
        -- @translators This is the footer letter prefix for light warmth of the frontlight (redshift).
        frontlight_warmth = C_("FooterLetterPrefix", "LW:"),
        -- @translators This is the footer letter prefix for memory usage.
        mem_usage = C_("FooterLetterPrefix", "M:"),
        -- @translators This is the footer letter prefix for Wi-Fi status.
        wifi_status = C_("FooterLetterPrefix", "W:"),
        -- @translators This is the footer letter prefix for page turning status.
        page_turning_inverted = C_("FooterLetterPrefix", "Pg:"),
    },
    icons = {
        time = "⌚",
        pages_left_book = BD.mirroredUILayout() and "↢" or "↣",
        pages_left = BD.mirroredUILayout() and "⇐" or "⇒",
        battery = "",
        bookmark_count = "\u{F097}", -- "empty bookmark" from nerdfont
        percentage = BD.mirroredUILayout() and "⤟" or "⤠",
        book_time_to_read = "⏳",
        chapter_time_to_read = BD.mirroredUILayout() and "⥖" or "⤻",
        frontlight = "☼",
        frontlight_warmth = "💡",
        mem_usage = "",
        wifi_status = "",
        wifi_status_off = "",
        page_turning_inverted = "⇄",
        page_turning_regular = "⇉",
    },
    compact_items = {
        time = nil,
        pages_left_book = BD.mirroredUILayout() and "‹" or "›",
        pages_left = BD.mirroredUILayout() and "‹" or "›",
        battery = "",
        bookmark_count = "\u{F097}",
        percentage = nil,
        book_time_to_read = nil,
        chapter_time_to_read = BD.mirroredUILayout() and "«" or "»",
        frontlight = "✺",
        frontlight_warmth = "⊛",
        -- @translators This is the footer compact item prefix for memory usage.
        mem_usage = C_("FooterCompactItemsPrefix", "M"),
        wifi_status = "",
        wifi_status_off = "",
        page_turning_inverted = "⇄",
        page_turning_regular = "⇉",
    }
}
if BD.mirroredUILayout() then
    -- We need to RTL-wrap these letters and symbols for proper layout
    for k, v in pairs(symbol_prefix.letters) do
        local colon = v:find(":")
        local wrapped
        if colon then
            local pre = v:sub(1, colon-1)
            local post = v:sub(colon)
            wrapped = BD.wrap(pre) .. BD.wrap(post)
        else
            wrapped = BD.wrap(v)
        end
        symbol_prefix.letters[k] = wrapped
    end
    for k, v in pairs(symbol_prefix.icons) do
        symbol_prefix.icons[k] = BD.wrap(v)
    end
end

-- Like util.splitWords(), but not capturing space and punctuations
local splitToWords = function(text)
    local wlist = {}
    for word in util.gsplit(text, "[%s%p]+", false) do
        if util.hasCJKChar(word) then
            for char in util.gsplit(word, "[\192-\255][\128-\191]+", true) do
                table.insert(wlist, char)
            end
        else
            table.insert(wlist, word)
        end
    end
    return wlist
end


getSessionsInfo = function (footer)
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if not footer.ui.statistics then
        return "n/a"
    end
    local session_started = footer.ui.statistics.start_current_period
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    -- best to e it to letters, to get '2m' ?
    user_duration_format = "letters"

    -- No necesitamos el id del libro para poder traer las páginas en la sesión actual
    local id_book = footer.ui.statistics.id_curr_book
    if id_book == nil then
        id_book = 0
    end

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
            WHERE DATE(start_time,'unixepoch','localtime') > DATE(DATE('now', '-180 day','localtime'),'localtime')
            GROUP BY DATE(start_time,'unixepoch','localtime'));"
            );
    ]]
    local avg_last_hundred_and_eighty_days = conn:rowexec(sql_stmt)

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

    if avg_last_hundred_and_eighty_days == nil then
        avg_last_hundred_and_eighty_days = 0
    end

    avg_last_seven_days = math.floor(tonumber(avg_last_seven_days)/7/60/60 * 100)/100
    avg_last_thirty_days = math.floor(tonumber(avg_last_thirty_days)/30/60/60 * 100)/100
    avg_last_sixty_days = math.floor(tonumber(avg_last_sixty_days)/60/60/60 * 100)/100
    avg_last_ninety_days = math.floor(tonumber(avg_last_ninety_days)/90/60/60 * 100)/100
    avg_last_hundred_and_eighty_days = math.floor(tonumber(avg_last_hundred_and_eighty_days)/180/60/60 * 100)/100

    return sessions, avg_wpm, avg_last_seven_days, avg_last_thirty_days, avg_last_sixty_days, avg_last_ninety_days, avg_last_hundred_and_eighty_days
end

getSessionStats = function (footer)
        local DataStorage = require("datastorage")
        local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        if not footer.ui.statistics then
            return "n/a"
        end



        local session_started = footer.ui.statistics.start_current_period
        local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
        -- best to e it to letters, to get '2m' ?
        -- user_duration_format = "letters"

        -- No necesitamos el id del libro para poder traer las páginas en la sesión actual
        local id_book = footer.ui.statistics.id_curr_book
        if id_book == nil then
            id_book = 0
        end

        local conn = SQ3.open(db_location)
        local sql_stmt = [[
            SELECT count(*)
            FROM   (
                        SELECT sum(duration)    AS sum_duration
                        FROM   page_stat
                        WHERE  start_time >= %d
                        GROUP  BY id_book, page
                   );
        ]]
        local pages_read_session = conn:rowexec(string.format(sql_stmt, session_started))


        local sql_stmt = [[
                SELECT pages
                FROM   book
                WHERE  id = %d;
        ]]


        local total_pages = conn:rowexec(string.format(sql_stmt, id_book))


        local sql_stmt = [[
            SELECT sum(sum_duration)
            FROM    (
                         SELECT sum(duration)    AS sum_duration
                         FROM   page_stat
                         WHERE  start_time >= %d
                         GROUP  BY id_book, page
                    );
        ]]

        local now_stamp = os.time()
        local now_t = os.date("*t")
        local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
        local start_today_time = now_stamp - from_begin_day

        local read_today = conn:rowexec(string.format(sql_stmt,start_today_time))

        local flow = footer.ui.document:getPageFlow(footer.pageno)

        conn:close()
        if pages_read_session == nil then
            pages_read_session = 0
        end
        pages_read_session = tonumber(pages_read_session)

        if total_pages == nil then
            total_pages = 0
        end
        total_pages = tonumber(total_pages)
        --local percentage_session = footer.pageno/total_pages

        if read_today == nil then
            read_today = 0
        end
        read_today = tonumber(read_today)

        local percentage_session = pages_read_session/total_pages
        local wpm_session = 0

        -- local title_pages = footer.ui.document._document:getDocumentProps().title
        -- local title_words = 0
        -- if (title_pages:find("([0-9,]+w)") ~= nil) then
        --     title_words = title_pages:match("([0-9,]+w)"):gsub("w",""):gsub(",","")
        -- end
        -- -- Just to calculate the sesssion wpm I will assume the WPP to be calculated with the books number of words/syntetic pages for the configuration
        -- -- Not accurate since pages we turn quick are counted when they should not
        -- WPP_SESSION = math.floor((title_words/footer.pages * 100) / 100)
        if pages_read_session > 0 then
            wpm_session = math.floor(((pages_read_session * WPP)/((os.time() - session_started)/60))* 100) / 100
        end

        local words_session = pages_read_session * WPP
        -- logger.warn(pages_read_session)
        -- logger.warn(percentage_session)

        percentage_session = math.floor(percentage_session*1000)/10
        local duration = datetime.secondsToClockDuration(user_duration_format, os.time() - session_started, false)


        local duration_raw =  math.floor(((os.time() - session_started)/60)* 100) / 100
        if duration_raw == nil then
            duration_raw = 0
        end
        return percentage_session, pages_read_session, duration, wpm_session, words_session, duration_raw, read_today
    end
getTodayBookStats = function ()
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT sum(duration), SUM(total_pages)
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
    local wpm_today = 0
    if today_pages > 0 then
        wpm_today = math.floor(((today_pages * WPP)/((today_duration)/60))* 100) / 100
    end

    local words_today = today_pages * WPP
    return today_duration, today_pages, wpm_today, words_today
end

getThisWeekBookStats = function ()
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT sum(duration), SUM(total_pages)
        FROM   wpm_stat_data
        WHERE  start_time >= strftime('%s', DATE('now', 'weekday 0','-6 day'))
    ]]
   local week_duration, week_pages = conn:rowexec(sql_stmt)
    conn:close()
    if week_pages == nil then
        week_pages = 0
    end
    if week_duration == nil then
        week_duration = 0
    end
    week_duration = tonumber(week_duration)
    week_pages = tonumber(week_pages)

    local wpm_week = 0
    if week_pages > 0 then
        wpm_week = math.floor(((week_pages * WPP)/((week_duration)/60))* 100) / 100
    end

    local words_week = week_pages * WPP

    return week_duration, week_pages, wpm_week, words_week
end

getThisMonthBookStats = function ()
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    local conn = SQ3.open(db_location)
    local sql_stmt = [[
        SELECT sum(duration), SUM(total_pages)
        FROM   wpm_stat_data
        WHERE DATE(start_time, 'unixepoch', 'localtime') >= DATE('now', 'localtime', 'start of month')
    ]]
   local month_duration, month_pages = conn:rowexec(sql_stmt)
    conn:close()
    if month_pages == nil then
        month_pages = 0
    end
    if month_duration == nil then
        month_duration = 0
    end
    month_duration = tonumber(month_duration)
    month_pages = tonumber(month_pages)

    local wpm_month = 0
    if month_pages > 0 then
        wpm_month = math.floor(((month_pages * WPP)/((month_duration)/60))* 100) / 100
    end

    local words_week = month_pages * WPP

    return month_duration, month_pages, wpm_month, words_week
end

getReadThisBook = function (footer)
    local now_stamp = os.time()
    local now_t = os.date("*t")
    local DataStorage = require("datastorage")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    local conn = SQ3.open(db_location)
    local title = footer.ui.document._document:getDocumentProps().title
    local sql_stmt = "SELECT id FROM book where title like 'titles' order by id desc LIMIT 1;"
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

    return total_time_book

end

-- functions that generates footer text for each mode
local footerTextGeneratorMap = {
    empty = function() return "" end,
    frontlight = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].frontlight
        local powerd = Device:getPowerDevice()
        if powerd:isFrontlightOn() then
            if Device:isCervantes() or Device:isKobo() then
                return (prefix .. " %d%%"):format(powerd:frontlightIntensity())
            else
                return (prefix .. " %d"):format(powerd:frontlightIntensity())
            end
        else
            if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                return ""
            else
                return T(_("%1 Off"), prefix)
            end
        end
    end,
    frontlight_warmth = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].frontlight_warmth
        local powerd = Device:getPowerDevice()
        if powerd:isFrontlightOn() then
            local warmth = powerd:frontlightWarmth()
            if warmth then
                return (prefix .. " %d%%"):format(warmth)
            end
        else
            if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                return ""
            else
                return T(_("%1 Off"), prefix)
            end
        end
    end,
    battery = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].battery
        local powerd = Device:getPowerDevice()
        local batt_lvl = 0
        local is_charging = false

        if Device:hasBattery() then
            local main_batt_lvl = powerd:getCapacity()

            if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
                local aux_batt_lvl = powerd:getAuxCapacity()
                is_charging = powerd:isAuxCharging()
                -- Sum both batteries for the actual text
                batt_lvl = main_batt_lvl + aux_batt_lvl
                -- But average 'em to compute the icon...
                if symbol_type == "icons" or symbol_type == "compact_items" then
                    prefix = powerd:getBatterySymbol(powerd:isAuxCharged(), is_charging, batt_lvl / 2)
                end
            else
                is_charging = powerd:isCharging()
                batt_lvl = main_batt_lvl
                if symbol_type == "icons" or symbol_type == "compact_items" then
                   prefix = powerd:getBatterySymbol(powerd:isCharged(), is_charging, main_batt_lvl)
                end
            end
        end

        if footer.settings.all_at_once and batt_lvl > footer.settings.battery_hide_threshold then
            return ""
        end

        -- If we're using icons, use the fancy variable icon from powerd:getBatterySymbol
        if symbol_type == "icons" or symbol_type == "compact_items" then
            if symbol_type == "compact_items" then
                return BD.wrap(prefix)
            else
                return BD.wrap(prefix) .. batt_lvl .. "%"
            end
        else
            return BD.wrap(prefix) .. " " .. (is_charging and "+" or "") .. batt_lvl .. "%"
        end
    end,
    bookmark_count = function(footer)
        local bookmark_count = footer.ui.annotation:getNumberOfAnnotations()
        if footer.settings.all_at_once and footer.settings.hide_empty_generators and bookmark_count == 0 then
            return ""
        end
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].bookmark_count
        return prefix .. " " .. tostring(bookmark_count)
    end,
    time = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].time
        local clock = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
        if not prefix then
            return clock
        else
            return prefix .. " " .. clock
        end
    end,
    page_progress = function(footer)
        if footer.pageno then
            if footer.ui.pagemap and footer.ui.pagemap:wantsPageLabels() then
                -- (Page labels might not be numbers)
                return ("%s de %s"):format(footer.ui.pagemap:getCurrentPageLabel(true),
                                          footer.ui.pagemap:getLastPageLabel(true))
            end
            if footer.ui.document:hasHiddenFlows() then
                -- i.e., if we are hiding non-linear fragments and there's anything to hide,
                local flow = footer.ui.document:getPageFlow(footer.pageno)
                local page = footer.ui.document:getPageNumberInFlow(footer.pageno)
                local pages = footer.ui.document:getTotalPagesInFlow(flow)
                if flow == 0 then
                    return ("%d // %d"):format(page, pages)
                else
                    return ("[%d / %d]%d"):format(page, pages, flow)
                end
            else
                return ("%d de %d"):format(footer.pageno, footer.pages)
            end
        elseif footer.position then
            return ("%d / %d"):format(footer.position, footer.doc_height)
        end
    end,
    pages_left_book = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].pages_left_book
        if footer.pageno then
            if footer.ui.pagemap and footer.ui.pagemap:wantsPageLabels() then
                -- (Page labels might not be numbers)
                local label, idx, count = footer.ui.pagemap:getCurrentPageLabel(false) -- luacheck: no unused
                local remaining = count - idx
                if footer.settings.pages_left_includes_current_page then
                    remaining = remaining + 1
                end
                return ("%s %s / %s"):format(prefix, remaining, footer.ui.pagemap:getLastPageLabel(true))
            end
            if footer.ui.document:hasHiddenFlows() then
                -- i.e., if we are hiding non-linear fragments and there's anything to hide,
                local flow = footer.ui.document:getPageFlow(footer.pageno)
                local page = footer.ui.document:getPageNumberInFlow(footer.pageno)
                local pages = footer.ui.document:getTotalPagesInFlow(flow)
                local remaining = pages - page
                if footer.settings.pages_left_includes_current_page then
                    remaining = remaining + 1
                end
                if flow == 0 then
                    return ("%s %d // %d"):format(prefix, remaining, pages)
                else
                    return ("%s [%d / %d]%d"):format(prefix, remaining, pages, flow)
                end
            else
                local remaining = footer.pages - footer.pageno
                if footer.settings.pages_left_includes_current_page then
                    remaining = remaining + 1
                end
                return ("%s %d / %d"):format(prefix, remaining, footer.pages)
            end
        elseif footer.position then
            return ("%s %d / %d"):format(prefix, footer.doc_height - footer.position, footer.doc_height)
        end
    end,
    pages_left = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].pages_left
        local left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
        if footer.settings.pages_left_includes_current_page then
            left = left + 1
        end
        return prefix .. " " .. ("%d"):format(left)
    end,
    chapter_progress = function(footer)
        return footer:getChapterProgress()
    end,
    percentage = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].percentage
        local digits = footer.settings.progress_pct_format
        local string_percentage = "%." .. digits .. "f%%"
        if footer.ui.document:hasHiddenFlows() then
            local flow = footer.ui.document:getPageFlow(footer.pageno)
            if flow ~= 0 then
                string_percentage = "[" .. string_percentage .. "]"
            end
        end
        if prefix then
            string_percentage = prefix .. " " .. string_percentage
        end
        return string_percentage:format(footer:getBookProgress() * 100)
    end,
    book_time_to_read = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].book_time_to_read
        local left = footer.ui.document:getTotalPagesLeft(footer.pageno)
        return footer:getDataFromStatistics(prefix and (prefix .. " ") or "", left)
    end,
    chapter_time_to_read = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].chapter_time_to_read
        local left = footer.ui.toc:getChapterPagesLeft(footer.pageno) or footer.ui.document:getTotalPagesLeft(footer.pageno)
        return footer:getDataFromStatistics(prefix .. " ", left)
    end,
    mem_usage = function(footer)
        local statm = io.open("/proc/self/statm", "r")
        if statm then
            local symbol_type = footer.settings.item_prefix
            local prefix = symbol_prefix[symbol_type].mem_usage
            local dummy, rss = statm:read("*number", "*number")
            statm:close()
            -- we got the nb of 4Kb-pages used, that we convert to MiB
            rss = math.floor(rss * (4096 / 1024 / 1024))
            return (prefix .. " %d"):format(rss)
        end
        return ""
    end,
    wifi_status = function(footer)
        -- NOTE: This one deviates a bit from the mold because, in icons mode, we simply use two different icons and no text.
        local symbol_type = footer.settings.item_prefix
        local NetworkMgr = require("ui/network/manager")
        if symbol_type == "icons" or symbol_type == "compact_items" then
            if NetworkMgr:isWifiOn() then
                return symbol_prefix.icons.wifi_status
            else
                if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                    return ""
                else
                    return symbol_prefix.icons.wifi_status_off
                end
            end
        else
            local prefix = symbol_prefix[symbol_type].wifi_status
            if NetworkMgr:isWifiOn() then
                return T(_("%1 On"), prefix)
            else
                if footer.settings.all_at_once and footer.settings.hide_empty_generators then
                    return ""
                else
                    return T(_("%1 Off"), prefix)
                end
            end
        end
    end,
    page_turning_inverted = function(footer)
        local symbol_type = footer.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].page_turning_inverted
        if G_reader_settings:isTrue("input_invert_page_turn_keys") or G_reader_settings:isTrue("input_invert_left_page_turn_keys") or
           G_reader_settings:isTrue("input_invert_right_page_turn_keys") or footer.view.inverse_reading_order then -- inverse_reading_order is set on a per_book basis and/or global one.
            if symbol_type == "icons" or symbol_type == "compact_items" then
                return symbol_prefix.icons.page_turning_inverted
            else
                return T(_("%1 On"), prefix)
            end
        elseif footer.settings.all_at_once and footer.settings.hide_empty_generators then
            return ""
        else
            if symbol_type == "icons" or symbol_type == "compact_items" then
                return symbol_prefix.icons.page_turning_regular
            else
                return T(_("%1 Off"), prefix)
            end
        end
    end,
    book_author = function(footer)
        local text = footer.ui.doc_props.authors
        return footer:getFittedText(text, footer.settings.book_author_max_width_pct)
    end,
    book_title = function(footer)
        local text = footer.ui.doc_props.display_title
        return footer:getFittedText(text, footer.settings.book_title_max_width_pct)
    end,
    book_chapter = function(footer)
        local text = footer.ui.toc:getTocTitleByPage(footer.pageno)
        return footer:getFittedText(text, footer.settings.book_chapter_max_width_pct)
    end,
    custom_text = function(footer)
        -- if custom_text contains only spaces, request to merge it with the text before and after,
        -- in other words, don't add a separator then.
        local merge = footer.custom_text:gsub(" ", ""):len() == 0
        return footer.custom_text:rep(footer.custom_text_repetitions), merge
    end,
}

local ReaderFooter = WidgetContainer:extend{
    mode = MODE.page_progress,
    pageno = nil,
    pages = nil,
    footer_text = nil,
    text_font_face = "myfont3",
    height = Screen:scaleBySize(G_defaults:readSetting("DMINIBAR_CONTAINER_HEIGHT")),
    horizontal_margin = Size.span.horizontal_default,
    bottom_padding = Size.padding.tiny,
    settings = nil, -- table
    -- added to expose them to unit tests
    textGeneratorMap = footerTextGeneratorMap,
}

-- NOTE: This is used in a migration script by ui/data/onetime_migration,
--       which is why it's public.
ReaderFooter.default_settings = {
    disable_progress_bar = false, -- enable progress bar by default
    chapter_progress_bar = false, -- the whole book
    disabled = false,
    all_at_once = false,
    reclaim_height = false,
    toc_markers = true,
    page_progress = true,
    pages_left_book = false,
    time = true,
    pages_left = true,
    battery = Device:hasBattery(),
    battery_hide_threshold = Device:hasAuxBattery() and 200 or 100,
    percentage = true,
    book_time_to_read = true,
    chapter_time_to_read = true,
    frontlight = false,
    mem_usage = false,
    wifi_status = false,
    page_turning_inverted = false,
    book_author = false,
    book_title = false,
    book_chapter = false,
    bookmark_count = false,
    chapter_progress = false,
    item_prefix = "icons",
    toc_markers_width = 2, -- unscaled_size_check: ignore
    text_font_size = 14, -- unscaled_size_check: ignore
    text_font_bold = false,
    container_height = G_defaults:readSetting("DMINIBAR_CONTAINER_HEIGHT"),
    container_bottom_padding = 1, -- unscaled_size_check: ignore
    progress_margin_width = Device:isAndroid() and Screen:scaleByDPI(16) or 10, -- android: guidelines for rounded corner margins
    progress_margin = false, -- true if progress bar margins same as book margins
    progress_bar_min_width_pct = 20,
    book_author_max_width_pct = 30,
    book_title_max_width_pct = 30,
    book_chapter_max_width_pct = 30,
    skim_widget_on_hold = false,
    progress_style_thin = false,
    progress_bar_position = "alongside",
    bottom_horizontal_separator = false,
    align = "center",
    auto_refresh_time = false,
    progress_style_thin_height = 3, -- unscaled_size_check: ignore
    progress_style_thick_height = 7, -- unscaled_size_check: ignore
    hide_empty_generators = false,
    lock_tap = false,
    items_separator = "bar",
    progress_pct_format = "0",
    pages_left_includes_current_page = false,
    initial_marker = false,
}

function ReaderFooter:init()
    self.settings = G_reader_settings:readSetting("footer", self.default_settings)

    self.additional_footer_content = {} -- array, where additional header content can be inserted.

    -- Remove items not supported by the current device
    if not Device:hasFastWifiStatusQuery() then
        MODE.wifi_status = nil
    end
    if not Device:hasFrontlight() then
        MODE.frontlight = nil
    end
    if not Device:hasBattery() then
        MODE.battery = nil
    end
    if not Device:hasNaturalLight() then
        MODE.frontlight_warmth = nil
    end

    -- self.mode_index will be an array of MODE names, with an additional element
    -- with key 0 for "off", which feels a bit strange but seems to work...
    -- (The same is true for self.settings.order which is saved in settings.)
    self.mode_index = {}
    self.mode_nb = 0

    local handled_modes = {}
    if self.settings.order then
        -- Start filling self.mode_index from what's been ordered by the user and saved
        for i=0, #self.settings.order do
            local name = self.settings.order[i]
            -- (if name has been removed from our supported MODEs: ignore it)
            if MODE[name] then -- this mode still exists
                self.mode_index[self.mode_nb] = name
                self.mode_nb = self.mode_nb + 1
                handled_modes[name] = true
            end
        end
        -- go on completing it with remaining new modes in MODE
    end
    -- If no previous self.settings.order, fill mode_index with what's in MODE
    -- in the original indices order
    local orig_indexes = {}
    local orig_indexes_to_name = {}
    for name, orig_index in pairs(MODE) do
        if not handled_modes[name] then
            table.insert(orig_indexes, orig_index)
            orig_indexes_to_name[orig_index] = name
        end
    end
    table.sort(orig_indexes)
    for i = 1, #orig_indexes do
        self.mode_index[self.mode_nb] = orig_indexes_to_name[orig_indexes[i]]
        self.mode_nb = self.mode_nb + 1
    end
    -- require("logger").dbg(self.mode_nb, self.mode_index)

    -- Container settings
    self.height = Screen:scaleBySize(self.settings.container_height)
    self.bottom_padding = Screen:scaleBySize(self.settings.container_bottom_padding)

    self.mode_list = {}
    for i = 0, #self.mode_index do
        self.mode_list[self.mode_index[i]] = i
    end
    if self.settings.disabled then
        -- footer feature is completely disabled, stop initialization now
        self:disableFooter()
        return
    end

    self.pageno = self.view.state.page
    self.has_no_mode = true
    self.reclaim_height = self.settings.reclaim_height
    for _, m in ipairs(self.mode_index) do
        if self.settings[m] then
            self.has_no_mode = false
            break
        end
    end

    self.footer_text_face = Font:getFace(self.text_font_face, self.settings.text_font_size)
    self.footer_text = TextWidget:new{
        text = "",
        face = self.footer_text_face,
        bold = self.settings.text_font_bold,
    }
    -- all width related values will be initialized in self:resetLayout()
    self.text_width = 0
    self.footer_text.height = 0
    self.progress_bar = ProgressWidget:new{
        width = nil,
        height = nil,
        percentage = nil,
        tick_width = Screen:scaleBySize(self.settings.toc_markers_width),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
        initial_pos_marker = self.settings.initial_marker,
    }

    if self.settings.progress_style_thin then
        self.progress_bar:updateStyle(false, nil)
    end

    self.text_container = RightContainer:new{
        dimen = Geom:new{ w = 0, h = self.height },
        self.footer_text,
    }

    if self.settings.bar_top then
        self.old_bottom_padding = self.bottom_padding
        self.bottom_padding = 0
    end
    self:updateFooterContainer()
    self.mode = G_reader_settings:readSetting("reader_footer_mode") or self.mode
    if self.has_no_mode and self.settings.disable_progress_bar then
        self.mode = self.mode_list.off
        self.view.footer_visible = false
        self:resetLayout()
        self.footer_text.height = 0
    end
    if self.settings.all_at_once then
        self.view.footer_visible = (self.mode ~= self.mode_list.off)
        self:updateFooterTextGenerator()
        if self.settings.progress_bar_position ~= "alongside" and self.has_no_mode then
            self.footer_text.height = 0
        end
    else
        self:applyFooterMode()
    end

    self.visibility_change = nil

    self.custom_text = G_reader_settings:readSetting("reader_footer_custom_text", "KOReader")
    self.custom_text_repetitions =
        tonumber(G_reader_settings:readSetting("reader_footer_custom_text_repetitions", "1"))

    self._goal_time = 120
    self._goal_pages = 100
end

function ReaderFooter:set_custom_text(touchmenu_instance)
    local text_dialog
    text_dialog = MultiInputDialog:new{
        title = _("Enter a custom text"),
        fields = {
            {
                text = self.custom_text or "",
                description = _("Custom string:"),
            },
            {
                text = self.custom_text_repetitions,
                description =_("Number of repetitions:"),
                input_type = "number",
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(text_dialog)
                    end,
                },
                {
                    text = _("Set"),
                    callback = function()
                        local inputs = text_dialog:getFields()
                        local new_text, new_repetitions = inputs[1], inputs[2]
                        if new_text == "" then
                            new_text = " "
                        end
                        if self.custom_text ~= new_text then
                            self.custom_text = new_text
                            G_reader_settings:saveSetting("reader_footer_custom_text",
                                self.custom_text)
                        end
                        new_repetitions = tonumber(new_repetitions) or 1
                        if new_repetitions < 1 then
                            new_repetitions = 1
                        end
                        if new_repetitions and self.custom_text_repetitions ~= new_repetitions then
                            self.custom_text_repetitions = new_repetitions
                            G_reader_settings:saveSetting("reader_footer_custom_text_repetitions",
                                self.custom_text_repetitions)
                        end
                        UIManager:close(text_dialog)
                        self:refreshFooter(true, true)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
            },
        },
    }
    UIManager:show(text_dialog)
    text_dialog:onShowKeyboard()
end

-- Help text string, or function, to be shown, or executed, on a long press on menu item
local option_help_text = {
    pages_left_book = _("Can be configured to include or exclude the current page."),
    percentage      = _("Progress percentage can be shown with zero, one or two decimal places."),
    mem_usage       = _("Show memory usage in MiB."),
    reclaim_height  = _("When the status bar is hidden, this setting will utilize the entirety of screen real estate (for your book) and will temporarily overlap the text when the status bar is shown."),
    custom_text     = ReaderFooter.set_custom_text,
}

function ReaderFooter:updateFooterContainer()
    local margin_span = HorizontalSpan:new{ width = self.horizontal_margin }
    self.vertical_frame = VerticalGroup:new{}
    if self.settings.bottom_horizontal_separator then
        self.separator_line = LineWidget:new{
            dimen = Geom:new{
                w = 0,
                h = Size.line.medium,
            }
        }
        local vertical_span = VerticalSpan:new{width = Size.span.vertical_default}
        table.insert(self.vertical_frame, self.separator_line)
        table.insert(self.vertical_frame, vertical_span)
    end
    if self.settings.progress_bar_position ~= "alongside" and not self.settings.disable_progress_bar then
        self.horizontal_group = HorizontalGroup:new{
            margin_span,
            self.text_container,
            margin_span,
        }
    else
        self.horizontal_group = HorizontalGroup:new{
            margin_span,
            self.progress_bar,
            self.text_container,
            margin_span,
        }
    end

    if self.settings.align == "left" then
        self.footer_container = LeftContainer:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.horizontal_group
        }
    elseif self.settings.align == "right" then
        self.footer_container = RightContainer:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.horizontal_group
        }
    else
        self.footer_container = CenterContainer:new{
            dimen = Geom:new{ w = 0, h = self.height },
            self.horizontal_group
        }
    end

    local vertical_span = VerticalSpan:new{width = Size.span.vertical_default}

    if self.settings.progress_bar_position == "above" and not self.settings.disable_progress_bar then
        table.insert(self.vertical_frame, self.progress_bar)
        table.insert(self.vertical_frame, vertical_span)
        table.insert(self.vertical_frame, self.footer_container)
    elseif self.settings.progress_bar_position == "below" and not self.settings.disable_progress_bar then
        table.insert(self.vertical_frame, self.footer_container)
        table.insert(self.vertical_frame, vertical_span)
        table.insert(self.vertical_frame, self.progress_bar)
    else
        table.insert(self.vertical_frame, self.footer_container)
    end
    -- If we don't use background, it will be transparent
    -- Bear in mind autorefresh won't refresh properly
    -- The self.autoRefreshFooter() function will need a second parameter true:
    -- self:onUpdateFooter(self:shouldBeRepainted(), true)

    -- In any case, the function updateFooterPage() will call always to self:updateFooterText(force_repaint, true) passing true as second parameter
    -- And autorefresh works without problem with a transparent status bar
    self.footer_content = FrameContainer:new{
        self.vertical_frame,
        -- background = Blitbuffer.COLOR_WHITE, -- Make the status bar transparent
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    self.footer_positioner = BottomContainer:new{
        dimen = Geom:new(),
        self.footer_content,
    }
    self[1] = self.footer_positioner
end

function ReaderFooter:unscheduleFooterAutoRefresh()
    if not self.autoRefreshFooter then return end -- not yet set up
    -- Slightly different wording than in rescheduleFooterAutoRefreshIfNeeded because it might not actually be scheduled at all
    logger.dbg("ReaderFooter: unschedule autoRefreshFooter")
    UIManager:unschedule(self.autoRefreshFooter)
end

function ReaderFooter:shouldBeRepainted()
    -- Since self.autoRefreshFooter() repaints also the topbar
    -- Repaint also when topbar is active even if footer is not visible
    if not self.view.footer_visible and not G_reader_settings:isTrue("show_top_bar") then
        return false
    end

    local top_wg = UIManager:getTopmostVisibleWidget() or {}
    -- logger.info("ReaderFooter:shouldBeRepainted, top_wg name:", top_wg.name, "src:", debug.getinfo(top_wg.init or top_wg._init or top_wg.free or top_wg.new or top_wg.paintTo or function() end, "S").short_src,  "fs:", top_wg.covers_fullscreen, "ft:", top_wg.covers_footer)
    if top_wg.name == "ReaderUI" then
        -- No overlap possible, it's safe to request a targeted widget repaint
        return true
    elseif top_wg.covers_fullscreen or top_wg.covers_footer then
        -- No repaint necessary at all
        return false
    end

    -- The topmost visible widget might overlap with us, but dimen isn't reliable enough to do a proper bounds check
    -- (as stuff often just sets it to the Screen dimensions),
    -- so request a full ReaderUI repaint to avoid out-of-order repaints.
    return true, true
end

function ReaderFooter:rescheduleFooterAutoRefreshIfNeeded()
    if not self.autoRefreshFooter then
        -- Create this function the first time we're called
        self.autoRefreshFooter = function()
            -- Only actually repaint the footer if nothing's being shown over ReaderUI (#6616)
            -- (We want to avoid the footer to be painted over a widget covering it - we would
            -- be fine refreshing it if the widget is not covering it, but this is hard to
            -- guess from here.)
            if self.ui.view[4] and G_reader_settings:isTrue("show_top_bar") then
                self:checkNewDay()
                self.ui.view[4]:toggleBar()
                UIManager:setDirty(self.ui.view[4], "ui")
            end
            self:onUpdateFooter(self:shouldBeRepainted())

            self:rescheduleFooterAutoRefreshIfNeeded() -- schedule (or not) next refresh
        end
    end
    local unscheduled = UIManager:unschedule(self.autoRefreshFooter) -- unschedule if already scheduled
    -- Only schedule an update if the footer has items that may change
    -- As self.view.footer_visible may be temporarily toggled off by other modules,
    -- we can't trust it for not scheduling auto refresh
    local schedule = false
    if self.settings.auto_refresh_time then
        if self.settings.all_at_once then
            if self.settings.time or self.settings.battery or self.settings.wifi_status or self.settings.mem_usage then
                schedule = true
            end
        else
            if self.mode == self.mode_list.time or self.mode == self.mode_list.battery
                    or self.mode == self.mode_list.wifi_status or self.mode == self.mode_list.mem_usage then
                schedule = true
            end
        end
    end
    if schedule then
        UIManager:scheduleIn(61 - tonumber(os.date("%S")), self.autoRefreshFooter)
        if not unscheduled then
            logger.dbg("ReaderFooter: scheduled autoRefreshFooter")
        else
            logger.dbg("ReaderFooter: rescheduled autoRefreshFooter")
        end
    elseif unscheduled then
        logger.dbg("ReaderFooter: unscheduled autoRefreshFooter")
    end
end

function ReaderFooter:setupTouchZones()
    if not Device:isTouchDevice() then return end
    local DTAP_ZONE_MINIBAR = G_defaults:readSetting("DTAP_ZONE_MINIBAR")
    local footer_screen_zone = {
        ratio_x = DTAP_ZONE_MINIBAR.x, ratio_y = DTAP_ZONE_MINIBAR.y,
        ratio_w = DTAP_ZONE_MINIBAR.w, ratio_h = DTAP_ZONE_MINIBAR.h,
    }
    self.ui:registerTouchZones({
        {
            id = "readerfooter_tap",
            ges = "tap",
            screen_zone = footer_screen_zone,
            handler = function(ges) return self:TapFooter(ges) end,
            overrides = {
                "readerconfigmenu_ext_tap",
                "readerconfigmenu_tap",
                "tap_forward",
                "tap_backward",
            },
            -- (Low priority: tap on existing highlights
            -- or links have priority)
        },
        {
            id = "readerfooter_hold",
            ges = "hold",
            screen_zone = footer_screen_zone,
            handler = function(ges) return self:onHoldFooter(ges) end,
            overrides = {
                "readerhighlight_hold",
            },
            -- (High priority: it's a fallthrough if we held outside the footer)
        },
    })
end

-- call this method whenever the screen size changes
function ReaderFooter:resetLayout(force_reset)
    local new_screen_width = Screen:getWidth()
    local new_screen_height = Screen:getHeight()
    if new_screen_width == self._saved_screen_width
        and new_screen_height == self._saved_screen_height and not force_reset then return end

    if self.settings.disable_progress_bar then
        self.progress_bar.width = 0
    elseif self.settings.progress_bar_position ~= "alongside" then
        self.progress_bar.width = math.floor(new_screen_width -
            2 * Screen:scaleBySize(self.settings.progress_margin_width))
    else
        self.progress_bar.width = math.floor(new_screen_width -
            2 * Screen:scaleBySize(self.settings.progress_margin_width) - self.text_width)
    end
    if self.separator_line then
        self.separator_line.dimen.w = new_screen_width - 2 * self.horizontal_margin
    end
    if self.settings.disable_progress_bar then
        self.progress_bar.height = 0
    else
        local bar_height
        if self.settings.progress_style_thin then
            bar_height = self.settings.progress_style_thin_height
        else
            bar_height = self.settings.progress_style_thick_height
        end
        self.progress_bar:setHeight(bar_height)
    end

    self.horizontal_group:resetLayout()
    self.footer_positioner.dimen.w = new_screen_width
    self.footer_positioner.dimen.h = new_screen_height
    self.footer_container.dimen.w = new_screen_width
    self.dimen = self.footer_positioner:getSize()

    self._saved_screen_width = new_screen_width
    self._saved_screen_height = new_screen_height
end

function ReaderFooter:getHeight()
    if self.footer_content then
        -- NOTE: self.footer_content is self.vertical_frame + self.bottom_padding,
        --       self.vertical_frame includes self.text_container (which includes self.footer_text)
        return self.footer_content:getSize().h
    else
        return 0
    end
end

function ReaderFooter:disableFooter()
    self.onReaderReady = function() end
    self.resetLayout = function() end
    self.updateFooterPage = function() end
    self.updateFooterPos = function() end
    self.mode = self.mode_list.off
    self.view.footer_visible = false
end

function ReaderFooter:updateFooterTextGenerator()
    local footerTextGenerators = {}
    for i, m in pairs(self.mode_index) do
        if self.settings[m] then
            table.insert(footerTextGenerators,
                         footerTextGeneratorMap[m])
            if not self.settings.all_at_once then
                -- if not show all at once, then one is enough
                self.mode = i
                break
            end
        end
    end
    if #footerTextGenerators == 0 then
        -- all modes are disabled
        self.genFooterText = footerTextGeneratorMap.empty
    elseif #footerTextGenerators == 1 then
        -- there is only one mode enabled, simplify the generator
        -- function to that one
        self.genFooterText = footerTextGenerators[1]
    else
        self.genFooterText = self.genAllFooterText
    end

    -- Even if there's no or a single mode enabled, all_at_once requires this to be set
     self.footerTextGenerators = footerTextGenerators

    -- notify caller that UI needs update
    return true
end

function ReaderFooter:textOptionTitles(option)
    local symbol = self.settings.item_prefix
    local option_titles = {
        all_at_once = _("Show all selected items at once"),
        reclaim_height = _("Overlap status bar"),
        bookmark_count = T(_("Bookmark count (%1)"), symbol_prefix[symbol].bookmark_count),
        page_progress = T(_("Current page (%1)"), "/"),
        pages_left_book = T(_("Pages left in book (%1)"), symbol_prefix[symbol].pages_left_book),
        time = symbol_prefix[symbol].time
            and T(_("Current time (%1)"), symbol_prefix[symbol].time) or _("Current time"),
        chapter_progress = T(_("Current page in chapter (%1)"), " ⁄⁄ "),
        pages_left = T(_("Pages left in chapter (%1)"), symbol_prefix[symbol].pages_left),
        battery = T(_("Battery percentage (%1)"), symbol_prefix[symbol].battery),
        percentage = symbol_prefix[symbol].percentage
            and T(_("Progress percentage (%1)"), symbol_prefix[symbol].percentage) or _("Progress percentage"),
        book_time_to_read = symbol_prefix[symbol].book_time_to_read
            and T(_("Time left to finish book (%1)"),symbol_prefix[symbol].book_time_to_read) or _("Time left to finish book"),
        chapter_time_to_read = T(_("Time left to finish chapter (%1)"), symbol_prefix[symbol].chapter_time_to_read),
        frontlight = T(_("Brightness level (%1)"), symbol_prefix[symbol].frontlight),
        frontlight_warmth = T(_("Warmth level (%1)"), symbol_prefix[symbol].frontlight_warmth),
        mem_usage = T(_("KOReader memory usage (%1)"), symbol_prefix[symbol].mem_usage),
        wifi_status = T(_("Wi-Fi status (%1)"), symbol_prefix[symbol].wifi_status),
        page_turning_inverted = T(_("Page turning inverted (%1)"), symbol_prefix[symbol].page_turning_inverted),
        book_author = _("Book author"),
        book_title = _("Book title"),
        book_chapter = _("Chapter title"),
        custom_text = T(_("Custom text (long-press to edit): \'%1\'%2"), self.custom_text,
            self.custom_text_repetitions > 1 and
            string.format(" × %d", self.custom_text_repetitions) or ""),
    }
    return option_titles[option]
end

function ReaderFooter:addToMainMenu(menu_items)
    local sub_items = {}
    menu_items.status_bar = {
        text = _("Status bar"),
        sub_item_table = sub_items,
    }

    -- If using crengine, add Alt status bar items at top
    if self.ui.crelistener then
        table.insert(sub_items, self.ui.crelistener:getAltStatusBarMenu())
    end

    -- menu item to fake footer tapping when touch area is disabled
    local DTAP_ZONE_MINIBAR = G_defaults:readSetting("DTAP_ZONE_MINIBAR")
    if DTAP_ZONE_MINIBAR.h == 0 or DTAP_ZONE_MINIBAR.w == 0 then
        table.insert(sub_items, {
            text = _("Toggle mode"),
            enabled_func = function()
                return not self.view.flipping_visible
            end,
            callback = function() self:onToggleFooterMode() end,
        })
    end

    local getMinibarOption = function(option, callback)
        return {
            text_func = function()
                return self:textOptionTitles(option)
            end,
            help_text = type(option_help_text[option]) == "string"
                and option_help_text[option],
            help_text_func = type(option_help_text[option]) == "function" and
                function(touchmenu_instance)
                    option_help_text[option](self, touchmenu_instance)
                end,
            checked_func = function()
                return self.settings[option] == true
            end,
            callback = function()
                self.settings[option] = not self.settings[option]
                -- We only need to send a SetPageBottomMargin event when we truly affect the margin
                local should_signal = false
                -- only case that we don't need a UI update is enable/disable
                -- non-current mode when all_at_once is disabled.
                local should_update = false
                local first_enabled_mode_num
                local prev_has_no_mode = self.has_no_mode
                local prev_reclaim_height = self.reclaim_height
                self.has_no_mode = true
                for mode_num, m in pairs(self.mode_index) do
                    if self.settings[m] then
                        first_enabled_mode_num = mode_num
                        self.has_no_mode = false
                        break
                    end
                end
                self.reclaim_height = self.settings.reclaim_height
                -- refresh margins position
                if self.has_no_mode then
                    self.footer_text.height = 0
                    should_signal = true
                    self.genFooterText = footerTextGeneratorMap.empty
                    self.mode = self.mode_list.off
                elseif prev_has_no_mode then
                    if self.settings.all_at_once then
                        self.mode = self.mode_list.page_progress
                        self:applyFooterMode()
                        G_reader_settings:saveSetting("reader_footer_mode", self.mode)
                    else
                        G_reader_settings:saveSetting("reader_footer_mode", first_enabled_mode_num)
                    end
                    should_signal = true
                elseif self.reclaim_height ~= prev_reclaim_height then
                    should_signal = true
                    should_update = true
                end
                if callback then
                    should_update = callback(self)
                elseif self.settings.all_at_once then
                    should_update = self:updateFooterTextGenerator()
                elseif (self.mode_list[option] == self.mode and self.settings[option] == false)
                        or (prev_has_no_mode ~= self.has_no_mode) then
                    -- current mode got disabled, redraw footer with other
                    -- enabled modes. if all modes are disabled, then only show
                    -- progress bar
                    if not self.has_no_mode then
                        self.mode = first_enabled_mode_num
                    else
                        -- If we've just disabled our last mode, first_enabled_mode_num is nil
                        -- If the progress bar is enabled,
                        -- fake an innocuous mode so that we switch to showing the progress bar alone, instead of nothing,
                        -- This is exactly what the "Show progress bar" toggle does.
                        self.mode = self.settings.disable_progress_bar and self.mode_list.off or self.mode_list.page_progress
                    end
                    should_update = true
                    self:applyFooterMode()
                    G_reader_settings:saveSetting("reader_footer_mode", self.mode)
                end
                if should_update or should_signal then
                    self:refreshFooter(should_update, should_signal)
                end
                -- The absence or presence of some items may change whether auto-refresh should be ensured
                self:rescheduleFooterAutoRefreshIfNeeded()
            end,
        }
    end

    table.insert(sub_items, {
        text = _("Progress bar"),
        separator = true,
        sub_item_table = {
            {
                text = _("Show progress bar"),
                checked_func = function()
                    return not self.settings.disable_progress_bar
                end,
                callback = function()
                    self.settings.disable_progress_bar = not self.settings.disable_progress_bar
                    if not self.settings.disable_progress_bar then
                        self:setTocMarkers()
                    end
                    -- If the status bar is currently disabled, switch to an innocuous mode to display it
                    if not self.view.footer_visible then
                        self.mode = self.mode_list.page_progress
                        self:applyFooterMode()
                        G_reader_settings:saveSetting("reader_footer_mode", self.mode)
                    end
                    self:refreshFooter(true, true)
                end,
            },
            {
                text = _("Show chapter-progress bar instead"),
                help_text = _("Show progress bar for the current chapter, instead of the whole book."),
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                checked_func = function()
                    return self.settings.chapter_progress_bar
                end,
                callback = function()
                    self:onToggleChapterProgressBar()
                end,
            },
            {
                text_func = function()
                    return T(_("Position: %1"), self:genProgressBarPositionMenuItems())
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                sub_item_table = {
                    self:genProgressBarPositionMenuItems("above"),
                    self:genProgressBarPositionMenuItems("alongside"),
                    self:genProgressBarPositionMenuItems("below"),
                },
                separator = true,
            },
            {
                text_func = function()
                    if self.settings.progress_style_thin then
                        return _("Thickness and height: thin")
                    else
                        return _("Thickness and height: thick")
                    end
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                sub_item_table = {
                    {
                        text = _("Thick"),
                        checked_func = function()
                            return not self.settings.progress_style_thin
                        end,
                        callback = function()
                            self.settings.progress_style_thin = nil
                            local bar_height = self.settings.progress_style_thick_height
                            self.progress_bar:updateStyle(true, bar_height)
                            self:setTocMarkers()
                            self:refreshFooter(true, true)
                        end,
                    },
                    {
                        text = _("Thin"),
                        checked_func = function()
                            return self.settings.progress_style_thin
                        end,
                        callback = function()
                            self.settings.progress_style_thin = true
                            local bar_height = self.settings.progress_style_thin_height
                            self.progress_bar:updateStyle(false, bar_height)
                            self:refreshFooter(true, true)
                        end,
                        separator = true,
                    },
                    {
                        text_func = function()
                            local height = self.settings.progress_style_thin
                                and self.settings.progress_style_thin_height or self.settings.progress_style_thick_height
                            return T(_("Height: %1"), height)
                        end,
                        callback = function(touchmenu_instance)
                            local value, value_min, value_max, default_value
                            if self.settings.progress_style_thin then
                                default_value = self.default_settings.progress_style_thin_height
                                value = self.settings.progress_style_thin_height
                                value_min = 1
                                value_max = 12
                            else
                                default_value = self.default_settings.progress_style_thick_height
                                value = self.settings.progress_style_thick_height
                                value_min = 5
                                value_max = 28
                            end
                            local items = SpinWidget:new{
                                value = value,
                                value_min = value_min,
                                value_step = 1,
                                value_hold_step = 2,
                                value_max = value_max,
                                default_value = default_value,
                                title_text = _("Progress bar height"),
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    if self.settings.progress_style_thin then
                                        self.settings.progress_style_thin_height = spin.value
                                    else
                                        self.settings.progress_style_thick_height = spin.value
                                    end
                                    self:refreshFooter(true, true)
                                    touchmenu_instance:updateItems()
                                end,
                            }
                            UIManager:show(items)
                        end,
                        keep_menu_open = true,
                    },
                },
            },
            {
                text_func = function()
                    local value = self.settings.progress_margin and _("same as book margins") or self.settings.progress_margin_width
                    return T(_("Margins: %1"), value)
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local spin_widget
                    spin_widget = SpinWidget:new{
                        title_text = _("Progress bar margins"),
                        value = self.settings.progress_margin_width,
                        value_min = 0,
                        value_max = 140, -- max creoptions h_page_margins
                        value_hold_step = 5,
                        default_value = self.default_settings.progress_margin_width,
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.progress_margin_width = spin.value
                            self.settings.progress_margin = false
                            self:refreshFooter(true)
                            touchmenu_instance:updateItems()
                        end,
                        extra_text = not self.ui.document.info.has_pages and _("Same as book margins"),
                        extra_callback = function()
                            local h_margins = self.ui.document.configurable.h_page_margins
                            local value = math.floor((h_margins[1] + h_margins[2])/2)
                            self.settings.progress_margin_width = value
                            self.settings.progress_margin = true
                            self:refreshFooter(true)
                            touchmenu_instance:updateItems()
                            spin_widget.value = value
                            spin_widget.original_value = value
                            spin_widget:update()
                        end,
                    }
                    UIManager:show(spin_widget)
                end,
            },
            {
                text_func = function()
                    return T(_("Minimum progress bar width: %1\xE2\x80\xAF%"), self.settings.progress_bar_min_width_pct) -- U+202F NARROW NO-BREAK SPACE
                end,
                enabled_func = function()
                    return self.settings.progress_bar_position == "alongside" and not self.settings.disable_progress_bar
                        and self.settings.all_at_once
                end,
                callback = function(touchmenu_instance)
                    local items = SpinWidget:new{
                        value = self.settings.progress_bar_min_width_pct,
                        value_min = 5,
                        value_step = 5,
                        value_hold_step = 20,
                        value_max = 50,
                        unit = "%",
                        title_text = _("Minimum progress bar width"),
                        text = _("Minimum percentage of screen width assigned to progress bar"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.progress_bar_min_width_pct = spin.value
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(items)
                end,
                keep_menu_open = true,
                separator = true,
            },
            {
                text = _("Show initial-position marker"),
                checked_func = function()
                    return self.settings.initial_marker == true
                end,
                enabled_func = function()
                    return not self.settings.disable_progress_bar
                end,
                callback = function()
                    self.settings.initial_marker = not self.settings.initial_marker
                    self.progress_bar.initial_pos_marker = self.settings.initial_marker
                    self:refreshFooter(true)
                end,
            },
            {
                text = _("Show chapter markers"),
                checked_func = function()
                    return self.settings.toc_markers == true and not self.settings.chapter_progress_bar
                end,
                enabled_func = function()
                    return not self.settings.progress_style_thin and not self.settings.chapter_progress_bar
                        and not self.settings.disable_progress_bar
                end,
                callback = function()
                    self.settings.toc_markers = not self.settings.toc_markers
                    self:setTocMarkers()
                    self:refreshFooter(true)
                end,
            },
            {
                text_func = function()
                    return T(_("Chapter marker width: %1"), self:genProgressBarChapterMarkerWidthMenuItems())
                end,
                enabled_func = function()
                    return not self.settings.progress_style_thin and not self.settings.chapter_progress_bar
                        and self.settings.toc_markers and not self.settings.disable_progress_bar
                end,
                sub_item_table = {
                    self:genProgressBarChapterMarkerWidthMenuItems(1),
                    self:genProgressBarChapterMarkerWidthMenuItems(2),
                    self:genProgressBarChapterMarkerWidthMenuItems(3),
                },
            },
        }
    })
    -- footer_items
    local footer_items = {}
    table.insert(sub_items, {
        text = _("Status bar items"),
        sub_item_table = footer_items,
    })
    table.insert(footer_items, getMinibarOption("page_progress"))
    table.insert(footer_items, getMinibarOption("pages_left_book"))
    table.insert(footer_items, getMinibarOption("time"))
    table.insert(footer_items, getMinibarOption("chapter_progress"))
    table.insert(footer_items, getMinibarOption("pages_left"))
    if Device:hasBattery() then
        table.insert(footer_items, getMinibarOption("battery"))
    end
    table.insert(footer_items, getMinibarOption("bookmark_count"))
    table.insert(footer_items, getMinibarOption("percentage"))
    table.insert(footer_items, getMinibarOption("book_time_to_read"))
    table.insert(footer_items, getMinibarOption("chapter_time_to_read"))
    if Device:hasFrontlight() then
        table.insert(footer_items, getMinibarOption("frontlight"))
    end
    if Device:hasNaturalLight() then
        table.insert(footer_items, getMinibarOption("frontlight_warmth"))
    end
    table.insert(footer_items, getMinibarOption("mem_usage"))
    if Device:hasFastWifiStatusQuery() then
        table.insert(footer_items, getMinibarOption("wifi_status"))
    end
    table.insert(footer_items, getMinibarOption("page_turning_inverted"))
    table.insert(footer_items, getMinibarOption("book_author"))
    table.insert(footer_items, getMinibarOption("book_title"))
    table.insert(footer_items, getMinibarOption("book_chapter"))
    table.insert(footer_items, getMinibarOption("custom_text"))

    -- configure footer_items
    table.insert(sub_items, {
        separator = true,
        text = _("Configure items"),
        sub_item_table = {
            {
                text = _("Arrange items in status bar"),
                separator = true,
                callback = function()
                    local item_table = {}
                    for i=1, #self.mode_index do
                        table.insert(item_table, {text = self:textOptionTitles(self.mode_index[i]), label = self.mode_index[i]})
                    end
                    local SortWidget = require("ui/widget/sortwidget")
                    local sort_item
                    sort_item = SortWidget:new{
                        title = _("Arrange items"),
                        item_table = item_table,
                        callback = function()
                            for i=1, #sort_item.item_table do
                                self.mode_index[i] = sort_item.item_table[i].label
                            end
                            self.settings.order = self.mode_index
                            self:updateFooterTextGenerator()
                            self:onUpdateFooter()
                            UIManager:setDirty(nil, "ui")
                        end
                    }
                    UIManager:show(sort_item)
                end,
            },
            getMinibarOption("all_at_once", self.updateFooterTextGenerator),
            {
                text = _("Auto refresh items"),
                help_text = _("This option allows certain items to update without needing user interaction (i.e page refresh). For example, the time item will update every minute regardless of user input."),
                checked_func = function()
                    return self.settings.auto_refresh_time == true
                end,
                callback = function()
                    self.settings.auto_refresh_time = not self.settings.auto_refresh_time
                    self:rescheduleFooterAutoRefreshIfNeeded()
                end,
            },
            {
                text = _("Hide inactive items"),
                help_text = _([[This option will hide inactive items from appearing on the status bar. For example, if the frontlight is 'off' (i.e 0 brightness), no symbols or values will be displayed until the brightness is set to a value >= 1.]]),
                enabled_func = function()
                    return self.settings.all_at_once == true
                end,
                checked_func = function()
                    return self.settings.hide_empty_generators == true
                end,
                callback = function()
                    self.settings.hide_empty_generators = not self.settings.hide_empty_generators
                    self:refreshFooter(true, true)
                end,
            },
            {
                text = _("Include current page in pages left"),
                help_text = _([[
By default, KOReader does not include the current page when calculating pages left. For example, in a book or chapter with n pages the 'pages left' item will range from 'n−1' to 0 (last page).
With this feature enabled, the current page is factored in, resulting in the count going from n to 1 instead.]]),
                enabled_func = function()
                    return self.settings.pages_left or self.settings.pages_left_book
                end,
                checked_func = function()
                    return self.settings.pages_left_includes_current_page == true
                end,
                callback = function()
                    self.settings.pages_left_includes_current_page = not self.settings.pages_left_includes_current_page
                    self:refreshFooter(true)
                end,
            },
            {
                text_func = function()
                    return T(_("Progress percentage format: %1"), self:genProgressPercentageFormatMenuItems())
                end,
                sub_item_table = {
                    self:genProgressPercentageFormatMenuItems("0"),
                    self:genProgressPercentageFormatMenuItems("1"),
                    self:genProgressPercentageFormatMenuItems("2"),
                },
                separator = true,
            },
            {
                text_func = function()
                    local font_weight = ""
                    if self.settings.text_font_bold == true then
                        font_weight = ", " .. _("bold")
                    end
                    return T(_("Item font: %1%2"), self.settings.text_font_size, font_weight)
                end,
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("Item font size: %1"), self.settings.text_font_size)
                        end,
                        callback = function(touchmenu_instance)
                            local items_font = SpinWidget:new{
                                title_text = _("Item font size"),
                                value = self.settings.text_font_size,
                                value_min = 8,
                                value_max = 36,
                                default_value = self.default_settings.text_font_size,
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    self.settings.text_font_size = spin.value
                                    self.footer_text_face = Font:getFace(self.text_font_face, self.settings.text_font_size)
                                    self.footer_text:free()
                                    self.footer_text = TextWidget:new{
                                        text = self.footer_text.text,
                                        face = self.footer_text_face,
                                        bold = self.settings.text_font_bold,
                                    }
                                    self.text_container[1] = self.footer_text
                                    self:refreshFooter(true, true)
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            }
                            UIManager:show(items_font)
                        end,
                        keep_menu_open = true,
                    },
                    {
                        text = _("Items in bold"),
                        checked_func = function()
                            return self.settings.text_font_bold == true
                        end,
                        callback = function()
                            self.settings.text_font_bold = not self.settings.text_font_bold
                            self.footer_text:free()
                            self.footer_text = TextWidget:new{
                                text = self.footer_text.text,
                                face = self.footer_text_face,
                                bold = self.settings.text_font_bold,
                            }
                            self.text_container[1] = self.footer_text
                            self:refreshFooter(true, true)
                        end,
                    },
                },
            },
            {
                text_func = function()
                    return T(_("Item symbols: %1"), self:genItemSymbolsMenuItems())
                end,
                sub_item_table = {
                    self:genItemSymbolsMenuItems("icons"),
                    self:genItemSymbolsMenuItems("letters"),
                    self:genItemSymbolsMenuItems("compact_items"),
                },
            },
            {
                text_func = function()
                    return T(_("Item separator: %1"), self:genItemSeparatorMenuItems())
                end,
                sub_item_table = {
                    self:genItemSeparatorMenuItems("bar"),
                    self:genItemSeparatorMenuItems("bullet"),
                    self:genItemSeparatorMenuItems("dot"),
                    self:genItemSeparatorMenuItems("none"),
                },
            },
            {
                text = _("Item max width"),
                sub_item_table = {
                    self:genItemMaxWidthMenuItems(_("Book-author item"),
                        _("Book-author item: %1\xE2\x80\xAF%"), "book_author_max_width_pct"), -- U+202F NARROW NO-BREAK SPACE
                    self:genItemMaxWidthMenuItems(_("Book-title item"),
                        _("Book-title item: %1\xE2\x80\xAF%"), "book_title_max_width_pct"),
                    self:genItemMaxWidthMenuItems(_("Chapter-title item"),
                        _("Chapter-title item: %1\xE2\x80\xAF%"), "book_chapter_max_width_pct"),
                },
            },
            {
                text_func = function()
                    return T(_("Alignment: %1"), self:genAlignmentMenuItems())
                end,
                enabled_func = function()
                    return self.settings.disable_progress_bar or self.settings.progress_bar_position ~= "alongside"
                end,
                sub_item_table = {
                    self:genAlignmentMenuItems("left"),
                    self:genAlignmentMenuItems("center"),
                    self:genAlignmentMenuItems("right"),
                },
            },
            {
                text_func = function()
                    return T(_("Height: %1"), self.settings.container_height)
                end,
                callback = function(touchmenu_instance)
                    local spin_widget = SpinWidget:new{
                        value = self.settings.container_height,
                        value_min = 7,
                        value_max = 98,
                        default_value = self.default_settings.container_height,
                        title_text = _("Items container height"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.container_height = spin.value
                            self.height = Screen:scaleBySize(self.settings.container_height)
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(spin_widget)
                end,
                keep_menu_open = true,
            },
            {
                text_func = function()
                    return T(_("Bottom margin: %1"), self.settings.container_bottom_padding)
                end,
                callback = function(touchmenu_instance)
                    local spin_widget = SpinWidget:new{
                        value = self.settings.container_bottom_padding,
                        value_min = 0,
                        value_max = 49,
                        default_value = self.default_settings.container_bottom_padding,
                        title_text = _("Container bottom margin"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.container_bottom_padding = spin.value
                            self.bottom_padding = Screen:scaleBySize(self.settings.container_bottom_padding)
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(spin_widget)
                end,
                keep_menu_open = true,
            },
           {
                text_func = function()
                    return T(_("Adjust margin top: %1"), self.settings.top_padding)
                end,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local top_padding = self.settings.top_padding
                    local items_font = SpinWidget:new{
                        value = top_padding,
                        value_min = 0,
                        value_max = 100,
                        default_value = 5,
                        ok_text = _("Set margin"),
                        title_text = _("Top bar margin"),
                        keep_shown_on_apply = true,
                        callback = function(spin)
                            self.settings.top_padding = spin.value
                            if not self.settings.top_padding then
                                self.top_padding = Screen:scaleBySize(self.settings.top_padding)
                            else
                                self.top_padding = Screen:scaleBySize(5)
                            end
                            self:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    }
                    UIManager:show(items_font)
                end,
                keep_menu_open = true,
            },
        }
    })
    local configure_items_sub_table = sub_items[#sub_items].sub_item_table -- will pick the last item of sub_items
    if Device:hasBattery() then
        table.insert(configure_items_sub_table, 5, {
            text_func = function()
                if self.settings.battery_hide_threshold <= self.default_settings.battery_hide_threshold then
                    return T(_("Hide battery item when higher than: %1\xE2\x80\xAF%"), self.settings.battery_hide_threshold) -- U+202F NARROW NO-BREAK SPACE
                else
                    return _("Hide battery item at custom threshold")
                end
            end,
            checked_func = function()
                return self.settings.battery_hide_threshold <= self.default_settings.battery_hide_threshold
            end,
            enabled_func = function()
                return self.settings.all_at_once == true
            end,
            callback = function(touchmenu_instance)
                local max_pct = self.default_settings.battery_hide_threshold
                local battery_threshold = SpinWidget:new{
                    value = math.min(self.settings.battery_hide_threshold, max_pct),
                    value_min = 0,
                    value_max = max_pct,
                    default_value = max_pct,
                    unit = "%",
                    value_hold_step = 10,
                    title_text = _("Minimum threshold to hide battery item"),
                    callback = function(spin)
                        self.settings.battery_hide_threshold = spin.value
                        self:refreshFooter(true, true)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    extra_text = _("Disable"),
                    extra_callback = function()
                        self.settings.battery_hide_threshold = max_pct + 1
                        self:refreshFooter(true, true)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                    ok_always_enabled = true,
                }
                UIManager:show(battery_threshold)
            end,
            keep_menu_open = true,
            separator = true,
        })
    end
    table.insert(sub_items, {
        text = _("Show status bar separator"),
        checked_func = function()
            return self.settings.bottom_horizontal_separator == true
        end,
        callback = function()
            self.settings.bottom_horizontal_separator = not self.settings.bottom_horizontal_separator
            self:refreshFooter(true, true)
        end,
    })
    if Device:isTouchDevice() then
        table.insert(sub_items, getMinibarOption("reclaim_height"))
        table.insert(sub_items, {
            text = _("Lock status bar"),
            checked_func = function()
                return self.settings.lock_tap == true
            end,
            callback = function()
                self.settings.lock_tap = not self.settings.lock_tap
            end,
        })
        table.insert(sub_items, {
            text = _("Long-press on status bar to skim"),
            checked_func = function()
                return self.settings.skim_widget_on_hold == true
            end,
            callback = function()
                self.settings.skim_widget_on_hold = not self.settings.skim_widget_on_hold
            end,
        })
    end
end

-- settings menu item generators

function ReaderFooter:genProgressBarPositionMenuItems(value)
    local strings = {
        above     = _("Above items"),
        alongside = _("Alongside items"),
        below     = _("Below items"),
    }
    if value == nil then
        return strings[self.settings.progress_bar_position]:lower()
    end
    return {
        text = strings[value],
        checked_func = function()
            return self.settings.progress_bar_position == value
        end,
        callback = function()
            if value == "alongside" then
                -- Text alignment is disabled in this mode
                self.settings.align = "center"
            end
            self.settings.progress_bar_position = value
            self:refreshFooter(true, true)
        end,
    }
end

function ReaderFooter:genProgressBarChapterMarkerWidthMenuItems(value)
    local strings = {
        _("Thin"),
        _("Medium"),
        _("Thick"),
    }
    if value == nil then
        return strings[self.settings.toc_markers_width]:lower()
    end
    return {
        text = strings[value],
        checked_func = function()
            return self.settings.toc_markers_width == value
        end,
        callback = function()
            self.settings.toc_markers_width = value -- unscaled_size_check: ignore
            self:setTocMarkers()
            self:refreshFooter(true)
        end,
    }
end

function ReaderFooter:genProgressPercentageFormatMenuItems(value)
    local strings = {
        ["0"] = _("No decimal places (%1)"),
        ["1"] = _("1 decimal place (%1)"),
        ["2"] = _("2 decimal places (%1)"),
    }
    local progressPercentage = function(digits)
        local symbol_type = self.settings.item_prefix
        local prefix = symbol_prefix[symbol_type].percentage
        local string_percentage = "%." .. digits .. "f%%"
        if prefix then
            string_percentage = prefix .. " " .. string_percentage
        end
        return string_percentage:format(self:getBookProgress() * 100)
    end
    if value == nil then
        return progressPercentage(self.settings.progress_pct_format)
    end
    return {
        text_func = function()
            return T(strings[value], progressPercentage(value))
        end,
        checked_func = function()
            return self.settings.progress_pct_format == value
        end,
        callback = function()
            self.settings.progress_pct_format = value
            self:refreshFooter(true)
        end,
    }
end

function ReaderFooter:genItemSymbolsMenuItems(value)
    local strings = {
        icons         = C_("Status bar", "Icons"),
        letters       = C_("Status bar", "Letters"),
        compact_items = C_("Status bar", "Compact"),
    }
    if value == nil then
        return strings[self.settings.item_prefix]:lower()
    end
    return {
        text_func = function()
            local sym_tbl = {}
            for _, letter in pairs(symbol_prefix[value]) do
                table.insert(sym_tbl, letter)
            end
            return T("%1 (%2)", strings[value], table.concat(sym_tbl, " "))
        end,
        checked_func = function()
            return self.settings.item_prefix == value
        end,
        callback = function()
            self.settings.item_prefix = value
            self:refreshFooter(true)
        end,
    }
end

function ReaderFooter:genItemSeparatorMenuItems(value)
    local strings = {
        bar    = _("Vertical bar (|)"),
        bullet = _("Bullet (•)"),
        dot    = _("Dot (·)"),
        none   = _("No separator"),
    }
    if value == nil then
        return strings[self.settings.items_separator]:lower()
    end
    return {
        text = strings[value],
        checked_func = function()
            return self.settings.items_separator == value
        end,
        callback = function()
            self.settings.items_separator = value
            self:refreshFooter(true)
        end,
    }
end

function ReaderFooter:genItemMaxWidthMenuItems(title_text, item_text, setting)
    return {
        text_func = function()
            return T(item_text, self.settings[setting])
        end,
        callback = function(touchmenu_instance)
            local spin_widget = SpinWidget:new{
                title_text = title_text,
                info_text = _("Maximum percentage of screen width used for the item"),
                value = self.settings[setting],
                value_min = 10,
                value_max = 100,
                value_step = 5,
                value_hold_step = 20,
                unit = "%",
                default_value = self.default_settings[setting],
                keep_shown_on_apply = true,
                callback = function(spin)
                    self.settings[setting] = spin.value
                    self:refreshFooter(true, true)
                    touchmenu_instance:updateItems()
                end
            }
            UIManager:show(spin_widget)
        end,
        keep_menu_open = true,
    }
end

function ReaderFooter:genAlignmentMenuItems(value)
    local strings = {
        left   = _("Left"),
        center = _("Center"),
        right  = _("Right"),
    }
    if value == nil then
        return strings[self.settings.align]:lower()
    end
    return {
        text = strings[value],
        checked_func = function()
            return self.settings.align == value
        end,
        callback = function()
            self.settings.align = value
            self:refreshFooter(true)
        end,
    }
end

function ReaderFooter:addAdditionalFooterContent(content_func)
    table.insert(self.additional_footer_content, content_func)
end

function ReaderFooter:removeAdditionalFooterContent(content_func)
    for i, v in ipairs(self.additional_footer_content) do
        if v == content_func then
            table.remove(self.additional_footer_content, i)
            return true
        end
    end
end

-- this method will be updated at runtime based on user setting
function ReaderFooter:genFooterText() end

function ReaderFooter:getFittedText(text, max_width_pct)
    if text == nil or text == "" then
        return ""
    end
    local text_widget = TextWidget:new{
        text = text:gsub(" ", "\u{00A0}"), -- no-break-space
        max_width = self._saved_screen_width * max_width_pct * (1/100),
        face = self.footer_text_face,
        bold = self.settings.text_font_bold,
    }
    local fitted_text, add_ellipsis = text_widget:getFittedText()
    text_widget:free()
    if add_ellipsis then
        fitted_text = fitted_text .. "…"
    end
    return BD.auto(fitted_text)
end

function ReaderFooter:genSeparator()
    local strings = {
        bar    = " | ",
        bullet = " • ",
        dot    = " · ",
    }
    return strings[self.settings.items_separator]
        or (self.settings.item_prefix == "compact_items" and " " or "  ")
end

function ReaderFooter:genAllFooterText()
    local info = {}
    -- We need to BD.wrap() all items and separators, so we're
    -- sure they are laid out in our order (reversed in RTL),
    -- without ordering by the RTL Bidi algorithm.
    local prev_had_merge
    for _, gen in ipairs(self.footerTextGenerators) do
        -- Skip empty generators, so they don't generate bogus separators
        local text, merge = gen(self)
        if text and text ~= "" then
            if self.settings.item_prefix == "compact_items" then
                -- remove whitespace from footer items if symbol_type is compact_items
                -- use a hair-space to avoid issues with RTL display
                text = text:gsub("%s", "\u{200A}")
            end
            -- if generator request a merge of this item, add it directly,
            -- i.e. no separator before and after the text then.
            if merge then
                local merge_pos = #info == 0 and 1 or #info
                info[merge_pos] = (info[merge_pos] or "") .. text
                prev_had_merge = true
            elseif prev_had_merge then
                info[#info] = info[#info] .. text
                prev_had_merge = false
            else
                table.insert(info, BD.wrap(text))
            end
        end
    end
    return table.concat(info, BD.wrap(self:genSeparator()))
end

function ReaderFooter:setTocMarkers(reset)
    if self.settings.disable_progress_bar or self.settings.progress_style_thin then return end
    if reset then
        self.progress_bar.ticks = nil
        self.pages = self.ui.document:getPageCount()
    end
    if self.settings.toc_markers and not self.settings.chapter_progress_bar then
        self.progress_bar.tick_width = Screen:scaleBySize(self.settings.toc_markers_width)
        if self.progress_bar.ticks ~= nil then -- already computed
            return
        end
        if self.ui.document:hasHiddenFlows() and self.pageno then
            local flow = self.ui.document:getPageFlow(self.pageno)
            self.progress_bar.ticks = {}
            if self.ui.toc then
                -- filter the ticks to show only those in the current flow
                for n, pageno in ipairs(self.ui.toc:getTocTicksFlattened()) do
                    if self.ui.document:getPageFlow(pageno) == flow then
                        table.insert(self.progress_bar.ticks, self.ui.document:getPageNumberInFlow(pageno))
                    end
                end
            end
            self.progress_bar.last = self.ui.document:getTotalPagesInFlow(flow)
        else
            if self.ui.toc then
                self.progress_bar.ticks = self.ui.toc:getTocTicksFlattened()
            end
            if self.view.view_mode == "page" then
                self.progress_bar.last = self.pages or self.ui.document:getPageCount()
            else
                -- in scroll mode, convert pages to positions
                if self.ui.toc then
                    self.progress_bar.ticks = {}
                    for n, pageno in ipairs(self.ui.toc:getTocTicksFlattened()) do
                        local idx = self.ui.toc:getTocIndexByPage(pageno)
                        local pos = self.ui.document:getPosFromXPointer(self.ui.toc.toc[idx].xpointer)
                        table.insert(self.progress_bar.ticks, pos)
                    end
                end
                self.progress_bar.last = self.doc_height or self.ui.document.info.doc_height
            end
        end
    else
        self.progress_bar.ticks = nil
    end
    -- notify caller that UI needs update
    return true
end

-- This is implemented by the Statistics plugin
function ReaderFooter:getAvgTimePerPage() end

function ReaderFooter:getDataFromStatistics(title, pages)
    local sec = _("N/A")
    local average_time_per_page = self:getAvgTimePerPage()
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    if average_time_per_page then
        sec = datetime.secondsToClockDuration(user_duration_format, pages * average_time_per_page, true)
    end
    return title .. sec
end

function ReaderFooter:onUpdateFooter(force_repaint, full_repaint)
    if self.pageno then
        self:updateFooterPage(force_repaint, full_repaint)
    else
        self:updateFooterPos(force_repaint, full_repaint)
    end
end

function ReaderFooter:updateFooterPage(force_repaint, full_repaint)
    if type(self.pageno) ~= "number" then return end
    if self.settings.chapter_progress_bar then
        if self.progress_bar.initial_pos_marker then
            if self.ui.toc:getNextChapter(self.pageno) == self.ui.toc:getNextChapter(self.initial_pageno) then
                self.progress_bar.initial_percentage = self:getChapterProgress(true, self.initial_pageno)
            else -- initial position is not in the current chapter
                self.progress_bar.initial_percentage = -1 -- do not draw initial position marker
            end
        end
        self.progress_bar:setPercentage(self:getChapterProgress(true))
    else
        self.progress_bar:setPercentage(self:getBookProgress())
    end

    -- If the footer is on top we want to repaint it always, otherwise it will be double-painted
    -- in certain circumstances like when changing bright or selecting a new typography configuration
    --if self.settings.bar_top then
    --    self:updateFooterText(true, true)
    --else
    --    self:updateFooterText(force_repaint, full_repaint)
    --end

    -- Full repaint always, otherwise, the status bar always covers the topbar side text which
    -- was made visible recently
    self:updateFooterText(force_repaint, true)
end

function ReaderFooter:updateFooterPos(force_repaint, full_repaint)
    if type(self.position) ~= "number" then return end
    if self.settings.chapter_progress_bar then
        if self.progress_bar.initial_pos_marker then
            if self.pageno and (self.ui.toc:getNextChapter(self.pageno) == self.ui.toc:getNextChapter(self.initial_pageno)) then
                self.progress_bar.initial_percentage = self:getChapterProgress(true, self.initial_pageno)
            else
                self.progress_bar.initial_percentage = -1
            end
        end
        self.progress_bar:setPercentage(self:getChapterProgress(true))
    else
        self.progress_bar:setPercentage(self.position / self.doc_height)
    end
    self:updateFooterText(force_repaint, full_repaint)
end

-- updateFooterText will start as a noop. After onReaderReady event is
-- received, it will initialized as _updateFooterText below
function ReaderFooter:updateFooterText(force_repaint, full_repaint)
end

-- only call this function after document is fully loaded
function ReaderFooter:_updateFooterText(force_repaint, full_repaint)
    -- footer is invisible, we need neither a repaint nor a recompute, go away.
    if not self.view.footer_visible and not force_repaint and not full_repaint then
        return
    end

    local text = self:genFooterText() or ""
    for _, v in ipairs(self.additional_footer_content) do
        local value = v()
        if value and value ~= "" then
            text = text == "" and value or value .. self:genSeparator() .. text
        end
    end
    self.footer_text:setText(text)

    if self.settings.disable_progress_bar then
        if self.has_no_mode or text == "" then
            self.text_width = 0
            self.footer_text.height = 0
        else
            -- No progress bar, we're only constrained to fit inside self.footer_container
            self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - 2 * self.horizontal_margin))
            self.text_width = self.footer_text:getSize().w
            self.footer_text.height = self.footer_text:getSize().h
        end
        self.progress_bar.height = 0
        self.progress_bar.width = 0
    elseif self.settings.progress_bar_position ~= "alongside" then
        local margins_width = 2 * Screen:scaleBySize(self.settings.progress_margin_width)
        if self.has_no_mode or text == "" then
            self.text_width = 0
            self.footer_text.height = 0
        else
            -- With a progress bar above or below us, we want to align ourselves to the bar's margins... iff text is centered.
            if self.settings.align == "center" then
                self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - margins_width))
            else
                -- Otherwise, we have to constrain ourselves to the container, or weird shit happens.
                self.footer_text:setMaxWidth(math.floor(self._saved_screen_width - 2 * self.horizontal_margin))
            end
            self.text_width = self.footer_text:getSize().w
            self.footer_text.height = self.footer_text:getSize().h
        end
        self.progress_bar.width = math.floor(self._saved_screen_width - margins_width)
    else
        local margins_width = 2 * Screen:scaleBySize(self.settings.progress_margin_width)
        if self.has_no_mode or text == "" then
            self.text_width = 0
            self.footer_text.height = 0
        else
            -- Alongside a progress bar, it's the bar's width plus whatever's left.
            local text_max_available_ratio = (100 - self.settings.progress_bar_min_width_pct) * (1/100)
            self.footer_text:setMaxWidth(math.floor(text_max_available_ratio * self._saved_screen_width - margins_width - self.horizontal_margin))
            -- Add some spacing between the text and the bar
            self.text_width = self.footer_text:getSize().w + self.horizontal_margin
            self.footer_text.height = self.footer_text:getSize().h
        end
        self.progress_bar.width = math.floor(self._saved_screen_width - margins_width - self.text_width)
    end

    if self.separator_line then
        self.separator_line.dimen.w = self._saved_screen_width - 2 * self.horizontal_margin
    end
    self.text_container.dimen.w = self.text_width
    self.horizontal_group:resetLayout()
    -- NOTE: This is essentially preventing us from truly using "fast" for panning,
    --       since it'll get coalesced in the "fast" panning update, upgrading it to "ui".
    -- NOTE: That's assuming using "fast" for pans was a good idea, which, it turned out, not so much ;).
    -- NOTE: We skip repaints on page turns/pos update, as that's redundant (and slow).
    if force_repaint then
        -- If there was a visibility change, notify ReaderView
        if self.visibility_change then
            self.visibility_change = nil
            self.ui:handleEvent(Event:new("ReaderFooterVisibilityChange"))
        end

        -- NOTE: Getting the dimensions of the widget is impossible without having drawn it first,
        --       so, we'll fudge it if need be...
        --       i.e., when it's no longer visible, because there's nothing to draw ;).
        local refresh_dim = self.footer_content.dimen
        -- No more content...
        if not self.view.footer_visible and not refresh_dim then
            -- So, instead, rely on self:getHeight to compute self.footer_content's height early...
            refresh_dim = self.dimen
            refresh_dim.h = self:getHeight()
            refresh_dim.y = self._saved_screen_height - refresh_dim.h
        end
        -- If we're making the footer visible (or it already is), we don't need to repaint ReaderUI behind it
        if self.view.footer_visible and not full_repaint then
            -- Unfortunately, it's not a modal (we never show() it), so it's not in the window stack,
            -- instead, it's baked inside ReaderUI, so it gets slightly trickier...
            -- NOTE: self.view.footer -> self ;).

            -- c.f., ReaderView:paintTo()
            UIManager:widgetRepaint(self.view.footer, 0, 0)
            -- We've painted it first to ensure self.footer_content.dimen is sane
            UIManager:setDirty(nil, function()
                return self.view.currently_scrolling and "fast" or "ui", self.footer_content.dimen
            end)
        else
            -- If the footer is invisible or might be hidden behind another widget, we need to repaint the full ReaderUI stack.
            UIManager:setDirty(self.view.dialog, function()
                return self.view.currently_scrolling and "fast" or "ui", refresh_dim
            end)
        end
    end
end

-- Note: no need for :onDocumentRerendered(), ReaderToc will catch "DocumentRerendered"
-- and will then emit a "TocReset" after the new ToC is made.
function ReaderFooter:onTocReset()
    self:setTocMarkers(true)
    if self.view.view_mode == "page" then
        self:updateFooterPage()
    else
        self:updateFooterPos()
    end
end

function ReaderFooter:checkNewDay()
    -- Put this code here, before topbar event and works even footer off
    local now_t = os.date("*t")
    local session_started = self.ui.statistics.start_current_period
    local daysdiff = now_t.day - os.date("*t", session_started).day
    if daysdiff > 0 then
        self.ui.statistics:insertDBSessionStats()
        self.ui.statistics:insertDB()
        self.ui.statistics._initial_read_today = nil
        self.ui.statistics.start_current_period = os.time()
        self.ui.statistics._pages_turned = 0
        self.ui.statistics._total_pages = 0
        self.ui.statistics._total_words  = 0
        local topbar = self.ui.view[4]
        if topbar then
            topbar.initial_read_today, topbar.initial_read_month, topbar.initial_total_time_book, topbar.avg_wpm  = topbar:getReadTodayThisMonth(topbar.title)
            topbar.start_session_time = os.time()
            topbar.init_page = nil
            topbar.init_page_screens = nil
        end
    end
end

function ReaderFooter:onPageUpdate(pageno)
    local toc_markers_update = false
    self:checkNewDay()
    if self.ui.document:hasHiddenFlows() then
        local flow = self.pageno and self.ui.document:getPageFlow(self.pageno)
        local new_flow = pageno and self.ui.document:getPageFlow(pageno)
        if pageno and new_flow ~= flow then
            toc_markers_update = true
        end
    end
    self.pageno = pageno
    if not self.initial_pageno then
        self.initial_pageno = pageno
    end
    self.pages = self.ui.document:getPageCount()
    if toc_markers_update then
        self:setTocMarkers(true)
    end
    self.ui.doc_settings:saveSetting("doc_pages", self.pages) -- for Book information
    -- This is called now in the onPageUpdate() event handler function of the statistic plugins main.lua source
    -- self:updateFooterPage()
end

function ReaderFooter:onPosUpdate(pos, pageno)
    self.position = pos
    self.doc_height = self.ui.document.info.doc_height
    if pageno then
        self.pageno = pageno
        if not self.initial_pageno then
            self.initial_pageno = pageno
        end
        self.pages = self.ui.document:getPageCount()
        self.ui.doc_settings:saveSetting("doc_pages", self.pages) -- for Book information
    end
    self:updateFooterPos()
end

function ReaderFooter:onReaderReady()
    self.ui.menu:registerToMainMenu(self)
    self:setupTouchZones()
    if self.settings.progress_margin then -- progress bar margins same as book margins
        if self.ui.paging then -- enforce default static margins
            self.settings.progress_margin_width = self.default_settings.progress_margin_width
        else -- current book margins
            local h_margins = self.ui.document.configurable.h_page_margins
            self.settings.progress_margin_width = math.floor((h_margins[1] + h_margins[2])/2)
        end
        self:updateFooterContainer()
    end
    self:resetLayout(self.settings.progress_margin) -- set widget dimen
    self:setTocMarkers()
    self.updateFooterText = self._updateFooterText
    self:onUpdateFooter()
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:applyFooterMode(mode)
    if mode ~= nil then self.mode = mode end
    local prev_visible_state = self.view.footer_visible
    self.view.footer_visible = (self.mode ~= self.mode_list.off)

    -- NOTE: _updateFooterText won't actually run the text generator(s) when hidden ;).

    -- We're hidden, disable text generation entirely
    if not self.view.footer_visible then
        self.genFooterText = footerTextGeneratorMap.empty
    else
        if self.settings.all_at_once then
            -- If all-at-once is enabled, we only have toggle from empty to All.
            self.genFooterText = self.genAllFooterText
        else
            -- Otherwise, switch to the right text generator for the new mode
            local mode_name = self.mode_index[self.mode]
            if not self.settings[mode_name] or self.has_no_mode then
                -- all modes disabled, only show progress bar
                mode_name = "empty"
            end
            self.genFooterText = footerTextGeneratorMap[mode_name]
        end
    end

    -- If we changed visibility state at runtime (as opposed to during init), better make sure the layout has been reset...
    if prev_visible_state ~= nil and self.view.footer_visible ~= prev_visible_state then
        self:updateFooterContainer()
        -- NOTE: _updateFooterText does a resetLayout, but not a forced one!
        self:resetLayout(true)
        -- Flag _updateFooterText to notify ReaderView to recalculate the visible_area!
        self.visibility_change = true
    end
end

function ReaderFooter:onEnterFlippingMode()
    self.orig_mode = self.mode
    self:applyFooterMode(self.mode_list.page_progress)
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onExitFlippingMode()
    self:applyFooterMode(self.orig_mode)
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:TapFooter(ges)
    if self.view.flipping_visible and ges then
        local pos = ges.pos
        local dimen = self.progress_bar.dimen
        -- if reader footer is not drawn before the dimen value should be nil
        if dimen then
            local percentage = (pos.x - dimen.x)/dimen.w
            self.ui:handleEvent(Event:new("GotoPercentage", percentage))
        end
        self:onUpdateFooter(true)
        return true
    end
    if self.settings.lock_tap then return end
    return self:onToggleFooterMode()
end

function ReaderFooter:onToggleFooterMode()
    if self.has_no_mode and self.settings.disable_progress_bar then return end
    if self.settings.all_at_once or self.has_no_mode then
        if self.mode >= 1 then
            --self.ui.view[4]:showTopBar()
            self.ui.view[4].status_bar = false
            self.mode = self.mode_list.off
        else
            --self.ui.view[4]:hideTopBar()
            self.ui.view[4].status_bar = true
            self.mode = self.mode_list.page_progress
        end
    else
        self.mode = (self.mode + 1) % self.mode_nb
        for i, m in ipairs(self.mode_index) do
            if self.mode == self.mode_list.off then break end
            if self.mode == i then
                if self.settings[m] then
                    break
                else
                    self.mode = (self.mode + 1) % self.mode_nb
                end
            end
        end
    end
    self:applyFooterMode()
    G_reader_settings:saveSetting("reader_footer_mode", self.mode)
    --self:onUpdateFooter(true)
    self:refreshFooter(true, true)
    self:rescheduleFooterAutoRefreshIfNeeded()
    return true
end

function ReaderFooter:onToggleChapterProgressBar()
    self.settings.chapter_progress_bar = not self.settings.chapter_progress_bar
    self:setTocMarkers()
    if self.progress_bar.initial_pos_marker and not self.settings.chapter_progress_bar then
        self.progress_bar.initial_percentage = self.initial_pageno / self.pages
    end
    self:refreshFooter(true)
end

function ReaderFooter:getBookProgress()
    if self.ui.document:hasHiddenFlows() then
        local flow = self.ui.document:getPageFlow(self.pageno)
        local page = self.ui.document:getPageNumberInFlow(self.pageno)
        local pages = self.ui.document:getTotalPagesInFlow(flow)
        return page / pages
    end
    return self.pageno / self.pages
end

function ReaderFooter:getChapterProgress(get_percentage, pageno)
    pageno = pageno or self.pageno
    local current = self.ui.toc:getChapterPagesDone(pageno)
    -- We want a page number, not a page read count
    if current then
        current = current + 1
    else
        current = pageno
        if self.ui.document:hasHiddenFlows() then
            current = self.ui.document:getPageNumberInFlow(pageno)
        end
    end
    local total = self.ui.toc:getChapterPageCount(pageno) or self.pages
    if get_percentage then
        return current / total
    end
    return ("%d"):format(current) .. " de " .. ("%d"):format(total)
end

function ReaderFooter:onHoldFooter(ges)
    -- We're higher priority than readerhighlight_hold, so, make sure we fall through properly...
    if not self.settings.skim_widget_on_hold then
        return
    end
    if not self.view.footer_visible then
        return
    end
    if not self.footer_content.dimen or not self.footer_content.dimen:contains(ges.pos) then
        -- We held outside the footer: meep!
        return
    end

    -- We're good, make sure we stop the event from going to readerhighlight_hold
    self.ui:handleEvent(Event:new("ShowSkimtoDialog"))
    return true
end

function ReaderFooter:refreshFooter(refresh, signal)
    self:updateFooterContainer()
    self:resetLayout(true)
    -- If we signal, the event we send will trigger a full repaint anyway, so we should be able to skip this one.
    -- We *do* need to ensure we at least re-compute the footer layout, though, especially when going from visible to invisible...
    self:onUpdateFooter(refresh and not signal, refresh and signal)
    if signal then
        if self.ui.document.provider == "crengine" then
            -- This will ultimately trigger an UpdatePos, hence a ReaderUI repaint.
            self.ui:handleEvent(Event:new("SetPageBottomMargin", self.ui.document.configurable.b_page_margin))
        else
            -- No fancy chain of events outside of CRe, just ask for a ReaderUI repaint ourselves ;).
            UIManager:setDirty(self.view.dialog, "partial")
        end
    end
end

function ReaderFooter:onResume()
    -- Reset the initial marker, if any
    if self.progress_bar.initial_pos_marker then
        self.initial_pageno = self.pageno
        self.progress_bar.initial_percentage = self.progress_bar.percentage
    end

    -- Don't repaint the footer until OutOfScreenSaver if screensaver_delay is enabled...
    local screensaver_delay = G_reader_settings:readSetting("screensaver_delay")
    if screensaver_delay and screensaver_delay ~= "disable" then
        self._delayed_screensaver = true
        return
    end

    -- Maybe perform a footer repaint on resume if it was visible.
    self:maybeUpdateFooter()
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onOutOfScreenSaver()
    if not self._delayed_screensaver then
        return
    end

    self._delayed_screensaver = nil
    -- Maybe perform a footer repaint on resume if it was visible.
    self:maybeUpdateFooter()
    self:rescheduleFooterAutoRefreshIfNeeded()
end

function ReaderFooter:onSuspend()
    self:unscheduleFooterAutoRefresh()
end

function ReaderFooter:onCloseDocument()
    self:unscheduleFooterAutoRefresh()
end

-- Used by event handlers that can trip without direct UI interaction...
function ReaderFooter:maybeUpdateFooter()
    -- ...so we need to avoid stomping over unsuspecting widgets (usually, ScreenSaver).
    self:onUpdateFooter(self:shouldBeRepainted())
end

function ReaderFooter:onFrontlightStateChanged()
    self:maybeUpdateFooter()
end
ReaderFooter.onCharging    = ReaderFooter.onFrontlightStateChanged
ReaderFooter.onNotCharging = ReaderFooter.onFrontlightStateChanged

function ReaderFooter:onNetworkConnected()
    if self.settings.wifi_status then
        self:maybeUpdateFooter()
    end
end
ReaderFooter.onNetworkDisconnected = ReaderFooter.onNetworkConnected

function ReaderFooter:onSwapPageTurnButtons()
    if self.settings.page_turning_inverted then
        -- We may receive the event *before* DeviceListener, so delay this to make sure it had a chance to actually swap the settings.
        -- Also delay it further to avoid screwing with TouchMenu highlights...
        UIManager:scheduleIn(0.5, self.maybeUpdateFooter, self)
    end
end
ReaderFooter.onToggleReadingOrder = ReaderFooter.onSwapPageTurnButtons

function ReaderFooter:onSetRotationMode()
    self:updateFooterContainer()
    self:resetLayout(true)
end
ReaderFooter.onScreenResize = ReaderFooter.onSetRotationMode

function ReaderFooter:onSetPageHorizMargins(h_margins)
    if self.settings.progress_margin then
        self.settings.progress_margin_width = math.floor((h_margins[1] + h_margins[2])/2)
        self:refreshFooter(true)
    end
end

function ReaderFooter:onTimeFormatChanged()
    self:refreshFooter(true, true)
end

function ReaderFooter:onBookMetadataChanged(prop_updated)
    if prop_updated and (prop_updated.metadata_key_updated == "title" or prop_updated.metadata_key_updated == "authors") then
        self:maybeUpdateFooter()
    end
end

function ReaderFooter:onRefreshAdditionalContent()
    if #self.additional_footer_content > 0 then
        -- Can be sent an any time, so we need to be careful about the repaint/refresh
        self:maybeUpdateFooter()
    end
end

function ReaderFooter:onCloseWidget()
    self:free()
end

function ReaderFooter:onPrintChapterLeftFbink()
    local clock ="⌚ " ..  datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    local left_chapter = self.ui.toc:getChapterPagesLeft(self.pageno) or self.ui.document:getTotalPagesLeft(self.pageno)
    if self.settings.pages_left_includes_current_page then
        left_chapter = left_chapter + 1
    end

    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left_chapter .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left_chapter .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left_chapter .. "\"")
        end
        output = execute:read('*a')
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = left_chapter
        UIManager:show(Notification:new{
            text = _(tostring(text)),
        })
    end
end

function ReaderFooter:onPrintSessionDurationFbink()
    local percentage_session, pages_read_session, duration = getSessionStats(self)


    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. duration .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format  \"" .. duration .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. duration .. "\"")
        end
        output = execute:read('*a')
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = duration
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function ReaderFooter:onPrintProgressBookFbink()
    local string_percentage  = "%0.f%%"
    local percentage = string_percentage:format(self.progress_bar.percentage * 100)

    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. percentage .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. percentage .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. percentage .. "\"")
        end
        output = execute:read('*a')
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = percentage
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function ReaderFooter:onPrintClockFbink()
    local clock =  datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. clock .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \""  .. clock .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. clock .. "\"")
        end

        output = execute:read('*a')
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = clock
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function ReaderFooter:onPrintDurationChapterFbink()
    if not self.ui.toc then
        return "n/a"
    end

    local left = self.ui.toc:getChapterPagesLeft(self.pageno) or self.ui.document:getTotalPagesLeft(self.pageno)
    left = self:getDataFromStatistics("Cur: ", left)

    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)

        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. left .. "\"")
        end


        output = execute:read('*a')
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = left
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function ReaderFooter:onPrintDurationNextChapterFbink()
    if not self.ui.toc then
        return "n/a"
    end

    local sigcap = self.ui.toc:getNextChapter(self.pageno, self.toc_level)
    if sigcap == nil then
    return "n/a"
    end
    local sigcap2 = self.ui.toc:getNextChapter(sigcap + 1, self.toc_level)
    if sigcap2 == nil then
        return "n/a"
    end
    sigcap2 = self:getDataFromStatistics("Sig: ", sigcap2 - sigcap)
    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. sigcap2 .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. sigcap2 .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. sigcap2 .. "\"")
        end

        output = execute:read('*a')
        -- if Device:isKobo() then
        --     execute = io.popen("/mnt/onboard/.adds/koreader/fbink -t regular=/mnt/onboard/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1150,right=50,format " .. duration)
        -- else --Kindle
        --     execute = io.popen("/mnt/us/koreader/fbink -t regular=/mnt/us/fonts/PoorRichard-Regular.ttf,size=14,top=10,bottom=500,left=1100,right=50,format " .. duration)
        -- end
        -- output = execute:read('*a')
        -- UIManager:show(InfoMessage:new{
        --     text = T(_(output)),
        --     face = Font:getFace("myfont"),
        -- })
    else
        local text = sigcap2
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end

function ReaderFooter:onPrintWpmSessionFbink()
    local duration_raw =  math.floor(((os.time() - self.ui.statistics.start_current_period)/60)* 100) / 100
    local wpm_session,_words_session = duration_raw
    if duration_raw == 0 then
        wpm_session = 0
        words_session = 0
    else
        wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        words_session = self.ui.statistics._total_words
    end

    wpm_session  = wpm_session .. "wpm"
    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        UIManager:scheduleIn(0.5, function()
            UIManager:setDirty("all", "full")
        end)
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/koreader/fbink -f -t regular=/mnt/onboard/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. wpm_session .. "\"")
        elseif Device:isKindle() then
            execute = io.popen("/mnt/us/koreader/fbink -f -t regular=/mnt/us/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. wpm_session .. "\"")
        else --PocketBook
            execute = io.popen("/mnt/ext1/applications/koreader/fbink -f -t regular=/mnt/ext1/applications/koreader/fonts/fonts/Capita-Regular.otf,size=14,top=10,bottom=500,left=25,right=50,format \"" .. wpm_session .. "\"")
        end
        output = execute:read('*a')
    else
        local text = wpm_session
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
end



function ReaderFooter:onGetStyles()
    local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")
    if file_type == "pdf" then return end
    local css_text = self.ui.document:getDocumentFileContent("OPS/styles/stylesheet.css")
    if css_text == nil then
        css_text = self.ui.document:getDocumentFileContent("stylesheet.css")
    end

    -- Special case for resources/arthur-conan-doyle_the-hound-of-the-baskervilles.epub but no important, since div and p tags don't use classes in this document
    if css_text == nil then
        css_text = self.ui.document:getDocumentFileContent("epub/css/core.css")
    end


    local first_text = self.ui.document._document:getTextFromPositions(0, 0, 10, Screen:getHeight(), false, false)
    local html, css_files, css_selectors_offsets =
    self.ui.document._document:getHTMLFromXPointers(first_text.pos0, first_text.pos1, 0xE830, true)
    if html == nil then
        local text =  "Could not retrieve styles"
        UIManager:show(InfoMessage:new{
            text = T(_(text)),
            no_refresh_on_close = false,
            face = Font:getFace("myfont3"),
            width = math.floor(Screen:getWidth() * 0.85),
        })
        return true
    end
    local htmlw=""

    -- No puedo hacerlo con gmatch, iré línea a línea que además viene bien para extraer las clases
    -- for w in string.gmatch(html, "(<%w* class=\"%w*\">)") do
    -- for w in string.gmatch(html,"(<%w* class=\"(.-)\">)") do
    --    htmlw = htmlw .. "," .. w
    -- end
    local classes = ""
    for line in html:gmatch("[^\n]+") do
        if (line:find("^.*<body") ~= nil or line:find("^.*<p") ~= nil or line:find("^.*<div") ~= nil) and line:find("class=") ~= nil then
            htmlw = htmlw .. "," .. string.match(line, " %b<>")
            classes = classes .. "," .. string.match(line, "class=\"(.-)\"")
            if line:find("^.*<span") ~= nil and string.match(line, "<span.*>$"):match("%b<>"):find("class") ~= nil then
                htmlw = htmlw .. "," .. string.match(line, "<span.*>$"):match("%b<>")
                classes = classes .. "," .. string.match(line, "<span.*>$"):match("%b<>"):match("class=\"(.-)\"")
            end
        end
    end
    -- Algunas clases contienen el caracter -. Tenemos que escaparlo
    classes = classes:sub(2,classes:len()):gsub("%-", "%%-")
    local csss = ""
    local csss_classes = ""
    for line in classes:gmatch("[^,]+") do
        if string.find(line, " ") then
            for line2 in classes:gmatch("[^ ]+") do
                local css_class = string.match(css_text, "%." .. line2 .. " %b{}")
                if css_class ~= nil and csss:match("%." .. line2 .. " {") == nil then
                    csss = csss .. css_class .. "\n"
                    csss_classes = csss_classes .. line2 .. ","
                end
            end
        else
            -- The regex was not matching properly thr classes, matching for instance fmtx when tx
            -- We match first the initial class dot scaping it in the regex
            local css_class = string.match(css_text, "%." .. line .. " %b{}")
            if css_class ~= nil and csss:match("%." .. line .. " {") == nil then
                csss = csss .. css_class .. "\n"
                csss_classes = csss_classes .. line .. ","
            end
        end
    end
    csss_classes = csss_classes:sub(1,csss_classes:len() - 1):gsub("%%", "")
    htmlw = htmlw:sub(2,htmlw:len())

    local text =  string.char(10) .. htmlw
    .. string.char(10) .. csss_classes
    .. string.char(10) .. csss
    UIManager:show(InfoMessage:new{
        text = T(_(text)),
        no_refresh_on_close = false,
        face = Font:getFace("myfont3"),
        width = math.floor(Screen:getWidth() * 0.85),
    })
    return true
end


-- The desktop publishing point (DTP point) or PostScript point is defined as 1/72 or 0.0138 of the international inch
-- In the United States and Great Britain, the point is approximately one-seventy-second of an inch (.351 mm), or one-twelfth of a pica and is called a pica point
-- In Europe, the point is a little bigger (.376 mm) and is called a Didot point
--  1pt = 0.93575 Didot point

-- The official size is 1 Didot point = 0.3759mm.
-- Convierte a  mm y multiplica por 0.3759mm (1000/2660) para pasar a Didot points

local function convertSizeTo(px, format)
    local format_factor = 1 -- we are defaulting on mm
    -- If we remove (2660 / 1000) the result are in mm
    if format == "pt" then
        format_factor =  format_factor * (2660 / 1000) -- see https://www.wikiwand.com/en/Metric_typographic_units
    elseif format == "in" then
        format_factor = 1 / 25.4
    end

    --  Screen:scaleBySize(px) returns real pixels from the number used in KOReader after scalating it taking into account device resolution and software dpi if set
    local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI() -- use device hardcoded dpi if available
    return Screen:scaleBySize(px) / display_dpi * 25.4 * format_factor

end

function ReaderFooter:onGetTextPage()
    local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")
    if file_type == "pdf" then return end
    local cur_page = self.ui.document:getCurrentPage()
    local total_characters = 0
    -- if not Device:isPocketBook() then
    total_characters, total_words = self.ui.document:getBookCharactersCount()
    -- total_words = math.ceil(total_characters/5.7)
    -- total_pages = math.ceil(total_characters/1767)
    -- end
    local res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, false)
    -- local name, name2, height, unitheight, height2, unitheight2, indent, unitindent, indent2, unitindent2, margin, unitmargin, margin2, unitmargin2 = "","","","","","","","","","","","","",""
    local text_properties=""

    -- print(require("dump")(res))

    -- We look first in the last element in page to retrieve styles and if we don't get information we check then the first element
    if res and res.pos1 ~= ".0" then
        name, name2, height, unitheight, height2, unitheight2, indent, unitindent, indent2, unitindent2, margin, unitmargin, margin2, unitmargin2, alignment, alignment2, fontsize, unitfontsize, fontsize2, unitfontsize2 = self.ui.document:getHeight(res.pos1)

        if name == "" and res.pos0 ~= ".0"  then
            name, name2, height, unitheight, height2, unitheight2, indent, unitindent, indent2, unitindent2, margin, unitmargin, margin2, unitmargin2, alignment, alignment2, fontsize, unitfontsize, fontsize2, unitfontsize2 = self.ui.document:getHeight(res.pos0)
        end


        -- If there is not css property line-height in any style, the CREngine return a value of -2
        -- And line-height is calculated using the font metrics
        -- I explicit calculated the value in cre.cpp
        -- lua_pushnumber(L, (float) sourceNodeParent->getFont()->getHeight()/sourceNodeParent->getFont()->getSize());

        -- The tweak does not seem to work and we won't to know which em value it is being applied considering the value of the line-height
        -- coming with the font metrics
        -- and that's why the following
        -- uniheight == "Font" means no line-height.
        -- if unitheight == "Font" and self.ui.tweaks:find("Spacing between lines %(1.2em%)") then

        -- I will leaving but, the tweak for line-height works since I modified to affect div tagas as well
        if unitheight == "Font" then
            height = height * self.ui.document.configurable.line_spacing/100
            height2 = height2 * self.ui.document.configurable.line_spacing/100
        end

        if self.ui.tweaks:find("Spacing between lines %(1.2em%)") then
            unitheight = unitheight .. "*"
            unitheight2 = unitheight2 .. "*"
        end

        if self.ui.tweaks:find("Indentation on first paragraph line") then
            unitindent = unitindent .. "*"
            unitindent2 = unitindent2 .. "*"
        end

        if self.ui.tweaks:find("Ignore publisher page margins") then
            unitmargin = unitmargin .. "*"
            unitmargin2 = unitmargin2 .. "*"
        end

        if self.ui.tweaks:find("Left align most text") or self.ui.tweaks:find("Justify most text") then
            alignment = alignment .. "*"
            alignment2 = alignment2 .. "*"
        end

        if self.ui.tweaks:find("Ignore publisher font sizes") then
            unitfontsize = unitfontsize .. "*"
            unitfontsize2 = unitfontsize2 .. "*"
        end

        if name ~= "" then
            local Math = require("optmath")
            -- If p doesnt have a class with line-height and body or the container tag does,
            -- it inherits the value
            height = Math.round(height*100)/100 .. unitheight
            height2 = Math.round(height2*100)/100 .. unitheight2
            indent = Math.round(indent*100)/100 .. unitindent
            indent2 = Math.round(indent2*100)/100 .. unitindent2
            margin =  Math.round(margin*100)/100 .. unitmargin
            margin2 = Math.round(margin2*100)/100 .. unitmargin2
            -- fontsize3 = string.format("%.2fp", convertSizeTo(fontsize, "pt"))
            -- This comes always in pxs, we convert it back to pt
            -- See readerfont function onSetFontSize()
            -- local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI()
            -- fontsize3 = Math.round((72 * fontsize / display_dpi)* 10)/10 .. "pt"
            -- fontsize4 = Math.round((72 * fontsize2 / display_dpi)* 10)/10 .. "pt"
            -- fontsize =  fontsize .. unitfontsize
            -- fontsize2 = fontsize2 .. unitfontsize2
            text_properties = string.format("%-15s%-10s%-5s","Tag",name2,name) .. string.char(10)
            text_properties = text_properties .. string.format("%-15s%-10s%-5s", "Line height", height2, height) .. string.char(10)
            text_properties = text_properties .. string.format("%-15s%-10s%-5s", "Text indent", indent2, indent) .. string.char(10)
            text_properties = text_properties .. string.format("%-15s%-10s%-5s", "Margin", margin2, margin) .. string.char(10)
            text_properties = text_properties .. string.format("%-15s%-10s%-5s", "Text align", alignment, alignment2) .. string.char(10)
            -- text_properties = text_properties .. string.format("%-15s%-15s%-5s", "Font size", fontsize .. ", " .. fontsize3, fontsize2 .. ", " .. fontsize4)
        else
            text_properties = "Can't find positions to retrieve styles:" .. string.char(10)
            text_properties = text_properties .. "Pos 0: " ..  res.pos0 .. string.char(10)
            text_properties = text_properties .. "Pos 1: " .. res.pos1
        end
    end

    local title_pages = self.ui.document._document:getDocumentProps().title

    -- local title_words = 0
    -- if (title_pages:find("([0-9,]+w)") ~= nil) then
    --     title_words = title_pages:match("([0-9,]+w)"):gsub("w",""):gsub(",","")
    -- end

    local font_size = self.ui.document._document:getFontSize()
    local font_face = self.ui.document._document:getFontFace()


    local display_dpi = Device:getDeviceScreenDPI() or Screen:getDPI()


    -- local font_size_pt = math.floor((font_size * 72 / display_dpi) * 100) / 100
    -- local font_size_mm = math.floor((font_size * 25.4 / display_dpi)  * 100) / 100

    -- We have now points in the font size
    local font_size_pt =  self.ui.document.configurable.font_size
    local font_size_mm =  self.ui.document.configurable.font_size * 0.35

    -- The desktop publishing point (DTP point) or PostScript point is defined as 1/72 or 0.0138 of the international inch
    -- We have now points in the font size, converting to didot points is simple, 1 points = 0.93575007368111 didot points
    -- local font_size_pt_koreader = string.format(" (%.2fp)", convertSizeTo(self.ui.document.configurable.font_size, "pt"))
    local font_size_pt_koreader = string.format(" (%.2fp)", self.ui.document.configurable.font_size * 0.94)
    -- if Device:isKobo() or Device:isPocketBook() or Device.model == "boox" then
    --     font_size_pt = math.floor((font_size * 72 / 300) * 100) / 100
    --     font_size_mm = math.floor((font_size * 25.4 / 300)  * 100) / 100
    -- elseif Device:isAndroid() then
    --     font_size_pt = math.floor((font_size * 72 / 446) * 100) / 100
    --     font_size_mm = math.floor((font_size * 25.4 / 446)  * 100) / 100
    -- else
    --     font_size_pt = math.floor((font_size * 72 / 160) * 100) / 100
    --     font_size_mm = math.floor((font_size * 25.4 / 160)  * 100) / 100
    -- end


    local sessions, avg_wpm, avg_last_seven_days, avg_last_thirty_days, avg_last_sixty_days, avg_last_ninety_days, avg_last_hundred_and_eighty_days = getSessionsInfo(self)
    avg_wpm = math.floor(avg_wpm) .. "wpm" .. ", " .. math.floor(avg_wpm*60) .. "wph"
    local text = ""




    -- if not Device:isPocketBook() then
    text = text .. "Total pages (screens): " .. self.pages .. string.char(10) ..
    "Total pages (1767cpp): " .. self.ui.pagemap:getLastPageLabel(true) .. string.char(10) ..

    --"Total pages assuming 1767 cpp: " .. tostring(total_pages) .. string.char(10) ..
    "Total characters: " .. tostring(total_characters) .. string.char(10) ..
    "Total words: " .. tostring(total_words) .. string.char(10) ..
    -- Dividing characters between 5.7
    "Total words (total chars/5.7): " .. tostring(math.ceil(total_characters/5.7)) .. string.char(10) -- Dividing characters between 5.7
    --"Words per screen page: " .. tostring(math.floor((total_words/self.pages * 100) / 100)) .. string.char(10)
    -- end

    --text = text .. "Total words Calibre: " .. title_words .. string.char(10) ..
    --"Words per page Calibre: " .. tostring(math.floor((title_words/self.pages * 100) / 100)) .. string.char(10) .. string.char(10) ..
    text = text .. "Total sessions in db: " .. tostring(sessions) .. string.char(10) ..
    "Average time read last 7 days: " .. avg_last_seven_days .. "h" .. string.char(10) ..
    "Average time read last 30 days: " .. avg_last_thirty_days .. "h" .. string.char(10) ..
    "Average time read last 60 days: " .. avg_last_sixty_days .. "h" .. string.char(10) ..
    "Average time read last 90 days: " .. avg_last_ninety_days .. "h" .. string.char(10) ..
    "Average time read last 180 days: " .. avg_last_hundred_and_eighty_days .. "h" .. string.char(10) ..
    "Avg wpm and wph: " .. avg_wpm .. string.char(10) .. string.char(10) ..
    "Font: " .. font_face .. ", " .. font_size_pt .. "pt" .. font_size_pt_koreader .. ", " .. font_size_mm .. "mm" .. string.char(10) ..
    "Number of tweaks: " .. self.ui.tweaks_no .. string.char(10) ..
    self.ui.tweaks .. string.char(10) ..
    text_properties
    UIManager:show(InfoMessage:new{
        text = T(_(text)),
        face = Font:getFace("myfont3"),
        width = math.floor(Screen:getWidth() * 0.7),
    })
    return true
end
function ReaderFooter:onShowTextProperties()
    if not self.ui.rolling then
        return "n/a"
    end
    if not self.ui.toc then
        return "n/a"
    end

    local res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, false)
    local nblines = 0
    if res and res.pos0 and res.pos1 then
        local segments = self.ui.document:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
        -- logger.warn(segments)
        nblines = #segments
    end
    res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, true)
    -- logger.warn(res.text)
    local nbwords = 0
    local nbcharacters = 0
    if res and res.text then
        local words = splitToWords(res.text) -- contar palabras
        local characters = res.text -- contar caracteres
        -- logger.warn(words)
        nbwords = #words -- # es equivalente a string.len()
        nbcharacters = #characters
    end
    res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), 1, false, true)
    local nbwords2 = 0
    if res and res.text then
        local words = res.text
        nbwords2 = #words
    end
    local font_size = self.ui.document._document:getFontSize()
    local font_face = self.ui.document._document:getFontFace()
    local title_pages = self.ui.document._document:getDocumentProps().title
    local author = self.ui.document._document:getDocumentProps().authors

    if author == "" then
        author = "No metadata"
    end
    if not self.ui.statistics.data.pages then
        return "n/a"
    end
    self.ui.statistics:insertDB()
    local avg_words = 0
    local avg_chars = 0
    local avg_chars_per_word = 0
    if self.ui.statistics._pages_turned > 0 then
        avg_words = math.floor(self.ui.statistics._total_words/self.ui.statistics._pages_turned)
        avg_chars = math.floor(self.ui.statistics._total_chars/self.ui.statistics._pages_turned)
        avg_chars_per_word =  math.floor((avg_chars/avg_words) * 100) / 100
    end
    local pages = self.ui.statistics.data.pages
    --  title_pages = string.match(title_pages, "%((%w+)")
    -- local title_pages_ex = string.match(title_pages, "%b()")


    -- if (title_pages_ex) then
    --     local title_words = title_pages:match("([0-9,]+w)"):gsub("w",""):gsub(",","")
    --     title_pages_ex = title_pages_ex:sub(2, title_pages_ex:len() - 1)
    -- else
    --     title_pages_ex = 0
    -- end

    local font_size_pt = nil
    local font_size_mm = nil
    if Device:isKobo() or Device:isPocketBook() or Device.model == "boox" then
        font_size_pt = math.floor((font_size * 72 / 300) * 100) / 100
        font_size_mm = math.floor((font_size * 25.4 / 300)  * 100) / 100
    elseif Device:isAndroid() then
        font_size_pt = math.floor((font_size * 72 / 446) * 100) / 100
        font_size_mm = math.floor((font_size * 25.4 / 446)  * 100) / 100
    else
        font_size_pt = math.floor((font_size * 72 / 160) * 100) / 100
        font_size_mm = math.floor((font_size * 25.4 / 160)  * 100) / 100
    end
    local chapter = self.ui.toc:getTocTitleByPage(self.pageno)
    local powerd = Device:getPowerDevice()
    local frontlight = ""
    local frontlightwarm = ""
    if powerd:isFrontlightOn() then
        local warmth = powerd:frontlightWarmth()
        if warmth then
            frontlightwarm = (" %d%%"):format(warmth)
        end
        frontlight = ("L: %d%%"):format(powerd:frontlightIntensity())
    end

  -- local css_text_body = string.match(css_text, "body %b{}")
    -- if css_text_body == nil then
    --     css_text_body = "No body style"
    -- end

    -- local css_text_calibre = string.match(css_text, "calibre %b{}")
    -- if css_text_calibre == nil then
    --     css_text_calibre = "No calibre style"
    -- end

    -- local css_text_calibre1 = string.match(css_text, "calibre1 %b{}")
    -- if css_text_calibre1 == nil then
    --     css_text_calibre1 = "No calibre1 style"
    -- end

    -- Mirar el fichero container.xml para verlo
    -- <rootfiles>
    --     <rootfile full-path="OEBPS/content.opf"
    --         media-type="application/oebps-package+xml" />
    -- </rootfiles>

    local opf_genre = ""
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

        if opf_text == nil then
            opf_genre = "No opf found"
        else
            for w in string.gmatch(opf_text, "<dc:subject>(.-)</dc:subject>") do
                opf_genre = opf_genre .. ", " .. w
            end
            opf_genre = opf_genre:sub(3,string.len(opf_genre))

            if opf_genre == "" then
                opf_genre = "No metadata"
            end
            -- local opf_calibre = string.match(opf_text, "<opf:meta property=\"calibre:user_metadata\">(.-)</opf:meta>")
            -- if opf_calibre == nil then
            --     opf_calibre = "No property"
            -- else

            --     opf_calibre = string.match(opf_calibre, "\"#genre\": {(.-)}")
            --     opf_calibre = string.match(opf_calibre, " \"#value#\": \".-\"")
            --     opf_calibre = string.match(opf_calibre, ": .*")
            --     opf_calibre = opf_calibre:sub(4,opf_calibre:len() - 1)
            -- end
        end
    end

    local spp = math.floor(self.ui.statistics.avg_time)
    local pages_read = self.ui.statistics.book_read_pages
    local time_read = self.ui.statistics.book_read_time
    -- local wpm = 0
    -- local wph = 0
    -- local wpm_test = 0
    -- if pages_read > 0 and time_read > 0 then
    --     local title_words = self.ui.document._document:getDocumentProps().title
    --     local title_words_ex = string.match(title_words, "%b()")
    --     title_words_ex = title_words_ex:sub(2, title_words_ex:len() - 1)
    --     title_words_ex = string.match(title_words_ex, "%- .*")
    --     title_words_ex = title_words_ex:sub(2,title_words_ex:len() - 1):gsub(",","")
    --     local percentage = self.progress_bar.percentage * 100
    --     wpm_test =  math.floor((title_words_ex * self.progress_bar.percentage/(time_read/60)))

    --     wpm = math.floor((pages_read * WPP)/(time_read/60))
    --     wph = math.floor((pages_read * WPP)/(time_read/60/60))
    -- end

    -- -- Extraigo la información más fácil así
    -- title_pages = self.ui.document._document:getDocumentProps().title

    -- local title_words, avg_words_cal, avg_chars_cal, avg_chars_per_word_cal = 0, 0, 0 ,0
    -- if (title_pages:find("([0-9,]+w)") ~= nil) then
    --     title_words = title_pages:match("([0-9,]+w)")
    --     avg_words_cal = math.floor(title_words:sub(1,title_words:len() - 1):gsub(",","")/pages)
    --     -- Estimated 5.7 chars per words
    --     avg_chars_cal = math.floor(avg_words_cal * 5.7)
    --     avg_chars_per_word_cal = math.floor((avg_chars_cal/avg_words_cal) * 100) / 100
    -- end


    local duration_raw =  math.floor(((os.time() - self.ui.statistics.start_current_period)/60)* 100) / 100
    local wpm_session, words_session = duration_raw, duration_raw
    if duration_raw == 0 then
        wpm_session = 0
        words_session = 0
    else
        wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        words_session = self.ui.statistics._total_words
    end

    local wph_session = wpm_session * 60

    local percentage_session, pages_read_session, duration, wpm_session, words_session, duration_raw = getSessionStats(self)
    local progress_book = ("%d de %d"):format(self.pageno, self.pages)
    local string_percentage  = "%0.f%%"
    local percentage = string_percentage:format(self.progress_bar.percentage * 100)
    local today_duration, today_pages, wpm_today, words_today = getTodayBookStats()
    local user_duration_format = "letters"
    local today_duration_number = math.floor(today_duration/60)
    local today_duration = datetime.secondsToClockDuration(user_duration_format,today_duration, true)

    local icon_goal_pages = "⚐"
    local icon_goal_time = "⚐"
    if today_pages > self._goal_pages or today_duration_number>self._goal_time then
        if today_pages >= self._goal_pages then
            icon_goal_pages = "⚑"
        end
        if today_duration_number >= self._goal_time  then
            icon_goal_time = "⚑"
        end
    end


    local this_week_duration, this_week_pages, wpm_week, words_week = getThisWeekBookStats()
    local this_month_duration, this_month_pages, wpm_month, words_month = getThisMonthBookStats()
    local time_reading_current_book = getReadThisBook(self)

    local user_duration_format = "letters"
    local this_week_duration = datetime.secondsToClockDuration(user_duration_format,this_week_duration, true)
    local this_month_duration = datetime.secondsToClockDuration(user_duration_format,this_month_duration, true)
    local time_reading_current_book = datetime.secondsToClockDuration(user_duration_format,time_reading_current_book, true)

    local left_chapter = self.ui.toc:getChapterPagesLeft(self.pageno) or self.ui.document:getTotalPagesLeft(self.pageno)
    if self.settings.pages_left_includes_current_page then
        left_chapter = left_chapter + 1
    end
    local clock ="⌚ " ..  datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

    if duration_raw == 0 then
        wpm_session = 0
        words_session = 0
    else
        wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        words_session = self.ui.statistics._total_words
    end
    percentage_session = pages_read_session/self.pages
    percentage_session = math.floor(percentage_session*1000)/10
    pages_read_session =  self.ui.statistics._total_pages

    -- local sessions, avg_wpm, avg_last_seven_days, avg_last_thirty_days = getSessionsInfo(self)
    -- avg_wpm = math.floor(avg_wpm) .. "wpm" .. ", " .. math.floor(avg_wpm*60) .. "wph"

    local line = "﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏﹏"
    local point = "‣"
    local important = " \u{261C}"


    -- .. "Avg wpm and wph in all sessions: " .. avg_wpm .. string.char(10)
    -- .. "Average time read last 7 days: " .. avg_last_seven_days .. "h" .. string.char(10)
    -- .. "Average time read last 30 days: " .. avg_last_thirty_days .. "h" .. string.char(10) .. string.char(10)
    local text = clock .. " " .. title_pages .. string.char(10) .. string.char(10)
    .. point .. " Progress book: " .. progress_book .. " (" .. percentage .. ")" ..  string.char(10)
    .. point .. " Left chapter " .. chapter .. ": " .. left_chapter  .. important .. string.char(10)
    .. line .. string.char(10)  .. string.char(10)
    .. point .. " Author: " ..  author .. string.char(10)
    .. point .. " Genres: " .. opf_genre .. string.char(10)
    -- .. opf_calibre .. string.char(10)
    .. line .. string.char(10)  .. string.char(10)
    .. point .. " RTRP out of " .. self._goal_pages .. ": " .. (self._goal_pages - today_pages) .. "p " .. icon_goal_pages .. string.char(10)
    .. point .. " RTRT out of " .. self._goal_time .. ": " .. (self._goal_time - today_duration_number) .. "m " .. icon_goal_time  .. string.char(10)
    .. point .. " This book: " .. time_reading_current_book .. string.char(10)
    .. point .. " This session: " .. duration .. "(" .. percentage_session .. "%, " .. words_session .. "w)"  .. "(" .. pages_read_session.. "p) " .. wpm_session .. "wpm" .. important .. string.char(10)
    .. point .. " Today: " .. today_duration  .. "(" .. today_pages .. "p, ".. words_today .. "w) " .. wpm_today .. "wpm" .. string.char(10)
    .. point .. " Week: " .. this_week_duration  .. "(" .. this_week_pages .. "p, ".. words_week .. "w) " .. wpm_week .. "wpm" .. string.char(10)
    .. point .. " Month: " .. this_month_duration  .. "(" .. this_month_pages .. "p, ".. words_month .. "w) " .. wpm_month .. "wpm" .. string.char(10)
    -- .. point .. " Stats: wpm: " .. wpm_session .. ", wph: " .. wph_session .. string.char(10)
    -- .. point .. " Stats: wpm: " .. wpm .. ", wph: " .. wph .. ", spp: " .. spp .. ", wpmp: " .. wpm_test .. important .. string.char(10)
    -- .. point .. " Static info (from Calibre info): wpp: " .. avg_words_cal .. ", cpp: " .. avg_chars_cal .. ", cpw: " .. avg_chars_per_word_cal .. important .. string.char(10)
    -- .. point .. " Dynamic info: p: " .. self.ui.statistics._pages_turned .. ", wpp: " .. avg_words .. ", cpp: " .. avg_chars .. ", cpw: " .. avg_chars_per_word .. string.char(10) -- Not used   .. line .. string.char(10) .. string.char(10)
    -- .. pages .. "p_" .. title_pages_ex .. string.char(10) ..  font_face .. "-" ..  "S: "
    -- .. point .. " Font parameters: " .. font_face .. ", " .. font_size .. "px, " .. font_size_pt .. "pt, " .. font_size_mm .. "mm" .. important ..  string.char(10)
    .. point .. " L: " ..  nblines .. " - W: " .. nbwords .. " - C: " .. nbcharacters .. " (CFL: " .. nbwords2 .. ")" .. important ..  string.char(10)
    .. line .. string.char(10) .. string.char(10)
    if frontlight ~= "" or frontlightwarm ~= "" then
        text = text .. point .. " Light: " .. frontlight .. " - " .. frontlightwarm .. string.char(10)
    else
        text = text .. point .. " Light off"
    end

    -- .. string.char(10) .. html:sub(100,250)


    -- self.ui.statistics._total_chars=self.ui.statistics._total_char + nbcharacters
    -- local avg_character_pages =  self.ui.statistics._total_chars/ self.ui.statistics._pages_turned
    UIManager:show(InfoMessage:new{
        text = T(_(text)),
        no_refresh_on_close = false,
        face = Font:getFace("myfont"),
        width = math.floor(Screen:getWidth() * 0.85),
    })
    return true
end

function ReaderFooter:onShowNotesFooter()
    local texto = ""
    local res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, true)
    if res and res.text then
        local annotations = self.ui.annotation.annotations
        for i, item in ipairs(annotations) do
            if item.note and res.text:find(item.text) then
                texto = texto .. '<b><p style="display:block;font-size:small;">' .. item.text .. ": </b>" ..  item.note .. "<br>"
            end
        end

        if texto ~= "" then
            -- texto = "<ol>" .. texto .. "</ol>"
            texto = '<b><p style="display:block;font-size:large;">Notes found in current page: </b><br>' .. texto
            local FootnoteWidget = require("ui/widget/footnotewidget")
            local popup
            popup = FootnoteWidget:new{
                html = texto,
                doc_font_name = self.ui.font.font_face,
                doc_font_size = Screen:scaleBySize(self.ui.document.configurable.font_size),
                doc_margins = self.ui.document:getPageMargins(),
                follow_callback = function() -- follow the link on swipe west
                    UIManager:close(popup)
                end,
                dialog = self.ui.dialog,
            }
            UIManager:show(popup)
        else
            local UIManager = require("ui/uimanager")
            local Notification = require("ui/widget/notification")
            UIManager:show(Notification:new{
                text =("No notes in current page"),
            })
        end
    end
end

function ReaderFooter:onSwitchStatusBarText()
    local text = ""
    self._show_just_toptextcontainer = not self._show_just_toptextcontainer
    if self.settings.disable_progress_bar and self.mode == 0 then
        -- text = "Status bar not on"
        -- UIManager:show(Notification:new{
        --     text = _(text),
        -- })
        -- return true
        self.view.footer_visible = true
    end

    -- if self._show_just_toptextcontainer then
    --     text = "Show just top text container. Toggle again to restore"
    --     -- self.height = Screen:scaleBySize(0) -- It was needed previously since we we were adding the text container instead of the footer container in updateFooterContainer()
    -- else
    --     text = "Status bar restored"
    --     self.height = Screen:scaleBySize(self.settings.container_height)
    -- end
    -- UIManager:show(Notification:new{
    --     text = _(text),
    --     my_height = Screen:scaleBySize(20),
    --     -- align = "left",
    --     -- timeout = 0.3,
    -- })
    UIManager:setDirty(self.dialog, "ui")
    self:refreshFooter(true, false) -- This uses _show_just_toptextcontainer
    self:onUpdateFooter(true, true) -- Importante pasar el segundo parámetro a true
    return true
end

function ReaderFooter:onMoveStatusBar()
    local text = ""
    if self.settings.bar_top then
        self.bottom_padding = self.old_bottom_padding
        --self.settings.container_bottom_padding = self.old_bottom_padding
        text = "status bar set to bottom"
        self.settings.progress_bar_position = "below"
    else
        self.old_bottom_padding = self.bottom_padding
        self.bottom_padding = 0
        --self.settings.container_bottom_padding = 0
        text = "status bar set to top"
        self.settings.progress_bar_position = "above"
    end

    self.settings.bar_top = not self.settings.bar_top
    UIManager:setDirty(self.dialog, "ui")
    if self.settings.bar_top then
        UIManager:show(Notification:new{
            text = _(text),
            -- my_height = Screen:scaleBySize(30),
            -- align = "left",
            timeout = 0.3,
        })
    else
        UIManager:show(Notification:new{
            text = _(text),
        })
    end
    self:onUpdateFooter(true)
    self:refreshFooter(true, true)
    self:rescheduleFooterAutoRefreshIfNeeded()
    return true
end

function ReaderFooter:onTest()
    local ConfirmBox = require("ui/widget/confirmbox")
    local multi_box= ConfirmBox:new{
        text = "Do you want to reload the document?",
        ok_text = "Yes",
        ok_callback = function()
            local ReaderUI = require("apps/reader/readerui")
            local ui = ReaderUI.instance
            ui:reloadDocument(nil, true) -- seamless reload (no infomsg, no flash)
            return true
        end,
    }

    UIManager:show(multi_box)
    -- -- Screen:clear()
    -- -- Screen:refreshFull(0, 0, Screen:getWidth(), Screen:getHeight())

    -- local util = require("ffi/util")
    -- -- util.usleep(20000000)


    -- local ScreenSaverWidget = require("ui/widget/screensaverwidget")
    -- local OverlapGroup = require("ui/widget/overlapgroup")
    -- local ImageWidget = require("ui/widget/imagewidget")
    -- local BookStatusWidget = require("ui/widget/bookstatuswidget")
    -- local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
    -- local widget_settings = {
    --     width = Screen:getWidth(),
    --     height = Screen:getHeight(),
    --     scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
    --     stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
    -- }
    -- local ReaderUI = require("apps/reader/readerui")
    -- local ui = ReaderUI.instance
    -- local lastfile = G_reader_settings:readSetting("screensaver_document_cover")
    -- local image = FileManagerBookInfo:getCoverImage(ui and ui.document, lastfile)
    -- widget_settings.image = image
    -- widget_settings.image_disposable = true


    -- -- if Device:isKobo() then
    -- --     widget_settings.file = "/mnt/onboard/.adds/colores.png"
    -- -- elseif Device:isPocketBook() then
    -- --     widget_settings.file = "/mnt/ext1/colores.png"
    -- -- end


    -- widget_settings.file_do_cache = false
    -- widget_settings.alpha = true


    -- local widget = ImageWidget:new(widget_settings)

    -- -- local doc = ui.document
    -- -- local doc_settings = ui.doc_settings
    -- -- widget = BookStatusWidget:new{
    -- --     thumbnail = FileManagerBookInfo:getCoverImage(doc),
    -- --     props = ui.doc_props,
    -- --     document = doc,
    -- --     settings = doc_settings,
    -- --     ui = ui,
    -- --     readonly = true,
    -- -- }

    -- local widget = OverlapGroup:new{
    --     dimen = {
    --         w = Screen:getWidth(),
    --         h = Screen:getHeight(),
    --     },
    --     widget,
    --     nil,
    -- }
    -- local screensaver_widget = ScreenSaverWidget:new{
    --     widget = widget,
    --     background = Blitbuffer.COLOR_WHITE,
    --     covers_fullscreen = true,
    -- }
    -- screensaver_widget.modal = true
    -- screensaver_widget.dithered = true

    -- UIManager:show(screensaver_widget, "full")


    -- UIManager:scheduleIn(2, function()
    --     -- Screen:refreshFullImp(0, 0, Screen:getWidth(), Screen:getHeight()) --
    --     -- UIManager:setDirty("all", "full")
    --     UIManager:close(screensaver_widget)
    -- end)
end

function ReaderFooter:onShowReadingMotive()
    -- Screen:clear()
    -- Screen:refreshFull(0, 0, Screen:getWidth(), Screen:getHeight())

    local util = require("ffi/util")
    -- util.usleep(20000000)


    local ScreenSaverWidget = require("ui/widget/screensaverwidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local ImageWidget = require("ui/widget/imagewidget")
    local BookStatusWidget = require("ui/widget/bookstatuswidget")
    local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
    local widget_settings = {
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        scale_factor = G_reader_settings:isFalse("screensaver_stretch_images") and 0 or nil,
        stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
    }

    widget_settings.image = image
    widget_settings.image_disposable = true
    widget_settings.file =  "resources/screenSaverKeepCalm.jpg"

    -- if Device:isKobo() then
    --     widget_settings.file = "/mnt/onboard/.adds/colores.png"
    -- elseif Device:isPocketBook() then
    --     widget_settings.file = "/mnt/ext1/colores.png"
    -- end


    widget_settings.file_do_cache = false
    widget_settings.alpha = true


    local widget = ImageWidget:new(widget_settings)

    -- local doc = ui.document
    -- local doc_settings = ui.doc_settings
    -- widget = BookStatusWidget:new{
    --     thumbnail = FileManagerBookInfo:getCoverImage(doc),
    --     props = ui.doc_props,
    --     document = doc,
    --     settings = doc_settings,
    --     ui = ui,
    --     readonly = true,
    -- }

    local widget = OverlapGroup:new{
        dimen = {
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        },
        widget,
        nil,
    }
    local screensaver_widget = ScreenSaverWidget:new{
        widget = widget,
        background = Blitbuffer.COLOR_WHITE,
        covers_fullscreen = true,
    }
    screensaver_widget.modal = true
    screensaver_widget.dithered = true

    UIManager:show(screensaver_widget, "full")


    UIManager:scheduleIn(0.25, function()
        -- Screen:refreshFullImp(0, 0, Screen:getWidth(), Screen:getHeight()) --
        -- UIManager:setDirty("all", "full")
        UIManager:close(screensaver_widget)
    end)
end

function ReaderFooter:onSynchronizeCode()
    local InfoMessage = require("ui/widget/infomessage")
    local rv
    local output = ""
    if not Device:isAndroid() then
        local NetworkMgr = require("ui/network/manager")
        if not NetworkMgr:isWifiOn() then
            NetworkMgr:turnOnWifiAndWaitForConnection()
        end
        local execute = nil
        if Device:isKobo() then
            execute = io.popen("/mnt/onboard/.adds/scripts/syncKOReaderCode.sh && echo $? || echo $?" )
        else --Kindle
            execute = io.popen("/mnt/us/scripts/syncKOReaderCode.sh && echo $? || echo $?" )
        end
        output = execute:read('*a')
        UIManager:show(InfoMessage:new{
            text = T(_(output)),
            face = Font:getFace("myfont"),
        })

    end
end


return ReaderFooter
