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

-- Runs a query on the statistics database and returns its rows, each one
-- turned into an item by `map` (which gets the row table, reused between
-- rows, so it must copy what it needs). Returns nil and a message when the
-- database cannot be read; the connection is closed in every case.
local function queryAll(sql_stmt, map)
    local SQ3 = require("lua-ljsqlite3/init")
    local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    local items = {}
    local ok, err = pcall(function()
        local conn = SQ3.open(db_location)
        local ok_query, err_query = pcall(function()
            local stmt = conn:prepare(sql_stmt)
            local row = {}
            while stmt:step(row) do
                items[#items + 1] = map(row)
            end
            stmt:close()
        end)
        conn:close()
        if not ok_query then error(err_query, 0) end
    end)
    if not ok then
        logger.warn("longest sessions: query failed:", err)
        return nil, "Could not read the statistics database"
    end
    return items
end

-- Swipes left and right change the view, so the list must not take them.
local SwipePassthroughScrollable = ScrollableContainer:extend{}

function SwipePassthroughScrollable:onScrollableSwipe(arg, ges)
    if ges.direction == "east" or ges.direction == "west" then
        return false
    end
    return ScrollableContainer.onScrollableSwipe(self, arg, ges)
end

-- ── View builder ───────────────────────────────────────────────────────────────
-- Every view is the same list: something on the left, the time on the right.
-- A view says its query (sql), how a row becomes an item (map), what to show
-- on the left (left) and how tall a row is; this builds the rows from that.

local function buildRows(view, w_width, w_font_face, w_font_size_small)
    local scrollbar_width = ScrollableContainer:getScrollbarWidth()
    local padding = Screen:scaleBySize(10) * 2
    local time_widget_width = Screen:scaleBySize(90)
    local bar_max_width = w_width - scrollbar_width - padding - time_widget_width - Screen:scaleBySize(10)

    local items, err = queryAll(view.sql, view.map)
    if not items then return nil, err end
    if #items == 0 then return nil, view.empty end

    local ctx = { font_face = w_font_face, font_size = w_font_size_small, max_width = bar_max_width }
    local row_height = view.row_height
    local rows = VerticalGroup:new({})

    for i, item in ipairs(items) do
        local row_item = HorizontalGroup:new({
            align = "center",
            LeftContainer:new({
                dimen = Geom:new({ w = bar_max_width, h = row_height }),
                view.left(item, ctx),
            }),
            HorizontalSpan:new({ width = Screen:scaleBySize(10) }),
            RightContainer:new({
                dimen = Geom:new({ w = time_widget_width, h = row_height }),
                TextWidget:new({
                    text = secondsToHMS(item.duration),
                    face = Font:getFace(w_font_face, w_font_size_small),
                }),
            }),
        })
        table.insert(rows, row_item)
        if i < #items then
            table.insert(rows, makeSeparator(w_width))
        end
    end

    return rows, #items, row_height
end

-- ── View definitions ───────────────────────────────────────────────────────────

-- One line of text on the left: the item's `field`, cut with "…" if too long.
local function textLabel(field)
    return function(item, ctx)
        return TextWidget:new({
            text = item[field],
            face = Font:getFace(ctx.font_face, ctx.font_size),
            max_width = ctx.max_width,
            ellipsis = true,
        })
    end
end

local VIEWS = {
    {
        title = "Time per Month",
        empty = "No monthly data found",
        row_height = ROW_HEIGHT_NORMAL,
        -- local time, as the dates of the sessions list (not UTC)
        sql = [[
            SELECT
                strftime('%Y', start_time, 'unixepoch', 'localtime') AS year,
                CAST(strftime('%m', start_time, 'unixepoch', 'localtime') AS INTEGER) AS month,
                SUM(duration) AS total_duration
            FROM wpm_stat_data
            WHERE start_time > 0
            GROUP BY year, month
            ORDER BY year DESC, month DESC
        ]],
        map = function(row)
            return {
                label = string.format("%s %d", row[1], tonumber(row[2])),
                duration = tonumber(row[3]),
            }
        end,
        left = textLabel("label"),
    },
    {
        title = "Longest Reading Sessions",
        empty = "No session data found",
        row_height = ROW_HEIGHT_TALL,
        sql = [[
            SELECT book.title, wpm_stat_data.duration, wpm_stat_data.start_time
            FROM wpm_stat_data
            INNER JOIN book ON wpm_stat_data.id_book = book.id
            WHERE wpm_stat_data.start_time > 0
            ORDER BY wpm_stat_data.duration DESC
            LIMIT 200;
        ]],
        map = function(row)
            return { title = row[1] or "Unknown", duration = tonumber(row[2]), start_time = tonumber(row[3]) }
        end,
        -- two lines: the book's title and the date
        left = function(item, ctx)
            return VerticalGroup:new({
                align = "left",
                TextWidget:new({
                    text = item.title,
                    face = Font:getFace(ctx.font_face, ctx.font_size),
                    max_width = ctx.max_width,
                    ellipsis = true,
                }),
                TextWidget:new({
                    text = formatDateTime(item.start_time),
                    face = Font:getFace(ctx.font_face, ctx.font_size - 2),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                }),
            })
        end,
    },
    {
        title = "Time per Device",
        empty = "No device data found",
        row_height = ROW_HEIGHT_NORMAL,
        sql = [[
            SELECT id_device, SUM(duration) as total_duration
            FROM wpm_stat_data
            GROUP BY id_device
            ORDER BY total_duration DESC
        ]],
        map = function(row)
            local id = tonumber(row[1])
            return {
                name = DEVICE_NAMES[id] or ("Device " .. tostring(id)),
                duration = tonumber(row[2]),
            }
        end,
        left = textLabel("name"),
    },
    {
        title = "Time per Font",
        empty = "No font data found",
        row_height = ROW_HEIGHT_NORMAL,
        sql = [[
            SELECT COALESCE(font_name, 'Unknown'), SUM(duration) as total_duration
            FROM wpm_stat_data
            GROUP BY font_name
            ORDER BY total_duration DESC
        ]],
        map = function(row)
            return { name = row[1], duration = tonumber(row[2]) }
        end,
        left = textLabel("name"),
    },
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

    local view_def = VIEWS[self.current_view]
    local rows, num_items, row_height = buildRows(view_def, w_width, w_font_face, w_font_size_small)

    if not rows then
        -- on failure the second value is the message
        UIManager:show(InfoMessage:new({ text = _(num_items or "Unknown error") }))
        self.failed = true -- nothing to show: see showWindow
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

    local scrollable = SwipePassthroughScrollable:new({
        dimen = Geom:new({ w = w_width, h = scrollable_height }),
        show_parent = self,
        rows,
    })

    local content = VerticalGroup:new({
        title_frame,
        makeVerticalSpacing(w_padding_internal),
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

-- Builds the window for a view and shows it. Returns the window, or nil when
-- it could not be built (the user has been told why).
local function showWindow(current_view)
    local widget = ShowLongestSessionsWindow:new({ current_view = current_view })
    if widget.failed then return nil end
    UIManager:show(widget, "ui", widget.dimen)
    return widget
end

function ShowLongestSessionsWindow:onSwipe(arg, ges)
    local BD = require("ui/bidi")
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    local next_view
    if direction == "west" then
        next_view = (self.current_view % #VIEWS) + 1
    elseif direction == "east" then
        next_view = ((self.current_view - 2) % #VIEWS) + 1
    else
        return false
    end
    -- the new view first: if it fails, this one stays
    local widget = ShowLongestSessionsWindow:new({ current_view = next_view })
    if widget.failed then return true end
    UIManager:close(self)
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
    -- save the session in progress first, so it is in the lists
    if self.statistics then
        self.statistics:insertDB()
    end
    showWindow()
end

local FileManager = require("apps/filemanager/filemanager")

function FileManager:onShowLongestSessions()
    showWindow()
end

logger.info("Longest sessions patch applied")
