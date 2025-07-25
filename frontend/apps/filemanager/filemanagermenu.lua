local BD = require("ui/bidi")
local BookList = require("ui/widget/booklist")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local KeyValuePage = require("ui/widget/keyvaluepage")
local PluginLoader = require("pluginloader")
local SetDefaults = require("apps/filemanager/filemanagersetdefaults")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local dbg = require("dbg")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util  = require("util")
local _ = require("gettext")
local T = ffiUtil.template

local FileManagerMenu = InputContainer:extend{
    tab_item_table = nil,
    menu_items = nil, -- table, mandatory
    registered_widgets = nil,
}

function FileManagerMenu:init()
    self.menu_items = {
        ["KOMenu:menu_buttons"] = {
            -- top menu
        },
        -- items in top menu
        filemanager_settings = {
            icon = "appbar.menu2",
        },
        setting = {
            icon = "appbar.settings",
        },
        tools = {
            icon = "appbar.tools",
        },
        search = {
            icon = "appbar.search",
        },
        main = {
            icon = "appbar.menu",
        },
    }

    self.registered_widgets = {}

    self:registerKeyEvents()

    self.activation_menu = G_reader_settings:readSetting("activate_menu")
    if self.activation_menu == nil then
        self.activation_menu = "swipe_tap"
    end
end

function FileManagerMenu:registerKeyEvents()
    if Device:hasKeys() then
        self.key_events.KeyPressShowMenu = { { "Menu" } }
        if Device:hasFewKeys() then
            self.key_events.KeyPressShowMenu = { { { "Menu", "Right" } } }
        end
        if Device:hasScreenKB() then
            self.key_events.OpenLastDoc = { { "ScreenKB", "Back" } }
        end
    end
end

FileManagerMenu.onPhysicalKeyboardConnected = FileManagerMenu.registerKeyEvents

-- NOTE: FileManager emits a SetDimensions on init, it's our only caller
function FileManagerMenu:initGesListener()
    if not Device:isTouchDevice() then return end

    local DTAP_ZONE_MENU = G_defaults:readSetting("DTAP_ZONE_MENU")
    local DTAP_ZONE_MENU_EXT = G_defaults:readSetting("DTAP_ZONE_MENU_EXT")
    self:registerTouchZones({
        {
            id = "filemanager_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU.x, ratio_y = DTAP_ZONE_MENU.y,
                ratio_w = DTAP_ZONE_MENU.w, ratio_h = DTAP_ZONE_MENU.h,
            },
            handler = function(ges) return self:onTapShowMenu(ges) end,
        },
        {
            id = "filemanager_ext_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU_EXT.x, ratio_y = DTAP_ZONE_MENU_EXT.y,
                ratio_w = DTAP_ZONE_MENU_EXT.w, ratio_h = DTAP_ZONE_MENU_EXT.h,
            },
            overrides = {
                "filemanager_tap",
            },
            handler = function(ges) return self:onTapShowMenu(ges) end,
        },
        {
            id = "filemanager_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU.x, ratio_y = DTAP_ZONE_MENU.y,
                ratio_w = DTAP_ZONE_MENU.w, ratio_h = DTAP_ZONE_MENU.h,
            },
            overrides = {
                "rolling_swipe",
                "paging_swipe",
            },
            handler = function(ges) return self:onSwipeShowMenu(ges) end,
        },
        {
            id = "filemanager_ext_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = DTAP_ZONE_MENU_EXT.x, ratio_y = DTAP_ZONE_MENU_EXT.y,
                ratio_w = DTAP_ZONE_MENU_EXT.w, ratio_h = DTAP_ZONE_MENU_EXT.h,
            },
            overrides = {
                "filemanager_swipe",
            },
            handler = function(ges) return self:onSwipeShowMenu(ges) end,
        },
    })
end

function FileManagerMenu:onOpenLastDoc()
    local last_file = G_reader_settings:readSetting("lastfile")
    if not last_file or lfs.attributes(last_file, "mode") ~= "file" then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = _("Cannot open last document"),
        })
        return
    end
    local BookList = require("ui/widget/booklist")
    if BookList.getBookStatus(last_file) ~= "reading" then
        local InfoMessage = require("ui/widget/infomessage")
        local title = last_file:gsub(".epub","")
        title = select(2, util.splitFilePathName(title))
        UIManager:show(InfoMessage:new{
            text = _(title .. " is not currently being read, is " .. BookList.getBookStatusString(BookList.getBookStatus(last_file))),
        })
        local FileManager = require("apps/filemanager/filemanager")
        FileManager.instance.history:onShowHist()
        return
    end

    -- Only close menu if we were called from the menu
    if self.menu_container then
        -- Mimic's FileManager's onShowingReader refresh optimizations
        self.ui.tearing_down = true
        self.ui.dithered = nil
        self:onCloseFileManagerMenu()
    end

    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(last_file)
end

-- function FileManagerMenu:onOpenRandomFav()
--     local random_file = require("readcollection"):OpenRandomFav()
--     if not random_file or lfs.attributes(random_file, "mode") ~= "file" then
--         local InfoMessage = require("ui/widget/infomessage")
--         UIManager:show(InfoMessage:new{
--             text = _("Cannot open random file"),
--         })
--         return
--     end

--     -- Only close menu if we were called from the menu
--     if self.menu_container then
--         -- Mimic's FileManager's onShowingReader refresh optimizations
--         self.ui.tearing_down = true
--         self.ui.dithered = nil
--         self:onCloseFileManagerMenu()
--     end

--     local ReaderUI = require("apps/reader/readerui")
--     ReaderUI:showReader(random_file)
-- end


