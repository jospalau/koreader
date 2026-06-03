local logger = require("logger")
logger.info("Applying longest sessions patch")

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local RightContainer = require("ui/widget/container/rightcontainer")
local ReaderUI = require("apps/reader/readerui")
local Screen = Device.screen
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local datetime = require("datetime")
local _ = require("gettext")

local DEVICE_NAMES = {
    [0]   = "Unknown device",
    [1]   = "Kobo Libra 2",
    [2]   = "Kobo Sage",
    [3]   = "Kobo Clara 2E",
    [4]   = "Kindle Paperwhite 6",
    [5]   = "Kindle Basic",
    [6]   = "Boox Palma",
    [7]   = "PocketBook",
    [8]   = "Likebook Ares",
    [9]   = "Kobo Elipsa 2E",
    [10]  = "Kobo Clara BW",
    [11]  = "Kobo Clara Colour",
    [12]  = "Kobo Libra Colour",
    [97]  = "Xiaomi 14T Pro",
    [98]  = "Boox Go6",
    [99]  = "Physical book",
    [100] = "Emulator",
}

local ShowLongestSessionsWindow = InputContainer:extend({
    modal = true,
    name = "show_longest_sessions_window",
})

local function formatDateTime(ts)
    ts = math.floor(tonumber(ts) or 0)
    local t = os.date("*t", ts)
    return string.format("%02d/%02d/%04d %02d:%02d:%02d",
        t.day, t.month, t.year, t.hour, t.min, t.sec)
end

