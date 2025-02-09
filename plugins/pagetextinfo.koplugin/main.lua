-- if true then
--     return { disabled = true, }
-- end

local Dispatcher = require("dispatcher")  -- luacheck:ignore
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local InputContainer = require("ui/widget/container/inputcontainer")
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
local Device = require("device")
local util = require("util")
local _ = require("gettext")

local PageTextInfo = InputContainer:extend{
    is_enabled = nil,
    name = "pagetextinfo",
    is_doc_only = false,
}

function PageTextInfo:onDispatcherRegisterActions()
    Dispatcher:registerAction("pagetextinfo_action", {category="none", event="PageTextInfo", title=_("Page text info widget"), general=true,})

    -- open_random_favorite = {category="none", event="OpenRandomFav", title=_("Open random book MBR"), general=true},
    Dispatcher:registerAction("series", {category="none", event="ShowSeriesList", title=_("Series"), general=true,})
    Dispatcher:registerAction("generate_favorites", {category="none", event="GenerateFavorites", title=_("Generate favorites"), general=true,})
    Dispatcher:registerAction("filemanager_scripts", {category="none", event="Scripts", title=_("File browser scripts"), general=true, separator=true,})
    Dispatcher:registerAction("filemanager", {category="none", event="Home", title=_("File browser"), general=true,})
    Dispatcher:registerAction("notebook_file", {category="none", event="ShowNotebookFile", title=_("Notebook file"), general=true, separator=true,})
    Dispatcher:registerAction("text_properties", {category="none", event="ShowTextProperties", title=_("Show text properties"), general=true, separator=true,})
    Dispatcher:registerAction("random_profile", {category="none", event="RandomProfile", title=_("Random profile"), general=true, separator=true,})
    Dispatcher:registerAction("get_styles", {category="none", event="GetStyles", title=_("Get styles"), general=true, separator=true,})
    Dispatcher:registerAction("synchronize_code", {category="none", event="SynchronizeCode", title=_("Synchronize code"), general=true, separator=true,})
    Dispatcher:registerAction("synchronize_code_phone", {category="none", event="SynchronizeCodePhone", title=_("Synchronize code phone"), general=true, separator=true,})
    Dispatcher:registerAction("install_last_version", {category="none", event="InstallLastVersion", title=_("Install last KOReader version"), general=true, separator=true,})
    Dispatcher:registerAction("synchronize_statistics", {category="none", event="SynchronizeStatistics", title=_("Synchronize statistics script"), general=true, separator=true,})
    Dispatcher:registerAction("toggle_ssh", {category="none", event="ToggleSSH", title=_("Toggle SSH server"), general=true, separator=true,})
    Dispatcher:registerAction("get_tbr", {category="none", event="GetTBR", title=_("Get TBR"), general=true, separator=true,})
    Dispatcher:registerAction("sync_books", {category="none", event="SyncBooks", title=_("Synchronize Books"), general=true, separator=true,})
    Dispatcher:registerAction("get_text_page", {category="none", event="GetTextPage", title=_("Get text page"), general=true, separator=true,})
    Dispatcher:registerAction("pull_config", {category="none", event="PullConfig", title=_("Pull configuration"), general=true, separator=true,})
    Dispatcher:registerAction("push_config", {category="none", event="PushConfig", title=_("Push configuration"), general=true, separator=true,})
    Dispatcher:registerAction("get_last_pushing_config", {category="none", event="GetLastPushingConfig", title=_("Who pushed last config"), general=true, separator=true,})
    Dispatcher:registerAction("pull_sidecar_files", {category="none", event="PullSidecarFiles", title=_("Pull sidecar files"), general=true, separator=true,})
    Dispatcher:registerAction("push_sidecar_files", {category="none", event="PushSidecarFiles", title=_("Push sidecar files"), general=true, separator=true,})
    Dispatcher:registerAction("get_last_pushing_sidecars", {category="none", event="GetLastPushingSidecars", title=_("Who pushed last sidecars"), general=true, separator=true,})
    Dispatcher:registerAction("wifi_on_kindle", {category="none", event="TurnOnWifiKindle", title=_("Turn on Wi-Fi Kindle"), general=true, separator=true,})
    Dispatcher:registerAction("print_chapter_left_fbink", {category="none", event="PrintChapterLeftFbink", title=_("Print chapter left Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("print_session_duration_fbink", {category="none", event="PrintSessionDurationFbink", title=_("Print session duration Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("print_progress_book_fbink", {category="none", event="PrintProgressBookFbink", title=_("Print progress book Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("print_clock_fbink", {category="none", event="PrintClockFbink", title=_("Print clock Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("print_duration_chapter_fbink", {category="none", event="PrintDurationChapterFbink", title=_("Print duration chapter Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("print_duration_next_chapter_fbink", {category="none", event="PrintDurationNextChapterFbink", title=_("Print duration next chapter Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("toggle_rsyncd", {category="none", event="ToggleRsyncdService", title=_("Toggle Rsyncd service"), general=true, separator=true,})
    Dispatcher:registerAction("print_wpm_session_fbink", {category="none", event="PrintWpmSessionFbink", title=_("Print wpm session Fbink"), general=true, separator=true,})
    Dispatcher:registerAction("show_db_stats", {category="none", event="ShowDbStats", title=_("Show db stats"), general=true, separator=true,})
    Dispatcher:registerAction("move_status_bar", {category="none", event="MoveStatusBar", title=_("Move status bar"), general=true, separator=true,})
    Dispatcher:registerAction("switch_status_bar_text", {category="none", event="SwitchStatusBarText", title=_("Switch status bar text"), general=true, separator=true,})
    Dispatcher:registerAction("switch_top_bar", {category="none", event="SwitchTopBar", title=_("Switch top bar"), general=true, separator=true,})
    Dispatcher:registerAction("test", {category="none", event="Test", title=_("Test"), general=true, separator=true,})
    Dispatcher:registerAction("toggle_horizontal_vertical", {category="none", event="ToggleHorizontalVertical", title=_("Toggle screen layout"), general=true, separator=true,})
    Dispatcher:registerAction("search_dictionary", {category="none", event="SearchDictionary", title=_("Search dictionary"), general=true, separator=true,})
    Dispatcher:registerAction("show_heatmap", {category="none", event="ShowHeatmapView", title=_("Show heatmap"), general=true, separator=true,})
    Dispatcher:registerAction("show_general_stats", {category="none", event="ShowGeneralStats", title=_("Show general stats"), general=true, separator=true,})
    Dispatcher:registerAction("adjust_margins_topbar", {category="none", event="AdjustMarginsTopbar", title=_("Adjust margins topbar"), general=true, separator=true,})
    Dispatcher:registerAction("show_notes_footer", {category="none", event="ShowNotesFooter", title=_("Show notes on footer"), general=true, separator=true,})
    Dispatcher:registerAction("file_search", {category="none", event="ShowFileSearch", title=_("File search"), filemanager=true, separator=true,})
    Dispatcher:registerAction("file_search_all", {category="none", event="ShowFileSearchLists", title=_("File search all"), filemanager=true, separator=true,})
    Dispatcher:registerAction("file_search_all_recent", {category="none", event="ShowFileSearchLists", arg={recent = true}, title=_("File search all recent"), filemanager=true, separator=true,})
    Dispatcher:registerAction("file_search_all_completed", {category="none", event="ShowFileSearchAllCompleted", title=_("File search all recent"), filemanager=true, separator=true,})
    Dispatcher:registerAction("mbr", {category="none", event="ShowHistMBR", title=_("MBR"), general=true,})
    Dispatcher:registerAction("tbr", {category="none", event="ShowHistTBR", title=_("TBR"), general=true,})
    Dispatcher:registerAction("toggle_status_bar", {category="none", event="ToggleFooterMode", title=_("Toggle status bar cycle"), reader=true,})
    Dispatcher:registerAction("toggle_status_bar_back", {category="none", event="ToggleFooterModeBack", title=_("Toggle status bar cycle back"), reader=true,})
    Dispatcher:registerAction("toggle_status_bar_onoff", {category="none", event="ToggleStatusBarOnOff", title=_("Toggle status bar on/off"), reader=true,})
    Dispatcher:registerAction("status_bar_just_progress_bar", {category="none", event="StatusBarJustProgressBar", title=_("Status bar just progress bar"), reader=true, separator=true,})
    Dispatcher:registerAction("toggle_reclaim_height", {category="none", event="ToggleReclaimHeight", title=_("Toggle reclaim height"), reader=true,})
    Dispatcher:registerAction("toggle_hyphenation", {category="none", event="ToggleHyphenation", title=_("Toggle hyphenation"), reader=true, separator=true,})
    Dispatcher:registerAction("increase_weight", {category="none", event="IncreaseWeightSize", title=_("Increase weight size"), rolling=true,})
    Dispatcher:registerAction("decrease_weight", {category="none", event="DecreaseWeightSize", title=_("Decrease weight size"), rolling=true,})
    Dispatcher:registerAction("toggle_sort_by_mode", {category="none", event="ToggleSortByMode", title=_("Toggle sort by mode"), general=true,})
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

function PageTextInfo:initGesListener()
    if not Device:isTouchDevice() then return end
    self.ui:registerTouchZones({

        {
            id = "pagetextinfo_double_tap",
            ges = "double_tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1,
            },
            handler = function(ges) return self:onDoubleTap(nil, ges) end,
        },
    })
end
function PageTextInfo:toggleHighlightAllWordsVocabulary(toggle)
    self.settings:saveSetting("highlight_all_words_vocabulary", toggle)
    self.settings:flush()
    if toggle then
        self:updateWordsVocabulary()
    end
    UIManager:setDirty("all", "full")
end



-- In order for double tap events to arrive we need to configure the gestures plugin:
-- Menu gear icon - Taps and gestures - Gesture manager - Double tap and we set Left side and Right side to Pass through

-- Originally, the OnDoubleTap() event handler function was readerrolling but it was not working because I was using a dispatcher action (defined now in this plugin)
-- configured for the left and right side double taps events of the gesture plugin

-- Original comment:
-- This won't work but I leave it as it is because I set the double tap gesture ready in this source in case we want to do something else with this or other gestures in the future
-- Instead, we are using a SearchDictionary event defined in the source dispatcher.lua with a corresponding action named Search dictionary
-- This Search dictionary action is assigned to double tap in both Left side and Right side in the Taps and gestures configuration instead of Turn pages with a value of 10 which is the default
-- The event is captured in the source readerui.lua and it is exactly the same as this, we turn 10 or -10 pages if we double tap on the right or left sides, or we call the dictionary if we double tap any other place
-- If we want to use this handler for the gesture, we have to set Pass through for both Left side and Right side in the Taps and gestures configuration
-- For the hold action press modification, I modified the readerhighlight.lua source which is capturing the hold event
function PageTextInfo:onDoubleTap(_, ges)
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub"  then return end
    local res = self.ui.document._document:getTextFromPositions(ges.pos.x, ges.pos.y,
                ges.pos.x, ges.pos.y, false, false)
    if ges.pos.x < Screen:scaleBySize(40) and not G_reader_settings:isTrue("ignore_hold_corners") then
        self.ui.rolling:onGotoViewRel(-10)
    elseif ges.pos.x > Screen:getWidth() - Screen:scaleBySize(40) and not G_reader_settings:isTrue("ignore_hold_corners") then
        self.ui.rolling:onGotoViewRel(10)
    else
        if res and res.text then
            local words = util.splitToWords2(res.text)
            if #words == 1 then
                local boxes = self.ui.document:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
                local word_boxes
                if boxes ~= nil then
                    word_boxes = {}
                    for i, box in ipairs(boxes) do
                        word_boxes[i] = self.ui.view:pageToScreenTransform(res.pos0.page, box)
                    end
                end
                self.ui.dictionary:onLookupWord(util.cleanupSelectedText(res.text), false, boxes)
                -- self:handleEvent(Event:new("LookupWord", util.cleanupSelectedText(res.text)))
            end
        end
    end
end

function PageTextInfo:init()
    if not self.settings then self:readSettingsFile() end
    self.is_enabled = self.settings:isTrue("is_enabled")

    -- if PageTextInfo.preserved_hightlight_all_notes then
    --     self.settings:saveSetting("highlight_all_notes", PageTextInfo.preserved_hightlight_all_notes)
    --     PageTextInfo.preserved_hightlight_all_notes = nil
    --     self.settings:flush()
    -- end

    -- if PageTextInfo.preserved_highlight_all_words_vocabulary then
    --     self.settings:saveSetting("highlight_all_words_vocabulary",  PageTextInfo.preserved_highlight_all_words_vocabulary)
    --     PageTextInfo.preserved_highlight_all_words_vocabulary = nil
    --     self.settings:flush()
    -- end




    -- if not self.is_enabled then
    --     return
    -- end
    self:onDispatcherRegisterActions()
    self:initGesListener()

    -- We call the function registerToMainMenu() here if we want the menu entry to be shown both for the fm and the reader top menus
    -- If we want the menu entry to be shown just for the reader like in this plugin, better to call it in the onReaderReady() event handler function
    -- In both cases we need to define the function PageTextInfo:addToMainMenu() with the custom menu items
    -- and configure them in a proper menu section adding the name given to the menu items (menu_items.pagetextinfo)
    -- in the filemanager_menu_order.lua source for the fm or in the reader_menu_order.lua source for the reader
    -- self.ui.menu:registerToMainMenu(self)

    -- Not needed since it is automatically available
    -- self.ui.pagetextinfo = self

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
    self.view:registerViewModule("pagetextinfo", self)
end


function PageTextInfo:onPageUpdate(pageno)
    -- Avoid double execution when loading document
    if self.pageno == nil then self.pageno = pageno return end
    self.pageno = pageno

    if self.settings:isTrue("highlight_all_words_vocabulary") and util.getFileNameSuffix(self.ui.document.file) == "epub" then
        self:updateWordsVocabulary()
    end
    if self.settings:isTrue("highlight_all_notes") and util.getFileNameSuffix(self.ui.document.file) == "epub" then
        self:updateNotes()
    end
end


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
    -- If we don't want this being called for the filemanager, better to call self.ui.menu:registerToMainMenu(self) in the onReaderReady() event handler function
    -- Although we can set in the init() function and skip it like this:
    -- if require("apps/filemanager/filemanager").instance then return end
    menu_items.pagetextinfo = {
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
            {
                text = _("Highlight"),
                sub_item_table ={
                    {
                        text = _("Highlight all notes"),
                        checked_func = function() return self.settings:isTrue("highlight_all_notes") end,
                        callback = function()
                            local highlight_all_notes = self.settings:isTrue("highlight_all_notes")
                            self.settings:saveSetting("highlight_all_notes", not highlight_all_notes)
                            -- self.ui:reloadDocument(nil, true) -- seamless reload (no infomsg, no flash)
                            self:updateNotes()
                            UIManager:setDirty("all", "full")
                            self.settings:flush()
                            return true
                        end,
                    },
                    {
                        text = _("Highlight all words vocabulary"),
                        checked_func = function() return self.settings:isTrue("highlight_all_words_vocabulary") end,
                        -- enabled_func = function()
                        --     return false
                        -- end,
                        callback = function()
                            local highlight_all_words_vocabulary = self.settings:isTrue("highlight_all_words_vocabulary")
                            self.settings:saveSetting("highlight_all_words_vocabulary", not highlight_all_words_vocabulary)
                            -- self.ui:reloadDocument(nil, true) -- seamless reload (no infomsg, no flash)
                            self:updateWordsVocabulary()
                            UIManager:setDirty("all", "full")
                            self.settings:flush()
                            return true
                        end,
                    }
                },
            }
        },
    }
end

-- function PageTextInfo:updateNotes()
--     -- self.search:fullTextSearch("Citra")
--     self.pages_notes = {}
--     self.notes = {}
--     local annotations = self.ui.annotation.annotations
--     for i, item in ipairs(annotations) do
--         if item.note and not item.text:find("%s+") then
--             item.words = self.document:findAllText(item.text, true, 5, 5000, 0, false)
--             table.insert(self.notes, item)
--             for i, word in ipairs(item.words) do
--                 word.note = item.note
--                 local page = self.document:getPageFromXPointer(word.start)
--                 if not self.pages_notes[page] then
--                     self.pages_notes[page]={}
--                 end
--                 table.insert(self.pages_notes[page], word)
--                 local page2 = self.document:getPageFromXPointer(word["end"])
--                 if not self.pages_notes[page2] then
--                     self.pages_notes[page2]={}
--                 end
--                 table.insert(self.pages_notes[page2], word)
--             end
--         end
--     end

--     --self.words = self.document:findAllText("Citra", true, 5, 5000, 0, false)
--     --local dump = require("dump")
--     --print(dump(self.notes))
-- end


function PageTextInfo:onCloseDocument()
    self.ui.gestures:onIgnoreHoldCorners(false)
    self.ui.disable_double_tap = false
    self.settings:saveSetting("highlight_all_notes", false)
    self.settings:saveSetting("highlight_all_words_vocabulary", false)
    self.settings:flush()
end

-- function PageTextInfo:onPreserveCurrentSession()
--     PageTextInfo.preserved_hightlight_all_notes = self.settings:readSetting("highlight_all_notes")
--     PageTextInfo.preserved_highlight_all_words_vocabulary = self.settings:readSetting("highlight_all_words_vocabulary")
-- end

function PageTextInfo:updateNotes()
    -- self.search:fullTextSearch("Citra")
    self.pages_notes = {}
    self.notes = {}
    local annotations = self.ui.annotation.annotations
    local res = self.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, false)
    if res and res.text then
        local t = util.splitToWords2(res.text) -- contar palabras
        local words_page = {}
        for i=1, #t do
            words_page[t[i]] = "";
        end
        if words_page and annotations then
            for i, item in ipairs(annotations) do
                if words_page[item.text] then
                    local words = self.document:findText(item.text, 1, false, true, -1, false, 15)
                    if item.note and not item.text:find("%s+") then
                        table.insert(self.notes, item)
                        for i, word in ipairs(words) do
                            word.note = item.note
                            local page = self.document:getPageFromXPointer(word.start)
                            if not self.pages_notes[page] then
                                self.pages_notes[page]={}
                            end
                            table.insert(self.pages_notes[page], word)
                            local page2 = self.document:getPageFromXPointer(word["end"])
                            if not self.pages_notes[page2] then
                                self.pages_notes[page2]={}
                            end
                            table.insert(self.pages_notes[page2], word)
                        end
                    end
                end
            end
        end
    end
    self.ui.document:clearSelection()
end

function PageTextInfo:updateWordsVocabulary()

    local db_location = require("datastorage"):getSettingsDir() .. "/vocabulary_builder.sqlite3"
    sql_stmt = "SELECT distinct(word) FROM vocabulary"
    local conn = require("lua-ljsqlite3/init").open(db_location)
    stmt = conn:prepare(sql_stmt)

    --local row, names = stmt:step({}, {})
    self.words = {}
    -- self.all_words = ""
    local t = {}
    row = {}
    while stmt:step(row) do
        local word = row[1]
        if not word:find("%s+") then -- and word:len() > 3 then
            -- self.all_words = self.all_words .. word .. "|"
            table.insert(t, word)
        end
    end

    conn:close()
    self.all_words = {}
    for i=1, #t do
        self.all_words[t[i]] = "";
    end


    -- Using regular expressions to get full words is very slow and then we have to remove the characters used in them
    -- Searching text without regular expressions we won't get words, we will get the position in the dom (start and end)
    -- for each of the places the text if found wether the full word or the text inside a word and we want full words to highlight them
    -- When painting in the source readerview.lua, we get the boxes from the positions and using the boxes we can get the fulls words to highlight them
    if self.all_words then
        local res = self.document._document:getTextFromPositions(0, 0, Screen:getWidth(), Screen:getHeight(), false, false)
        if res and res.text then
            -- print(res.pos0)
            -- print(res.pos1)
            local words_page = util.splitToWords2(res.text) -- contar palabras
            if words_page and self.all_words then
                for i = 1, #words_page do
                    local word_page = words_page[i] --:gsub("[^%w%s]+", "")
                    if i == 1 or self.all_words[word_page] then
                        local words  = {}
                        if i > 1 then
                            -- words = self.document:findText(word_page, 1, false, true, -1, false, 100)
                            -- words = self.document:findText("[ ^]+" .. word_page .. "[ .,!?^]+", 1, false, true, -1, true, 5)
                            words = self.document:findText(word_page, 1, false, true, -1, false, 40)
                        else
                            -- local cre = require("document/credocument"):engineInit()
                            local cre = require("libs/libkoreader-cre")
                            local suggested_hyphenation = cre.getHyphenationForWord(word_page)
                            if self.all_words[word_page] and suggested_hyphenation:find("-") then
                                word_page = suggested_hyphenation:sub(suggested_hyphenation:find("-") + 1, suggested_hyphenation:len())
                                words = self.document:findText(word_page, 1, false, true, -1, false, 1) -- Page not used, set -1
                                if not words then
                                    word_page = suggested_hyphenation:sub(suggested_hyphenation:find("-") + 1, suggested_hyphenation:len()):gsub("-","")
                                    words = self.document:findText(word_page, 1, false, true, -1, false, 1) -- Page not used, set -1
                                end
                            elseif self.all_words[word_page] then
                                -- words = self.document:findText("[ ^]+" .. word_page .. "[ .,!?^]+", 1, false, true, -1, true, 5)
                                words = self.document:findText(word_page, 1, false, true, -1, false, 40)
                            end
                        end
                        if words then
                            for j = 1, #words do
                                local wordi = words[j]
                                -- First result of the first word of the page in case is hyphenated
                                -- In this case we want always
                                if i == 1 and j == 1 then
                                    wordi.text = nil
                                else
                                    wordi.text = word_page
                                end

                                local word = self.document:getTextFromXPointers(wordi.start, wordi["end"])
                                -- Not using regular expressions
                                -- print(word)
                                -- print(wordi.start)
                                -- if word:sub(word:len()) == " " then
                                --     local pos = tonumber(wordi["end"]:sub(wordi["end"]:find("%.") + 1, wordi["end"]:len()))
                                --     pos = pos - 1
                                --     wordi["end"] = wordi["end"]:sub(1, wordi["end"]:find("%.") - 1) .. "." .. pos
                                --     word = self.document:getTextFromXPointers(wordi.start, wordi["end"])
                                -- end
                                -- if word:sub(word:len()) == "." or
                                --     word:sub(word:len()) == "," or
                                --     word:sub(word:len()) == "!" or
                                --     word:sub(word:len()) == "?" then
                                --     local pos = tonumber(wordi["end"]:sub(wordi["end"]:find("%.") + 1, wordi["end"]:len()))
                                --     pos = pos - 1
                                --     wordi["end"] = wordi["end"]:sub(1, wordi["end"]:find("%.") - 1) .. "." .. pos
                                -- end
                                local page = self.document:getPageFromXPointer(wordi.start)
                                if not self.words[page] then
                                    self.words[page] = {}
                                end
                                table.insert(self.words[page], wordi)
                                local page2 = self.document:getPageFromXPointer(wordi["end"])
                                if not self.words[page2] then
                                    self.words[page2] = {}
                                end
                                table.insert(self.words[page2], wordi)
                            end
                        end
                    end
                end
            end
        end
    end

    -- if all_words then
    --     all_words = all_words:sub(1, all_words:len() - 1)
    --     local words = self.document:findAllText(all_words, true, 5, 300000, 0, false)
    --     if words then
    --         for i, wordi in ipairs(words) do
    --             local page = self.document:getPageFromXPointer(wordi.start)
    --             if not self.words[page] then
    --                 self.words[page]={}
    --             end
    --             table.insert(self.words[page], wordi)
    --             local page2 = self.document:getPageFromXPointer(wordi["end"])
    --             if not self.words[page2] then
    --                 self.words[page2]={}
    --             end
    --             table.insert(self.words[page2], wordi)
    --         end
    --     end
    -- end

    -- if self.all_words then
    --     self.all_words = self.all_words:sub(1, self.all_words:len() - 1)
    --     local words = self.document:findText(self.all_words, 1, false, true, -1, true, 100) -- Page not used, set -1
    --     if words then
    --         for i, wordi in ipairs(words) do
    --             local page = self.document:getPageFromXPointer(wordi.start)
    --             if not self.words[page] then
    --                 self.words[page]={}
    --             end
    --             table.insert(self.words[page], wordi)
    --             local page2 = self.document:getPageFromXPointer(wordi["end"])
    --             if not self.words[page2] then
    --                 self.words[page2]={}
    --             end
    --             table.insert(self.words[page2], wordi)
    --         end
    --     end
    -- end
    -- In the cre.cpp source findText() function, there is a call to doc->text_view->selectWords( words ); when looking for words
    -- But when it finishes doesn't called doc->text_view->clearSelection(); like thefindAllText() function does
    -- The result is that the words are highlighted by the CREngine
    -- But only happens here when loading the document. It does not happen when turning pages
    -- It should be done in the cre.cpp source but I do it here since I haven't found any other issue
    self.ui.document:clearSelection()
end
function PageTextInfo:paintTo(bb, x, y)
    if util.getFileNameSuffix(self.ui.document.file) ~= "epub" then return end
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

        -- local times_text = TextWidget:new{
        --     text =  "",
        --     face = Font:getFace("myfont3", 12),
        --     fgcolor = Blitbuffer.COLOR_BLACK,
        --     invert = true,
        -- }

        -- local Device = require("device")
        -- local datetime = require("datetime")
        -- local powerd = Device:getPowerDevice()
        -- local batt_lvl = tostring(powerd:getCapacity())



        -- local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))

        -- local last_file = "None"
        -- if G_reader_settings:readSetting("lastfile") ~= nil then
        --     last_file = G_reader_settings:readSetting("lastfile")
        -- end


        -- -- local time_battery_text_text = time .. "|" .. batt_lvl .. "%|" ..  last_file

        -- -- times_text:setText(time_battery_text_text:reverse())
        -- -- times_text:paintTo(bb, x - times_text:getSize().w - TopBar.MARGIN_BOTTOM - Screen:scaleBySize(12), y)

        -- local Screen = Device.screen

        -- local books_information = FrameContainer:new{
        --     left_container:new{
        --         dimen = Geom:new{ w = Screen:getWidth(), h = 12 },
        --         TextWidget:new{
        --             text =  "",
        --             face = Font:getFace("myfont3", 12),
        --             fgcolor = Blitbuffer.COLOR_BLACK,
        --         },
        --     },
        --     background = Blitbuffer.COLOR_WHITE,
        --     bordersize = 0,
        --     padding = 0,
        --     padding_left = Screen:scaleBySize(10),
        --     padding_bottom = Screen:scaleBySize(6),
        -- }

        -- -- local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
        -- -- local _, files = self:getList("*.epub")
        -- -- books_information[1][1]:setText("TF: " .. tostring(#files))

        -- local ffiutil = require("ffi/util")
        -- local topbar = self.ui.view[4]
        -- if G_reader_settings:readSetting("home_dir") and ffiutil.realpath(G_reader_settings:readSetting("home_dir") .. "/stats.lua") then
        --     local ok, stats = pcall(dofile, G_reader_settings:readSetting("home_dir") .. "/stats.lua")
        --     local last_days = ""
        --     for k, v in pairs(stats["stats_last_days"]) do
        --         last_days = v > 0 and last_days .. " ● " or last_days .. " ○ "
        --     end
        --     -- local execute = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub' | wc -l" )
        --     -- local execute2 = io.popen("find " .. G_reader_settings:readSetting("home_dir") .. " -iname '*.epub.lua' -exec ls {} + | wc -l")
        --     -- books_information[1][1]:setText("TB: " .. execute:read('*a') .. "TBC: " .. execute2:read('*a'))

        --     local stat_years = 0
        --     if topbar then
        --         stats_year = topbar:getReadThisYearSoFar()
        --     end
        --     if stats_year > 0 then
        --         stats_year = "+" .. stats_year
        --     end
        --     books_information[1][1]:setText("B: " .. stats["total_books"]
        --     .. ", BF: " .. stats["total_books_finished"]
        --     .. ", BFTM: " .. stats["total_books_finished_this_month"]
        --     .. ", BFTY: " .. stats["total_books_finished_this_year"]
        --     .. ", BFLY: " .. stats["total_books_finished_last_year"]
        --     .. ", BMBR: " .. stats["total_books_mbr"]
        --     .. ", BTBR: " .. stats["total_books_tbr"]
        --     .. ", LD: " .. last_days
        --     .. " " .. stats_year)
        -- else
        --     books_information[1][1]:setText("No stats.lua file in home dir")
        -- end

        -- -- books_information:paintTo(bb, x + topbar.MARGIN_SIDES, Screen:getHeight() - topbar.MARGIN_BOTTOM)


        -- local times = FrameContainer:new{
        --     left_container:new{
        --         dimen = Geom:new{ w = Screen:getWidth(), h = 12 },
        --         TextWidget:new{
        --             text =  "",
        --             face = Font:getFace("myfont3", 12),
        --             fgcolor = Blitbuffer.COLOR_BLACK,
        --         },
        --     },
        --     background = Blitbuffer.COLOR_WHITE,
        --     bordersize = 0,
        --     padding = 0,
        --     padding_left = Screen:scaleBySize(10),
        --     padding_bottom = Screen:scaleBySize(11),
        --     padding_top = Screen:scaleBySize(6),
        -- }


        -- -- times[1][1]:setText(time .. "|" .. batt_lvl .. "%")


        -- -- local space = FrameContainer:new{
        -- --     left_container:new{
        -- --         dimen = Geom:new{ w = Screen:getWidth(), h = 12 },
        -- --         VerticalSpan:new{width = 29, background = Blitbuffer.COLOR_WHITE},
        -- --     },
        -- --     background = Blitbuffer.COLOR_WHITE,
        -- --     bordersize = 0,
        -- --     padding = 0,
        -- -- }

        -- local total_read = ""
        -- local total_books = ""
        -- if topbar then
        --     total_read = topbar:getTotalRead()
        --     total_books = topbar:getBooksOpened()
        -- end
        -- self.vertical_frame2 = VerticalGroup:new{}
        -- table.insert(self.vertical_frame2, times)
        -- -- table.insert(self.vertical_frame2, VerticalSpan:new{width = 8}) -- We set the vertical space using padding for both of the elements that make up the vertical frame
        -- table.insert(self.vertical_frame2, books_information)

        -- -- times[1].dimen.w = self.vertical_frame2:getSize().w
        -- times[1].dimen.wh = self.vertical_frame2:getSize().h
        -- times[1][1]:setText("BDB: " .. total_books .. ", TR: " .. total_read .. "d")
        -- self.vertical_frame2:paintTo(bb, x, Screen:getHeight() - self.vertical_frame2:getSize().h )
    end
end

-- Moved from readerui.lua. It won't be used since I handle double taps events in this plugin
-- function ReaderUI:onSearchDictionary()
--     if util.getFileNameSuffix(self.document.file) ~= "epub"  then return end
--     if self.lastevent  then
--         local res = self.document._document:getTextFromPositions(self.lastevent.gesture.pos.x, self.lastevent.gesture.pos.y,
--                     self.lastevent.gesture.pos.x, self.lastevent.gesture.pos.y, false, false)

--         if self.lastevent.gesture.pos.x < math.max(Screen:scaleBySize(40), Screen:scaleBySize(self.document.configurable.h_page_margins[1])) then
--             if not G_reader_settings:isTrue("ignore_hold_corners") then
--                 self.rolling:onGotoViewRel(-10)
--             end
--         elseif self.lastevent.gesture.pos.x > Screen:getWidth() - math.max(Screen:scaleBySize(40), Screen:scaleBySize(self.document.configurable.h_page_margins[1])) then
--             if not G_reader_settings:isTrue("ignore_hold_corners") then
--                 self.rolling:onGotoViewRel(10)
--             end
--         else
--             if res and res.text then
--                 local words = util.splitToWords2(res.text)
--                 if #words == 1 then
--                     local boxes = self.document:getScreenBoxesFromPositions(res.pos0, res.pos1, true)
--                     local word_boxes
--                     if boxes ~= nil then
--                         word_boxes = {}
--                         for i, box in ipairs(boxes) do
--                             word_boxes[i] = self.view:pageToScreenTransform(res.pos0.page, box)
--                         end
--                     end
--                     self.dictionary:onLookupWord(util.cleanupSelectedText(res.text), false, boxes)
--                     -- self:handleEvent(Event:new("LookupWord", util.cleanupSelectedText(res.text)))
--                 end
--             end
--         end
--     end
-- end

-- function ReaderUI:onOpenRandomFav()
--     self:switchDocument(self.menu:getRandomFav())
-- end

return PageTextInfo
