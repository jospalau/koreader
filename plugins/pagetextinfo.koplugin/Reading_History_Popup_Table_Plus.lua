--[[
Reading History Popup Table Plus
Version: 2.13.0 (cleaner look, no full-screen flashing refresh)

Notes:
- Keeps the visual layout of the user's preferred version
- Uses daily view only
- All numbers come from the table wpm_stat_data (stored sessions); '-' where a session has no data
]]--

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local LineWidget = require("ui/widget/linewidget")
local SQ3 = require("lua-ljsqlite3/init")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local gettext = require("gettext")
local ReaderUI = require("apps/reader/readerui")

local PATCH_L10N = {
    en = {
        ["DATE"] = "DATE",
        ["TIME"] = "TIME",
        ["PAGES"] = "PAGES",
        ["SPEED"] = "SPEED",
        ["DELTA"] = "ΔPROG",
        ["TOTAL"] = "TOTAL",
        ["RANGE"] = "RANGE",
        ["Days Read"] = "Days read",
        ["reading in this session"] = "reading in this session",
        ["Book total"] = "Book total",
        ["Actual reading total"] = "Actual reading",
        ["Visible period"] = "Visible period",
        ["Visible sessions"] = "Visible sessions",
        ["Daily avg"] = "Daily avg",
        ["Avg session"] = "Avg session",
        ["Med session"] = "Med session",
        ["Summary"] = "Summary",
        ["PAGES and SPEED count stable pages"] = "PAGES and SPEED count stable pages",
        ["Pages per hour"] = "Stable pages / hour",
        ["Pages per session"] = "Stable pages / session",
        ["Progress per hour"] = "Progress / hour",
        ["total"] = "total",
        ["gain"] = "gain",
        ["days"] = "days",
        ["No data"] = "No data",
        ["avg"] = "avg",
        ["min"] = "min",
        ["max"] = "max",
        ["early"] = "early",
        ["late"] = "late",
    }
}

local function l10nLookup(msg)
    local lang = "en"
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language") or "en"
    end
    local lang_base = lang:match("^([a-z]+)") or lang
    local map = PATCH_L10N[lang] or PATCH_L10N[lang_base] or PATCH_L10N.en or {}
    return map[msg]
end

local function _(msg)
    return l10nLookup(msg) or gettext(msg)
end

local stats_db_path = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local ROWS_PER_PAGE = 7
local SPEED_MIN_DURATION_SECONDS = 120
local SPEED_MIN_PAGES = 3
local _current_page = 1

-- Colours: black for what matters, grey for labels and secondary text
local COLOR_TEXT  = Blitbuffer.COLOR_BLACK
local COLOR_MUTED = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
local COLOR_RULE  = Blitbuffer.COLOR_LIGHT_GRAY

local function truncateTitle(title, max_chars)
    if not title then return "" end
    if #title > max_chars then
        return title:sub(1, max_chars - 3) .. "..."
    end
    return title
end


