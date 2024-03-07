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



local TopBar = WidgetContainer:extend{
    name = "Topbar",
    is_enabled = G_reader_settings:isTrue("show_time"),
}

function TopBar:init()
    self:createUI()
end

function TopBar:createUI()
    return
end

function TopBar:onReaderReady()
    self.duration_raw =  math.floor(((os.time() - self.ui.statistics.start_current_period)/60)* 100) / 100

    self.wpm_session = 0
    if self.duration_raw > 0 and self.ui.statistics._total_words then
        self.wpm_session = math.floor(self.ui.statistics._total_words/self.duration_raw)
    end


    self.wpm_text = TextWidget:new{
        text = self.wpm_session .. "wpm",
        face = Font:getFace("myfont4"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }


    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    local session_time =   datetime.secondsToClockDuration(user_duration_format, os.time() - self.ui.statistics.start_current_period, false)

    self.session_time_text = TextWidget:new{
        text = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) .. "|" .. session_time,
        face = Font:getFace("myfont4"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    self.progress_text = TextWidget:new{
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
        self.progress_text,
    }

end
function TopBar:onToggleShowTime()
    local show_time = G_reader_settings:isTrue("show_time")
    G_reader_settings:saveSetting("show_time", not show_time)
    self.is_enabled = not show_time
    self:toggleBar()
end

-- Executed after setting self[4] = self.topbar in readerview.lua
function TopBar:resetLayout()
    self:createUI()
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
        local session_time =   datetime.secondsToClockDuration(user_duration_format, os.time() - self.ui.statistics.start_current_period, false)

        self.duration_raw =  math.floor(((os.time() - self.ui.statistics.start_current_period)/60)* 100) / 100
        self.wpm_session = math.floor(self.ui.statistics._total_words/self.duration_raw)
        self.wpm_text:setText(self.wpm_session .. "wpm")

        self.session_time_text:setText(datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) .. "|" .. session_time)
        self.progress_text:setText(("%d de %d"):format(self.view.footer.pageno, self.view.footer.pages))
    else
        self.session_time_text:setText("")
        self.progress_text:setText("")
    end
end
function TopBar:onPageUpdate()

    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    local session_time =   datetime.secondsToClockDuration(user_duration_format, os.time() - self.ui.statistics.start_current_period, false)

    self.duration_raw =  math.floor(((os.time() - self.ui.statistics.start_current_period)/60)* 100) / 100
    self.wpm_session = math.floor(self.ui.statistics._total_words/self.duration_raw)
    self.wpm_text:setText(self.wpm_session .. "wpm")

    self.session_time_text:setText(datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")) .. "|" .. session_time)
    self.progress_text:setText(("%d de %d"):format(self.view.footer.pageno, self.view.footer.pages))

end



function TopBar:paintTo(bb, x, y)
        self[1]:paintTo(bb, x + 20, y + 20)
        self[2].dimen = Geom:new{ w = self[2][1]:getSize().w, self[2][1]:getSize().h }
        self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - 20, y + 20)

        -- text_container2:paintTo(bb, x + Screen:getWidth() - text_container2:getSize().w - 20, y + 20)
        -- text_container2:paintTo(bb, x + Screen:getWidth()/2 - text_container2:getSize().w/2, y + 20)
end

return TopBar
