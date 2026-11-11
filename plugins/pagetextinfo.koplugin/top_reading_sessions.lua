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
-- Most views are the same list: something on the left, the time on the right.
-- A view says its query (sql), how a row becomes an item (map), what to show
-- on the left (left) and how tall a row is; this builds the rows from that.
-- (A view with its own `build` function, like the heatmap, does not use it.)

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

-- ── Reading Insights heatmap ───────────────────────────────────────────────────
-- The calendar heatmap of the Reading Insights plugin. Its own layout code
-- (views/heatmap_view.lua) is loaded from the plugin's folder and given the
-- daily reading time from the statistics database. The plugin's colours,
-- settings and language helpers live in modules this patch cannot reach, so
-- the few the heatmap needs are replaced by small stand-ins below: the
-- colours, the period and the first day of the week follow these settings,
-- not the plugin's.

local HEATMAP_MONTHS = 6                    -- period shown, ending today: 3, 4, 6 or 12 months
local HEATMAP_WEEK_STARTS_ON_SUNDAY = false

local HEATMAP_MONTH_NAMES = {
    _("Jan"), _("Feb"), _("Mar"), _("Apr"), _("May"), _("Jun"),
    _("Jul"), _("Aug"), _("Sep"), _("Oct"), _("Nov"), _("Dec"),
}

-- A folder of any plugin that has views/heatmap_view.lua (the plugin's own
-- folder name is not assumed).
local function findHeatmapFile()
    local lfs = require("libs/libkoreader-lfs")
    local found
    pcall(function()
        for _i, dir in ipairs({ DataStorage:getDataDir() .. "/plugins", "plugins" }) do
            if lfs.attributes(dir, "mode") == "directory" then
                for name in lfs.dir(dir) do
                    if name:match("%.koplugin$") then
                        local path = dir .. "/" .. name .. "/views/heatmap_view.lua"
                        if lfs.attributes(path, "mode") == "file" then
                            found = path
                            return
                        end
                    end
                end
            end
        end
    end)
    return found
end

local function parseDateYMD(dstr)
    local y, m, d = tostring(dstr):match("^(%d+)-(%d+)-(%d+)$")
    return tonumber(y), tonumber(m), tonumber(d)
end

-- What the heatmap module takes from the plugin: only these three are used
-- by the calendar grid, the period maths and the legend.
local function heatmapDeps()
    local function gray(v) return Blitbuffer.Color8(v) end
    local Colors = {
        -- no reading, then 0-25%, 25-50%, 50-75% and 75-100% of the busiest day
        heatmap0   = function() return gray(240) end,
        heatmap25  = function() return gray(195) end,
        heatmap50  = function() return gray(150) end,
        heatmap75  = function() return gray(100) end,
        heatmap100 = function() return gray(40) end,
        separator  = function() return gray(215) end,
        small      = function() return Blitbuffer.COLOR_DARK_GRAY end,
        label      = function() return Blitbuffer.COLOR_DARK_GRAY end,
        -- a solid rectangle
        newBar = function(w, h, color)
            return LineWidget:new{ dimen = Geom:new{ w = w, h = h }, background = color }
        end,
    }
    local VS = {
        readHeatmapMonthsSetting = function() return HEATMAP_MONTHS end,
        weekStartWday = function() return HEATMAP_WEEK_STARTS_ON_SUNDAY and 0 or 1 end, -- 0 = Sunday
        readWeekStartSetting = function() return HEATMAP_WEEK_STARTS_ON_SUNDAY and "sunday" or "monday" end,
    }
    local Locale = {
        _ = _,
        shortMonthNames = HEATMAP_MONTH_NAMES,
        monthAxisLabel = function(_m, name) return name end,
        formatYearShortMonth = function(year, month)
            return string.format("%d %s", year, HEATMAP_MONTH_NAMES[month])
        end,
    }
    return { Colors = Colors, VS = VS, Locale = Locale }
end

local heatmap_module -- loaded once; false when it could not be
local heatmap_error