local function wrapTitle(title, max_chars_per_line, max_lines)
    if not title then return "" end
    max_chars_per_line = max_chars_per_line or 28
    max_lines = max_lines or 2

    local words = {}
    for w in tostring(title):gmatch("%S+") do
        table.insert(words, w)
    end
    if #words == 0 then return "" end

    local lines = {}
    local current = ""
    for _, w in ipairs(words) do
        local candidate = (current == "") and w or (current .. " " .. w)
        if #candidate <= max_chars_per_line then
            current = candidate
        else
            if current ~= "" then
                table.insert(lines, current)
            end
            current = w
            if #lines >= max_lines - 1 then
                break
            end
        end
    end
    if current ~= "" and #lines < max_lines then
        table.insert(lines, current)
    end

    local used_words = 0
    for _, line in ipairs(lines) do
        for _ in line:gmatch("%S+") do
            used_words = used_words + 1
        end
    end
    if used_words < #words and #lines > 0 then
        lines[#lines] = lines[#lines] .. "..."
    end

    return table.concat(lines, "\n")
end

local function formatDate(iso_date)
    local year, month, day = iso_date:match("(%d+)-(%d+)-(%d+)")
    if year then
        local yy = year:sub(-2)
        return string.format("%s/%s/%s", day, month, yy)
    end
    return iso_date
end

local function formatSeconds(seconds)
    if not seconds or seconds <= 0 then
        return "0m 0s"
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = math.floor(seconds % 60)
    if hours > 0 then
        return string.format("%dh %dm %ds", hours, minutes, secs)
    else
        return string.format("%dm %ds", minutes, secs)
    end
end

local function formatDurationCompact(seconds)
    if not seconds or seconds <= 0 then
        return "0m"
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
end

local function formatHoursMinutes(seconds)
    if not seconds or seconds <= 0 then
        return "0 hr 0 min"
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    return string.format("%d hr %d min", hours, minutes)
end

local function formatMinutesSeconds(seconds)
    if not seconds or seconds <= 0 then
        return "0m"
    end
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%dm %ds", minutes, secs)
end

local function formatProgressDelta(delta)
    local value = tonumber(delta)
    if not value then return "-" end
    return string.format("%+.1f%%", value * 100)
end

local function formatProgressTotal(progress)
    local value = tonumber(progress)
    if not value then return "-" end
    return string.format("%.1f%%", value * 100)
end

local function formatSpeed(pages, seconds)
    if not pages or pages < SPEED_MIN_PAGES or not seconds or seconds < SPEED_MIN_DURATION_SECONDS then
        return "-"
    end
    local pph = (pages * 3600) / seconds
    return string.format("%.0fpg/h", pph)
end

local function formatPages(pages)
    if pages == nil then return "-" end
    return string.format("%d", math.floor(pages + 0.5))
end

local function formatRange(first_page, last_page, max_page)
    if first_page == nil and last_page == nil then
        return "-"
    end
    first_page = tonumber(first_page)
    last_page = tonumber(last_page)
    max_page = tonumber(max_page)
    if max_page and max_page > 0 then
        if first_page then first_page = math.min(first_page, max_page) end
        if last_page then last_page = math.min(last_page, max_page) end
    end
    if first_page and last_page then
        if first_page == last_page then
            return tostring(first_page)
        end
        return string.format("%d-%d", first_page, last_page)
    elseif first_page then
        return tostring(first_page)
    elseif last_page then
        return tostring(last_page)
    end
    return "-"
end

local function getDB()
    return SQ3.open(stats_db_path)
end

-- ---------------------------------------------------------------------------
-- Data layer: everything comes from the table wpm_stat_data (one row per stored
-- reading session). Nothing is guessed from page_stat_data anymore.
--   duration   = wall-clock time of the session
--   read_secs  = counted reading time of the session
--   ref_pages  = stable (reference) pages read in the session  (NULL if none)
--   ref_start / ref_end = reference page at the start / end of the session
--   pct_start / pct_end = book progress in % at the start / end of the session
-- Sessions stored before those columns existed have NULLs: they show "-".
-- ---------------------------------------------------------------------------
local function getTableColumns(conn, table_name)
    local cols = {}
    local res = conn:exec("PRAGMA table_info(" .. table_name .. ");")
    if res and res.name then
        for i = 1, #res.name do
            cols[res.name[i]] = true
        end
    end
    return cols
end

-- Stored sessions of the book, oldest first.
local function loadSessions(book_id, days)
    if not book_id or not days or days <= 0 then return {} end
    local ok_open, conn = pcall(getDB)
    if not ok_open or not conn then return {} end

    local sessions = {}
    local ok = pcall(function()
        local cols = getTableColumns(conn, "wpm_stat_data")
        if not cols.start_time then return end

        local select_list = { "start_time", "date(start_time, 'unixepoch', 'localtime') AS dates" }
        local optional = { "duration", "read_secs", "total_pages", "ref_pages", "ref_start", "ref_end", "pct_start", "pct_end" }
        local present = {}
        for _i, col in ipairs(optional) do
            if cols[col] then
                table.insert(select_list, col)
                table.insert(present, col)
            end
        end

        local sql = string.format([[
            SELECT %s
            FROM wpm_stat_data
            WHERE id_book = %d
              AND date(start_time, 'unixepoch', 'localtime') >= date('now', '-' || %d || ' days')
            ORDER BY start_time ASC;
        ]], table.concat(select_list, ", "), book_id, days)

        local results = conn:exec(sql)
        if not results or not results.start_time then return end

        local function num(col, i)
            local values = results[col]
            if not values then return nil end
            return tonumber(values[i])
        end

        for i = 1, #results.start_time do
            local pct_start = num("pct_start", i)
            local pct_end = num("pct_end", i)
            local delta
            if pct_start and pct_end then
                delta = (pct_end - pct_start) / 100
            end
            table.insert(sessions, {
                start_time = tonumber(results.start_time[i]) or 0,
                date = results.dates[i],
                duration = num("duration", i) or 0,
                read_secs = num("read_secs", i),
                screens = num("total_pages", i),
                pages = num("ref_pages", i),
                first_page = num("ref_start", i),
                last_page = num("ref_end", i),
                progress = pct_end and (pct_end / 100) or nil,
                delta_progress = delta,
            })
        end
    end)
    conn:close()
    if not ok then return {} end
    return sessions
end

-- Sessions grouped by day, newest day first.
local function buildDailyStats(sessions)
    local by_date, order = {}, {}
    for _i, s in ipairs(sessions or {}) do
        local day = by_date[s.date]
        if not day then
            day = {
                date = s.date,
                duration = 0,
                read_secs = 0,
                pages = nil,
                first_page = nil,
                last_page = nil,
                progress = nil,
                delta_progress = nil,
                delta_duration = 0,
                speed_pages = 0,
                speed_secs = 0,
                sessions = 0,
            }
            by_date[s.date] = day
            table.insert(order, day)
        end
        day.sessions = day.sessions + 1
        day.duration = day.duration + (s.duration or 0)
        day.read_secs = day.read_secs + (s.read_secs or 0)
        if s.pages then
            day.pages = (day.pages or 0) + s.pages
            if s.read_secs and s.read_secs > 0 then
                day.speed_pages = day.speed_pages + s.pages
                day.speed_secs = day.speed_secs + s.read_secs
            end
        end
        if day.first_page == nil then day.first_page = s.first_page end
        if s.last_page ~= nil then day.last_page = s.last_page end
        if s.progress ~= nil then day.progress = s.progress end
        if s.delta_progress ~= nil then
            day.delta_progress = (day.delta_progress or 0) + s.delta_progress
            day.delta_duration = day.delta_duration + (s.duration or 0)
        end
    end

    local out = {}
    for i = #order, 1, -1 do
        table.insert(out, order[i])
    end
    return out
end

local function getTotalDaysRead(book_id)
    if not book_id then return 0 end
    local ok_open, conn = pcall(getDB)
    if not ok_open or not conn then return 0 end
    local value = 0
    pcall(function()
        local result = conn:rowexec(string.format([[
            SELECT count(DISTINCT date(start_time, 'unixepoch', 'localtime'))
            FROM wpm_stat_data
            WHERE id_book = %d;
        ]], book_id))
        value = tonumber(result) or 0
    end)
    conn:close()
    return value
end

-- Sum of the counted reading time (read_secs) of every stored session of the book.
local function getActualReadingTotal(book_id)
    if not book_id then return 0 end
    local ok_open, conn = pcall(getDB)
    if not ok_open or not conn then return 0 end
    local value = 0
    pcall(function()
        local cols = getTableColumns(conn, "wpm_stat_data")
        if not cols.read_secs then return end
        local result = conn:rowexec(string.format([[
            SELECT COALESCE(sum(read_secs), 0)
            FROM wpm_stat_data
            WHERE id_book = %d;
        ]], book_id))
        value = tonumber(result) or 0
    end)
    conn:close()
    return value
end

local function getCurrentSessionDuration(book_id, start_current_period)
    if not book_id or not start_current_period then return 0 end
    local conn = getDB()
    if not conn then return 0 end

    local sql_stmt = [[
        SELECT count(*),
               sum(sum_duration)
        FROM (
            SELECT sum(duration) AS sum_duration
            FROM page_stat
            WHERE start_time >= %d
            GROUP BY id_book, page
        );
    ]]
    local _, current_duration = conn:rowexec(string.format(sql_stmt, start_current_period))
    conn:close()

    if current_duration == nil then
        current_duration = 0
    end
    return tonumber(current_duration) or 0
end

local function getBookTitle(ui)
    if not ui then return "" end
    local book_title = ui.doc_props and ui.doc_props.display_title or ""
    local colon_pos = book_title:find(":")
    if colon_pos then
        book_title = book_title:sub(1, colon_pos - 1)
    end
    return book_title
end

local function getBookAuthor(ui)
    if not ui or not ui.doc_props then return "" end
    local author = ui.doc_props.display_author or ui.doc_props.authors or ui.doc_props.author or ""
    if type(author) == "table" then
        author = table.concat(author, ", ")
    end
    return tostring(author)
end

local function getEffectiveTotalPages(ui)
    if not ui or not ui.document then
        return nil
    end
    local doc = ui.document

    if doc.hasHiddenFlows and doc:hasHiddenFlows()
        and ui.getCurrentPage and doc.getPageFlow and doc.getTotalPagesInFlow then
        local current_page = ui:getCurrentPage()
        if current_page then
            local flow = doc:getPageFlow(current_page)
            local flow_total = flow and doc:getTotalPagesInFlow(flow) or nil
            if flow_total and flow_total > 0 then
                return flow_total
            end
        end
    end
    if doc.getPageCount then
        return doc:getPageCount()
    end
    return nil
end

local function sumDuration(stats)
    local total = 0
    for _, row in ipairs(stats or {}) do
        total = total + (tonumber(row.duration) or 0)
    end
    return total
end

local function getDailyAverageSeconds(stats)
    local total_time = sumDuration(stats)
    local total_days = #(stats or {})
    if total_days == 0 then
        return 0
    end
    return total_time / total_days
end

local function getFilteredSessionStatsByDates(session_stats, daily_rows)
    local allowed_dates = {}
    for _, row in ipairs(daily_rows or {}) do
        if row and row.date then
            allowed_dates[row.date] = true
        end
    end

    local filtered = {}
    for _, session in ipairs(session_stats or {}) do
        if session and session.date and allowed_dates[session.date] then
            table.insert(filtered, session)
        end
    end
    return filtered
end

-- Stored sessions are already valid ones (>= 3 minutes and >= 3 counted pages),
-- so only the duration is checked here.
local function getSessionDurations(stats)
    local durations = {}
    for _, row in ipairs(stats or {}) do
        local duration = tonumber(row.duration) or 0
        if duration >= 60 then
            table.insert(durations, duration)
        end
    end
    return durations
end

local function formatAvgSessionLength(stats)
    local durations = getSessionDurations(stats)
    if #durations == 0 then
        return "-"
    end
    local total = 0
    for _, d in ipairs(durations) do total = total + d end
    return formatMinutesSeconds(total / #durations)
end

local function getMedianSessionLength(stats)
    local durations = getSessionDurations(stats)
    if #durations == 0 then
        return "-"
    end
    table.sort(durations)
    local n = #durations
    local median
    if n % 2 == 1 then
        median = durations[(n + 1) / 2]
    else
        median = (durations[n / 2] + durations[n / 2 + 1]) / 2
    end
    return formatMinutesSeconds(median)
end

-- Average stable pages per session (only sessions that have stored reference pages).
local function getPagesPerSession(stats)
    local count, total = 0, 0
    for _, row in ipairs(stats or {}) do
        if row.pages and (tonumber(row.duration) or 0) >= 60 then
            count = count + 1
            total = total + row.pages
        end
    end
    if count == 0 then
        return "-"
    end
    return string.format("%.1f", total / count)
end

-- Stable pages per hour of counted reading time (read_secs), over the sessions that have both.
local function getOverallSpeed(stats)
    local pages, secs = 0, 0
    for _, row in ipairs(stats or {}) do
        if row.pages and row.read_secs and row.read_secs > 0 then
            pages = pages + row.pages
            secs = secs + row.read_secs
        end
    end
    if pages < SPEED_MIN_PAGES or secs < SPEED_MIN_DURATION_SECONDS then
        return nil
    end
    return (pages * 3600) / secs
end

-- Book progress gained per hour (wall-clock time of the days that have stored progress).
local function getProgressEfficiency(days)
    local total_delta, total_seconds = 0, 0
    for _, day in ipairs(days or {}) do
        if day.delta_progress ~= nil then
            total_delta = total_delta + day.delta_progress
            total_seconds = total_seconds + (day.delta_duration or 0)
        end
    end
    if total_seconds <= 0 then
        return "-"
    end
    return string.format("%.2f", (total_delta * 100) / (total_seconds / 3600))
end

local function fixedCol(widget, width)
    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = widget:getSize().h },
        widget,
    }