local function secondsToHMS(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h >= 24 then
        local d = math.floor(h / 24)
        h = h % 24
        return string.format("%dd %02d:%02d:%02d", d, h, m, s)
    end
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- ── Shared helpers ─────────────────────────────────────────────────────────────

local ROW_HEIGHT_TALL = Screen:scaleBySize(52)  -- sessions (título + fecha)
local ROW_HEIGHT_NORMAL = Screen:scaleBySize(36) -- resto de vistas

local function makeVerticalSpacing(w_padding_internal, h)
    h = h or 1
    return VerticalSpan:new({ width = math.floor(w_padding_internal * h) })
end

local function makeSeparator(w_width)
    return LineWidget:new{
        background = Blitbuffer.COLOR_LIGHT_GRAY,
        dimen = Geom:new{
            w = w_width - ScrollableContainer:getScrollbarWidth(),
            h = Size.line.thick,
        },
    }
end

-- ── View builders ──────────────────────────────────────────────────────────────

local function buildSessionsRows(w_width, w_font_face, w_font_size_small, w_padding_internal)
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local padding = Screen:scaleBySize(10) * 2
    local time_widget_width = Screen:scaleBySize(90)
    local bar_max_width = w_width - scrollbar_width - padding - time_widget_width - Screen:scaleBySize(10)

    local SQ3 = require("lua-ljsqlite3/init")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local conn = SQ3.open(db_location)

    local sql_stmt = [[
        SELECT book.title, wpm_stat_data.duration, wpm_stat_data.start_time
        FROM wpm_stat_data
        INNER JOIN book ON wpm_stat_data.id_book = book.id
        WHERE wpm_stat_data.start_time > 0
        ORDER BY wpm_stat_data.duration DESC
        LIMIT 200;
    ]]

    local sessions = {}
    local stmt = conn:prepare(sql_stmt)
    local row = {}
    while stmt:step(row) do
        table.insert(sessions, { title = row[1], duration = tonumber(row[2]), start_time = tonumber(row[3]) })
    end
    conn:close()

    if #sessions == 0 then return nil, "No session data found" end

    local rows = VerticalGroup:new({})

    for i, session in ipairs(sessions) do
        local row_item = HorizontalGroup:new({
            align = "center",
            LeftContainer:new({
                dimen = Geom:new({ w = bar_max_width, h = ROW_HEIGHT_TALL }),
                VerticalGroup:new({
                    align = "left",
                    TextWidget:new({
                        text = session.title,
                        face = Font:getFace(w_font_face, w_font_size_small),
                        max_width = bar_max_width,
                        ellipsis = true,
                    }),
                    TextWidget:new({
                        text = formatDateTime(session.start_time),
                        face = Font:getFace(w_font_face, w_font_size_small - 2),
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    }),
                }),
            }),
            HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
            RightContainer:new({
                dimen = Geom:new({ w = time_widget_width, h = ROW_HEIGHT_TALL }),
                TextWidget:new({
                    text = secondsToHMS(session.duration),
                    face = Font:getFace(w_font_face, w_font_size_small),
                }),
            }),
        })
        table.insert(rows, row_item)
        if i < #sessions then
            table.insert(rows, makeSeparator(w_width))
        end
    end

    return rows, #sessions, ROW_HEIGHT_TALL
end

local function buildDevicesRows(w_width, w_font_face, w_font_size_small, w_padding_internal)
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local padding = Screen:scaleBySize(10) * 2
    local time_widget_width = Screen:scaleBySize(90)
    local bar_max_width = w_width - scrollbar_width - padding - time_widget_width - Screen:scaleBySize(10)

    local SQ3 = require("lua-ljsqlite3/init")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local conn = SQ3.open(db_location)

    local sql_stmt = [[
        SELECT id_device, SUM(duration) as total_duration
        FROM wpm_stat_data
        GROUP BY id_device
        ORDER BY total_duration DESC
    ]]

    local devices = {}
    local stmt = conn:prepare(sql_stmt)
    local row = {}
    while stmt:step(row) do
        table.insert(devices, { id = tonumber(row[1]), duration = tonumber(row[2]) })
    end
    conn:close()

    if #devices == 0 then return nil, "No device data found" end

    local rows = VerticalGroup:new({})

    for i, device in ipairs(devices) do
        local name = DEVICE_NAMES[device.id] or ("Device " .. tostring(device.id))
        local row_item = HorizontalGroup:new({
            align = "center",
            LeftContainer:new({
                dimen = Geom:new({ w = bar_max_width, h = ROW_HEIGHT_NORMAL }),
                TextWidget:new({
                    text = name,
                    face = Font:getFace(w_font_face, w_font_size_small),
                    max_width = bar_max_width,
                    ellipsis = true,
                }),
            }),
            HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
            RightContainer:new({
                dimen = Geom:new({ w = time_widget_width, h = ROW_HEIGHT_NORMAL }),
                TextWidget:new({
                    text = secondsToHMS(device.duration),
                    face = Font:getFace(w_font_face, w_font_size_small),
                }),
            }),
        })
        table.insert(rows, row_item)
        if i < #devices then
            table.insert(rows, makeSeparator(w_width))
        end
    end

    return rows, #devices, ROW_HEIGHT_NORMAL
end

local function buildFontsRows(w_width, w_font_face, w_font_size_small, w_padding_internal)
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local padding = Screen:scaleBySize(10) * 2
    local time_widget_width = Screen:scaleBySize(90)
    local bar_max_width = w_width - scrollbar_width - padding - time_widget_width - Screen:scaleBySize(10)

    local SQ3 = require("lua-ljsqlite3/init")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local conn = SQ3.open(db_location)

    local sql_stmt = [[
        SELECT COALESCE(font_name, 'Unknown'), SUM(duration) as total_duration
        FROM wpm_stat_data
        GROUP BY font_name
        ORDER BY total_duration DESC
    ]]

    local fonts = {}
    local stmt = conn:prepare(sql_stmt)
    local row = {}
    while stmt:step(row) do
        table.insert(fonts, { name = row[1], duration = tonumber(row[2]) })
    end
    conn:close()

    if #fonts == 0 then return nil, "No font data found" end

    local rows = VerticalGroup:new({})

    for i, font in ipairs(fonts) do
        local row_item = HorizontalGroup:new({
            align = "center",
            LeftContainer:new({
                dimen = Geom:new({ w = bar_max_width, h = ROW_HEIGHT_NORMAL }),
                TextWidget:new({
                    text = font.name,
                    face = Font:getFace(w_font_face, w_font_size_small),
                    max_width = bar_max_width,
                    ellipsis = true,
                }),
            }),
            HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
            RightContainer:new({
                dimen = Geom:new({ w = time_widget_width, h = ROW_HEIGHT_NORMAL }),
                TextWidget:new({
                    text = secondsToHMS(font.duration),
                    face = Font:getFace(w_font_face, w_font_size_small),
                }),
            }),
        })
        table.insert(rows, row_item)
        if i < #fonts then
            table.insert(rows, makeSeparator(w_width))
        end
    end

    return rows, #fonts, ROW_HEIGHT_NORMAL
end

local function buildMonthlyRows(w_width, w_font_face, w_font_size_small, w_padding_internal)
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local padding = Screen:scaleBySize(10) * 2
    local time_widget_width = Screen:scaleBySize(90)
    local bar_max_width = w_width - scrollbar_width - padding - time_widget_width - Screen:scaleBySize(10)

    local SQ3 = require("lua-ljsqlite3/init")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local conn = SQ3.open(db_location)

    local sql_stmt = [[
        SELECT
            strftime('%Y', datetime(start_time, 'unixepoch')) AS year,
            CAST(strftime('%m', datetime(start_time, 'unixepoch')) AS INTEGER) AS month,
            SUM(duration) AS total_duration
        FROM wpm_stat_data
        WHERE start_time > 0
        GROUP BY year, month
        ORDER BY year DESC, month DESC
    ]]

    local months = {}
    local stmt = conn:prepare(sql_stmt)
    local row = {}
    while stmt:step(row) do
        table.insert(months, {
            label = string.format("%s %d", row[1], tonumber(row[2])),
            duration = tonumber(row[3]),
        })
    end
    conn:close()

    if #months == 0 then return nil, "No monthly data found" end

    local rows = VerticalGroup:new({})

    for i, entry in ipairs(months) do
        local row_item = HorizontalGroup:new({
            align = "center",
            LeftContainer:new({
                dimen = Geom:new({ w = bar_max_width, h = ROW_HEIGHT_NORMAL }),
                TextWidget:new({
                    text = entry.label,
                    face = Font:getFace(w_font_face, w_font_size_small),
                    max_width = bar_max_width,
                    ellipsis = true,
                }),
            }),
            HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
            RightContainer:new({
                dimen = Geom:new({ w = time_widget_width, h = ROW_HEIGHT_NORMAL }),
                TextWidget:new({
                    text = secondsToHMS(entry.duration),
                    face = Font:getFace(w_font_face, w_font_size_small),
                }),
            }),
        })
        table.insert(rows, row_item)
        if i < #months then
            table.insert(rows, makeSeparator(w_width))
        end
    end

    return rows, #months, ROW_HEIGHT_NORMAL
end

-- ── View definitions ───────────────────────────────────────────────────────────

local VIEWS = {
    { title = "Time per Month",           builder = buildMonthlyRows },
    { title = "Longest Reading Sessions", builder = buildSessionsRows },
    { title = "Time per Device",          builder = buildDevicesRows },
    { title = "Time per Font",            builder = buildFontsRows },
}
-- ── Main window ────────────────────────────────────────────────────────────────

function ShowLongestSessionsWindow:init()
    self.current_view = self.current_view or 1
    self:_buildUI()
end

function ShowLongestSessionsWindow:_buildUI()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local w_width = math.floor(screen_width * 0.85)
    if screen_width > screen_height then
        w_width = math.floor(w_width * screen_height / screen_width)
    end

    local w_font_face = "cfont"
    local w_font_size_med = 18
    local w_font_size_small = 15
    local w_padding_internal = Screen:scaleBySize(10)
    local w_padding_external = Screen:scaleBySize(10)

    local function vertical_spacing(h)
        h = h or 1
        return VerticalSpan:new({ width = math.floor(w_padding_internal * h) })
    end

    local view_def = VIEWS[self.current_view]
    local rows, num_items, row_height = view_def.builder(w_width, w_font_face, w_font_size_small, w_padding_internal)

    if not rows then
        UIManager:show(InfoMessage:new({ text = _(num_items or "Unknown error") }))
        return
    end

    local effective_row_height = row_height + Size.line.thick
    local scrollable_height = math.min(num_items, 12) * effective_row_height

    local title_widget = TextWidget:new({
        text = view_def.title,
        face = Font:getFace(w_font_face, w_font_size_med),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    })

    local title_frame = FrameContainer:new({
        dimen = Geom:new({ w = w_width, h = title_widget:getSize().h }),
        bordersize = 0,
        padding = 0,
        title_widget,
    })

    local SwipePassthroughScrollable = ScrollableContainer:extend{}

    function SwipePassthroughScrollable:onScrollableSwipe(_, ges)
        if ges.direction == "east" or ges.direction == "west" then
            return false
        end
        return ScrollableContainer.onScrollableSwipe(self, _, ges)
    end

    local scrollable = SwipePassthroughScrollable:new({
        dimen = Geom:new({ w = w_width, h = scrollable_height }),
        show_parent = self,
        rows,
    })

    local content = VerticalGroup:new({
        title_frame,
        vertical_spacing(),
        scrollable,
    })

    local frame = FrameContainer:new({
        radius = Screen:scaleBySize(22),
        bordersize = Screen:scaleBySize(2),
        padding = w_padding_external,
        background = Blitbuffer.COLOR_WHITE,
        content,
    })

    self[1] = CenterContainer:new({
        dimen = Screen:getSize(),
        frame,
    })

    self.dimen = Geom:new({ x = 0, y = 0, w = screen_width, h = screen_height })

    if Device:hasDPad() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new({ ges = "tap", range = self.dimen }),
        }
        self.ges_events.Swipe = {
            GestureRange:new({ ges = "swipe", range = self.dimen }),
        }
    end