local function loadHeatmap()
    if heatmap_module ~= nil then return heatmap_module or nil, heatmap_error end
    heatmap_module = false
    local path = findHeatmapFile()
    if not path then
        heatmap_error = "Reading Insights plugin not found"
        return nil, heatmap_error
    end
    local chunk, load_err = loadfile(path)
    if not chunk then
        logger.warn("longest sessions: cannot load", path, load_err)
        heatmap_error = "Could not load the Reading Insights heatmap"
        return nil, heatmap_error
    end
    local ok, module = pcall(chunk, heatmapDeps())
    if not ok or type(module) ~= "table" or not module.buildRangeHeatmapWidget then
        logger.warn("longest sessions: heatmap module failed:", tostring(module))
        heatmap_error = "Could not load the Reading Insights heatmap"
        return nil, heatmap_error
    end
    module.bind({ parseDateYMD = parseDateYMD, getCachedFonts = function() return nil end })
    heatmap_module = module
    return module
end

-- The widgets of the heatmap view (the window puts them under its title).
local function buildHeatmapView(w_width, w_font_face, w_font_size_small)
    local Heatmap, err = loadHeatmap()
    if not Heatmap then return nil, err end

    local start_t, end_t = Heatmap.getHeatmapPeriodRange(0)

    -- seconds read on each day of the period (sessions, by local date)
    local items, query_err = queryAll(string.format([[
        SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS day, SUM(duration)
        FROM wpm_stat_data
        WHERE start_time >= %d
        GROUP BY day
    ]], start_t - 2 * 86400), function(row)
        return { day = row[1], seconds = tonumber(row[2]) or 0 }
    end)
    if not items then return nil, query_err end
    if #items == 0 then return nil, "No reading data found" end

    local daily_map = {}
    for _i, item in ipairs(items) do daily_map[item.day] = item.seconds end

    local fonts = {
        small   = Font:getFace(w_font_face, w_font_size_small - 3),
        label   = Font:getFace(w_font_face, w_font_size_small - 1),
        section = Font:getFace(w_font_face, w_font_size_small),
    }

    local grid = Heatmap.buildRangeHeatmapWidget(daily_map, start_t, end_t, fonts, w_width)
    local legend = Heatmap.buildHeatmapLegendWidget(fonts, 0)

    local st, et = os.date("*t", start_t), os.date("*t", end_t)
    local range = string.format("%s \xE2\x80\x93 %s",
        string.format("%d %s", st.year, HEATMAP_MONTH_NAMES[st.month]),
        string.format("%d %s", et.year, HEATMAP_MONTH_NAMES[et.month]))
    local caption = TextWidget:new{ text = range, face = fonts.label, fgcolor = Blitbuffer.COLOR_DARK_GRAY }

    -- Flat list, like the plugin builds its own popup: the grid sits in a
    -- container and the spacers are direct children of the window's column.
    local gap = Screen:scaleBySize(6)
    return {
        caption,
        makeVerticalSpacing(gap),
        LeftContainer:new{ dimen = Geom:new{ w = w_width, h = grid:getSize().h }, grid },
        makeVerticalSpacing(gap),
        RightContainer:new{ dimen = Geom:new{ w = w_width, h = legend:getSize().h }, legend },
    }
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
    {
        -- not a list: it builds its own widgets
        title = "Reading Heatmap",
        build = buildHeatmapView,
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

    -- Nothing to show: tell the user why, and see showWindow.
    local function fail(message)
        UIManager:show(InfoMessage:new({ text = _(message or "Unknown error") }))
        self.failed = true
    end

    -- The widgets that go under the title: a list in a scrollable
    -- container, or whatever the view builds itself.
    local view_def = VIEWS[self.current_view]
    local body
    if view_def.build then
        local widgets, err = view_def.build(w_width, w_font_face, w_font_size_small)
        if not widgets then return fail(err) end
        body = widgets
    else
        local rows, num_items, row_height = buildRows(view_def, w_width, w_font_face, w_font_size_small)
        -- on failure the second value is the message
        if not rows then return fail(num_items) end

        local effective_row_height = row_height + Size.line.thick
        local scrollable_height = math.min(num_items, 12) * effective_row_height
        body = {
            SwipePassthroughScrollable:new({
                dimen = Geom:new({ w = w_width, h = scrollable_height }),
                show_parent = self,
                rows,
            }),
        }
    end

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

    local content = VerticalGroup:new({
        title_frame,
        makeVerticalSpacing(w_padding_internal),
    })
    for _i, widget in ipairs(body) do
        table.insert(content, widget)
    end

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