end

local function buildRowSeparator(width)
    return LineWidget:new{
        dimen = Geom:new{ w = width, h = Size.line.thin },
        background = COLOR_RULE,
    }
end

local function buildLayout(screen_w, padding_h, column_gap)
    local col_count = 7
    local col_width = math.floor((screen_w - 2 * padding_h - (col_count - 1) * 2 * column_gap) / col_count)
    return {
        full_width = screen_w,
        padding_h = padding_h,
        column_gap = column_gap,
        col_width = col_width,
    }
end

local function buildTableHeader(fonts, layout)
    local headers = { _("DATE"), _("TIME"), _("PAGES"), _("SPEED"), _("DELTA"), _("TOTAL"), _("RANGE") }
    local header_row = HorizontalGroup:new{ align = "center" }
    for i, header_text in ipairs(headers) do
        local header_widget = TextWidget:new{ text = header_text, face = fonts.header, fgcolor = COLOR_MUTED }
        table.insert(header_row, fixedCol(header_widget, layout.col_width))
        if i < #headers then
            table.insert(header_row, HorizontalSpan:new{ width = 2 * layout.column_gap })
        end
    end
    return VerticalGroup:new{
        align = "left",
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding_top = Size.padding.small,
            padding_bottom = Size.padding.small,
            padding_left = layout.padding_h,
            padding_right = layout.padding_h,
            header_row,
        },
        LineWidget:new{
            dimen = Geom:new{ w = layout.full_width, h = Size.line.medium },
            background = COLOR_TEXT,
        },
    }
