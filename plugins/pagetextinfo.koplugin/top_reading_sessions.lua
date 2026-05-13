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
local RightContainer = require("ui/widget/container/rightcontainer")
local ReaderUI = require("apps/reader/readerui")
local Screen = Device.screen
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local datetime = require("datetime")
local _ = require("gettext")

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
    return string.format("%02d:%02d:%02d", h, m, s)
end

function ShowLongestSessionsWindow:init()
    local screen_width = Screen:getWidth()
    local screen_height = Screen:getHeight()
    local w_width = math.floor(screen_width * 0.85)
    if screen_width > screen_height then
        w_width = math.floor(w_width * screen_height / screen_width)
    end

    local w_font_face = "cfont"
    local w_font_size_big = 22
    local w_font_size_med = 18
    local w_font_size_small = 15

    local w_padding_internal = Screen:scaleBySize(10)
    local w_padding_external = Screen:scaleBySize(10)

    local function vertical_spacing(h)
        h = h or 1
        return VerticalSpan:new({ width = math.floor(w_padding_internal * h) })
    end

    local function buildWindow()
        local scrollbar_width = ScrollableContainer:getScrollbarWidth()
        local padding = w_padding_external * 2
        local time_widget_width = Screen:scaleBySize(90)
        local bar_max_width = w_width - scrollbar_width - padding - time_widget_width - Screen:scaleBySize(10)

        -- Query DB for longest sessions
        local SQ3 = require("lua-ljsqlite3/init")
        local db_location = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
        local conn = SQ3.open(db_location)

        local sql_stmt = [[
            SELECT book.title, wpm_stat_data.duration, wpm_stat_data.start_time
            FROM wpm_stat_data
            INNER JOIN book ON wpm_stat_data.id_book = book.id
            ORDER BY wpm_stat_data.duration DESC
            LIMIT 50;
        ]]

        local sessions = {}
        local stmt = conn:prepare(sql_stmt)
        local row = {}
        while stmt:step(row) do
            table.insert(sessions, { title = row[1], duration = tonumber(row[2]), start_time = tonumber(row[3]) })
        end
        conn:close()

        if #sessions == 0 then
            return nil, "No session data found"
        end

        local rows = VerticalGroup:new({})

        for _, session in ipairs(sessions) do
            local title_widget = TextWidget:new({
                text = session.title,
                face = Font:getFace(w_font_face, w_font_size_small),
                max_width = bar_max_width,
                ellipsis = true,
            })

            local date_widget = TextWidget:new({
                text = formatDateTime(session.start_time),
                face = Font:getFace(w_font_face, w_font_size_small - 2),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            })

            local time_widget = TextWidget:new({
                text = secondsToHMS(session.duration),
                face = Font:getFace(w_font_face, w_font_size_small),
            })

            local left_group = VerticalGroup:new({
                title_widget,
                date_widget,
            })

            local row_item = HorizontalGroup:new({
                align = "center",
                LeftContainer:new({
                    dimen = Geom:new({ w = bar_max_width, h = Screen:scaleBySize(36) }),
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
                    dimen = Geom:new({ w = time_widget_width, h = Screen:scaleBySize(36) }),
                    TextWidget:new({
                        text = secondsToHMS(session.duration),
                        face = Font:getFace(w_font_face, w_font_size_small),
                    }),
                }),
            })

            table.insert(rows, row_item)
            table.insert(rows, vertical_spacing(0.5))
        end

        local title_widget = TextWidget:new({
            text = "Longest Reading Sessions",
            face = Font:getFace(w_font_face, w_font_size_med),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        })

        local title = FrameContainer:new({
            dimen = Geom:new({
                w = w_width,
                h = title_widget:getSize().h,
            }),
            bordersize = 0,
            padding = 0,
            title_widget,
        })

        local row_height = Screen:scaleBySize(36) + math.floor(w_padding_internal * 0.5)
        local num_items = #sessions
        local scrollable_height
        if num_items <= 12 then
            scrollable_height = num_items * row_height
        else
            scrollable_height = 12 * row_height
        end

        local scrollable = ScrollableContainer:new({
            dimen = Geom:new({
                w = w_width,
                h = scrollable_height,
            }),
            show_parent = self,
            rows,
        })

        return VerticalGroup:new({
            title,
            vertical_spacing(),
            scrollable,
        })
    end

    local content, error_msg = buildWindow()

    if not content then
        UIManager:show(InfoMessage:new({ text = _(error_msg or "Unknown error") }))
        return
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

    self.dimen = Geom:new({
        x = 0,
        y = 0,
        w = screen_width,
        h = screen_height,
    })

    if Device:hasDPad() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new({
                ges = "tap",
                range = self.dimen,
            }),
        }
    end
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

logger.info("Longest sessions patch applied")
