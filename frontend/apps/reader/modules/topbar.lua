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
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")

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
    is_enabled = G_reader_settings:isTrue("show_top_bar"),
    start_session_time = os.time(),
    initial_read_today = getReadToday(),
    initial_read_month = getReadThisMonth(),
    MARGIN_SIDES = Screen:scaleBySize(10),
    -- El margen de las pantallas, flushed o recessed no es perfecto. La pantalla suele empezar un poco más arriba en casi todos los dispositivos estando un poco por debajo del bezel
    -- Al menos los Kobos y el Boox Palma
    -- Podemos cambiar los márgenes
    -- Para verlo en detalle, es mejor no poner ningún estilo en las barras de progreso
    MARGIN_TOP = Screen:scaleBySize(9),
    MARGIN_BOTTOM = Screen:scaleBySize(9),
    show_top_bar = true,
}

function TopBar:init()
    -- La inicialización del objeto ocurre una única vez pero el método init ocurre cada vez que abrimos el documento
    TopBar.is_enabled = G_reader_settings:isTrue("show_top_bar")
    TopBar.show_top_bar = true
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


    self[4] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.times_text,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
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
        width = 200,
        height = 5,
        percentage = 0,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }

    self[7] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_bar,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }

    self.progress_chapter_bar = ProgressWidget:new{
        width = 200,
        height = 5,
        percentage = 0,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
    }


    self[8] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_chapter_bar,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
    }


    -- self.progress_bar2  = ProgressWidget:new{
    --     width = Screen:getSize().w,
    --     height = 5,
    --     percentage = 0,
    --     tick_width = Screen:scaleBySize(1),
    --     ticks = nil, -- ticks will be populated in self:updateFooterText
    --     last = nil, -- last will be initialized in self:updateFooterText
    --     altbar = true,
    --     altbar_position = 4,
    --     altbar_ticks_height = 12,
    --     altbar_line_thickness = 4,
    --     bordersize = 0,
    --     radius = 0,
    -- }

    self.progress_bar2  = ProgressWidget:new{
        width = Screen:getSize().w,
        height = 5,
        percentage = 0,
        -- bordercolor = Blitbuffer.COLOR_GRAY,
        tick_width = Screen:scaleBySize(1),
        ticks = nil, -- ticks will be populated in self:updateFooterText
        last = nil, -- last will be initialized in self:updateFooterText
        -- bordercolor = Blitbuffer.COLOR_WHITE,
    }

    self[9] = FrameContainer:new{
        left_container:new{
            dimen = Geom:new(),
            self.progress_bar2,
        },
        -- background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        padding_bottom = self.bottom_padding,
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


    self.separator_line = LineWidget:new{
        background = Blitbuffer.COLOR_BLACK,
        style = "solid",
        dimen = Geom:new{
            w = Screen:getSize().w,
            h = Size.line.medium,
        }
    }

    if Device:isAndroid() then
        TopBar.MARGIN_SIDES =  Screen:scaleBySize(30)
    end
end
function TopBar:onToggleShowTopBar()
    local show_top_bar = G_reader_settings:isTrue("show_top_bar")
    G_reader_settings:saveSetting("show_top_bar", not show_top_bar)
    TopBar.is_enabled = not show_top_bar
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
    if G_reader_settings:isTrue("show_top_bar") then
        if TopBar.show_top_bar then
            TopBar.show_top_bar = false
            TopBar.MARGIN_TOP = Screen:scaleBySize(9)
        elseif TopBar.is_enabled then
            TopBar.is_enabled = false
        else
            TopBar.is_enabled = true
            TopBar.show_top_bar = true
            TopBar.MARGIN_TOP = Screen:scaleBySize(9) + self.progress_bar2.height + Screen:scaleBySize(3)
        end
        self:toggleBar()

        -- TopBar.is_enabled = not TopBar.is_enabled
        -- self:toggleBar()
        UIManager:setDirty("all", "partial")
    end
end


function TopBar:toggleBar()
    if TopBar.is_enabled then
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
        self.progress_bar2.width = Screen:getSize().w
        self.progress_bar2.height = 20
        -- -- progress bars size slightly bigger than the font size
        -- self.progress_bar.height = Font:getFace("myfont4").size + 10
        -- self.progress_chapter_bar.height = Font:getFace("myfont4").size + 10

        -- self.progress_bar.height = self.title_text:getSize().h
        -- self.progress_chapter_bar.height = self.title_text:getSize().h

        self.progress_bar.height = 20
        self.progress_chapter_bar.height = 20

        if Device:isAndroid() then
            self.progress_bar.width = 150
            self.progress_chapter_bar.width = 150
        else
            self.progress_bar.width = 250
            self.progress_chapter_bar.width = 250
        end


--
        self.chapter_text:setText(chapter)
        self.progress_chapter_text:setText(self.view.footer:getChapterProgress(false))


        -- self.progress_bar:updateStyle(false, nil)
        self.progress_bar.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        self.progress_bar.fillcolor = Blitbuffer.COLOR_BLACK

        -- self.progress_chapter_bar:updateStyle(false, nil)
        self.progress_chapter_bar.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        self.progress_chapter_bar.fillcolor = Blitbuffer.COLOR_BLACK



        -- self.progress_bar2:updateStyle(false, 5)

        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_BLACK


        -- -- This profile to go with the line widget
        -- self.progress_bar2:updateStyle(false, 5)
        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_WHITE
        -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_BLACK
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_BLACK



        self.progress_bar2:updateStyle(false, 5)
        self.progress_bar2.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        self.progress_bar2.bordercolor = Blitbuffer.COLOR_WHITE
        self.progress_bar2.fillcolor = Blitbuffer.COLOR_BLACK



        -- self.progress_bar2:updateStyle(false, 5)
        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_BLACK
        -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_WHITE
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_DARK_GRAY


        -- self.progress_bar2:updateStyle(false, 5)
        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_BLACK
        -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_WHITE

        -- self.progress_bar2:updateStyle(false, 10)
        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_BLACK


        -- self.progress_bar2:updateStyle(false, 1)
        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_WHITE
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_DARK_GRAY
        -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_BLACK

        -- self.progress_bar2:updateStyle(false, 1)
        -- self.progress_bar2.bgcolor = Blitbuffer.COLOR_WHITE
        -- self.progress_bar2.bordercolor = Blitbuffer.COLOR_BLACK
        -- self.progress_bar2.fillcolor = Blitbuffer.COLOR_DARK_GRAY


        self.progress_bar.last = self.pages or self.ui.document:getPageCount()
        -- self.progress_bar.ticks = self.ui.toc:getTocTicksFlattened()
        self.progress_bar2.last = self.pages or self.ui.document:getPageCount()
        self.progress_bar2.ticks = self.ui.toc:getTocTicksFlattened()
        self.progress_bar:setPercentage(self.view.footer.pageno / self.view.footer.pages)
        self.progress_bar2:setPercentage(self.view.footer.pageno / self.view.footer.pages)
        self.progress_chapter_bar:setPercentage(self.view.footer:getChapterProgress(true))
        -- self.progress_bar.height = self.title_text:getSize().h
        -- self.progress_chapter_bar.height = self.title_text:getSize().h
        if TopBar.show_top_bar == true then
            TopBar.MARGIN_TOP = Screen:scaleBySize(9) + self.progress_bar2.height + Screen:scaleBySize(3)
        end
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
end

function TopBar:paintTo(bb, x, y)
        -- Top left
        if TopBar.show_top_bar then
            self[9]:paintTo(bb, x, y + 15)
            -- self.separator_line:paintTo(bb, x, y + 15)
            -- self[9]:paintTo(bb, x, Screen:getHeight() - 15)
        end
        self[1]:paintTo(bb, x + TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)

        -- Top center

        self[3]:paintTo(bb, x + Screen:getWidth()/2 - self[3][1]:getSize().w/2, y + TopBar.MARGIN_TOP)
        -- self[3]:paintTo(bb, x + Screen:getWidth()/2, y + 20)


        -- Top right
        -- Commented the text, using progress bar
        if not TopBar.show_top_bar then
            self[7]:paintTo(bb, x + Screen:getWidth() - self[7][1][1]:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        end

        self[2].dimen = Geom:new{ w = self[2][1]:getSize().w, self[2][1]:getSize().h } -- The text width change and we need to adjust the container dimensions to be able to align it on the right

        if TopBar.show_top_bar then
            self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        end

        -- Si no se muestra la barra de progreso de arriba, se muestra la de arriba a la derecha
        -- Y si se muestra la de arriba a la derecha, queremos mover el texto unos pocos píxeles a la izquierda
        -- if not TopBar.show_top_bar then
        --     self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - TopBar.MARGIN_SIDES - 20, y + TopBar.MARGIN_TOP)
        -- else
        --     self[2]:paintTo(bb, Screen:getWidth() - self[2]:getSize().w - TopBar.MARGIN_SIDES, y + TopBar.MARGIN_TOP)
        -- end



        -- For the bottom components it is better to use frame containers.
        -- It is better to position them without the dimensions simply passing x and y to the paintTo method
        -- Bottom left
        self[4][1].dimen.w = self[4][1][1]:getSize().w
        self[4]:paintTo(bb, x + TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

        -- Bottom center
        self[5]:paintTo(bb, x + Screen:getWidth()/2 - self[5][1][1]:getSize().w/2, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

        -- Bottom right
        -- Use progress bar
        self[8]:paintTo(bb, x + Screen:getWidth() - self[8][1][1]:getSize().w - TopBar.MARGIN_SIDES, Screen:getHeight() - TopBar.MARGIN_BOTTOM)





        -- self[6][1].dimen.w = self[6][1][1]:getSize().w
        -- -- La barra de progreso de abajo a la derecha se muestra siempre y queremos mover el texto unos pocos píxeles a la izquierda
        -- self[6]:paintTo(bb, x + Screen:getWidth() - self[6][1]:getSize().w - TopBar.MARGIN_SIDES - 20, Screen:getHeight() - TopBar.MARGIN_BOTTOM)

        -- text_container2:paintTo(bb, x + Screen:getWidth() - text_container2:getSize().w - 20, y + 20)
        -- text_container2:paintTo(bb, x + Screen:getWidth()/2 - text_container2:getSize().w/2, y + 20)
end

return TopBar