end

local function buildTableRows(stats_data, fonts, layout)
    local rows = VerticalGroup:new{ align = "left" }
    local today_iso = os.date("%Y-%m-%d")
    local highlight_latest = stats_data[1] and stats_data[1].date == today_iso
    local gap = HorizontalSpan:new{ width = 2 * layout.column_gap }
    local pad = Size.padding.small or 4
    for idx, item in ipairs(stats_data) do
        local is_today = highlight_latest and idx == 1
        local value_face = (is_today and (fonts.cell_bold or fonts.cell)) or fonts.cell
        local function cell(text, face, color)
            return fixedCol(TextWidget:new{ text = text, face = face, fgcolor = color or COLOR_TEXT }, layout.col_width)
        end

        local row = HorizontalGroup:new{
            align = "center",
            cell(formatDate(item.date), fonts.cell, COLOR_MUTED), gap,
            cell(formatDurationCompact(item.duration), value_face), gap,
            cell(item.pages and (formatPages(item.pages) .. "pg") or "-", value_face), gap,
            cell(formatSpeed(item.speed_pages, item.speed_secs), value_face), gap,
            cell(formatProgressDelta(item.delta_progress), value_face), gap,
            cell(formatProgressTotal(item.progress), fonts.cell, COLOR_MUTED), gap,
            cell(formatRange(item.first_page, item.last_page, nil), fonts.cell, COLOR_MUTED),
        }

        table.insert(rows, VerticalSpan:new{ height = pad })
        table.insert(rows, row)
        table.insert(rows, VerticalSpan:new{ height = pad })
        if idx < #stats_data then
            table.insert(rows, buildRowSeparator(layout.full_width - 2 * layout.padding_h))
        end
    end
    return rows
