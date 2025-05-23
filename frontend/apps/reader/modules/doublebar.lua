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
local Device = require("device")


-- self[4] = self.topbar in readerview.lua

local DoubleBar = WidgetContainer:extend{
    name = "DoubleBar",
    is_enabled = G_reader_settings:isTrue("show_double_bar"),
    start_session_time = os.time(),
    MARGIN_SIDES = Screen:scaleBySize(10),
    -- El margen de las pantallas, flushed o recessed no es perfecto. La pantalla suele empezar un poco más arriba en casi todos los dispositivos estando un poco por debajo del bezel
    -- Al menos los Kobos y el Boox Palma
    -- Podemos cambiar los márgenes
    -- Para verlo en detalle, es mejor no poner ningún estilo en las barras de progreso
    MARGIN_TOP = Screen:scaleBySize(9),
    MARGIN_BOTTOM = Screen:scaleBySize(9),
    show_top_bar = true,
}

function DoubleBar:init()
    DoubleBar.is_enabled = G_reader_settings:isTrue("show_double_bar")
    if DoubleBar.preserved_start_session_time then
        self.start_session_time = DoubleBar.preserved_start_session_time
        DoubleBar.preserved_start_session_time = nil
    end

    self.ui:registerPostReaderReadyCallback(function()
        self.ui.menu:registerToMainMenu(self)
    end)
end

function DoubleBar:onReaderReady()
    if Device:isAndroid() then
        DoubleBar.MARGIN_SIDES =  Screen:scaleBySize(30)
    end
    local duration_raw =  math.floor((os.time() - self.start_session_time))

    if duration_raw < 360 or self.ui.statistics._total_pages < 6 then
        self.start_session_time = os.time()
    end

    self.wpm_session = 0
    if duration_raw > 0 and self.ui.statistics and self.ui.statistics._total_words then
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


    self[1] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.session_time_text,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    self[2] = left_container:new{
        dimen = Geom:new{ w = self.progress_text:getSize().w, self.progress_text:getSize().h },
        self.progress_text,
    }


    self[3] = left_container:new{
        dimen = Geom:new{ w = self.title_text:getSize().w, self.title_text:getSize().h },
        self.title_text,
    }



    self[5] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.chapter_text,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }
    self[6] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_chapter_text,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }


    self.progress_bar  = ProgressWidget:new{
        width = Screen:getSize().w,
        height = 5,
        percentage = 0,
        -- bordercolor = Blitbuffer.COLOR_GRAY,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }



    self[9] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_bar,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }


    self.progress_bar_chapters  = ProgressWidget:new{
        width = Screen:getSize().w,
        height = 5,
        percentage = 0,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }



    self[10] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_bar_chapters,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

end

function DoubleBar:onToggleShowDoubleBar()
    local show_double_bar = G_reader_settings:isTrue("show_double_bar")
    G_reader_settings:saveSetting("show_double_bar", not show_double_bar)
    DoubleBar.is_enabled = not show_double_bar
    self:toggleBar()
end

function DoubleBar:resetLayout()
    -- if self.wpm_text then
    --     self:toggleBar()
    -- end
end

function DoubleBar:onResume()
    self.start_session_time = os.time()
    self:toggleBar()
end


function DoubleBar:onPreserveCurrentSession()
    -- Can be called before ReaderUI:reloadDocument() to not reset the current session
    DoubleBar.preserved_start_session_time = self.start_session_time
end


function DoubleBar:onSwitchTopBar()
    if G_reader_settings:isTrue("show_double_bar") then
        DoubleBar.is_enabled = not DoubleBar.is_enabled
        self:toggleBar()
        UIManager:setDirty("all", "partial")
    end
end


