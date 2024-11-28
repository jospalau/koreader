-- if true then
--     return { disabled = true, }
-- end

local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local LineWidget = require("ui/widget/linewidget")
local Blitbuffer = require("ffi/blitbuffer")
local left_container = require("ui/widget/container/leftcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local Size = require("ui/size")
local Screen = require("device").screen
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local util = require("util")
local _ = require("gettext")

local PageTextInfo = WidgetContainer:extend{
    is_enabled = nil,
    name = "textinfo",
    is_doc_only = true,
}

function PageTextInfo:onDispatcherRegisterActions()
    Dispatcher:registerAction("pagetextinfo_action", {category="none", event="PageTextInfo", title=_("Page text info widget"), general=true,})
end

function PageTextInfo:onPageTextInfo()
    self.is_enabled = not self.is_enabled
    self.settings:saveSetting("is_enabled", self.is_enabled)
    self.settings:flush()
    if self.is_enabled then
        local Screen = require("device").screen
        self:paintTo(Screen.bb, 0, 0)
    end
    UIManager:setDirty("all", "ui")
    -- local popup = InfoMessage:new{
    --     text = _("Test"),
    -- }
    -- UIManager:show(popup)
end

function PageTextInfo:init()

    if not self.settings then self:readSettingsFile() end
    self.is_enabled = self.settings:isTrue("is_enabled")
    -- if not self.is_enabled then
    --     return
    -- end
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    self.width = 400
    self.height = 20

    self.vg1 = VerticalGroup:new{
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
        VerticalSpan:new{width = self.height},
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
        VerticalSpan:new{width = self.height},
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
        VerticalSpan:new{width = self.height},
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
    }

    self.f1 = FrameContainer:new{
        self.vg1,
        background = Blitbuffer.COLOR_WHITE,
        padding = self.height,
        bordersize = 0,
    }

    self.vg2 = VerticalGroup:new{
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
        VerticalSpan:new{width = self.height},
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        },
        VerticalSpan:new{width = self.height},
        left_container:new{
            dimen = Geom:new{ w = self.width, h = self.height },
            TextWidget:new{
                text =  "",
                face = Font:getFace("myfont4"),
                fgcolor = Blitbuffer.COLOR_BLACK,
            },
        }
    }

    self.f2 = FrameContainer:new{
        self.vg2,
        background = Blitbuffer.COLOR_WHITE,
        padding = self.height,
        bordersize = 0,
    }
    -- self.f1 = FrameContainer:new{
    --     left_container:new{
    --         dimen = Geom:new{ w = 80, h = 80 },
    --         self.test,
    --     },
    --     background = Blitbuffer.COLOR_WHITE,
    --     bordersize = 0,
    --     padding = 0,
    --     padding_bottom = self.bottom_padding,
    -- }
    -- self.f2 = FrameContainer:new{
    --     left_container:new{
    --         dimen = Geom:new{ w = 80, h = 80 },
    --         self.test,
    --     },
    --     background = Blitbuffer.COLOR_WHITE,
    --     bordersize = 0,
    --     padding = 0,
    --     padding_bottom = self.bottom_padding,
    -- }


    -- self.f1 = FrameContainer:new{
    --     left_container:new{
    --         dimen = Geom:new{ w = 80, h = 80 },
    --         self.test,
    --     },
    --     background = Blitbuffer.COLOR_WHITE,
    --     bordersize = 0,
    --     padding = 0,
    --     padding_bottom = self.bottom_padding,
    -- }
    -- self.f2 = FrameContainer:new{
    --     left_container:new{
    --         dimen = Geom:new{ w = 80, h = 80 },
    --         self.test,
    --     },
    --     background = Blitbuffer.COLOR_WHITE,
    --     bordersize = 0,
    --     padding = 0,
    --     padding_bottom = self.bottom_padding,
    -- }

    -- self.vertical_frame = VerticalGroup:new{
    --     FrameContainer:new{
    --         left_container:new{
    --             dimen = Geom:new{ w = 80, h = 80 },
    --             self.test,
    --         },
    --         left_container:new{
    --             dimen = Geom:new{ w = 80, h = 80 },
    --             self.test2,
    --         },
    --         background = Blitbuffer.COLOR_WHITE,
    --         bordersize = 0,
    --         padding = 0,
    --         padding_bottom = self.bottom_padding,
    --     },
    -- }
    self.vertical_frame = VerticalGroup:new{}
    table.insert(self.vertical_frame, self.f1)
    table.insert(self.vertical_frame, self.f2)
    -- local vertical_span = VerticalSpan:new{width = Size.span.vertical_default}
    -- table.insert(self.vertical_frame, self.separator_line)
    -- table.insert(self.vertical_frame, vertical_span)