end

local function buildPaginationBar(fonts, layout, current_page, total_pages)
    local bar_h  = Screen:scaleBySize(44)
    local full_w = layout.full_width
    local can_prev = current_page > 1
    local can_next = current_page < total_pages
    local zone_w = math.floor(full_w / 5)
    local lbl_w  = full_w - zone_w * 4

    local function makeZone(label, enabled, w)
        return CenterContainer:new{
            dimen = Geom:new{ w = w, h = bar_h },
            TextWidget:new{
                text = label,
                face = enabled and fonts.cell or fonts.header,
            },
        }
    end

    local function makeSep()
        return LineWidget:new{
            dimen = Geom:new{ w = Size.line.thin, h = Screen:scaleBySize(24) },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        }
    end

    local page_lbl = TextWidget:new{
        text = string.format("%d / %d", current_page, total_pages),
        face = fonts.cell,
    }
    local lbl_zone = CenterContainer:new{
        dimen = Geom:new{ w = lbl_w, h = bar_h },
        page_lbl,
    }

    local bar = HorizontalGroup:new{ align = "center",
        makeZone("«", can_prev, zone_w), makeSep(),
        makeZone("‹", can_prev, zone_w), makeSep(),
        lbl_zone, makeSep(),
        makeZone("›", can_next, zone_w), makeSep(),
        makeZone("»", can_next, zone_w),
    }

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        bar,
    }

    local x0 = 0
    local x1 = zone_w
    local x2 = zone_w * 2
    local x3 = zone_w * 2 + lbl_w
    local x4 = x3 + zone_w

    local hits = {
        { enabled = can_prev, target = 1,                x_min = x0, x_max = x1 },
        { enabled = can_prev, target = current_page - 1, x_min = x1, x_max = x2 },
        { enabled = can_next, target = current_page + 1, x_min = x3, x_max = x4 },
        { enabled = can_next, target = total_pages,      x_min = x4, x_max = full_w },
    }
    return frame, hits