function FileManagerMenu:setUpdateItemTable()
    local FileChooser = self.ui.file_chooser

    -- setting tab
    self.menu_items.filebrowser_settings = {
        text = _("Settings"),
        sub_item_table = {
            {
                text = _("Show hidden files"),
                checked_func = function() return FileChooser.show_hidden end,
                callback = function() FileChooser:toggleShowFilesMode("show_hidden") end,
            },
            {
                text = _("Show unsupported files"),
                checked_func = function() return FileChooser.show_unsupported end,
                callback = function() FileChooser:toggleShowFilesMode("show_unsupported") end,
                separator = true,
            },
            {
                text = _("Classic mode settings"),
                sub_item_table = {
                    {
                        text_func = function()
                            return T(_("Items per page: %1"),
                                G_reader_settings:readSetting("items_per_page") or FileChooser.items_per_page_default)
                        end,
                        help_text = _([[This sets the number of items per page in:
- File browser, history and favorites in 'classic' display mode
- Search results and folder shortcuts
- File and folder selection
- Calibre and OPDS browsers/search results]]),
                        callback = function(touchmenu_instance)
                            local default_value = FileChooser.items_per_page_default
                            local current_value = G_reader_settings:readSetting("items_per_page") or default_value
                            local widget = SpinWidget:new{
                                title_text =  _("Items per page"),
                                value = current_value,
                                value_min = 6,
                                value_max = 30,
                                default_value = default_value,
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    G_reader_settings:saveSetting("items_per_page", spin.value)
                                    FileChooser:refreshPath()
                                    touchmenu_instance:updateItems()
                                end,
                            }
                            UIManager:show(widget)
                        end,
                    },
                    {
                        text_func = function()
                            local default_value = FileChooser.getItemFontSize(G_reader_settings:readSetting("items_per_page")
                                or FileChooser.items_per_page_default)
                            return T(_("Item font size: %1"), FileChooser.font_size or default_value)
                        end,
                        callback = function(touchmenu_instance)
                            local default_value = FileChooser.getItemFontSize(G_reader_settings:readSetting("items_per_page")
                                or FileChooser.items_per_page_default)
                            local current_value = FileChooser.font_size or default_value
                            local widget = SpinWidget:new{
                                title_text =  _("Item font size"),
                                value = current_value,
                                value_min = 10,
                                value_max = 72,
                                default_value = default_value,
                                keep_shown_on_apply = true,
                                callback = function(spin)
                                    if spin.value == default_value then
                                        -- We can't know if the user has set a size or hit "Use default", but
                                        -- assume that if it is the default font size, he will prefer to have
                                        -- our default font size if he later updates per-page
                                        G_reader_settings:delSetting("items_font_size")
                                    else
                                        G_reader_settings:saveSetting("items_font_size", spin.value)
                                    end
                                    FileChooser:refreshPath()
                                    touchmenu_instance:updateItems()
                                end,
                            }
                            UIManager:show(widget)
                        end,
                    },
                    {
                        text = _("Shrink item font size to fit more text"),
                        checked_func = function()
                            return G_reader_settings:isTrue("items_multilines_show_more_text")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("items_multilines_show_more_text")
                            FileChooser:refreshPath()
                        end,
                        separator = true,
                    },
                    {
                        text = _("Show opened files in bold"),
                        checked_func = function()
                            return G_reader_settings:readSetting("show_file_in_bold") == "opened"
                        end,
                        callback = function()
                            if G_reader_settings:readSetting("show_file_in_bold") == "opened" then
                                G_reader_settings:saveSetting("show_file_in_bold", false)
                            else
                                G_reader_settings:saveSetting("show_file_in_bold", "opened")
                            end
                            FileChooser:refreshPath()
                        end,
                    },
                    {
                        text = _("Show new (not yet opened) files in bold"),
                        checked_func = function()
                            return G_reader_settings:hasNot("show_file_in_bold")
                        end,
                        callback = function()
                            if G_reader_settings:hasNot("show_file_in_bold") then
                                G_reader_settings:saveSetting("show_file_in_bold", false)
                            else
                                G_reader_settings:delSetting("show_file_in_bold")
                            end
                            FileChooser:refreshPath()
                        end,
                    },
                },
            },
            {
                text = _("History settings"),
                sub_item_table = {
                    {
                        text = _("Shorten date/time"),
                        checked_func = function()
                            return G_reader_settings:isTrue("history_datetime_short")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("history_datetime_short")
                            require("readhistory"):updateDateTimeString()
                        end,
                    },
                    {
                        text = _("Freeze last read date of finished books"),
                        checked_func = function()
                            return G_reader_settings:isTrue("history_freeze_finished_books")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("history_freeze_finished_books")
                        end,
                        separator = true,
                    },
                    {
                        text = _("Clear history of deleted files"),
                        callback = function()
                            UIManager:show(ConfirmBox:new{
                                text = _("Clear history of deleted files?"),
                                ok_text = _("Clear"),
                                ok_callback = function()
                                    require("readhistory"):clearMissing()
                                end,
                            })
                        end,
                    },
                    {
                        text = _("Auto-remove deleted or purged items from history"),
                        checked_func = function()
                            return G_reader_settings:isTrue("autoremove_deleted_items_from_history")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("autoremove_deleted_items_from_history")
                        end,
                        separator = true,
                    },
                    {
                        text = _("Show filename in Open last/previous menu items"),
                        checked_func = function()
                            return G_reader_settings:isTrue("open_last_menu_show_filename")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("open_last_menu_show_filename")
                        end,
                    },
                },
            },
            {
                text = _("Home folder settings"),
                sub_item_table = {
                    {
                        text = _("Set home folder"),
                        callback = function()
                            local title_header = _("Current home folder:")
                            local current_path = G_reader_settings:readSetting("home_dir")
                            local default_path = filemanagerutil.getDefaultDir()
                            local caller_callback = function(path)
                                G_reader_settings:saveSetting("home_dir", path)
                                self.ui:updateTitleBarPath()
                            end
                            filemanagerutil.showChooseDialog(title_header, caller_callback, current_path, default_path)
                        end,
                    },
                    {
                        text = _("Shorten home folder"),
                        checked_func = function()
                            return G_reader_settings:nilOrTrue("shorten_home_dir")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrTrue("shorten_home_dir")
                            self.ui:updateTitleBarPath()
                        end,
                        help_text = _([[
"Shorten home folder" will display the home folder itself as "Home" instead of its full path.

Assuming the home folder is:
`/mnt/onboard/.books`
A subfolder will be shortened from:
`/mnt/onboard/.books/Manga/Cells at Work`
To:
`Manga/Cells at Work`.]]),
                    },
                    {
                        text = _("Lock home folder"),
                        enabled_func = function()
                            return G_reader_settings:has("home_dir")
                        end,
                        checked_func = function()
                            return G_reader_settings:isTrue("lock_home_folder")
                        end,
                        callback = function()
                            G_reader_settings:flipNilOrFalse("lock_home_folder")
                            FileChooser:refreshPath()
                        end,
                    },
                },
                separator = true,
            },
            {
                text = _("Show collection mark"),
                checked_func = function()
                    return G_reader_settings:hasNot("collection_show_mark")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("collection_show_mark")
                    self.ui.collections.show_mark = G_reader_settings:nilOrTrue("collection_show_mark")
                    FileChooser:refreshPath()
                end,
            },
            {
                text_func = function()
                    local nb_items_landscape, nb_items_portrait = KeyValuePage.getCurrentItemsPerPage()
                    return T(_("Info lists items per page: %1 / %2"), nb_items_portrait, nb_items_landscape)
                end,
                help_text = _([[This sets the number of items per page in:
- Book information
- Dictionary and Wikipedia lookup history
- Reading statistics details
- A few other plugins]]),
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local nb_items_landscape_default, nb_items_portrait_default = KeyValuePage.getDefaultItemsPerPage()
                    local nb_items_landscape, nb_items_portrait =
                        KeyValuePage.getCurrentItemsPerPage(nb_items_landscape_default, nb_items_portrait_default)
                    local widget = DoubleSpinWidget:new{
                        title_text =  _("Info lists items per page"),
                        width_factor = 0.6,
                        left_text = _("Portrait"),
                        left_value = nb_items_portrait,
                        left_min = 10,
                        left_max = 30,
                        left_default = nb_items_portrait_default,
                        right_text = _("Landscape"),
                        right_value = nb_items_landscape,
                        right_min = 10,
                        right_max = 30,
                        right_default = nb_items_landscape_default,
                        callback = function(left_value, right_value)
                            -- We can't know if the user has set a value or hit "Use default", but
                            -- assume that if it is the default, he will prefer to stay with our
                            -- default if he later changes screen DPI
                            if left_value == nb_items_portrait_default then
                                G_reader_settings:delSetting("keyvalues_per_page")
                            else
                                G_reader_settings:saveSetting("keyvalues_per_page", left_value)
                            end
                            if right_value == nb_items_landscape_default then
                                G_reader_settings:delSetting("keyvalues_per_page_landscape")
                            else
                                G_reader_settings:saveSetting("keyvalues_per_page_landscape", right_value)
                            end
                            touchmenu_instance:updateItems()
                        end,
                    }
                    UIManager:show(widget)
                end,
            },
        },
    }

    for _, widget in pairs(self.registered_widgets) do
        local ok, err = pcall(widget.addToMainMenu, widget, self.menu_items)
        if not ok then
            logger.err("failed to register widget", widget.name, err)
        end
    end

    self.menu_items.show_filter = self:getShowFilterMenuTable()
    self.menu_items.sort_by = self:getSortingMenuTable()
    self.menu_items.reverse_sorting = {
        text = _("Reverse sorting"),
        checked_func = function()
            return G_reader_settings:isTrue("reverse_collate")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("reverse_collate")
            FileChooser:refreshPath()
        end,
    }
    self.menu_items.sort_mixed = {
        text = _("Folders and files mixed"),
        enabled_func = function()
            local collate = FileChooser:getCollate()
            return collate.can_collate_mixed
        end,
        checked_func = function()
            local collate = FileChooser:getCollate()
            return collate.can_collate_mixed and G_reader_settings:isTrue("collate_mixed")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("collate_mixed")
            FileChooser:refreshPath()
        end,
    }
    self.menu_items.start_with = self:getStartWithMenuTable()

    if Device:supportsScreensaver() then
        self.menu_items.screensaver = {
            text = _("Sleep screen"),
            sub_item_table = dofile("frontend/ui/elements/screensaver_menu.lua"),
        }
    end

    -- insert common settings
    for id, common_setting in pairs(dofile("frontend/ui/elements/common_settings_menu_table.lua")) do
        self.menu_items[id] = common_setting
    end

    -- Settings > Navigation; this mostly concerns physical keys, and applies *everywhere*
    if Device:hasKeys() then
        self.menu_items.physical_buttons_setup = dofile("frontend/ui/elements/physical_buttons.lua")
    end

    -- settings tab - Document submenu
    self.menu_items.document_metadata_location_move = {
        text = _("Move book metadata"),
        keep_menu_open = true,
        callback = function()
            self.ui.bookinfo:moveBookMetadata()
        end,
    }

    -- tools tab
    self.menu_items.plugin_management = {
        text = _("Plugin management"),
        sub_item_table = PluginLoader:genPluginManagerSubItem(),
    }
    self.menu_items.patch_management = dofile("frontend/ui/elements/patch_management.lua")
    self.menu_items.advanced_settings = {
        text = _("Advanced settings"),
        callback = function()
            SetDefaults:ConfirmEdit()
        end,
    }

    self.menu_items.developer_options = {
        text = _("Developer options"),
        sub_item_table = {
            {
                text = _("Clear caches"),
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = _("Clear the cache folder?"),
                        ok_callback = function()
                            local DataStorage = require("datastorage")
                            local cachedir = DataStorage:getDataDir() .. "/cache"
                            if lfs.attributes(cachedir, "mode") == "directory" then
                                ffiUtil.purgeDir(cachedir)
                            end
                            lfs.mkdir(cachedir)
                            -- Also remove from the Cache object references to the cache files we've just deleted
                            local Cache = require("cache")
                            Cache.cached = {}
                            UIManager:askForRestart(_("Caches cleared. Please restart KOReader."))
                        end,
                    })
                end,
            },
            {
                text = _("Enable debug logging"),
                checked_func = function()
                    return G_reader_settings:isTrue("debug")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("debug")
                    if G_reader_settings:isTrue("debug") then
                        dbg:turnOn()
                    else
                        dbg:setVerbose(false)
                        dbg:turnOff()
                        G_reader_settings:makeFalse("debug_verbose")
                    end
                end,
            },
            {
                text = _("Enable verbose debug logging"),
                enabled_func = function()
                    return G_reader_settings:isTrue("debug")
                end,
                checked_func = function()
                    return G_reader_settings:isTrue("debug_verbose")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("debug_verbose")
                    if G_reader_settings:isTrue("debug_verbose") then
                        dbg:setVerbose(true)
                    else
                        dbg:setVerbose(false)
                    end
                end,
            },
        },
    }
    self.menu_items.top_manager_infmandhistory = {
        text = _("Topbar in fm and history"),
        checked_func = function() return G_reader_settings:isTrue("top_manager_infmandhistory") end,
        callback = function()
            local top_manager_infmandhistory = G_reader_settings:isTrue("top_manager_infmandhistory")
            G_reader_settings:saveSetting("top_manager_infmandhistory", not top_manager_infmandhistory)
            if G_reader_settings:isTrue("top_manager_infmandhistory") then
                local util = require("util")
                _G.all_files = util.getListAll()
                util.generateStats()
            end
            local ui = require("apps/filemanager/filemanager")
            ui:onClose()
            local FileManager = require("apps/filemanager/filemanager")
            local home_dir = G_reader_settings:readSetting("home_dir") or Device.home_dir or lfs.currentdir()
            FileManager:showFiles(home_dir)

            -- UIManager:restartKOReader()
        end
    }
    self.menu_items.sort_dir_number_files = {
        text = _("Sort dirs by number of files"),
        checked_func = function() return G_reader_settings:isTrue("sort_dir_number_files") end,
        callback = function()
            local sort_dir_number_files = G_reader_settings:isTrue("sort_dir_number_files")
            G_reader_settings:saveSetting("sort_dir_number_files", not sort_dir_number_files)
            if G_reader_settings:isTrue("sort_dir_number_files") then
                G_reader_settings:saveSetting("sort_dir_number_files_finished", false)
                local util = require("util")
                util.generateStats()
            end
            FileChooser:refreshPath()
        end
    }
    self.menu_items.sort_dir_number_files_finished = {
        text = _("Sort dirs by number of files finished"),
        checked_func = function() return G_reader_settings:isTrue("sort_dir_number_files_finished") end,
        callback = function()
            local sort_dir_number_files_finished = G_reader_settings:isTrue("sort_dir_number_files_finished")
            G_reader_settings:saveSetting("sort_dir_number_files_finished", not sort_dir_number_files_finished)
            if G_reader_settings:isTrue("sort_dir_number_files_finished") then
                G_reader_settings:saveSetting("sort_dir_number_files", false)
                local util = require("util")
                util.generateStats()
            end
            FileChooser:refreshPath()
        end
    }
    self.menu_items.apply_extra_patches = {
        text = _("Apply extra patches"),
        checked_func = function() return G_reader_settings:isTrue("apply_extra_patches") end,
        callback = function()
            local apply_extra_patches = G_reader_settings:isTrue("apply_extra_patches")
            G_reader_settings:saveSetting("apply_extra_patches", not apply_extra_patches)
            UIManager:askForRestart()
        end
    }
    if Device:isKobo() and not Device:isSunxi() and not Device:hasColorScreen() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Disable forced 8-bit pixel depth"),
            checked_func = function()
                return G_reader_settings:isTrue("dev_startup_no_fbdepth")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("dev_startup_no_fbdepth")
                UIManager:askForRestart()
            end,
        })
    end
    --- @note Currently, only Kobo, rM & PB have a fancy crash display (#5328)
    if Device:isKobo() or Device:isRemarkable() or Device:isPocketBook() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Always abort on crash"),
            checked_func = function()
                return G_reader_settings:isTrue("dev_abort_on_crash")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("dev_abort_on_crash")
                UIManager:askForRestart()
            end,
        })
    end
    local Blitbuffer = require("ffi/blitbuffer")
    table.insert(self.menu_items.developer_options.sub_item_table, {
        text = _("Disable C blitter"),
        enabled_func = function()
            return Blitbuffer.has_cblitbuffer
        end,
        checked_func = function()
            return G_reader_settings:isTrue("dev_no_c_blitter")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("dev_no_c_blitter")
            Blitbuffer:enableCBB(G_reader_settings:nilOrFalse("dev_no_c_blitter"))
        end,
    })
    if Device:hasEinkScreen() and Device:canHWDither() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Disable HW dithering"),
            checked_func = function()
                return not Device.screen.hw_dithering
            end,
            callback = function()
                Device.screen:toggleHWDithering()
                G_reader_settings:saveSetting("dev_no_hw_dither", not Device.screen.hw_dithering)
                -- Make sure SW dithering gets disabled when we enable HW dithering
                if Device.screen.hw_dithering and Device.screen.sw_dithering then
                    G_reader_settings:makeTrue("dev_no_sw_dither")
                    Device.screen:toggleSWDithering(false)
                end
                UIManager:setDirty("all", "full")
            end,
        })
    end
    if Device:hasEinkScreen() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Disable SW dithering"),
            enabled_func = function()
                return Device.screen.fb_bpp == 8
            end,
            checked_func = function()
                return not Device.screen.sw_dithering
            end,
            callback = function()
                Device.screen:toggleSWDithering()
                G_reader_settings:saveSetting("dev_no_sw_dither", not Device.screen.sw_dithering)
                -- Make sure HW dithering gets disabled when we enable SW dithering
                if Device.screen.hw_dithering and Device.screen.sw_dithering then
                    G_reader_settings:makeTrue("dev_no_hw_dither")
                    Device.screen:toggleHWDithering(false)
                end
                UIManager:setDirty("all", "full")
            end,
        })
    end
    if Device:isKobo() and Device:hasColorScreen() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            -- We default to a flag (G2) that slightly boosts saturation,
            -- but it *is* a destructive process, so we want to allow disabling it.
            -- @translators CFA is a technical term for the technology behind eInk's color panels. It stands for Color Film/Filter Array, leave the abbreviation alone ;).
            text = _("Disable CFA post-processing"),
            checked_func = function()
                return G_reader_settings:isTrue("no_cfa_post_processing")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("no_cfa_post_processing")
                UIManager:askForRestart()
            end,
        })
    end
    table.insert(self.menu_items.developer_options.sub_item_table, {
        text = _("Anti-alias rounded corners"),
        checked_func = function()
            return G_reader_settings:nilOrTrue("anti_alias_ui")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("anti_alias_ui")
        end,
    })
    --- @note: Currently, only Kobo implements this quirk
    if Device:hasEinkScreen() and Device:isKobo() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            -- @translators Highly technical (ioctl is a Linux API call, the uppercase stuff is a constant). What's translatable is essentially only the action ("bypass") and the article.
            text = _("Bypass the WAIT_FOR ioctls"),
            checked_func = function()
                local mxcfb_bypass_wait_for
                if G_reader_settings:has("mxcfb_bypass_wait_for") then
                    mxcfb_bypass_wait_for = G_reader_settings:isTrue("mxcfb_bypass_wait_for")
                else
                    mxcfb_bypass_wait_for = not Device:hasReliableMxcWaitFor()
                end
                return mxcfb_bypass_wait_for
            end,
            callback = function()
                local mxcfb_bypass_wait_for
                if G_reader_settings:has("mxcfb_bypass_wait_for") then
                    mxcfb_bypass_wait_for = G_reader_settings:isTrue("mxcfb_bypass_wait_for")
                else
                    mxcfb_bypass_wait_for = not Device:hasReliableMxcWaitFor()
                end
                G_reader_settings:saveSetting("mxcfb_bypass_wait_for", not mxcfb_bypass_wait_for)
                UIManager:askForRestart()
            end,
        })
    end
    --- @note: Intended to debug/investigate B288 quirks on PocketBook devices
    if Device:hasEinkScreen() and Device:isPocketBook() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            -- @translators B288 is the codename of the CPU/chipset (SoC stands for 'System on Chip').
            text = _("Ignore feature bans on B288 SoCs"),
            enabled_func = function()
                return Device:isB288SoC()
            end,
            checked_func = function()
                return G_reader_settings:isTrue("pb_ignore_b288_quirks")
            end,
            callback = function()
                G_reader_settings:flipNilOrFalse("pb_ignore_b288_quirks")
                UIManager:askForRestart()
            end,
        })
    end
    if Device:isAndroid() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            text = _("Start compatibility test"),
            callback = function()
                Device:test()
            end,
        })
    end

    table.insert(self.menu_items.developer_options.sub_item_table, {
        text = _("Disable enhanced UI text shaping (xtext)"),
        checked_func = function()
            return G_reader_settings:isFalse("use_xtext")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("use_xtext")
            UIManager:askForRestart()
        end,
    })
    table.insert(self.menu_items.developer_options.sub_item_table, {
        text = _("UI layout mirroring and text direction"),
        sub_item_table = {
            {
                text = _("Reverse UI layout mirroring"),
                checked_func = function()
                    return G_reader_settings:isTrue("dev_reverse_ui_layout_mirroring")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("dev_reverse_ui_layout_mirroring")
                    UIManager:askForRestart()
                end
            },
            {
                text = _("Reverse UI text direction"),
                checked_func = function()
                    return G_reader_settings:isTrue("dev_reverse_ui_text_direction")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("dev_reverse_ui_text_direction")
                    UIManager:askForRestart()
                end
            },
        },
    })
    table.insert(self.menu_items.developer_options.sub_item_table, {
        text_func = function()
            if G_reader_settings:nilOrTrue("use_cre_call_cache")
                    and G_reader_settings:isTrue("use_cre_call_cache_log_stats") then
                return _("Enable CRE call cache (with stats)")
            end
            return _("Enable CRE call cache")
        end,
        checked_func = function()
            return G_reader_settings:nilOrTrue("use_cre_call_cache")
        end,
        callback = function()
            G_reader_settings:flipNilOrTrue("use_cre_call_cache")
            -- No need to show "This will take effect on next CRE book opening."
            -- as this menu is only accessible from file browser
        end,
        hold_callback = function(touchmenu_instance)
            G_reader_settings:flipNilOrFalse("use_cre_call_cache_log_stats")
            touchmenu_instance:updateItems()
        end,
    })
    table.insert(self.menu_items.developer_options.sub_item_table, {
        text = _("Dump the fontlist cache"),
        callback = function()
            local FontList = require("fontlist")
            FontList:dumpFontList()
        end,
    })
    if Device:isKobo() and Device:canToggleChargingLED() then
        table.insert(self.menu_items.developer_options.sub_item_table, {
            -- @translators This is a debug option to help determine cases when standby failed to initiate properly. PM = power management.
            text = _("Turn on the LED on PM entry failure"),
            checked_func = function()
                return G_reader_settings:isTrue("pm_debug_entry_failure")
            end,
            callback = function()
                G_reader_settings:toggle("pm_debug_entry_failure")
            end,
        })
    end

    self.menu_items.cloud_storage = {
        text = _("Cloud storage"),
        callback = function()
            local cloud_storage = require("apps/cloudstorage/cloudstorage"):new{}
            UIManager:show(cloud_storage)
            local filemanagerRefresh = function() self.ui:onRefresh() end
            function cloud_storage:onClose()
                filemanagerRefresh()
                UIManager:close(cloud_storage)
            end
        end,
    }

    self.menu_items.find_file_all = {
        -- @translators Search for files by name.
        text = _("File search all"),
        help_text = _([[Search a book by filename in the current or home folder and its subfolders.

Wildcards for one '?' or more '*' characters can be used.
A search for '*' will show all files.

The sorting order is the same as in filemanager.

Tap a book in the search results to open it.]]),
        callback = function()
            self.ui.filesearcher:onShowFileSearchLists(false)
        end
    }