end

function ShowLongestSessionsWindow:onSwipe(arg, ges)
    local BD = require("ui/bidi")
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then
        self.current_view = (self.current_view % #VIEWS) + 1
    elseif direction == "east" then
        self.current_view = ((self.current_view - 2) % #VIEWS) + 1
    else
        return false
    end
    UIManager:close(self)
    local widget = ShowLongestSessionsWindow:new({ current_view = self.current_view })
    UIManager:show(widget, "ui", widget.dimen)
    return true
end

function ShowLongestSessionsWindow:onShow()
    UIManager:setDirty(self, function()
        return "ui", self[1][1].dimen
    end)
    return true
end

function ShowLongestSessionsWindow:onClose()
    UIManager:close(self)
    return true
end

function ShowLongestSessionsWindow:onTapClose()
    self:onClose()
    return true
end

-- ── Dispatcher ─────────────────────────────────────────────────────────────────

Dispatcher:registerAction("show_longest_sessions", {
    category = "none",
    event = "ShowLongestSessions",
    title = _("Show longest reading sessions"),
    general = true,
})

function ReaderUI:onShowLongestSessions()
    if self.statistics then
        self.statistics:insertDB()
    end
    local widget = ShowLongestSessionsWindow:new()
    UIManager:show(widget, "ui", widget.dimen)
end

local FileManager = require("apps/filemanager/filemanager")

function FileManager:onShowLongestSessions()
    local widget = ShowLongestSessionsWindow:new()
    UIManager:show(widget, "ui", widget.dimen)
end

logger.info("Longest sessions patch applied")
