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
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local datetime = require("datetime")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local SQ3 = require("lua-ljsqlite3/init")



getReadToday = function ()
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
                     WHERE  start_time >= %d
                     GROUP  BY id_book, page
                );
    ]]

    local now_stamp = os.time()
    local now_t = os.date("*t")
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    local read_today = conn:rowexec(string.format(sql_stmt,start_today_time))

    conn:close()

    if read_today == nil then
        read_today = 0
    end
    read_today = tonumber(read_today)


    return read_today
end

-- self[4] = self.topbar in readerview.lua
local TopBar = WidgetContainer:extend{
    name = "Topbar",
    is_enabled = G_reader_settings:isTrue("show_time"),
    start_session_time = os.time(),
    initial_read_today = getReadToday(),
}

function TopBar:init()
    if TopBar.preserved_start_session_time then
        self.start_session_time = TopBar.start_session_time
        TopBar.preserved_start_start_session_time = nil

    end

    if TopBar.preserved_initial_read_today then
        self.initial_read_today = TopBar.preserved_initial_read_today
        TopBar.preserved_initial_read_todays= nil
    end

end

function TopBar:onReaderReady()

    local duration_raw =  math.floor((os.time() - self.start_session_time))

    if duration_raw < 360 or self.ui.statistics._total_pages < 6 then
        self.start_session_time = os.time()
    end

    self.wpm_session = 0
    if duration_raw > 0 and self.ui.statistics._total_words then
        self.wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
    end


    self.wpm_text = TextWidget:new{
        text = self.wpm_session .. "wpm",
        face = Font:getFace("myfont4"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")

    self.session_time_text = TextWidget:new{
        text = "",
        face = Font:getFace("myfont4"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.progress_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont4"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.progress_chapter_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont4"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }


    -- self[1] = left_container:new{
    --     dimen = Geom:new{ w = self.wpm_text:getSize().w, self.wpm_text:getSize().h },
    --     self.wpm_text,
    -- }

    self[1] = left_container:new{
        dimen = Geom:new{ w = self.session_time_text:getSize().w, self.session_time_text:getSize().h },
        self.session_time_text,
    }

    self[2] = left_container:new{
        dimen = Geom:new{ w = self.progress_text:getSize().w, self.progress_text:getSize().h },
        self.progress_chapter_text,
    }

    self.dialog_frame = FrameContainer:new{
        -- background = Blitbuffer.COLOR_WHITE,
        padding_bottom = 20,
        bordersize = 0,
        VerticalGroup:new{
            -- self.progress_text,
            self.progress_text,
        },
    }

    self[3] = BottomContainer:new{
        dimen = Screen:getSize(),
        self.dialog_frame,
    }

end
function TopBar:onToggleShowTime()
    local show_time = G_reader_settings:isTrue("show_time")
    G_reader_settings:saveSetting("show_time", not show_time)
    self.is_enabled = not show_time
    self:toggleBar()
end

function TopBar:resetLayout()
    -- if self.wpm_text then
    --     self:toggleBar()
    -- end
end

function TopBar:onResume()
    self.start_session_time = os.time()
    self.initial_read_today = getReadToday()
    self:toggleBar()
end


function TopBar:onPreserveCurrentSession()
    -- Can be called before ReaderUI:reloadDocument() to not reset the current session
    TopBar.preserved_start_session_time = self.start_session_time
    TopBar.preserved_initial_read_today = self.initial_read_today
end


function TopBar:onSwitchTopBar()
    if G_reader_settings:isTrue("show_time") then
        self.is_enabled = not self.is_enabled
        self:toggleBar()
        UIManager:setDirty("all", "partial")
    end
end


function TopBar:toggleBar()
    if self.is_enabled then
        local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
        local session_time = datetime.secondsToClockDuration(user_duration_format, os.time() - self.start_session_time, false)

        local duration_raw =  math.floor((os.time() - self.start_session_time))
        self.wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        self.wpm_text:setText(self.wpm_session .. "wpm")

        local session_started = self.start_session_time

        local now_t = os.date("*t")
        local daysdiff = now_t.day - os.date("*t",session_started).day
        if daysdiff > 0 then
            self.initial_read_today = getReadToday()
        end

        local read_today = self.initial_read_today + (os.time() - session_started)
        read_today = datetime.secondsToClockDuration(user_duration_format, read_today, false)
        self.session_time_text:setText(datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) .. "|" .. session_time .. "|≃" .. read_today)
        self.progress_text:setText(("%d de %d"):format(self.view.footer.pageno, self.view.footer.pages))


        self.progress_chapter_text:setText(self.view.footer:getChapterProgress(false))


    else
        self.session_time_text:setText("")
        self.progress_text:setText("")
        self.progress_chapter_text:setText("")
    end
end

function TopBar:onPageUpdate()
    self:toggleBar()
end

function TopBar:paintTo(bb, x, y)
        self[1]:paintTo(bb, x + 20, y + 20)
        self[2].dimen = Geom:new{ w = self[2][1]:getSize().w, self[2][1]:getSize().h } -- The text width change and we need to adjust the container dimensions to be able to align it on the right
        self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - 20, y + 20)


        self[3]:paintTo(bb, x + 20, y + 20)
        -- text_container2:paintTo(bb, x + Screen:getWidth() - text_container2:getSize().w - 20, y + 20)
        -- text_container2:paintTo(bb, x + Screen:getWidth()/2 - text_container2:getSize().w/2, y + 20)
end

return TopBar