--     self.menu_items.find_file_all_sorted = {
--         -- @translators Search for files by name.
--         text = _("File search all sorted by size"),
--         help_text = _([[Search a book by filename in the current or home folder and its subfolders.

-- Wildcards for one '?' or more '*' characters can be used.
-- A search for '*' will show all files.

-- The sorting order is the same as in filemanager.

-- Tap a book in the search results to open it.]]),
--         callback = function()
--             self.ui.filesearcher:onShowFileSearchLists(false, nil, nil, true)
--         end
--     }
    self.menu_items.find_file_all_recent = {
        -- @translators Search for files by name.
        text = _("File search all recent"),
        help_text = _([[Search a book by filename in the current or home folder and its subfolders.

Wildcards for one '?' or more '*' characters can be used.
A search for '*' will show all files.

The sorting order is the same as in filemanager.

Tap a book in the search results to open it.]]),
        callback = function()
            self.ui.filesearcher:onShowFileSearchLists(true)
        end
    }
    self.menu_items.find_file_all_completed = {
        -- @translators Search for files by name.
        text = _("File search all completed"),
        help_text = _([[Search a book by filename in the current or home folder and its subfolders.

Wildcards for one '?' or more '*' characters can be used.
A search for '*' will show all files.

The sorting order is the same as in filemanager.

Tap a book in the search results to open it.]]),
        callback = function()
            self.ui.filesearcher:onShowFileSearchAllCompleted()
        end
    }


    self.menu_items.tbr = {
        -- @translators Search for files by name.
        text = _("TBR"),
        help_text = _([[Search a book by filename in the current or home folder and its subfolders.

Wildcards for one '?' or more '*' characters can be used.
A search for '*' will show all files.

The sorting order is the same as in filemanager.

Tap a book in the search results to open it.]]),
        callback = function()
            local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
            FileManagerHistory:onShowHistTBR()
        end
    }

    self.menu_items.mbr = {
        -- @translators Search for files by name.
        text = _("MBR"),
        help_text = _([[Search a book by filename in the current or home folder and its subfolders.

Wildcards for one '?' or more '*' characters can be used.
A search for '*' will show all files.

The sorting order is the same as in filemanager.

Tap a book in the search results to open it.]]),
        callback = function()
            local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
            FileManagerHistory:onShowHistMBR()
        end
    }

    -- main menu tab
    self.menu_items.open_last_document = {
        text_func = function()
            if not G_reader_settings:isTrue("open_last_menu_show_filename") or G_reader_settings:hasNot("lastfile") then
                return _("Open last document")
            end
            local last_file = G_reader_settings:readSetting("lastfile")
            local path, file_name = util.splitFilePathName(last_file) -- luacheck: no unused
            return T(_("Last: %1"), BD.filename(file_name))
        end,
        enabled_func = function()
            return G_reader_settings:has("lastfile")
        end,
        callback = function()
            self:onOpenLastDoc()
        end,
        hold_callback = function()
            local last_file = G_reader_settings:readSetting("lastfile")
            UIManager:show(ConfirmBox:new{
                text = T(_("Would you like to open the last document: %1?"), BD.filepath(last_file)),
                ok_text = _("OK"),
                ok_callback = function()
                    self:onOpenLastDoc()
                end,
            })
        end
    }
    self.menu_items.generate_favorites = {
        text_func = function()
            return _("Generate Favorites")
        end,
        enabled_func = function()
        end,
        callback = function()
            local files = util.getListAll()
            local ReadCollection = require("readcollection")
            ReadCollection:RemoveAllFavoritesAll()
            local collections = {}
            collections["favorites"] = true
            ReadCollection:addItemsMultiple(files, collections)
            local ordered_files = ReadCollection:getOrderedCollectionName("favorites")
            ReadCollection:updateCollectionOrder("favorites", ordered_files)


            local UIManager = require("ui/uimanager")
            local Notification = require("ui/widget/notification")
            UIManager:show(Notification:new{
                text = _("All books added to the All collection."),
            })
            self.ui.collections:onShowColl()
        end,
        hold_callback = function()
        end
    }
    -- self.menu_items.open_random_favorite = {
    --     text_func = function()
    --         local random_file = require("readcollection"):OpenRandomFav()
    --         if not G_reader_settings:isTrue("open_last_menu_show_filename") or not random_file then
    --             return _("Open random MBR book")
    --         end
    --         local path, file_name = util.splitFilePathName(random_file) -- luacheck: no unused
    --         return T(_("Previous: %1"), BD.filename(file_name))
    --     end,
    --     enabled_func = function()
    --         return require("readcollection"):OpenRandomFav() ~= nil
    --     end,
    --     callback = function()
    --         self:onOpenRandomFav()
    --     end,
    --     hold_callback = function()
    --         local previous_file = self:getRandomFav()
    --         UIManager:show(ConfirmBox:new{
    --             text = T(_("Would you like to open the previous document: %1?"), BD.filepath(previous_file)),
    --             ok_text = _("OK"),
    --             ok_callback = function()
    --                 self.ui:switchDocument(previous_file)
    --             end,
    --         })
    --     end
    -- }

   self.menu_items.generate_font_profiles = {
        text_func = function()
            return _("Generate Font Profiles")
        end,
        enabled_func = function()
        end,
        callback = function()
            local profiles_file = require("datastorage"):getSettingsDir() .. "/profiles.lua"
            local profiles = require("luasettings"):open(profiles_file)
            local data = profiles.data
            local cre = require("document/credocument"):engineInit()
            local face_list = cre.getFontFaces()
            local gestures_path = ffiUtil.joinPath(require("datastorage"):getSettingsDir(), "gestures.lua")
            local settings_data = require("luasettings"):open(gestures_path)
            local gestures = settings_data.data["gesture_reader"]
            for _, font_name in ipairs(face_list) do
                --print(font_name)
                local encuentra = false
                for k, v in pairs(data) do
                    if data[k] and data[k].settings then
                        if data[k].settings.name == font_name then
                            encuentra=true
                            break
                        end
                    end
                end
                if not encuentra then
                    data[font_name] =  {
                        ["font_base_weight"] = 0,
                        ["set_font"] = font_name,
                        ["settings"] = {
                            ["name"] = font_name,
                            ["registered"] = true,
                            ["order"] = {
                                [2] = "font_base_weight",
                                [1] = "set_font",
                            },
                        }
                    }
                end
            end

            -- local dump = require("dump")
            -- print(dump(gestures))
            if not gestures["multiswipe_north_east"] or not gestures["multiswipe_north_east"]["settings"] then
                -- local UIManager = require("ui/uimanager")
                -- local Notification = require("ui/widget/notification")
                -- UIManager:show(Notification:new{
                --  text = _("Not exits"),
                -- })
                gestures["multiswipe_north_east"] = {
                ["profile_exec_Reset defaults"] = true,
                ["decrease_weight"] = true,
                ["profile_exec_Spectral"] = true,
                ["profile_exec_Vollkorn"] = true,
                ["toggle_horizontal_vertical"] = true,
                ["settings"] = {
                    ["show_as_quickmenu"] = true,
                    ["keep_open_on_apply"] = true,
                    ["order"] = {
                        [1] = "profile_exec_Reset defaults",
                        [2] = "toggle_horizontal_vertical",
                        [3] = "profile_exec_Font size small",
                        [4] = "profile_exec_Font size default (normal)",
                        [5] = "profile_exec_Font size big",
                        [6] = "increase_font",
                        [7] = "decrease_font",
                        [8] = "profile_exec_Line spacing 1.1em",
                        [9] = "profile_exec_Line spacing 1.2em (normal)",
                        [10] = "profile_exec_Line spacing 1.3em",
                        [11] = "profile_exec_Line spacing 1.4em",
                        [12] = "profile_exec_Margins default (small)",
                        [13] = "profile_exec_Margins slightly bigger",
                        [14] = "profile_exec_Margins big",
                        [15] = "profile_exec_Margins bigger",
                        [16] = "increase_weight",
                        [17] = "decrease_weight",
                        [18] = "profile_exec_Alegreya",
                        [19] = "profile_exec_Amasis",
                        [20] = "profile_exec_Andada Pro",
                        [21] = "profile_exec_Average",
                        [22] = "profile_exec_Bitter Pro",
                        [23] = "profile_exec_Bookerly",
                        [24] = "profile_exec_Caecilia",
                        [25] = "profile_exec_Canela Text",
                        [26] = "profile_exec_Capita",
                        [27] = "profile_exec_ChareInk",
                        [28] = "profile_exec_Constantia",
                        [29] = "profile_exec_Crimson Pro",
                        [30] = "profile_exec_EB Garamond",
                        [31] = "profile_exec_Gentium Book Plus",
                        [32] = "profile_exec_Georgia",
                        [33] = "profile_exec_Goudy Old Style",
                        [34] = "profile_exec_IBM Plex Serif",
                        [35] = "profile_exec_Iowan Old Style",
                        [36] = "profile_exec_Lexia DaMa",
                        [37] = "profile_exec_Liberation Serif",
                        [38] = "profile_exec_Libre Baskerville",
                        [39] = "profile_exec_Literata",
                        [40] = "profile_exec_Luciole",
                        [41] = "profile_exec_Mearriweather",
                        [42] = "profile_exec_Palatino",
                        [43] = "profile_exec_Souvenir",
                        [44] = "profile_exec_Spectral",
                        [45] = "profile_exec_Vollkorn",
                    },
                },
                ["profile_exec_Souvenir"] = true,
                ["profile_exec_Literata"] = true,
                ["profile_exec_Mearriweather"] = true,
                ["profile_exec_Margins bigger"] = true,
                ["profile_exec_Alegreya"] = true,
                ["profile_exec_Amasis"] = true,
                ["profile_exec_Andada Pro"] = true,
                ["profile_exec_Average"] = true,
                ["profile_exec_Bitter Pro"] = true,
                ["profile_exec_Bookerly"] = true,
                ["profile_exec_Caecilia"] = true,
                ["profile_exec_Canela Text"] = true,
                ["profile_exec_Capita"] = true,
                ["profile_exec_ChareInk"] = true,
                ["profile_exec_Constantia"] = true,
                ["profile_exec_Crimson Pro"] = true,
                ["profile_exec_EB Garamond"] = true,
                ["profile_exec_Font size big"] = true,
                ["profile_exec_Font size default (normal)"] = true,
                ["profile_exec_Font size small"] = true,
                ["profile_exec_Gentium Book Plus"] = true,
                ["profile_exec_Georgia"] = true,
                ["profile_exec_Goudy Old Style"] = true,
                ["profile_exec_IBM Plex Serif"] = true,
                ["profile_exec_Iowan Old Style"] = true,
                ["profile_exec_Lexia DaMa"] = true,
                ["profile_exec_Liberation Serif"] = true,
                ["profile_exec_Libre Baskerville"] = true,
                ["profile_exec_Line spacing 1.1em"] = true,
                ["profile_exec_Line spacing 1.2em (normal)"] = true,
                ["profile_exec_Line spacing 1.3em"] = true,
                ["profile_exec_Line spacing 1.4em"] = true,
                ["increase_font"] = 0.5,
                ["profile_exec_Luciole"] = true,
                ["profile_exec_Margins big"] = true,
                ["decrease_font"] = 0.5,
                ["profile_exec_Margins default (small)"] = true,
                ["profile_exec_Margins slightly bigger"] = true,
                ["increase_weight"] = true,
                ["profile_exec_Palatino"] = true,
            }
            else

                local all_fonts = {}
                -- print(dump(all_fonts))
                for _, font_name in ipairs(face_list) do
                    if not font_name:find("Noto Sans") then
                        table.insert(all_fonts, "profile_exec_" .. font_name)
                        gestures["multiswipe_north_east"]["profile_exec_" .. font_name] = true
                    end
                end
                --print(dump(all_fonts))
                gestures["multiswipe_north_east"]["settings"]["order"] = all_fonts
            end
            local data_ordered = {}
            for k, v in ffiUtil.orderedPairs(data) do
                data_ordered[k] = v
            end


            --bag = {}
            --for k,v in pairs(data) do
            --    table.insert(bag,{key=k,v})
            --end

            --table.sort(bag,function(a,b) return string.upper(a.key)<string.upper(b.key)end)

            --data = {}
            --for k,v in pairs(bag) do
                --print(v[1].settings.name)
            --    data[v[1].settings.name]=v[1]
            --end
            --local dump = require("dump")
            --print(dump(data_ordered))
            --util.writeToFile(dump(data_ordered),require("datastorage"):getSettingsDir() .. "/profiles.lua")

            profiles.data = data_ordered
            profiles:flush()
            settings_data:flush()
            local Size = require("ui/size")
            UIManager:show(ConfirmBox:new{
                dismissable = false,
                text = _("KOReader needs to be restarted."),
                ok_text = save_text,
                margin = Size.margin.tiny,
                padding = Size.padding.tiny,
                ok_callback = function()
                    if Device:canRestart() then
                        UIManager:restartKOReader()
                        -- The new Clara BW is so quick closing that when presing on Restart it doesn't flash
                        -- Set a little delay for all devices
                        local util = require("ffi/util")
                        util.usleep(100000)
                    else
                        UIManager:quit()
                    end
                end,
                cancel_text = _("No need to restart"),
                cancel_callback = function()
                    logger.info("discard defaults")
                end,
                flash_yes = true,
            })
        end,
        hold_callback = function()
        end
    }
    -- self.menu_items.open_random_favorite = {
    -- -- insert common info
    for id, common_setting in pairs(dofile("frontend/ui/elements/common_info_menu_table.lua")) do
        self.menu_items[id] = common_setting
    end
    -- insert common exit for filemanager
    for id, common_setting in pairs(dofile("frontend/ui/elements/common_exit_menu_table.lua")) do
        self.menu_items[id] = common_setting
    end
    if not Device:isTouchDevice() then
        -- add a shortcut on non touch-device
        -- because this menu is not accessible otherwise
        self.menu_items.plus_menu = {
            icon = "plus",
            remember = false,
            callback = function()
                self:onCloseFileManagerMenu()
                self.ui:tapPlus()
            end,
        }
    end

    -- NOTE: This is cached via require for ui/plugin/insert_menu's sake...
    local order = require("ui/elements/filemanager_menu_order")

    local MenuSorter = require("ui/menusorter")
    self.tab_item_table = MenuSorter:mergeAndSort("filemanager", self.menu_items, order)
end
dbg:guard(FileManagerMenu, 'setUpdateItemTable',
    function(self)
        local mock_menu_items = {}
        for _, widget in pairs(self.registered_widgets) do
            -- make sure addToMainMenu works in debug mode
            widget:addToMainMenu(mock_menu_items)
        end
    end)

function FileManagerMenu:getShowFilterMenuTable()
    local FileChooser = require("ui/widget/filechooser")
    local statuses = { "new", "mbr", "tbr", "reading", "abandoned", "complete" }
    local sub_item_table = {
        {
            text = BookList.getBookStatusString("all"):lower(),
            checked_func = function()
                return FileChooser.show_filter.status == nil
            end,
            radio = true,
            callback = function()
                FileChooser.show_filter.status = nil
                self.ui.file_chooser:refreshPath()
            end,
            separator = true,
        },
    }
    for _, v in ipairs(statuses) do
        table.insert(sub_item_table, {
            text = BookList.getBookStatusString(v):lower(),
            checked_func = function()
                return FileChooser.show_filter.status and FileChooser.show_filter.status[v]
            end,
            callback = function()
                FileChooser.show_filter.status = FileChooser.show_filter.status or {}
                FileChooser.show_filter.status[v] = not FileChooser.show_filter.status[v] or nil
                local statuses_nb = util.tableSize(FileChooser.show_filter.status)
                if statuses_nb == 0 or statuses_nb == #statuses then
                    FileChooser.show_filter.status = nil
                end
                self.ui.file_chooser:refreshPath()
            end,
        })
    end
    return {
        text_func = function()
            local text
            if FileChooser.show_filter.status == nil then
                text = BookList.getBookStatusString("all"):lower()
            else
                for _, v in ipairs(statuses) do
                    if FileChooser.show_filter.status[v] then
                        local status_string = BookList.getBookStatusString(v):lower()
                        text = text and text .. ", " .. status_string or status_string
                    end
                end
            end
            return T(_("Book status: %1"), text)
        end,
        sub_item_table = sub_item_table,
        hold_callback = function(touchmenu_instance)
            FileChooser.show_filter.status = nil
            self.ui.file_chooser:refreshPath()
            touchmenu_instance:updateItems()
        end,
    }
end

function FileManagerMenu:getSortingMenuTable()
    local sub_item_table = {
        max_per_page = 9, -- metadata collates in page 2
    }
    for k, v in pairs(self.ui.file_chooser.collates) do
        table.insert(sub_item_table, {
            text = v.text,
            menu_order = v.menu_order,
            checked_func = function()
                local _, id = self.ui.file_chooser:getCollate()
                return k == id
            end,
            callback = function()
                self.ui:onSetSortBy(k)
            end,
        })
    end
    table.sort(sub_item_table, function(a, b) return a.menu_order < b.menu_order end)
    return {
        text_func = function()
            local collate = self.ui.file_chooser:getCollate()
            return T(_("Sort by: %1"), collate.text)
        end,
        sub_item_table = sub_item_table,
    }
end

function FileManagerMenu:getStartWithMenuTable()
    local start_withs = {
        { _("file browser"), "filemanager" },
        { _("history"), "history" },
        { _("favorites"), "favorites" },
        { _("folder shortcuts"), "folder_shortcuts" },
        { _("last file"), "last" },
    }
    local sub_item_table = {}
    for i, v in ipairs(start_withs) do
        table.insert(sub_item_table, {
            text = v[1],
            checked_func = function()
                return v[2] == G_reader_settings:readSetting("start_with", "filemanager")
            end,
            callback = function()
                G_reader_settings:saveSetting("start_with", v[2])
            end,
        })
    end
    return {
        text_func = function()
            local start_with = G_reader_settings:readSetting("start_with") or "filemanager"
            for i, v in ipairs(start_withs) do
                if v[2] == start_with then
                    return T(_("Start with: %1"), v[1])
                end
            end
        end,
        sub_item_table = sub_item_table,
    }
end

function FileManagerMenu:exitOrRestart(callback, force)
    -- Only restart sets a callback, which suits us just fine for this check ;)
    if callback and not force and not Device:isStartupScriptUpToDate() then
        UIManager:show(ConfirmBox:new{
            text = _("KOReader's startup script has been updated. You'll need to completely exit KOReader to finalize the update."),
            ok_text = _("Restart anyway"),
            ok_callback = function()
                self:exitOrRestart(callback, true)
            end,
        })
        return
    end

    UIManager:close(self.menu_container)
    self.ui:onClose()
    if callback then
        callback()
    end