end


Dispatcher:registerAction("reading_history_popup_table_plus_v1", {
    category = "none",
    event = "ShowReadingHistoryPopupTablePlusV1",
    title = "ReadingStats+",
    reader = true,
})

local ReadingStatsTable = InputContainer:extend{
    modal = true,
    ui = nil,
}

function ReadingStatsTable:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    self.screen_w = screen_w
    self.screen_h = screen_h

    self.fonts = {
        header  = Font:getFace("NotoSans-Regular.ttf", 14),
        cell    = Font:getFace("NotoSans-Regular.ttf", 15),
        cell_bold = Font:getFace("NotoSans-Bold.ttf", 15),
        title   = Font:getFace("NotoSans-Regular.ttf", 18),
        title_main = Font:getFace("NotoSans-Bold.ttf", 20),
        stat_value = Font:getFace("NotoSans-Bold.ttf", 17),
        stat_label = Font:getFace("NotoSans-Regular.ttf", 12),
        title_author = Font:getFace("NotoSans-Regular.ttf", 13),
        title_meta = Font:getFace("NotoSans-Regular.ttf", 14),
        meta    = Font:getFace("NotoSans-Regular.ttf", 15),
        session = Font:getFace("NotoSans-Regular.ttf", 16),
        session_bold = Font:getFace("NotoSans-Bold.ttf", 16),
        summary = Font:getFace("NotoSans-Regular.ttf", 15),
    }

    self.layout = buildLayout(screen_w, Size.padding.default, Screen:scaleBySize(4))
    self.dimen = Geom:new{ w = screen_w, h = screen_h }
    self.stats_plugin = self.ui and self.ui.statistics
    self:buildContent()

    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            }
        }
    end
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end
end