end

function PageTextInfo:readSettingsFile()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/pagetextinfo.lua")
end

function PageTextInfo:onReaderReady()
    self.ui.menu:registerToMainMenu(self)
    self.view:registerViewModule("textinfo", self)
end


-- function PageTextInfo:onPageUpdate()

-- end


-- function PageTextInfo:addToMainMenu(menu_items)
--     menu_items.hello_world = {
--         text = _("Hello World"),
--         -- in which menu this should be appended
--         sorting_hint = "more_tools",
--         -- a callback when tapping
--         callback = function()
--             UIManager:show(InfoMessage:new{
--                 text = _("Hello, plugin world"),
--             })
--         end,
--     }
-- end

function PageTextInfo:addToMainMenu(menu_items)
    menu_items.page_text_info = {
        text = _("Page text info"),
        sub_item_table ={
            {
                text = _("Enable"),
                checked_func = function() return self.is_enabled end,
                callback = function()
                    self.is_enabled = not self.is_enabled
                    self.settings:saveSetting("is_enabled", self.is_enabled)
                    self.settings:flush()
                    return true
                end,
            },
        },
    }
end

function PageTextInfo:paintTo(bb, x, y)
    local total_words = 0
    if self.is_enabled and self.vertical_frame then
        local res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, false)
        if res and res.pos0 and res.pos1 then
            local boxes = self.ui.document:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
            if boxes then
                -- local last_word = ""
                for _, box in ipairs(boxes) do
                    if box.h ~= 0 then
                        -- local t = TextWidget:new{
                        --     text =  "New line",
                        --     face = Font:getFace("myfont4", 6),
                        --     fgcolor = Blitbuffer.COLOR_BLACK,
                        -- }
                        -- t:paintTo(bb, x, box.y)
                            local text_line = self.ui.document._document:getTextFromPositions(box.x, box.y, Screen:getWidth(), box.y, false, true).text
                            text_line = text_line:gsub("’", ""):gsub("‘", ""):gsub("–", ""):gsub("— ", ""):gsub(" ", ""):gsub("”", ""):gsub("“", ""):gsub("”", "…")
                            local wordst = util.splitToWords2(text_line)
                            -- for i = #wordst, 1, -1 do
                            --     if wordst[i] == "’" or wordst[i] == "–" or wordst[i] == " " or wordst[i] == "”" or wordst[i] == "…" or wordst[i] == "…’" then
                            --       table.remove(wordst, i)
                            --     end
                            -- end
                            local words = #wordst
                            -- local dump = require("dump")
                            -- print(dump(wordst))
                            -- Hyphenated words are counted twice since getTextFromPositions returns the whole word for the line.
                            -- They can be removed but it is fine to count them twice
                            -- if last_word:find(util.splitToWords2(text_line)[1]) then
                            -- if util.splitToWords2(text_line)[1] == last_word then
                            --     words = words - 1
                            -- end
                            -- last_word = util.splitToWords2(text_line)[#util.splitToWords2(text_line)]
                            -- print(text_line:sub(1, 10))
                            -- print(text_line:sub(#text_line-10, #text_line))
                            -- if text_line:sub(#text_line, #text_line) == "-" then
                            --     words = words - 1
                            -- end
                            total_words = total_words + words
                            local t = TextWidget:new{
                                text =  words,
                                face = Font:getFace("myfont4", self.ui.document.configurable.font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            }
                            t:paintTo(bb, x, box.y)
                            local t2 = TextWidget:new{
                                text =  total_words,
                                face = Font:getFace("myfont4", self.ui.document.configurable.font_size),
                                fgcolor = Blitbuffer.COLOR_BLACK,
                            }
                            t2:paintTo(bb, x + Screen:getWidth() - t2:getSize().w, box.y)
                    end
                    self.view:drawHighlightRect(bb, x, y, box, "underscore", nil, false)
                end
            end
        end
        local res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, false)
        local nblines = 0
        if res and res.pos0 and res.pos1 then
            local segments = self.ui.document:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
            -- logger.warn(segments)
            nblines = #segments
        end
        res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, true)
        -- logger.warn(res.text)
        local nbwords = 0
        local nbcharacters = 0
        if res and res.text then
            local words = util.splitToWords2(res.text) -- contar palabras
            local characters = res.text -- contar caracteres
            -- logger.warn(words)
            nbwords = #words -- # es equivalente a string.len()
            nbcharacters = #characters
        end
        res = self.ui.document._document:getTextFromPositions(0, 0, Screen:getWidth(), 1, false, true)
        local chars_first_line = 0
        if res and res.text then
            local words = res.text
            chars_first_line = #words
        end

        local duration_raw =  math.floor(((os.time() - self.ui.statistics.start_current_period)/60)* 100) / 100
        local wpm = 0
        if self.ui.statistics._total_words > 0 then
            wpm = math.floor(self.ui.statistics._total_words/duration_raw)
        end
        self.vg1[1][1]:setText("Lines      " .. nblines)
        self.vg1[3][1]:setText("Words      " .. total_words)
        self.vg1[5][1]:setText("Characters " .. nbcharacters)
        self.vg1[7][1]:setText("CFL        " .. chars_first_line)


        self.vg2[1][1]:setText("Total words session " .. self.ui.statistics._total_words)
        self.vg2[3][1]:setText("Total pages session " .. self.ui.statistics._total_pages)
        self.vg2[5][1]:setText("Wpm session         " .. wpm)

        self.vertical_frame:paintTo(bb, x + Screen:getWidth() - self.vertical_frame[1][1]:getSize().w - self.vertical_frame[1].padding, y)
        -- -- This is painted before some other stuff like for instance the dogear widget. This is the way to paint it just after all in the next UI tick.
        -- -- But we leave it commented since sometimes it is painted even over the application menus
        -- UIManager:scheduleIn(0, function()
        --     self.vertical_frame:paintTo(bb, x + Screen:getWidth() -  self.vertical_frame[1][1]:getSize().w - self.vertical_frame[1].padding, y)
        --     local Screen = require("device").screen
        --     -- self:paintTo(Screen.bb, 0, 0)
        --     UIManager:setDirty(self, "ui")
        -- end)

        local times_text = TextWidget:new{
            text =  "",
            face = Font:getFace("myfont3", 12),
            fgcolor = Blitbuffer.COLOR_BLACK,
            invert = true,
        }

        local Device = require("device")
        local datetime = require("datetime")
        local powerd = Device:getPowerDevice()
        local batt_lvl = tostring(powerd:getCapacity())



        local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

        local last_file = "None"
        if G_reader_settings:readSetting("lastfile") ~= nil then
            last_file = G_reader_settings:readSetting("lastfile")
        end


        -- local time_battery_text_text = time .. "|" .. batt_lvl .. "%|" ..  last_file

        -- times_text:setText(time_battery_text_text:reverse())
        -- times_text:paintTo(bb, x - times_text:getSize().w - TopBar.MARGIN_BOTTOM - Screen:scaleBySize(12), y)

        local Screen = Device.screen

        local books_information = FrameContainer:new{
            left_container:new{
                dimen = Geom:new{ w = Screen:getWidth(), h = 12 },
                TextWidget:new{
                    text =  "",
                    face = Font:getFace("myfont3", 12),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            },
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            padding_left = Screen:scaleBySize(10),
            padding_bottom = Screen:scaleBySize(6),
        }

        -- local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
        -- local _, files = self:getList("*.epub")
        -- books_information[1][1]:setText("TF: " .. tostring(#files))

        local ffiutil = require("ffi/util")
        local topbar = self.ui.view[4]
        if G_reader_settings:readSetting("home_dir") and ffiutil.realpath(G_reader_settings:readSetting("home_dir") .. "/stats.lua") then
            local ok, stats = pcall(dofile, G_reader_settings:readSetting("home_dir") .. "/stats.lua")
            local last_days = ""
            for k, v in pairs(stats["stats_last_days"]) do
                last_days = v > 0 and last_days .. " ● " or last_days .. " ○ "
            end
            -- local execute = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub' | wc -l" )
            -- local execute2 = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub.lua' -exec ls {} + | wc -l")
            -- books_information[1][1]:setText("TB: " .. execute:read('*a') .. "TBC: " .. execute2:read('*a'))

            local stat_years = 0
            if topbar then
                stats_year = topbar:getReadThisYearSoFar()
            end
            if stats_year > 0 then
                stats_year = "+" .. stats_year
            end
            books_information[1][1]:setText("B: " .. stats["total_books"]
            .. ", BF: " .. stats["total_books_finished"]
            .. ", BFTM: " .. stats["total_books_finished_this_month"]
            .. ", BFTY: " .. stats["total_books_finished_this_year"]
            .. ", BFLY: " .. stats["total_books_finished_last_year"]
            .. ", BMBR: " .. stats["total_books_mbr"]
            .. ", BTBR: " .. stats["total_books_tbr"]
            .. ", LD: " .. last_days
            .. " " .. stats_year)
        else
            books_information[1][1]:setText("No stats.lua file in home dir")
        end

        -- books_information:paintTo(bb, x + topbar.MARGIN_SIDES, Screen:getHeight() - topbar.MARGIN_BOTTOM)


        local times = FrameContainer:new{
            left_container:new{
                dimen = Geom:new{ w = Screen:getWidth(), h = 12 },
                TextWidget:new{
                    text =  "",
                    face = Font:getFace("myfont3", 12),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            },
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            padding_left = Screen:scaleBySize(10),
            padding_bottom = Screen:scaleBySize(11),
            padding_top = Screen:scaleBySize(6),
        }


        -- times[1][1]:setText(time .. "|" .. batt_lvl .. "%")


        -- local space = FrameContainer:new{
        --     left_container:new{
        --         dimen = Geom:new{ w = Screen:getWidth(), h = 12 },
        --         VerticalSpan:new{width = 29, background = Blitbuffer.COLOR_WHITE},
        --     },
        --     background = Blitbuffer.COLOR_WHITE,
        --     bordersize = 0,
        --     padding = 0,
        -- }

        local total_read = ""
        local total_books = ""
        if topbar then
            total_read = topbar:getTotalRead()
            total_books = topbar:getBooksOpened()
        end
        self.vertical_frame2 = VerticalGroup:new{}
        table.insert(self.vertical_frame2, times)
        -- table.insert(self.vertical_frame2, VerticalSpan:new{width = 8}) -- We set the vertical space using padding for both of the elements that make up the vertical frame
        table.insert(self.vertical_frame2, books_information)

        -- times[1].dimen.w = self.vertical_frame2:getSize().w
        times[1].dimen.wh = self.vertical_frame2:getSize().h
        times[1][1]:setText("BDB: " .. total_books .. ", TR: " .. total_read .. "d")
    self.vertical_frame2:paintTo(bb, x, Screen:getHeight() - self.vertical_frame2:getSize().h )
    end
end
return PageTextInfo