end

function FileManagerMenu:onShowMenu(tab_index, do_not_show)
    if self.tab_item_table == nil then
        self:setUpdateItemTable()
    end

    local menu_container = CenterContainer:new{
        ignore = "height",
        dimen = Screen:getSize(),
    }

    local main_menu
    if Device:isTouchDevice() or Device:hasDPad() then
        local TouchMenu = require("ui/widget/touchmenu")
        main_menu = TouchMenu:new{
            width = Screen:getWidth(),
            last_index = tab_index or G_reader_settings:readSetting("filemanagermenu_tab_index") or 1,
            tab_item_table = self.tab_item_table,
            show_parent = menu_container,
            not_shown = do_not_show,
        }
    else
        local Menu = require("ui/widget/menu")
        main_menu = Menu:new{
            title = _("File manager menu"),
            item_table = Menu.itemTableFromTouchMenu(self.tab_item_table),
            width = Screen:getWidth() - (Size.margin.fullscreen_popout * 2),
            show_parent = menu_container,
        }
    end

    main_menu.close_callback = function()
        self:onCloseFileManagerMenu()
    end

    menu_container[1] = main_menu
    -- maintain a reference to menu_container
    self.menu_container = menu_container
    if not do_not_show then
        UIManager:show(menu_container)
    end
    return true
