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
local SQ3 = require("lua-ljsqlite3/init")
local ProgressWidget = require("ui/widget/progresswidget")


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
                     WHERE  DATE(start_time,'unixepoch','localtime')=DATE('now', '0 day','localtime')
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

getReadThisMonth = function ()
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
                     WHERE  start_time >= strftime('%s', DATE('now', 'start of month'))
                     GROUP  BY id_book, page
                );
    ]]

    local read_month = conn:rowexec(sql_stmt)

    conn:close()

    if read_month == nil then
        read_month = 0
    end
    read_month = tonumber(read_month)


    return read_month
end

-- self[4] = self.topbar in readerview.lua
local TopBar = WidgetContainer:extend{
    name = "Topbar",
    is_enabled = G_reader_settings:isTrue("show_time"),
    start_session_time = os.time(),
    initial_read_today = getReadToday(),
    initial_read_month = getReadThisMonth(),
    MARGIN =  Screen:scaleBySize(9),
}

function TopBar:init()
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

    self.times_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont4"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }


    self.title_text = TextWidget:new{
        text =  "",
        face = Font:getFace("myfont4"),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }


    self.chapter_text = TextWidget:new{
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
        self.progress_text,
    }


    self[3] = left_container:new{
        dimen = Geom:new{ w = self.title_text:getSize().w, self.title_text:getSize().h },
        self.title_text,
    }

    self[4] = left_container:new{
        dimen = Geom:new{ w = self.progress_text:getSize().w, h = Screen:getSize().h * 2},
        self.times_text,
    }

    self[5] = left_container:new{
        dimen = Geom:new{ w = self.chapter_text:getSize().w, h = Screen:getSize().h * 2},
        self.chapter_text,

    }

    self[6] = left_container:new{
        dimen = Geom:new{ w = self.chapter_text:getSize().w, h = Screen:getSize().h * 2 },
        self.progress_chapter_text,
    }


    self.progress_bar  = ProgressWidget:new{
        width = 200,
        height = 20,
        percentage = 0,
        tick_width = Screen:scaleBySize(4),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }


    self[7] = left_container:new{
        dimen = Geom:new{ w = self.title_text:getSize().w, self.title_text:getSize().h },
        self.progress_bar,
    }

    self.progress_chapter_bar = ProgressWidget:new{
        width = 200,
        height = 20,
        percentage = 0,
        tick_width = Screen:scaleBySize(4),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }


    self[8] = left_container:new{
        dimen = Geom:new{ w = self.chapter_text:getSize().w, h = Screen:getSize().h * 2},
        self.progress_chapter_bar,
    }

    self.progress_bar2  = ProgressWidget:new{
        width = Screen:getSize().w,
        height = 5,
        percentage = 0,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }


    self[9] = left_container:new{
        dimen = Geom:new{ w = self.title_text:getSize().w, self.title_text:getSize().h },
        self.progress_bar2,
    }


    -- self.bottom_frame = FrameContainer:new{
    --     -- background = Blitbuffer.COLOR_WHITE,
    --     padding_bottom = 20,
    --     bordersize = 0,
    --     VerticalGroup:new{
    --         -- self.progress_text,
    --         self.progress_text,
    --     },
    -- }

    -- self[4] = BottomContainer:new{
    --     dimen = Screen:getSize(),
    --     self.bottom_frame,
    -- }



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
    TopBar.preserved_initial_read_month = self.initial_read_month
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
        local now_t = os.date("*t")
        local daysdiff = now_t.day - os.date("*t",self.start_session_time).day
        if daysdiff > 0 then
            self.initial_read_today = getReadToday()
            self.start_session_time = os.time()
        end


        local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
        local session_time = datetime.secondsToClockDuration(user_duration_format, os.time() - self.start_session_time, false)

        local duration_raw =  math.floor((os.time() - self.start_session_time))
        self.wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        self.wpm_text:setText(self.wpm_session .. "wpm")

        local read_today = self.initial_read_today + (os.time() - self.start_session_time)
        read_today = datetime.secondsToClockDuration(user_duration_format, read_today, false)

        local read_month = self.initial_read_month + (os.time() - self.start_session_time)
        read_month = datetime.secondsToClockDuration(user_duration_format, read_month, false)

        self.session_time_text:setText(datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")))
        self.progress_text:setText(("%d de %d"):format(self.view.footer.pageno, self.view.footer.pages))


        self.times_text:setText(session_time .. "|≃" .. read_today .. "|≃" .. read_month)


        local title = self.ui.document._document:getDocumentProps().title
        local words = "?w"
        local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")
        if file_type == "epub" then
            if title:find('%[%d?.%d]') then
                title = title:sub(title:find('%]')+2, title:len())
            end

            if (title:find("([0-9,]+w)") ~= nil) then
                words = title:match("([0-9,]+w)"):gsub("w",""):gsub(",","") .. "w"
                title = title:sub(1, title:find('%(')-2, title:len())
            end
        end
        title = TextWidget.PTF_BOLD_START .. title .. " with " .. words .. TextWidget.PTF_BOLD_END
        self.title_text:setText(title)

        local chapter = TextWidget.PTF_BOLD_START .. self.ui.toc:getTocTitleByPage(self.view.footer.pageno) .. TextWidget.PTF_BOLD_END
        self.progress_bar.width = 250
        self.progress_bar2.width = Screen:getSize().w
        self.progress_chapter_bar.width = 250
        self.progress_bar.height = 15
        self.progress_bar2.height = 15
        self.progress_chapter_bar.height = 15

        self.chapter_text:setText(chapter)
        self.progress_chapter_text:setText(self.view.footer:getChapterProgress(false))
        self.progress_bar:updateStyle(false, nil)
        self.progress_chapter_bar:updateStyle(false, nil)
        self.progress_bar.last = self.pages or self.ui.document:getPageCount()
        -- self.progress_bar.ticks = self.ui.toc:getTocTicksFlattened()
        self.progress_bar2.last = self.pages or self.ui.document:getPageCount()
        self.progress_bar2.ticks = self.ui.toc:getTocTicksFlattened()
    else
        self.session_time_text:setText("")
        self.progress_text:setText("")
        self.times_text:setText("")
        self.title_text:setText("")
        self.chapter_text:setText("")
        self.progress_chapter_text:setText("")
        self.progress_bar.width = 0
        self.progress_bar2.width = 0
        self.progress_chapter_bar.width = 0
    end
end

function TopBar:onPageUpdate()
    self:toggleBar()
    self.progress_bar:setPercentage(self.view.footer.pageno / self.view.footer.pages)
    self.progress_bar2:setPercentage(self.view.footer.pageno / self.view.footer.pages)
    self.progress_chapter_bar:setPercentage(self.view.footer:getChapterProgress(true))
end

function TopBar:paintTo(bb, x, y)
        -- Top left
        -- self[9]:paintTo(bb, x , y + 15)
        self[1]:paintTo(bb, x + TopBar.MARGIN, y + TopBar.MARGIN)

        -- Top center

        self[3]:paintTo(bb, x + Screen:getWidth()/2 - self[3][1]:getSize().w/2, y + TopBar.MARGIN)
        -- self[3]:paintTo(bb, x + Screen:getWidth()/2, y + 20)


        -- Top right
        -- Commented the text, using progress bar
        -- self[2].dimen = Geom:new{ w = self[2][1]:getSize().w, self[2][1]:getSize().h } -- The text width change and we need to adjust the container dimensions to be able to align it on the right
        -- self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - TopBar.MARGIN, y + TopBar.MARGIN)

        -- self[7]:paintTo(bb,  x + Screen:getWidth()/2 - self[3][1]:getSize().w/2 + self[3][1]:getSize().w + 20, y + 10)
        self[7]:paintTo(bb, x + Screen:getWidth() - self[7][1]:getSize().w - TopBar.MARGIN, y + TopBar.MARGIN)


        -- Bottom left
        self[4].dimen.w = self[4][1]:getSize().w
        self[4]:paintTo(bb, x + TopBar.MARGIN, y - TopBar.MARGIN)

        -- Bottom center
        self[5]:paintTo(bb, x + Screen:getWidth()/2 - self[5][1]:getSize().w/2,  y - TopBar.MARGIN)

        -- Bottom right
        -- self[6].dimen.w = self[6][1]:getSize().w
        -- self[6]:paintTo(bb, x + Screen:getWidth() - self[6]:getSize().w - TopBar.MARGIN, y - TopBar.MARGIN)

        -- Use progress bar
        self[8]:paintTo(bb, x + Screen:getWidth() - self[8][1]:getSize().w - TopBar.MARGIN,  y - TopBar.MARGIN)


        -- text_container2:paintTo(bb, x + Screen:getWidth() - text_container2:getSize().w - 20, y + 20)
        -- text_container2:paintTo(bb, x + Screen:getWidth()/2 - text_container2:getSize().w/2, y + 20)
end

return TopBar