function DoubleBar:toggleBar()
    if DoubleBar.is_enabled then
        local now_t = os.date("*t")
        local daysdiff = now_t.day - os.date("*t",self.start_session_time).day
        if daysdiff > 0 then
            self.start_session_time = os.time()
        end


        local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
        local session_time = datetime.secondsToClockDuration(user_duration_format, os.time() - self.start_session_time, false)

        local duration_raw =  math.floor((os.time() - self.start_session_time))
        if self.ui.statistics and self.ui.statistics._total_words then
            self.wpm_session = math.floor(self.ui.statistics._total_words/duration_raw)
        end
        self.wpm_text:setText(self.wpm_session .. "wpm")

        self.session_time_text:setText(datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock")))
        self.progress_text:setText(("%d de %d"):format(self.view.footer.pageno, self.view.footer.pages))



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
        title = TextWidget.PTF_BOLD_START .. title .. TextWidget.PTF_BOLD_END
        self.title_text:setText(title)

        local chapter = self.ui.toc:getTocTitleByPage(self.view.footer.pageno) ~= ""
        and TextWidget.PTF_BOLD_START .. self.ui.toc:getTocTitleByPage(self.view.footer.pageno) .. TextWidget.PTF_BOLD_END or ""
        self.progress_bar.width = Screen:getSize().w
        self.progress_bar_chapters.width = Screen:getSize().w


        if Device:isAndroid() then
            self.progress_bar.height = 20
            self.progress_bar_chapters.height = 20
        end

        self.chapter_text:setText(chapter)
        self.progress_chapter_text:setText(self.view.footer:getChapterProgress(false))

        self.progress_bar.height = self.title_text._height
        self.progress_bar_chapters.height = self.title_text._height
        self.progress_bar:updateStyle(false, nil)
        self.progress_bar_chapters:updateStyle(false, nil)

        -- self.progress_bar.last = self.pages or self.ui.document:getPageCount()
        -- self.progress_bar.ticks = self.ui.toc:getTocTicksFlattened()
        self.progress_bar:setPercentage(self.view.footer.pageno / self.view.footer.pages)
        self.progress_bar_chapters:setPercentage(self.view.footer:getChapterProgress(true))
    else
        self.session_time_text:setText("")
        self.progress_text:setText("")
        self.title_text:setText("")
        self.chapter_text:setText("")
        self.progress_chapter_text:setText("")
        self.progress_bar.width = 0
        self.progress_bar_chapters.width = 0
    end
end

function DoubleBar:onPageUpdate()
    self:toggleBar()
end

function DoubleBar:paintTo(bb, x, y)
        -- Top left with bar first
        self[9]:paintTo(bb, x, y + DoubleBar.MARGIN_TOP)
        -- self[1]:paintTo(bb, x + DoubleBar.MARGIN_SIDES, y + DoubleBar.MARGIN_TOP)

        -- Top center
        self[3]:paintTo(bb, x + Screen:getWidth()/2 - self[3][1]:getSize().w/2, y + DoubleBar.MARGIN_TOP)

        -- Top right
        -- self[2].dimen = Geom:new{ w = self[2][1]:getSize().w, self[2][1]:getSize().h } -- The text width change and we need to adjust the container dimensions to be able to align it on the right
        -- self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - DoubleBar.MARGIN_SIDES, y + DoubleBar.MARGIN_TOP)

        -- Bottom left with bar first
        self[10]:paintTo(bb, x, Screen:getHeight() - DoubleBar.MARGIN_TOP)
        -- self[4][1].dimen.w = self[4][1][1]:getSize().w
        -- self[4]:paintTo(bb, x + DoubleBar.MARGIN_SIDES, Screen:getHeight() - DoubleBar.MARGIN_BOTTOM)

        -- Bottom center
        self[5]:paintTo(bb, x + Screen:getWidth()/2 - self[5][1][1]:getSize().w/2, Screen:getHeight() - DoubleBar.MARGIN_BOTTOM)

        -- Bottom right
        -- self[6][1].dimen.w = self[6][1][1]:getSize().w
        -- self[6]:paintTo(bb, x + Screen:getWidth() - self[6][1]:getSize().w - DoubleBar.MARGIN_SIDES, Screen:getHeight() - DoubleBar.MARGIN_BOTTOM)
end

-- This is called after self.ui.menu:registerToMainMenu(self) in the init method
-- But in this case registerToMainMenu() needs to be called in readerui.lua because the menu is still not available
-- We do it in the init() function using a registerPostReaderReadyCallback() function
function DoubleBar:addToMainMenu(menu_items)
    local Event = require("ui/event")
    menu_items.show_double_bar = {
        text = _("Show double bar"),
        checked_func = function() return G_reader_settings:isTrue("show_double_bar") end,
        -- enabled_func = function()
        --     local file_type = string.lower(string.match(self.ui.document.file, ".+%.([^.]+)") or "")
        --     return file_type == "epub"
        -- end,
        callback = function()
            UIManager:broadcastEvent(Event:new("ToggleShowDoubleBar"))
        end
    }
end

return DoubleBar