end

function FileManagerMenu:onCloseFileManagerMenu()
    if not self.menu_container then return true end
    local last_tab_index = self.menu_container[1].last_index
    G_reader_settings:saveSetting("filemanagermenu_tab_index", last_tab_index)
    UIManager:close(self.menu_container)
    self.menu_container = nil
    return true
end

function FileManagerMenu:_getTabIndexFromLocation(ges)
    if self.tab_item_table == nil then
        self:setUpdateItemTable()
    end
    local last_tab_index = G_reader_settings:readSetting("filemanagermenu_tab_index") or 1
    if not ges then
        return last_tab_index
    -- if the start position is far right
    elseif ges.pos.x > Screen:getWidth() * (2/3) then
        return BD.mirroredUILayout() and 1 or #self.tab_item_table
    -- if the start position is far left
    elseif ges.pos.x < Screen:getWidth() * (1/3) then
        return BD.mirroredUILayout() and #self.tab_item_table or 1
    -- if center return the last index
    else
        return last_tab_index
    end
end

function FileManagerMenu:onTapShowMenu(ges)
    if self.activation_menu ~= "swipe" then
        self:onShowMenu(self:_getTabIndexFromLocation(ges))
        return true
    end
end

function FileManagerMenu:onSwipeShowMenu(ges)
    if self.activation_menu ~= "tap" and ges.direction == "south" then
        self:onShowMenu(self:_getTabIndexFromLocation(ges))
        return true
    end
end

function FileManagerMenu:onKeyPressShowMenu(_, key_ev)
    return self:onShowMenu()
end

function FileManagerMenu:onSetDimensions(dimen)
    -- This widget doesn't support in-place layout updates, so, close & reopen
    if self.menu_container then
        self:onCloseFileManagerMenu()
        self:onShowMenu()
    end

    -- update gesture zones according to new screen dimen
    self:initGesListener()
end

function FileManagerMenu:onMenuSearch()
    self:onShowMenu(nil, true)
    self.menu_container[1]:onShowMenuSearch()
end

function FileManagerMenu:registerToMainMenu(widget)
    table.insert(self.registered_widgets, widget)
end

return FileManagerMenu