function ReadingStatsTable:buildContent()
    if self.stats_plugin then
        self.stats_plugin:insertDB()
    end

    local book_id = self.stats_plugin and self.stats_plugin.id_curr_book
    local session_stats = loadSessions(book_id, 365)
    local daily_stats = buildDailyStats(session_stats)
    local all_stats = daily_stats

    local book_title = getBookTitle(self.ui)
    local book_author = getBookAuthor(self.ui)
    local days_read = getTotalDaysRead(book_id)

    local display_stats = all_stats

    local total_rows = #display_stats
    local total_pages = math.max(1, math.ceil(total_rows / ROWS_PER_PAGE))
    local has_pagination = total_rows > ROWS_PER_PAGE

    if _current_page > total_pages then _current_page = total_pages end
    if _current_page < 1 then _current_page = 1 end

    local page_start = (_current_page - 1) * ROWS_PER_PAGE + 1
    local page_end   = math.min(page_start + ROWS_PER_PAGE - 1, total_rows)
    local stats_data = {}
    for i = page_start, page_end do
        table.insert(stats_data, display_stats[i])
    end

    local inner_w = self.layout.full_width - 2 * self.layout.padding_h
    local fonts = self.fonts

    -- small grey label over the value, in a column of the given width
    local function statBlock(value, label, width)
        return LeftContainer:new{
            dimen = Geom:new{ w = width, h = 0 },
            VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = label, face = fonts.stat_label, fgcolor = COLOR_MUTED },
                TextWidget:new{ text = value, face = fonts.stat_value, fgcolor = COLOR_TEXT },
            },
        }
    end
    local function statRow(blocks)
        local col_w = math.floor(inner_w / #blocks)
        local row = HorizontalGroup:new{ align = "top" }
        local h = 0
        for _i, b in ipairs(blocks) do
            local w = statBlock(b[1], b[2], col_w)
            h = math.max(h, w[1]:getSize().h)
            row[#row + 1] = w
        end
        for _i, w in ipairs(row) do w.dimen.h = h end
        return row
    end

    local total_book_time = sumDuration(daily_stats)
    local actual_book_time = getActualReadingTotal(book_id)

    -- title and author
    local title = VerticalGroup:new{
        align = "left",
        TextWidget:new{
            text = wrapTitle(book_title, 28, 2),
            face = fonts.title_main, fgcolor = COLOR_TEXT,
        },
        VerticalSpan:new{ height = Size.padding.tiny or 2 },
        TextWidget:new{
            text = book_author or "",
            face = fonts.title_author, fgcolor = COLOR_MUTED,
        },
    }

    -- the book in three numbers
    local book_row = statRow{
        { string.format("%dd", days_read), _("Days Read") },
        { formatDurationCompact(total_book_time), _("Book total") },
        { formatDurationCompact(actual_book_time), _("Actual reading total") },
    }

    local all_time = sumDuration(all_stats)
    local visible_speed = "-"
    local overall_pph = getOverallSpeed(session_stats)
    if overall_pph then
        visible_speed = string.format("%.0fpg/h", overall_pph)
    end
    local daily_avg_seconds = getDailyAverageSeconds(all_stats)
    local visible_sessions = getFilteredSessionStatsByDates(session_stats, all_stats)
    local avg_session_minutes = formatAvgSessionLength(visible_sessions)
    local med_session_minutes = getMedianSessionLength(visible_sessions)
    local pages_per_session = getPagesPerSession(visible_sessions)
    local progress_efficiency = getProgressEfficiency(all_stats)

    -- habits: time per day and per session, then speed
    local habits_row = statRow{
        { formatDurationCompact(daily_avg_seconds), _("Daily avg") },
        { avg_session_minutes, _("Avg session") },
        { med_session_minutes, _("Med session") },
    }
    local speed_row = statRow{
        { visible_speed, _("Pages per hour") },
        { pages_per_session == "-" and "-" or (pages_per_session .. "pg"), _("Pages per session") },
        { progress_efficiency == "-" and "-" or (progress_efficiency .. "%/h"), _("Progress per hour") },
    }

    local stats_widget = VerticalGroup:new{
        align = "left",
        book_row,
        VerticalSpan:new{ height = Size.padding.default },
        habits_row,
        VerticalSpan:new{ height = Size.padding.default },
        speed_row,
    }

    local session_duration = getCurrentSessionDuration(
        book_id,
        self.stats_plugin and self.stats_plugin.start_current_period
    )
    if self.stats_plugin and self.stats_plugin.page_start_time then
        local live_seconds = os.time() - self.stats_plugin.page_start_time
        if live_seconds > 0 then
            session_duration = session_duration + live_seconds
        end
    end

    local session_widget = HorizontalGroup:new{
        TextWidget:new{ text = _("This session") .. "  ", face = fonts.session, fgcolor = COLOR_MUTED },
        TextWidget:new{ text = formatSeconds(session_duration), face = fonts.session_bold, fgcolor = COLOR_TEXT },
    }

    local note_widget = TextWidget:new{
        text = _("PAGES and SPEED count stable pages"),
        face = fonts.stat_label, fgcolor = COLOR_MUTED,
    }

    local summary_widget = TextWidget:new{
        text = string.format("%s: %s · %s %s · %s %s",
            _("Summary"),
            formatDurationCompact(all_time),
            formatProgressTotal((all_stats[1] and all_stats[1].progress) or 0), _("total"),
            formatProgressDelta((all_stats[1] and all_stats[1].delta_progress) or 0), _("gain")),
        face = fonts.summary, fgcolor = COLOR_MUTED,
    }

    local summary_block = VerticalGroup:new{
        align = "left",
        summary_widget,
        VerticalSpan:new{ height = Size.padding.tiny or 2 },
        note_widget,
    }

    local header = buildTableHeader(self.fonts, self.layout)
    local rows = buildTableRows(stats_data, self.fonts, self.layout)

    local table_content = VerticalGroup:new{ align = "left" }

    local function makeFrame(widget, pt, pb)
        return FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding_top = pt,
            padding_bottom = pb,
            padding_left = self.layout.padding_h,
            padding_right = self.layout.padding_h,
            widget,
        }
    end

    local title_frame = makeFrame(title, Size.padding.large or Size.padding.default, Size.padding.default)
    local stats_frame = makeFrame(stats_widget, 0, Size.padding.default)
    local session_frame = makeFrame(session_widget, Size.padding.small, Size.padding.default)
    local rows_frame = makeFrame(rows, Size.padding.small, Size.padding.small)
    local summary_frame = makeFrame(summary_block, Size.padding.default, Size.padding.default)

    table.insert(table_content, title_frame)
    table.insert(table_content, stats_frame)
    table.insert(table_content, session_frame)
    table.insert(table_content, header)
    table.insert(table_content, rows_frame)
    table.insert(table_content, summary_frame)

    local current_y = title_frame:getSize().h + stats_frame:getSize().h
        + session_frame:getSize().h + header:getSize().h + rows_frame:getSize().h + summary_frame:getSize().h

    self._chart_hit = nil

    if has_pagination then
        local sep_line = LineWidget:new{
            dimen = Geom:new{ w = self.layout.full_width, h = Size.line.thin },
            background = Blitbuffer.COLOR_LIGHT_GRAY,
        }
        local pagination_frame, hits = buildPaginationBar(self.fonts, self.layout, _current_page, total_pages)

        self._pagination_hits = hits
        self._pagination_bar_y = current_y + sep_line:getSize().h

        table.insert(table_content, sep_line)
        table.insert(table_content, pagination_frame)

        current_y = self._pagination_bar_y + pagination_frame:getSize().h
    else
        self._pagination_hits = nil
        self._pagination_bar_y = nil
    end

    local bottom_line = LineWidget:new{
        dimen = Geom:new{ w = self.layout.full_width, h = Size.line.medium },
        background = Blitbuffer.COLOR_BLACK,
    }
    table.insert(table_content, bottom_line)

    self._popup_bottom_y = current_y + bottom_line:getSize().h

    self.popup_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        radius = 0,
        padding = 0,
        width = self.screen_w,
        table_content,
    }

    self[1] = self.popup_frame
end

function ReadingStatsTable:onShow()
    -- "ui" repaints only what changed, without the black flash of a full refresh
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
    return true
end

-- Changes the page of the table in place (no close and reopen, so one single refresh)
function ReadingStatsTable:goToPage(target)
    _current_page = target
    self:buildContent()
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

function ReadingStatsTable:onTapClose(arg, ges_ev)
    if ges_ev and ges_ev.pos then
        local tx = ges_ev.pos.x
        local ty = ges_ev.pos.y

        local bar_y = self._pagination_bar_y or 0
        local popup_bot = self._popup_bottom_y or 0

        if ty <= popup_bot then
            if ty >= bar_y and self._pagination_hits then
                for _, hit in ipairs(self._pagination_hits) do
                    if hit.enabled and tx >= hit.x_min and tx <= hit.x_max then
                        self:goToPage(hit.target)
                        return true
                    end
                end
                return true
            end
            return true
        end
    end

    UIManager:close(self)
    return true
end

function ReadingStatsTable:onAnyKeyPressed()
    UIManager:close(self)
    return true
end

function ReadingStatsTable:onCloseWidget()
    UIManager:setDirty(nil, "ui")
end

function ReaderUI.onShowReadingHistoryPopupTablePlusV1(this)
    _current_page = 1
    UIManager:show(ReadingStatsTable:new{ ui = this }, "ui")
    return true
end

return ReadingStatsTable
